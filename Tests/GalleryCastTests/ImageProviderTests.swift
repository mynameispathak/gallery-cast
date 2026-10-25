import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GalleryCast

/// The viewer's decode pipeline: decode-and-cache identity, prefetch
/// warming, and graceful failure on unreadable files.
@Suite
struct ImageProviderTests {

    @Test func presentationDecodesAndCachesByIdentity() async throws {
        let folder = makeImageFolder()
        let photo = try makePhotoFile(in: folder, name: "cache-test.jpg")
        let provider = ImageProvider()

        let first = try #require(await provider.presentation(for: photo, maxPixel: 64))
        let second = try #require(await provider.presentation(for: photo, maxPixel: 64))

        // The second load must be the same object, not another decode.
        #expect(first === second)
        #expect(first.bytes > 0)
        #expect(max(first.cgImage.width, first.cgImage.height) <= 64)
    }

    @Test func prefetchWarmsThePresentationCache() async throws {
        let folder = makeImageFolder()
        let photo = try makePhotoFile(in: folder, name: "prefetch-test.jpg")
        let provider = ImageProvider()

        let prefetched = await provider.prefetch([photo], maxPixel: 64)
        let warmed = try #require(prefetched.first ?? nil)

        // The viewer's load for the same photo must return the exact
        // object the prefetch cached: the slideshow tick is a cache
        // hit, not another decode.
        let loaded = try #require(await provider.presentation(for: photo, maxPixel: 64))
        #expect(loaded === warmed)
    }

    @Test func prefetchReportsFailuresWithoutCachingThem() async throws {
        let folder = makeImageFolder()
        let missing = Photo(
            url: folder.appendingPathComponent("missing.jpg"),
            byteSize: 0,
            modifiedDate: Date()
        )
        let provider = ImageProvider()

        let prefetched = await provider.prefetch([missing], maxPixel: 64)
        #expect(prefetched.count == 1)
        #expect(prefetched[0] == nil)
        #expect(await provider.presentation(for: missing, maxPixel: 64) == nil)
    }

    @Test func warmCastDerivativesTurnsPresentationsIntoServedJPEGs() async throws {
        let folder = makeImageFolder()
        let photo = try makePhotoFile(in: folder, name: "cast-warm-test.jpg")
        let provider = ImageProvider()

        // The slideshow already decoded this photo at the cast budget;
        // warming must turn those pixels into the JPEG the photo server
        // serves — no second read of the file.
        _ = try #require(await provider.presentation(for: photo, maxPixel: CastPhotoDerivative.maxPixel))
        await provider.warmCastDerivatives(for: [photo])

        let jpeg = try #require(CastPhotoDerivative.cached(for: photo))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width > 0 && decoded.height > 0)
    }

    // MARK: Fixtures

    private func makeImageFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-image-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a real (tiny) JPEG so the decode path has actual bytes to work with.
    private func makePhotoFile(in folder: URL, name: String) throws -> Photo {
        let side = 96
        let context = try #require(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.75, green: 0.45, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let cgImage = try #require(context.makeImage())

        let url = folder.appendingPathComponent(name)
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
            )
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return Photo(
            url: url,
            byteSize: attributes[.size] as? Int64 ?? 0,
            modifiedDate: attributes[.modificationDate] as? Date ?? Date()
        )
    }
}
