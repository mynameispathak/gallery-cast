import Foundation
import Network
import Testing
@testable import GalleryCast

/// The AppModel wiring that casting depends on: `startCasting` opens a
/// viewer, the viewer's didSet mirrors every photo, and closing the
/// viewer ends the session.
@MainActor
@Suite
struct CastAppModelTests {

    @Test func startCastingWithoutAFolderIsANoOp() {
        let model = AppModel()
        model.startCasting(CastDevice(
            name: "Nowhere TV",
            endpoint: .hostPort(host: .ipv4(IPv4Address.loopback), port: 8009)
        ))
        #expect(!model.casting.isActive)
        #expect(model.viewerPhoto == nil)
    }

    @Test func castingOpensTheViewerAndClosingItEndsTheSession() async throws {
        let (folder, _) = try makePhotoFolder(["photo-01.jpg", "photo-02.jpg"])
        let fake = FakeCastReceiver()
        try fake.start()
        defer { fake.stop() }

        let model = AppModel()
        model.openFolder(folder)
        let scanned = await waitUntil { !model.filteredPhotos.isEmpty }
        #expect(scanned)

        model.startCasting(CastDevice(
            name: "Test TV",
            endpoint: .hostPort(
                host: .ipv4(IPv4Address.loopback),
                port: NWEndpoint.Port(rawValue: fake.port)!
            )
        ), useTLS: false)

        // Casting needs something to mirror: the viewer is open.
        #expect(model.casting.phase == .connecting)
        #expect(model.viewerPhoto != nil)

        // Complete the receiver handshake like a real device would.
        let sawStatus = await waitUntil {
            fake.received().contains { $0.namespace == CastNamespace.receiver }
        }
        #expect(sawStatus)
        fake.send(CastMessage(
            sourceID: "receiver-0",
            destinationID: "sender-0",
            namespace: CastNamespace.receiver,
            payloadJSON: #"{"requestId":1,"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","sessionId":"sess-1","transportId":"transport-1"}]}}"#
        ))

        let casting = await waitUntil { model.casting.isCasting }
        #expect(casting)

        // The viewer's close is the hook that ends the mirror.
        model.closeViewer()
        #expect(model.casting.phase == .idle)
    }

    // MARK: Launch argument parsing

    @Test func launchArgumentsAcceptCastAndPlayInAnyOrder() throws {
        let folder = try makeTemporaryFolder()

        // `play cast BRAVIA` — the order this regression was found in.
        let castAfterPlay = AppModel.parseLaunchArguments(
            [folder.path, "play", "cast", "bravia"]
        )
        #expect(castAfterPlay?.castDeviceName == "bravia")
        #expect(castAfterPlay?.slideshow == true)

        // `cast BRAVIA play` — the previously documented order.
        let castBeforePlay = AppModel.parseLaunchArguments(
            [folder.path, "cast", "bravia", "play"]
        )
        #expect(castBeforePlay?.castDeviceName == "bravia")
        #expect(castBeforePlay?.slideshow == true)
    }

    @Test func launchArgumentsCastWithoutANameAcceptsAnyDevice() throws {
        let folder = try makeTemporaryFolder()
        let options = AppModel.parseLaunchArguments([folder.path, "cast"])
        #expect(options?.castDeviceName == "")
    }

    @Test func launchArgumentsDoNotMistakeAFlagForACastName() throws {
        let folder = try makeTemporaryFolder()
        let options = AppModel.parseLaunchArguments([folder.path, "cast", "play"])
        #expect(options?.castDeviceName == "")
        #expect(options?.slideshow == true)
    }

    @Test func launchArgumentsStillParseIndexAndInfo() throws {
        let folder = try makeTemporaryFolder()
        let options = AppModel.parseLaunchArguments([folder.path, "4", "info"])
        #expect(options?.viewerIndex == 4)
        #expect(options?.infoPanel == true)
        #expect(options?.castDeviceName == nil)
    }

    private func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-appmodel-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
