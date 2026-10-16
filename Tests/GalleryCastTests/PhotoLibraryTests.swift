import Foundation
import Testing
@testable import GalleryCast

@Suite
struct PhotoLibraryTests {

    private func makeFixture(
        _ names: [String],
        subdirImages: [String] = []
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent(name).path,
                contents: Data(repeating: 0xFF, count: 5)
            )
        }
        if !subdirImages.isEmpty {
            let sub = dir.appendingPathComponent("nested")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for name in subdirImages {
                FileManager.default.createFile(
                    atPath: sub.appendingPathComponent(name).path,
                    contents: Data(repeating: 0xFF, count: 5)
                )
            }
        }
        return dir
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func photo(named name: String, modified: Date = .distantPast) -> Photo {
        Photo(url: URL(fileURLWithPath: name), byteSize: 0, modifiedDate: modified)
    }

    // MARK: Scan

    @Test func scanFindsOnlySupportedImages() throws {
        let dir = try makeFixture(["a.jpg", "b.png", "c.HEIC", "notes.txt", "d.mp4", ".hidden.jpg"])
        defer { remove(dir) }

        let photos = try PhotoLibrary(folder: dir).scan()

        #expect(photos.map(\.filename).sorted() == ["a.jpg", "b.png", "c.HEIC"])
    }

    @Test func scanIsFlatNotRecursive() throws {
        let dir = try makeFixture(["a.jpg"], subdirImages: ["deep.png"])
        defer { remove(dir) }

        let photos = try PhotoLibrary(folder: dir).scan()

        #expect(photos.map(\.filename) == ["a.jpg"])
    }

    @Test func scanReadsFileAttributes() throws {
        let dir = try makeFixture(["sized.jpg"])
        defer { remove(dir) }

        let photos = try PhotoLibrary(folder: dir).scan()

        #expect(photos.count == 1)
        #expect(photos[0].byteSize == 5)
        #expect(photos[0].modifiedDate > .distantPast)
    }

    // MARK: Sort

    @Test func nameSortIsNatural() {
        let photos = [
            photo(named: "IMG_10.jpg"),
            photo(named: "IMG_2.jpg"),
            photo(named: "img_1.jpg"),
        ]
        let sorted = PhotoLibrary.sort(photos, by: .nameAscending)
        #expect(sorted.map(\.filename) == ["img_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
    }

    @Test func dateSortOrdersNewestAndOldest() {
        let base = Date(timeIntervalSince1970: 1_000)
        let a = photo(named: "a.jpg", modified: base)
        let b = photo(named: "b.jpg", modified: base.addingTimeInterval(50))

        #expect(PhotoLibrary.sort([a, b], by: .dateNewest).map(\.filename) == ["b.jpg", "a.jpg"])
        #expect(PhotoLibrary.sort([a, b], by: .dateOldest).map(\.filename) == ["a.jpg", "b.jpg"])
    }

    // MARK: Filter

    @Test func filterIsCaseAndDiacriticInsensitive() {
        let photos = [
            photo(named: "café.jpg"),
            photo(named: "BEACH.png"),
            photo(named: "nope.txt"),
        ]
        #expect(PhotoLibrary.filter(photos, matching: "CAF").count == 1)
        #expect(PhotoLibrary.filter(photos, matching: "beach").count == 1)
        #expect(PhotoLibrary.filter(photos, matching: "").count == 3)
        #expect(PhotoLibrary.filter(photos, matching: "  ").count == 3)
        #expect(PhotoLibrary.filter(photos, matching: "zzz").isEmpty)
    }
}
