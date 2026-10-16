import Foundation

/// How the grid (and the slideshow, which follows the grid) orders photos.
enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case nameAscending = "Name"
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"

    var id: String { rawValue }
}

/// Scans one directory — flat, non-recursive — for supported image files.
struct PhotoLibrary: Sendable {
    let folder: URL

    func scan() throws -> [Photo] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
        ]
        let children = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        var photos: [Photo] = []
        photos.reserveCapacity(children.count)
        for child in children {
            guard Photo.isSupported(child),
                  let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            photos.append(Photo(
                url: child,
                byteSize: Int64(values.fileSize ?? 0),
                modifiedDate: values.contentModificationDate ?? .distantPast
            ))
        }
        return photos
    }

    /// Case- and diacritic-insensitive filename search.
    static func filter(_ photos: [Photo], matching query: String) -> [Photo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return photos }
        let foldedQuery = trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current
        )
        return photos.filter {
            $0.filename.folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: .current
            ).contains(foldedQuery)
        }
    }

    /// Applies the given ordering. Name order is natural (Finder-like),
    /// so IMG_2 sorts before IMG_10.
    static func sort(_ photos: [Photo], by order: SortOrder) -> [Photo] {
        switch order {
        case .nameAscending:
            photos.sorted {
                $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
            }
        case .dateNewest:
            photos.sorted { $0.modifiedDate > $1.modifiedDate }
        case .dateOldest:
            photos.sorted { $0.modifiedDate < $1.modifiedDate }
        }
    }
}
