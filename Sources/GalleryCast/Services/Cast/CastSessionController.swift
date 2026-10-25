import Foundation
import Observation
import os

/// Drives one cast session: connect to the device, bring up the Default
/// Media Receiver, then mirror the viewer — every current-photo change
/// becomes one media `LOAD`, which the receiver fetches from the Mac's
/// photo server.
///
/// The viewer owns what is on screen; this controller only keeps the
/// receiver in sync with it. Closing the viewer stops the session.
@MainActor
@Observable
final class CastSessionController: @unchecked Sendable {

    enum Phase: Equatable {
        case idle
        case connecting
        case launching
        case casting
    }

    private(set) var phase: Phase = .idle
    private(set) var deviceName: String?
    private(set) var lastError: String?

    var isCasting: Bool { phase == .casting }
    var isActive: Bool { phase != .idle }

    private let server = PhotoWebServer()
    private var client: CastV2Client?
    private var lanAddress: String?
    private var connectedTransportID: String?
    private var sessionID: String?
    private var hasLaunched = false
    private var pendingPhoto: Photo?
    private var requestID = 0
    private var watchdog: Task<Void, Never>?
    private var teardown: Task<Void, Never>?

    private static let senderID = "sender-0"
    private static let receiverID = "receiver-0"
    private static let log = Logger(subsystem: "com.aniketpathak.gallerycast", category: "cast")

    // MARK: Session lifecycle

    /// Starts casting `currentPhoto` (and everything the viewer shows
    /// afterwards) to `device`.
    func start(device: CastDevice, folder: URL, currentPhoto: Photo?, useTLS: Bool = true) {
        stop()
        deviceName = device.name
        lastError = nil
        hasLaunched = false
        pendingPhoto = currentPhoto
        phase = .connecting
        Self.log.info("cast: session to \(device.name, privacy: .public) starting")

        // Wire the handlers before any awaiting so captures stay
        // consistent and no state can race the first callback.
        let server = self.server
        let client = CastV2Client(endpoint: device.endpoint, useTLS: useTLS)
        client.onStateChange = { [weak self] state in
            Task { @MainActor in self?.handleClientState(state) }
        }
        client.onMessage = { [weak self] message in
            Task { @MainActor in self?.handleMessage(message) }
        }
        self.client = client

        Task {
            do {
                let port = try await server.start(folder: folder)
                Self.log.info("cast: photo server bound on port \(port)")
                client.start()
            } catch {
                self.fail(with: error.localizedDescription)
            }
        }

        armWatchdog(seconds: connectTimeout)
    }

    /// The viewer moved — or closed. `nil` stops the session, matching
    /// "the TV shows what the viewer shows".
    func mirror(_ photo: Photo?) {
        guard let photo else {
            stop()
            return
        }
        guard isActive else { return }
        pendingPhoto = photo
        if phase == .casting {
            load(photo)
        }
    }

    func stop() {
        if isActive {
            Self.log.info("cast: stopping session")
        }
        watchdog?.cancel()
        watchdog = nil

        // Tell the receiver to close the app before dropping the socket;
        // give the messages a moment to flush.
        if isActive, let sessionID, let client {
            requestID += 1
            client.send(CastMessage(
                sourceID: Self.senderID,
                destinationID: Self.receiverID,
                namespace: CastNamespace.receiver,
                payloadJSON: CastPayloads.stopApp(sessionID: sessionID, requestID: requestID)
            ))
            if let transportID = connectedTransportID {
                client.send(CastMessage(
                    sourceID: Self.senderID,
                    destinationID: transportID,
                    namespace: CastNamespace.connection,
                    payloadJSON: CastPayloads.close()
                ))
            }
            teardown?.cancel()
            let dyingClient = client
            teardown = Task {
                try? await Task.sleep(for: .milliseconds(250))
                dyingClient.stop()
            }
        }

        client = nil
        server.stop()
        connectedTransportID = nil
        sessionID = nil
        hasLaunched = false
        pendingPhoto = nil
        lanAddress = nil
        deviceName = nil
        phase = .idle
    }

    // MARK: Connection

    private func handleClientState(_ state: CastV2Client.State) {
        guard isActive else { return }
        switch state {
        case .ready(let remoteIPv4):
            // The URL must name an address the device can reach.
            lanAddress = LocalAddress.bestAddress(
                interfaces: LocalAddress.interfaces(),
                deviceIPv4: remoteIPv4 ?? ""
            )
            Self.log.info(
                "cast: connected (remote \(remoteIPv4 ?? "non-IPv4", privacy: .public), serving from \(self.lanAddress ?? "none", privacy: .public))"
            )
            client?.send(CastMessage(
                sourceID: Self.senderID,
                destinationID: Self.receiverID,
                namespace: CastNamespace.connection,
                payloadJSON: CastPayloads.connect()
            ))
            requestID += 1
            client?.send(CastMessage(
                sourceID: Self.senderID,
                destinationID: Self.receiverID,
                namespace: CastNamespace.receiver,
                payloadJSON: CastPayloads.getStatus(requestID: requestID)
            ))
            // The socket is up; the remaining budget covers the
            // receiver's handshake and app launch, which is the slow
            // part on real TVs.
            armWatchdog(seconds: launchTimeout)
        case .failed(let message):
            Self.log.error("cast: connection failed: \(message, privacy: .public)")
            fail(with: message)
        case .cancelled:
            break
        }
    }

    private func handleMessage(_ message: CastMessage) {
        guard isActive else { return }

        switch message.namespace {
        case CastNamespace.receiver:
            guard CastPayloads.messageType(of: message.payloadString ?? "") == "RECEIVER_STATUS",
                  let status = ReceiverStatus.parse(message.payloadString ?? "")
            else { return }
            handleReceiverStatus(status)

        case CastNamespace.media:
            let type = CastPayloads.messageType(of: message.payloadString ?? "")
            if type == "LOAD_FAILED" {
                Self.log.error("cast: receiver could not display the photo (LOAD_FAILED)")
                lastError = "The receiver could not display this photo."
            } else if type == "MEDIA_STATUS" {
                Self.log.info("cast: receiver acknowledged media (MEDIA_STATUS)")
            }

        default:
            break
        }
    }

    private func handleReceiverStatus(_ status: ReceiverStatus) {
        guard let app = status.applications.first(where: {
            $0.appID == CastPayloads.defaultMediaReceiverAppID
        }) else {
            // Idle receiver: launch the media app once.
            if !hasLaunched {
                hasLaunched = true
                phase = .launching
                Self.log.info("cast: receiver idle, launching media app")
                requestID += 1
                client?.send(CastMessage(
                    sourceID: Self.senderID,
                    destinationID: Self.receiverID,
                    namespace: CastNamespace.receiver,
                    payloadJSON: CastPayloads.launch(
                        appID: CastPayloads.defaultMediaReceiverAppID,
                        requestID: requestID
                    )
                ))
            }
            return
        }

        sessionID = app.sessionID

        guard let transportID = app.transportID else { return }

        // New transport (fresh launch or restart): open its channel,
        // then take over the screen with the current photo.
        if connectedTransportID != transportID {
            connectedTransportID = transportID
            Self.log.info("cast: media app ready (session \(app.sessionID ?? "unknown", privacy: .public)), opening transport channel")
            client?.send(CastMessage(
                sourceID: Self.senderID,
                destinationID: transportID,
                namespace: CastNamespace.connection,
                payloadJSON: CastPayloads.connect()
            ))
            watchdog?.cancel()
            phase = .casting
            if let photo = pendingPhoto {
                load(photo)
            }
        }
    }

    private func load(_ photo: Photo) {
        guard let lanAddress,
              let transportID = connectedTransportID,
              let url = server.url(for: photo, host: lanAddress)
        else { return }
        Self.log.info("cast: loading \(photo.displayName, privacy: .public) from \(url, privacy: .public)")
        requestID += 1
        client?.send(CastMessage(
            sourceID: Self.senderID,
            destinationID: transportID,
            namespace: CastNamespace.media,
            payloadJSON: CastPayloads.load(
                mediaURL: url,
                contentType: PhotoWebServer.contentType(forExtension: photo.url.pathExtension),
                title: photo.displayName,
                requestID: requestID
            )
        ))
    }

    // MARK: Failure

    private func fail(with message: String) {
        guard isActive else { return }
        Self.log.error("cast: session failed: \(message, privacy: .public)")
        lastError = message
        watchdog?.cancel()
        watchdog = nil
        teardown?.cancel()
        client?.stop()
        client = nil
        server.stop()
        connectedTransportID = nil
        sessionID = nil
        hasLaunched = false
        pendingPhoto = nil
        lanAddress = nil
        phase = .idle
    }

    /// Connection budget: a healthy Cast device on the LAN finishes
    /// TCP + TLS in well under a second (measured 0.04 s on a real TV),
    /// so this mostly catches advertised-but-dead services — such as a
    /// mirroring app on the TV that publishes `_googlecast._tcp`
    /// without answering CASTV2 connections. Sized to let the client's
    /// three retry attempts complete before it fires.
    var connectTimeout: Double = 6.5

    /// Launch budget: GET_STATUS + LAUNCH + the Default Media Receiver
    /// coming up. Measured ~7 s warm on a real TV, slower cold, so this
    /// is deliberately generous.
    var launchTimeout: Double = 20

    /// A receiver that never completes the current phase is not coming.
    /// The message names the phase so the menu can say what stalled.
    private func armWatchdog(seconds: Double) {
        watchdog?.cancel()
        let name = deviceName
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            switch self.phase {
            case .connecting:
                self.fail(with: "\(name ?? "The device") is not responding. Is it turned on?")
            case .launching:
                self.fail(with: "\(name ?? "The device") took too long to start the media app.")
            default:
                break
            }
        }
    }
}
