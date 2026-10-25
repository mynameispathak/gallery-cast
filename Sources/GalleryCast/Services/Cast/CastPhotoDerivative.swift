import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The JPEG a Cast receiver is told to fetch: the original photo
/// downscaled to TV-appropriate pixels and re-encoded, so a 10 MB
/// 12-megapixel original becomes a few hundred kilobytes a TV can
/// download and decode in well under a second.
///
/// EXIF orientation is baked into the pixels, so receivers that ignore
/// EXIF still show the photo upright — and HEIC sources come out as
/// the JPEG every receiver can decode.
///
/// The cache is shared by two producers on purpose. ImageProvider warms
/// derivatives from the slideshow's prefetch window on its actor; the
/// photo server generates on demand on its serial queue when the
/// receiver's GET arrives before the warm pass did. Whoever finishes
/// first populates the cache and the other side becomes a hit.
enum CastPhotoDerivative {
    /// A 4K panel fits 2160 rows; 2880 on the long edge covers it with
    /// margin while keeping the JPEG small — and matches the viewer's
    /// decode budget on a 1440 pt screen, so warming can reuse pixels
    /// the slideshow pipeline has already decoded.
    static let maxPixel: CGFloat = 2880

    /// Every derivative is a JPEG, whatever the source file was.
    static let contentType = "image/jpeg"

    private static let cache = DerivativeCache()

    /// Cache-or-generate for the serving path, callable from any queue.
    /// The receiver's GET either lands on a derivative the warm pass
    /// already produced, or pays one decode + encode here.
    static func jpeg(for fileURL: URL, modified: Date) -> Data? {
        let key = cacheKey(path: fileURL.path, modified: modified)
        if let hit = cache.storage.object(forKey: key) { return hit as Data }
        guard let cgImage = ImageProvider.decode(url: fileURL, maxPixel: maxPixel),
              let jpeg = encode(cgImage)
        else { return nil }
        cache.storage.setObject(jpeg as NSData, forKey: key, cost: jpeg.count)
        return jpeg
    }

    /// The warm pass's view of the cache.
    static func cached(for photo: Photo) -> Data? {
        cache.storage.object(forKey: cacheKey(photo)) as Data?
    }

    /// Stores a derivative the warm pass produced.
    static func store(_ jpeg: Data, for photo: Photo) {
        cache.storage.setObject(jpeg as NSData, forKey: cacheKey(photo), cost: jpeg.count)
    }

    /// Re-encodes already-decoded pixels as JPEG.
    static func encode(_ cgImage: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.8,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Same shape as ImageProvider's cache keys: the file's mtime means
    /// an edited photo invalidates its derivative on the next fetch.
    private static func cacheKey(_ photo: Photo) -> NSString {
        cacheKey(path: photo.url.path, modified: photo.modifiedDate)
    }

    private static func cacheKey(path: String, modified: Date) -> NSString {
        "\(path)#\(Int(modified.timeIntervalSince1970))#\(Int(maxPixel))" as NSString
    }

    /// NSCache is thread-safe but not Sendable-annotated; the unchecked
    /// conformance documents exactly that guarantee for the compiler.
    private final class DerivativeCache: @unchecked Sendable {
        let storage = NSCache<NSString, NSData>()

        init() {
            // Derivatives run a few hundred KB each; keep the cast
            // working set well below the presentation cache's budget.
            storage.countLimit = 64
            storage.totalCostLimit = 128 * 1_024 * 1_024
        }
    }
}
