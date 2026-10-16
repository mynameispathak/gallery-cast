import Foundation

/// A single image file discovered inside the user's chosen folder.
struct Photo: Identifiable, Hashable, Sendable {
    let url: URL
    let byteSize: Int64
    let modifiedDate: Date

    var id: URL { url }
    var filename: String { url.lastPathComponent }
    var displayName: String {
        (url.lastPathComponent as NSString).deletingPathExtension
    }
    var fileKind: String { url.pathExtension.uppercased() }

    /// Extensions the app treats as photos for browsing and slideshows.
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif",
        "tif", "tiff", "bmp", "avif",
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    var formattedByteSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
