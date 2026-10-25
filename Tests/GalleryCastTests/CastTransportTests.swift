import CoreGraphics
import Foundation
import ImageIO
import Network
import Testing
import UniformTypeIdentifiers
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
        #expect(url?.absoluteString == "http://192.168.1.5:8096/cast/family%20trip%20%281%29.jpg")

        let plain = PhotoWebServer.url(for: "photo-01.jpg", host: "192.168.1.5", port: 8096)
        #expect(plain?.absoluteString == "http://192.168.1.5:8096/cast/photo-01.jpg")
    }

    // MARK: Photo web server

    @MainActor
    @Test func webServerServesDownscaledCastDerivative() async throws {
        let (folder, original) = try temporaryPhotoFolder(
            name: "photo-01.jpg", width: 4000, height: 2500
        )
        let server = PhotoWebServer()
        let port = try await server.start(folder: folder)
        defer { server.stop() }

        let url = PhotoWebServer.url(for: "photo-01.jpg", host: "127.0.0.1", port: port)!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.mimeType == "image/jpeg")
        // A re-encoded derivative, never the original file bytes…
        #expect(data != original)

        // …and a downscaled one: the long edge obeys the cast budget.
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(decoded.width, decoded.height) <= Int(CastPhotoDerivative.maxPixel))
        #expect(max(decoded.width, decoded.height) < 4000)
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

        for path in [
            "/cast/../secret.jpg", "/cast/sub/photo.jpg", "/cast/.hidden.jpg",
            "/%2e%2e/secret.jpg", "/sub/photo.jpg", "/.DS_Store",
        ] {
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

    /// The derivative cache keys on the file's mtime: replacing the
    /// photo regenerates what the server serves.
    @MainActor
    @Test func derivativeServesFreshBytesAfterThePhotoChanges() async throws {
        let (folder, _) = try temporaryPhotoFolder(
            name: "photo-01.jpg", width: 200, height: 100, color: (0.1, 0.2, 0.3)
        )
        let server = PhotoWebServer()
        let port = try await server.start(folder: folder)
        defer { server.stop() }

        let url = PhotoWebServer.url(for: "photo-01.jpg", host: "127.0.0.1", port: port)!
        let (first, _) = try await URLSession.shared.data(from: url)

        // Different pixels, and an mtime delta the second-granularity
        // cache key can see.
        try await Task.sleep(for: .seconds(1.2))
        _ = try makeJPEG(
            width: 200, height: 100, color: (0.9, 0.8, 0.7), orientation: nil,
            writingTo: folder.appendingPathComponent("photo-01.jpg")
        )
        let (second, _) = try await URLSession.shared.data(from: url)
        #expect(second != first)
    }

    /// EXIF orientation is baked into the derivative's pixels, so the
    /// TV needs no metadata support to show the photo upright.
    @MainActor
    @Test func derivativeBakesEXIFOrientationIntoPixels() async throws {
        let (folder, _) = try temporaryPhotoFolder(
            name: "photo-01.jpg", width: 800, height: 400, orientation: 6
        )
        let server = PhotoWebServer()
        let port = try await server.start(folder: folder)
        defer { server.stop() }

        let url = PhotoWebServer.url(for: "photo-01.jpg", host: "127.0.0.1", port: port)!
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        // Decoding without applying any EXIF transform still yields
        // the rotated shape: the pixels themselves are portrait.
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.height > decoded.width)
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

    /// A folder holding one real JPEG, so the derivative pipeline has
    /// actual image bytes to downscale and re-encode.
    private func temporaryPhotoFolder(
        name: String = "photo-01.jpg",
        width: Int = 200,
        height: Int = 150,
        color: (CGFloat, CGFloat, CGFloat) = (0.2, 0.4, 0.6),
        orientation: Int? = nil
    ) throws -> (URL, Data) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-cast-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let payload = try makeJPEG(
            width: width, height: height, color: color, orientation: orientation,
            writingTo: folder.appendingPathComponent(name)
        )
        return (folder, payload)
    }

    private func makeJPEG(
        width: Int,
        height: Int,
        color: (CGFloat, CGFloat, CGFloat),
        orientation: Int?,
        writingTo url: URL
    ) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try #require(context.makeImage())

        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
            )
        )
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return try Data(contentsOf: url)
    }
}
