import Foundation
import Network
import Testing
@testable import GalleryCast

@Suite
struct CastTransportTests {

    // MARK: Discovery mapping

    @Test func discoveryMapsServiceEndpointsSortedByName() {
        let livingRoom = NWEndpoint.service(name: "Living Room", type: "_googlecast._tcp", domain: "local.", interface: nil)
        let bedroom = NWEndpoint.service(name: "Bedroom TV", type: "_googlecast._tcp", domain: "local.", interface: nil)
        let devices = CastDiscoveryService.devices(from: [livingRoom, bedroom])
        #expect(devices.map(\.name) == ["Bedroom TV", "Living Room"])
        #expect(devices.map(\.endpoint) == [bedroom, livingRoom])
    }

    @Test func discoverySkipsNonServiceEndpoints() {
        let endpoints: [NWEndpoint] = [
            .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: 8009),
        ]
        #expect(CastDiscoveryService.devices(from: endpoints).isEmpty)
    }

    // MARK: LAN address selection

    @Test func bestAddressPrefersTheInterfaceSharingTheDeviceSubnet() {
        let interfaces = [
            LocalAddress.Interface(name: "lo0", address: "127.0.0.1", netmask: "255.0.0.0"),
            LocalAddress.Interface(name: "en0", address: "192.168.1.5", netmask: "255.255.255.0"),
            LocalAddress.Interface(name: "en1", address: "10.0.0.7", netmask: "255.0.0.0"),
        ]
        #expect(
            LocalAddress.bestAddress(interfaces: interfaces, deviceIPv4: "192.168.1.42") == "192.168.1.5"
        )
        #expect(
            LocalAddress.bestAddress(interfaces: interfaces, deviceIPv4: "10.9.9.9") == "10.0.0.7"
        )
    }

    @Test func bestAddressFallsBackToARealInterfaceWhenSubnetsDiffer() {
        let interfaces = [
            LocalAddress.Interface(name: "lo0", address: "127.0.0.1", netmask: "255.0.0.0"),
            LocalAddress.Interface(name: "en0", address: "192.168.1.5", netmask: "255.255.255.0"),
        ]
        #expect(
            LocalAddress.bestAddress(interfaces: interfaces, deviceIPv4: "172.16.0.9") == "192.168.1.5"
        )
    }

    @Test func bestAddressRejectsGarbageDeviceIPs() {
        let interfaces = [
            LocalAddress.Interface(name: "en0", address: "192.168.1.5", netmask: "255.255.255.0"),
        ]
        #expect(LocalAddress.bestAddress(interfaces: interfaces, deviceIPv4: "not-an-ip") == "192.168.1.5")
        #expect(LocalAddress.bestAddress(interfaces: [], deviceIPv4: "192.168.1.42") == nil)
    }

    @Test func bestAddressUsesLoopbackForLoopbackDevices() {
        let interfaces = [
            LocalAddress.Interface(name: "lo0", address: "127.0.0.1", netmask: "255.0.0.0"),
            LocalAddress.Interface(name: "en0", address: "192.168.1.5", netmask: "255.255.255.0"),
        ]
        #expect(
            LocalAddress.bestAddress(interfaces: interfaces, deviceIPv4: "127.0.0.1") == "127.0.0.1"
        )
    }

    @Test func liveInterfacesIncludeLoopback() {
        #expect(LocalAddress.interfaces().contains { $0.name == "lo0" })
    }

    // MARK: Photo URLs and content types

    @Test func photoURLEscapesEverythingButUnreservedCharacters() {
        let url = PhotoWebServer.url(for: "family trip (1).jpg", host: "192.168.1.5", port: 8096)
        #expect(url?.absoluteString == "http://192.168.1.5:8096/family%20trip%20%281%29.jpg")

        let plain = PhotoWebServer.url(for: "photo-01.jpg", host: "192.168.1.5", port: 8096)
        #expect(plain?.absoluteString == "http://192.168.1.5:8096/photo-01.jpg")
    }

    @Test func contentTypeCoversSupportedPhotoFormats() {
        #expect(PhotoWebServer.contentType(forExtension: "jpg") == "image/jpeg")
        #expect(PhotoWebServer.contentType(forExtension: "JPG") == "image/jpeg")
        #expect(PhotoWebServer.contentType(forExtension: "jpeg") == "image/jpeg")
        #expect(PhotoWebServer.contentType(forExtension: "png") == "image/png")
        #expect(PhotoWebServer.contentType(forExtension: "heic") == "image/heic")
        #expect(PhotoWebServer.contentType(forExtension: "webp") == "image/webp")
        #expect(PhotoWebServer.contentType(forExtension: "gif") == "image/gif")
        #expect(PhotoWebServer.contentType(forExtension: "tif") == "image/tiff")
        #expect(PhotoWebServer.contentType(forExtension: "bmp") == "image/bmp")
        #expect(PhotoWebServer.contentType(forExtension: "avif") == "image/avif")
        #expect(PhotoWebServer.contentType(forExtension: "xyz") == "application/octet-stream")
    }

    // MARK: Photo web server

    @MainActor
    @Test func webServerServesPhotoBytesWithCorrectHeaders() async throws {
        let (folder, payload) = try temporaryPhotoFolder()
        let server = PhotoWebServer()
        let port = try await server.start(folder: folder)
        defer { server.stop() }

        let url = PhotoWebServer.url(for: "photo-01.jpg", host: "127.0.0.1", port: port)!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.mimeType == "image/jpeg")
        #expect(data == payload)
    }

    @MainActor
    @Test func webServerAnswersMissingFilesWith404() async throws {
        let (folder, _) = try temporaryPhotoFolder()
        let server = PhotoWebServer()
        let port = try await server.start(folder: folder)
        defer { server.stop() }

        let url = PhotoWebServer.url(for: "missing.jpg", host: "127.0.0.1", port: port)!
        let (_, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }

    /// Percent-encoded traversal must not be normalized away by any HTTP
    /// client before it reaches the server's own guard.
    @MainActor
    @Test func webServerRefusesTraversalAndSubdirectories() async throws {
        let (folder, _) = try temporaryPhotoFolder()
        let server = PhotoWebServer()
        let port = try await server.start(folder: folder)
        defer { server.stop() }

        for path in ["/%2e%2e/secret.jpg", "/sub/photo.jpg", "/.DS_Store"] {
            let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
            let (_, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode
            #expect(status == 403 || status == 404)
        }
    }

    @MainActor
    @Test func webServerRefusesNonGETRequests() async throws {
        let (folder, _) = try temporaryPhotoFolder()
        let server = PhotoWebServer()
        let port = try await server.start(folder: folder)
        defer { server.stop() }

        var request = URLRequest(url: PhotoWebServer.url(for: "photo-01.jpg", host: "127.0.0.1", port: port)!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
    }

    // MARK: CASTV2 client

    @Test func clientSendsFramesAndAnswersPings() async throws {
        let fake = FakeCastReceiver()
        try fake.start()
        defer { fake.stop() }

        let client = CastV2Client(
            endpoint: .hostPort(
                host: .ipv4(IPv4Address.loopback),
                port: NWEndpoint.Port(rawValue: fake.port)!
            ),
            useTLS: false
        )
        client.start()
        defer { client.stop() }

        client.send(CastMessage(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: CastNamespace.connection,
            payloadJSON: CastPayloads.connect()
        ))

        let sawConnect = await waitUntil {
            fake.received().contains { $0.namespace == CastNamespace.connection }
        }
        #expect(sawConnect)

        // The device pings; the client must answer with a PONG reflex.
        fake.send(CastMessage(
            sourceID: "receiver-0",
            destinationID: "sender-0",
            namespace: CastNamespace.heartbeat,
            payloadJSON: CastPayloads.ping()
        ))

        let sawPong = await waitUntil {
            fake.received().contains {
                $0.namespace == CastNamespace.heartbeat
                    && $0.payloadString == CastPayloads.pong()
            }
        }
        #expect(sawPong)
    }

    // MARK: Helpers

    private func temporaryPhotoFolder() throws -> (URL, Data) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-cast-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let payload = Data("jpeg-bytes-\(UUID().uuidString)".utf8)
        try payload.write(to: folder.appendingPathComponent("photo-01.jpg"))
        return (folder, payload)
    }
}
