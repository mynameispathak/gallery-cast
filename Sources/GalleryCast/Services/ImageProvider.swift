import CoreGraphics
import Foundation
import ImageIO

/// A decoded image, safe to hop across concurrency domains:
/// CGImage is immutable and the wrapper is never mutated after creation.
final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// Loads and caches images off the main actor.
///
/// - Grid thumbnails: small, aggressively cached, 2x pixel density.
/// - Viewer images: decoded at screen-appropriate size so a huge
///   source file never consumes more memory than the display needs.
actor ImageProvider {
    static let shared = ImageProvider()

    private let thumbnails = NSCache<NSString, DecodedImage>()
    private let presentations = NSCache<NSString, DecodedImage>()

    init() {
        thumbnails.countLimit = 2_500
        presentations.countLimit = 24
    }

    func thumbnail(for photo: Photo, side: CGFloat) -> DecodedImage? {
        // 2x pixel density keeps grid cells crisp on retina displays.
        image(for: photo, cache: thumbnails, maxPixel: side * 2)
    }

    func presentation(for photo: Photo, maxPixel: CGFloat) -> DecodedImage? {
        image(for: photo, cache: presentations, maxPixel: maxPixel)
    }

    // MARK: Internals

    private func image(
        for photo: Photo, cache: NSCache<NSString, DecodedImage>, maxPixel: CGFloat
    ) -> DecodedImage? {
        let key = cacheKey(photo, maxPixel: maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        guard let decoded = decode(url: photo.url, maxPixel: maxPixel) else { return nil }
        cache.setObject(decoded, forKey: key)
        return decoded
    }

    /// Cache includes the file's modification time so edits invalidate.
    private func cacheKey(_ photo: Photo, maxPixel: CGFloat) -> NSString {
        let stamp = Int(photo.modifiedDate.timeIntervalSince1970)
        return "\(photo.url.path)#\(stamp)#\(Int(maxPixel))" as NSString
    }

    private func decode(url: URL, maxPixel: CGFloat) -> DecodedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, off the main actor, so rendering stays cheap.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
            return nil
        }
        return DecodedImage(cgImage: cgImage)
    }
}
