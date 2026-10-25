import Foundation
import Network
import os
import Security

/// One socket to a Cast device: TLS (plain TCP in tests), CASTV2 frame
/// handling, and the heartbeat reflex that keeps the connection alive.
/// Protocol *semantics* — what to send, and when — live one layer up in
/// `CastSessionController`.
///
/// Connection state is confined to `queue` (the first connection is
/// created on the caller's thread before any queue work exists);
/// callers may touch the instance from any isolation domain but must
/// set the callbacks before `start()`.
///
/// An attempt that reaches no verdict within `attemptBudget` is
/// discarded and re-opened, up to `maxAttempts` times: a stalled mDNS
/// resolution or a badly scoped route can leave `NWConnection` silent
/// in `.preparing` forever, and a fresh connection re-runs both.
/// Observed on a real TV: the first attempt from a freshly launched
/// process stalls, while the next one connects in milliseconds.
final class CastV2Client: @unchecked Sendable {

    private static let log = Logger(subsystem: "com.aniketpathak.gallerycast", category: "cast")

    enum State: Sendable {
        case ready(remoteIPv4: String?)
        case failed(String)
        case cancelled
    }

    /// Inbound messages, on the client's queue. Heartbeat PINGs never
    /// arrive here — they are answered by reflex inside the client.
    var onMessage: (@Sendable (CastMessage) -> Void)?
    var onStateChange: (@Sendable (State) -> Void)?

    private let endpoint: NWEndpoint
    private let useTLS: Bool
    private let queue = DispatchQueue(label: "gallerycast.castv2")
    private let buffer = MessageBuffer()
    private var connection: NWConnection?
    private var attempt = 0

    /// Per-attempt budget before the attempt is considered stalled.
    private static let attemptBudget: TimeInterval = 2

    /// Total attempts, including the first. Three 2-second attempts fit
    /// inside the session controller's connect watchdog.
    private static let maxAttempts = 3

    /// - Parameters:
    ///   - endpoint: device to connect to (Bonjour service or host:port).
    ///   - useTLS: production CASTV2 is TLS; tests use plain TCP against
    ///     a loopback receiver.
    init(endpoint: NWEndpoint, useTLS: Bool = true) {
        self.endpoint = endpoint
        self.useTLS = useTLS
    }

    func start() {
        openConnection()
    }

    func stop() {
        queue.async {
            self.connection?.cancel()
            self.connection = nil
        }
    }

    func send(_ message: CastMessage) {
        queue.async {
            self.connection?.send(
                content: message.encoded(),
                completion: .contentProcessed { _ in }
            )
        }
    }

    // MARK: Connection lifecycle

    private func openConnection() {
        let parameters: NWParameters
        if useTLS {
            let tls = NWProtocolTLS.Options()
            // Cast devices identify with self-signed certificates; the
            // protocol's security model is the LAN, not a cert chain.
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, _, complete in complete(true) },
                queue
            )
            parameters = NWParameters(tls: tls)
        } else {
            parameters = NWParameters.tcp
        }

        attempt += 1
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            self?.handle(state, on: connection)
        }
        Self.log.info(
            "cast: transport attempt \(self.attempt) connecting to \(String(describing: self.endpoint), privacy: .public)"
        )
        connection.start(queue: queue)

        // Stall guard: unless this attempt is ready by now, throw it
        // away and open a fresh one.
        queue.asyncAfter(deadline: .now() + Self.attemptBudget) { [weak self, weak connection] in
            guard let self, let connection, connection === self.connection else { return }
            guard case .ready = connection.state else {
                if self.attempt < Self.maxAttempts {
                    Self.log.notice("cast: transport attempt \(self.attempt) stalled, retrying")
                    connection.cancel()
                    self.openConnection()
                }
                return
            }
        }
    }

    private func handle(_ state: NWConnection.State, on connection: NWConnection?) {
        guard let connection, connection === self.connection else { return }
        switch state {
        case .ready:
            Self.log.info(
                "cast: transport ready via \(connection.currentPath.map { "\($0)" } ?? "?", privacy: .public)"
            )
            onStateChange?(.ready(remoteIPv4: self.remoteIPv4(of: connection)))
            receiveNext(on: connection)
        case .failed(let error):
            Self.log.error("cast: transport failed: \(String(describing: error), privacy: .public)")
            onStateChange?(.failed(error.localizedDescription))
        case .waiting(let error):
            Self.log.notice("cast: transport waiting: \(String(describing: error), privacy: .public)")
        case .preparing:
            Self.log.info("cast: transport preparing")
        case .setup:
            Self.log.info("cast: transport setup")
        case .cancelled:
            Self.log.info("cast: transport cancelled")
            onStateChange?(.cancelled)
        @unknown default:
            break
        }
    }

    // MARK: Receive loop

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.data.append(data)
                for message in CastMessage.decodeFrames(from: &self.buffer.data) {
                    self.handleMessage(message)
                }
            }
            if let error {
                self.onStateChange?(.failed(error.localizedDescription))
            } else {
                self.receiveNext(on: connection)
            }
        }
    }

    private func handleMessage(_ message: CastMessage) {
        // Heartbeat reflex: the wire stays alive without any higher
        // layer knowing about it.
        if message.namespace == CastNamespace.heartbeat,
           CastPayloads.messageType(of: message.payloadString ?? "") == "PING" {
            send(CastMessage(
                sourceID: message.destinationID,
                destinationID: message.sourceID,
                namespace: CastNamespace.heartbeat,
                payloadJSON: CastPayloads.pong()
            ))
            return
        }
        onMessage?(message)
    }

    private func remoteIPv4(of connection: NWConnection) -> String? {
        guard case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint,
              case .ipv4(let address) = host
        else { return nil }
        return "\(address)"
    }
}

/// Receive-buffer cell. Mutated only on the client's serial queue.
private final class MessageBuffer: @unchecked Sendable {
    var data = Data()
}
