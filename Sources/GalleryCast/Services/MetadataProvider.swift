import Foundation
import ImageIO

/// EXIF-derived presentation data for a photo. Every field is optional:
/// photos without EXIF (screenshots, exports) simply show fewer rows.
struct PhotoMetadata: Sendable, Equatable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var takenDate: Date?
    var cameraModel: String?
    var lensModel: String?
    var iso: Int?
    var aperture: Double?
    var shutterSeconds: Double?
    var focalLengthMM: Double?

    var megapixels: Double? {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }
        return Double(pixelWidth * pixelHeight) / 1_000_000
    }
}

/// Reads image metadata off the main actor, with a small in-memory cache
/// so toggling the info panel on and off never re-parses EXIF.
actor MetadataProvider {
    static let shared = MetadataProvider()

    private var cache: [String: PhotoMetadata] = [:]

    func metadata(for photo: Photo) -> PhotoMetadata? {
        let key = cacheKey(photo)
        if let hit = cache[key] { return hit }
        guard let parsed = parse(url: photo.url) else { return nil }
        cache[key] = parsed
        return parsed
    }

    private func cacheKey(_ photo: Photo) -> String {
        let stamp = Int(photo.modifiedDate.timeIntervalSince1970)
        return "\(photo.url.path)#\(stamp)"
    }

    private func parse(url: URL) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any]
        else { return nil }

        var meta = PhotoMetadata()
        meta.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
        meta.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]

        meta.cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        meta.lensModel = exif?[kCGImagePropertyExifLensModel] as? String

        if let ratings = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int] {
            meta.iso = ratings.first
        } else {
            meta.iso = exif?[kCGImagePropertyExifISOSpeed] as? Int
        }
        meta.aperture = exif?[kCGImagePropertyExifFNumber] as? Double
        meta.shutterSeconds = exif?[kCGImagePropertyExifExposureTime] as? Double
        meta.focalLengthMM = exif?[kCGImagePropertyExifFocalLength] as? Double

        if let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            meta.takenDate = Self.parseEXIFDate(raw)
        }
        return meta
    }

    /// EXIF timestamps look like "2024:07:19 14:32:05" in local time.
    static func parseEXIFDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
