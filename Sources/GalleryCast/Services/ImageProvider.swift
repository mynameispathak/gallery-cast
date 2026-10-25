import CoreGraphics
import Foundation
import ImageIO
import os

/// A decoded image, safe to hop across concurrency domains:
/// CGImage is immutable and the wrapper is never mutated after creation.
final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    /// Rough memory footprint, used as the cache's cost value.
    var bytes: Int { cgImage.bytesPerRow * cgImage.height }
}

/// Loads and caches images off the main actor.
///
/// - Grid thumbnails: small, aggressively cached, 2x pixel density.
/// - Viewer images: decoded at screen-appropriate size so a huge
///   source file never consumes more memory than the display needs.
///
/// `prefetch(_:)` decodes a bounded batch ahead of the viewer, so a
/// slideshow's load at slide time is a cache hit rather than a cold
/// read from (possibly slow) storage.
actor ImageProvider {
    static let shared = ImageProvider()

    private static let log = Logger(subsystem: "com.aniketpathak.gallerycast", category: "images")

    private let thumbnails = NSCache<NSString, DecodedImage>()
    private let presentations = NSCache<NSString, DecodedImage>()

    init() {
        thumbnails.countLimit = 2_500
        presentations.countLimit = 24
        // A decoded presentation is screen-sized RGBA — tens of MB. The
        // count limit alone could hold ~600 MB, which invites the system
        // to evict everything under memory pressure; a byte budget
        // keeps the working set bounded on its own.
        presentations.totalCostLimit = 256 * 1_024 * 1_024
    }

    func thumbnail(for photo: Photo, side: CGFloat) -> DecodedImage? {
        image(for: photo, cache: thumbnails, maxPixel: side * 2)
    }

    func presentation(for photo: Photo, maxPixel: CGFloat) -> DecodedImage? {
        let started = Date()
        let decoded = image(for: photo, cache: presentations, maxPixel: maxPixel)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        if let decoded {
            Self.log.info(
                "images: viewer loaded \(photo.filename, privacy: .public) (\(decoded.cgImage.width)x\(decoded.cgImage.height)) in \(elapsed)ms"
            )
        } else {
            Self.log.error("images: viewer failed to load \(photo.filename, privacy: .public)")
        }
        return decoded
    }

    /// Decodes a batch for the slides (or arrow steps) that follow, so
    /// navigation lands on a warm cache. Duplicate photos collapse via
    /// the cache, and an entry whose caller was canceled is skipped.
    func prefetch(_ photos: [Photo], maxPixel: CGFloat) -> [DecodedImage?] {
        let started = Date()
        let results = photos.map { image(for: $0, cache: presentations, maxPixel: maxPixel) }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Self.log.info("images: prefetched \(photos.count) photo(s) in \(elapsed)ms")
        return results
    }

    /// Warms cast derivatives — the downscaled JPEGs the receiver will
    /// be told to fetch — for the photos the prefetch window already
    /// decoded, so the TV's GET lands on a hot cache instead of paying a
    /// decode + encode on the serving queue. Reuses the viewer's
    /// decoded presentation when it matches the derivative's pixel
    /// budget (the common case on this screen), else reads the file.
    func warmCastDerivatives(for photos: [Photo]) {
        let started = Date()
        var warmed = 0
        for photo in photos {
            // A canceled caller navigated past this window; superseded
            // work must not pile up on the actor.
            if Task.isCancelled { break }
            guard CastPhotoDerivative.cached(for: photo) == nil else { continue }
            let cgImage = presentations.object(
                forKey: cacheKey(photo, maxPixel: CastPhotoDerivative.maxPixel)
            )?.cgImage
                ?? Self.decode(url: photo.url, maxPixel: CastPhotoDerivative.maxPixel)
            if let cgImage, let jpeg = CastPhotoDerivative.encode(cgImage) {
                CastPhotoDerivative.store(jpeg, for: photo)
                warmed += 1
            }
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Self.log.info("images: warmed \(warmed) cast derivative(s) in \(elapsed)ms")
    }

    // MARK: Internals

    private func image(
        for photo: Photo, cache: NSCache<NSString, DecodedImage>, maxPixel: CGFloat
    ) -> DecodedImage? {
        let key = cacheKey(photo, maxPixel: maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        // A canceled caller no longer wants this decode — its photo was
        // navigated past — so don't let superseded requests pile up on
        // the actor and delay the one decode that matters.
        if Task.isCancelled { return nil }
        guard let cgImage = Self.decode(url: photo.url, maxPixel: maxPixel) else { return nil }
        let decoded = DecodedImage(cgImage: cgImage)
        cache.setObject(decoded, forKey: key, cost: decoded.bytes)
        return decoded
    }

    /// Cache includes the file's modification time so edits invalidate.
    private func cacheKey(_ photo: Photo, maxPixel: CGFloat) -> NSString {
        let stamp = Int(photo.modifiedDate.timeIntervalSince1970)
        return "\(photo.url.path)#\(stamp)#\(Int(maxPixel))" as NSString
    }

    /// Pure ImageIO downscale-decode: no actor state, so the cast
    /// derivative pipeline can reuse it from its own queues. EXIF
    /// orientation is baked into the pixels.
    nonisolated static func decode(url: URL, maxPixel: CGFloat) -> CGImage? {
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
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions)
    }
}
