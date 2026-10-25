import Foundation
import Network
import Testing
@testable import GalleryCast

/// Full-session flow against a loopback fake receiver: connect,
/// launch-or-adopt the media app, mirror the current photo, follow
/// navigation, and stop when the viewer closes.
@MainActor
@Suite
struct CastSessionTests {

    @Test func sessionCastsCurrentPhotoAndMirrorsNavigation() async throws {
        let (folder, payloads) = try temporaryPhotoFolder(names: ["photo-01.jpg", "photo-02.jpg"])
        let fake = FakeCastReceiver()
        try fake.start()
        defer { fake.stop() }

        let session = CastSessionController()
        session.start(
            device: testDevice(port: fake.port),
            folder: folder,
            currentPhoto: photo(named: "photo-01.jpg", in: folder, payloads: payloads),
            useTLS: false
        )
        #expect(session.phase == .connecting)

        // Handshake: the session asks the receiver for its status.
        let sawStatusRequest = await waitUntil {
            fake.received().contains { $0.namespace == CastNamespace.receiver }
        }
        #expect(sawStatusRequest)

        // Reply: the Default Media Receiver is already running.
        fake.send(receiverStatus(appRunning: true))

        let sawLoad = await waitUntil {
            fake.received().contains {
                $0.namespace == CastNamespace.media
                    && CastPayloads.messageType(of: $0.payloadString ?? "") == "LOAD"
            }
        }
        #expect(sawLoad)
        #expect(session.phase == .casting)

        // The LOAD goes to the app's transport channel…
        let loadMessage = try #require(
            fake.received().last { $0.namespace == CastNamespace.media }
        )
        #expect(loadMessage.destinationID == "transport-1")

        // …and the URL it names actually serves the photo's bytes.
        let contentID = try #require(mediaContentID(of: loadMessage.payloadString))
        let (data, response) = try await URLSession.shared.data(from: URL(string: contentID)!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == payloads["photo-01.jpg"])

        // Navigating in the viewer mirrors to the TV.
        session.mirror(photo(named: "photo-02.jpg", in: folder, payloads: payloads))
        let sawSecondLoad = await waitUntil {
            fake.received().contains {
                $0.namespace == CastNamespace.media
                    && ($0.payloadString ?? "").contains("photo-02.jpg")
            }
        }
        #expect(sawSecondLoad)

        // Closing the viewer stops the session.
        session.mirror(nil)
        #expect(session.phase == .idle)
    }

    @Test func sessionLaunchesTheMediaAppOnAnIdleReceiver() async throws {
        let (folder, payloads) = try temporaryPhotoFolder(names: ["photo-01.jpg"])
        let fake = FakeCastReceiver()
        try fake.start()
        defer { fake.stop() }

        let session = CastSessionController()
        session.start(
            device: testDevice(port: fake.port),
            folder: folder,
            currentPhoto: photo(named: "photo-01.jpg", in: folder, payloads: payloads),
            useTLS: false
        )

        let sawStatusRequest = await waitUntil {
            fake.received().contains { $0.namespace == CastNamespace.receiver }
        }
        #expect(sawStatusRequest)

        // Idle receiver: nothing is running yet.
        fake.send(receiverStatus(appRunning: false))

        let sawLaunch = await waitUntil {
            fake.received().contains {
                $0.namespace == CastNamespace.receiver
                    && CastPayloads.messageType(of: $0.payloadString ?? "") == "LAUNCH"
            }
        }
        #expect(sawLaunch)
        #expect(session.phase == .launching)

        // The app comes up.
        fake.send(receiverStatus(appRunning: true))

        let sawLoad = await waitUntil {
            fake.received().contains {
                $0.namespace == CastNamespace.media
                    && CastPayloads.messageType(of: $0.payloadString ?? "") == "LOAD"
            }
        }
        #expect(sawLoad)
        #expect(session.phase == .casting)

        session.stop()
        #expect(session.phase == .idle)
    }

    @Test func sessionFailsFastWhenTheReceiverAcceptsButNeverAnswers() async throws {
        let (folder, payloads) = try temporaryPhotoFolder(names: ["photo-01.jpg"])
        let fake = FakeCastReceiver()
        try fake.start()
        defer { fake.stop() }

        let session = CastSessionController()
        session.connectTimeout = 0.5
        session.launchTimeout = 0.5
        session.start(
            device: testDevice(port: fake.port),
            folder: folder,
            currentPhoto: photo(named: "photo-01.jpg", in: folder, payloads: payloads),
            useTLS: false
        )

        // The socket is accepted but GET_STATUS is never answered.
        let failed = await waitUntil(timeout: 5) {
            session.phase == .idle && session.lastError != nil
        }
        #expect(failed)
        #expect(session.lastError == "Test TV is not responding. Is it turned on?")
    }

    @Test func sessionFailsWhenTheMediaAppNeverComesUp() async throws {
        let (folder, payloads) = try temporaryPhotoFolder(names: ["photo-01.jpg"])
        let fake = FakeCastReceiver()
        try fake.start()
        defer { fake.stop() }

        let session = CastSessionController()
        session.launchTimeout = 0.5
        session.start(
            device: testDevice(port: fake.port),
            folder: folder,
            currentPhoto: photo(named: "photo-01.jpg", in: folder, payloads: payloads),
            useTLS: false
        )

        let sawStatusRequest = await waitUntil {
            fake.received().contains { $0.namespace == CastNamespace.receiver }
        }
        #expect(sawStatusRequest)

        // Idle receiver: the session launches the media app…
        fake.send(receiverStatus(appRunning: false))
        let sawLaunch = await waitUntil {
            fake.received().contains {
                $0.namespace == CastNamespace.receiver
                    && CastPayloads.messageType(of: $0.payloadString ?? "") == "LAUNCH"
            }
        }
        #expect(sawLaunch)
        #expect(session.phase == .launching)

        // …but the app never appears, so the watchdog ends the wait.
        let failed = await waitUntil(timeout: 5) {
            session.phase == .idle && session.lastError != nil
        }
        #expect(failed)
        #expect(session.lastError == "Test TV took too long to start the media app.")
    }

    // MARK: Fixtures

    private func testDevice(port: UInt16) -> CastDevice {
        CastDevice(
            name: "Test TV",
            endpoint: .hostPort(
                host: .ipv4(IPv4Address.loopback),
                port: NWEndpoint.Port(rawValue: port)!
            )
        )
    }

    private func receiverStatus(appRunning: Bool) -> CastMessage {
        let apps = appRunning
            ? #"[{"appId":"CC1AD845","displayName":"Default Media Receiver","sessionId":"sess-1","transportId":"transport-1"}]"#
            : "[]"
        return CastMessage(
            sourceID: "receiver-0",
            destinationID: "sender-0",
            namespace: CastNamespace.receiver,
            payloadJSON: #"{"requestId":1,"type":"RECEIVER_STATUS","status":{"applications":\#(apps)}}"#
        )
    }

    private func photo(named name: String, in folder: URL, payloads: [String: Data]) -> Photo {
        Photo(
            url: folder.appendingPathComponent(name),
            byteSize: Int64(payloads[name]?.count ?? 0),
            modifiedDate: Date()
        )
    }

    private func mediaContentID(of payloadJSON: String?) -> String? {
        guard let json = payloadJSON?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let media = object["media"] as? [String: Any]
        else { return nil }
        return media["contentId"] as? String
    }

    private func temporaryPhotoFolder(names: [String]) throws -> (URL, [String: Data]) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-cast-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var payloads: [String: Data] = [:]
        for name in names {
            let payload = Data("cast-test-bytes-\(name)".utf8)
            try payload.write(to: folder.appendingPathComponent(name))
            payloads[name] = payload
        }
        return (folder, payloads)
    }
}
