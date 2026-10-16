import Foundation
import Observation

/// The app's single source of truth.
///
/// Invariants this model owns:
/// - Grid, viewer, and slideshow all read the same filtered + sorted list.
/// - The viewer tracks a photo *by identity*, never by grid position,
///   so search or sort changes while it is open cannot desync it.
/// - The slideshow is never running while the viewer is closed.
@MainActor
@Observable
final class AppModel {

    // MARK: Library state

    private(set) var currentFolder: URL?
    private(set) var photos: [Photo] = []
    private(set) var isScanning = false
    private(set) var recentFolders: [URL] = []

    // MARK: UI state

    var sortOrder: SortOrder = .dateNewest
    var searchQuery = ""
    var selectedPhoto: Photo?
    private(set) var viewerPhoto: Photo?
    var showFilmstrip = false
    var showInfoPanel = false

    let slideshow = SlideshowController()

    private var scanGeneration = 0
    private static let recentFoldersKey = "recentFolders"

    /// Viewer index to open once the initial scan finishes (set by
    /// launch arguments: `GalleryCast /path/to/folder [index] [info]`).
    private var pendingViewerIndex: Int?
    private var pendingInfoPanel = false

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentFoldersKey) ?? []
        recentFolders = paths.map { URL(fileURLWithPath: $0) }
    }

    // MARK: Derived

    var isViewerPresented: Bool { viewerPhoto != nil }

    /// The photos as the grid shows them: filtered by search, then sorted.
    /// The slideshow follows this same order.
    var filteredPhotos: [Photo] {
        PhotoLibrary.sort(
            PhotoLibrary.filter(photos, matching: searchQuery),
            by: sortOrder
        )
    }

    /// Viewer position derived by identity from the visible order.
    var viewerIndex: Int? {
        guard let viewerPhoto else { return nil }
        return filteredPhotos.firstIndex(of: viewerPhoto)
    }

    var photoCountDescription: String {
        let count = photos.count
        let noun = count == 1 ? "photo" : "photos"
        let bytes = photos.reduce(Int64(0)) { $0 + $1.byteSize }
        let total = "\(count) \(noun) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return total
        }
        return "\(filteredPhotos.count) of \(total)"
    }

    // MARK: Folders

    func chooseFolder() {
        guard let url = FolderPicker.pick() else { return }
        openFolder(url)
    }

    func openFolder(_ url: URL) {
        currentFolder = url
        selectedPhoto = nil
        closeViewer()
        rememberRecent(url)
        rescan()
    }

    func forgetRecent(_ url: URL) {
        recentFolders.removeAll { $0 == url }
        persistRecents()
    }

    func rescan() {
        guard let folder = currentFolder else { return }
        isScanning = true
        scanGeneration += 1
        let generation = scanGeneration
        Task {
            let scanned = (try? await Task.detached(priority: .userInitiated) {
                try PhotoLibrary(folder: folder).scan()
            }.value) ?? []
            // Drop results from a scan that has since been superseded.
            guard generation == scanGeneration else { return }
            photos = scanned
            isScanning = false
            openPendingViewerIfPossible()
        }
    }

    // MARK: Launch arguments

    /// Opens a folder (and optionally the viewer at a photo index) from
    /// launch arguments: `GalleryCast /path/to/folder [index] [info]`.
    /// Enables shell and automation workflows, such as:
    /// `open GalleryCast.app --args ~/Pictures/vacation 4`
    func handleLaunchArgumentsIfNeeded() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let rawPath = args.first, !rawPath.hasPrefix("-") else { return }
        let path = (rawPath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }

        if let indexText = args.dropFirst().first,
           let index = Int(indexText), index >= 0 {
            pendingViewerIndex = index
        }
        pendingInfoPanel = args.dropFirst(2).first?.lowercased() == "info"
        openFolder(URL(fileURLWithPath: path))
    }

    private func openPendingViewerIfPossible() {
        guard let index = pendingViewerIndex else { return }
        pendingViewerIndex = nil
        let order = filteredPhotos
        guard order.indices.contains(index) else { return }
        openViewer(order[index])
        showInfoPanel = pendingInfoPanel
        pendingInfoPanel = false
    }

    // MARK: Viewer

    func openViewer(_ photo: Photo) {
        viewerPhoto = photo
        selectedPhoto = photo
    }

    func closeViewer() {
        viewerPhoto = nil
        showInfoPanel = false
        showFilmstrip = false
        slideshow.stop()
    }

    func jump(to photo: Photo) {
        viewerPhoto = photo
    }

    /// Moves the viewer by `delta` positions through the visible order,
    /// wrapping around both ends.
    func navigate(_ delta: Int) {
        let order = filteredPhotos
        guard !order.isEmpty else { return }
        guard let index = viewerIndex else {
            viewerPhoto = order[0]
            return
        }
        let next = ((index + delta) % order.count + order.count) % order.count
        viewerPhoto = order[next]
    }

    // MARK: Slideshow

    func startSlideshow(from photo: Photo? = nil) {
        let order = filteredPhotos
        guard !order.isEmpty else { return }
        if viewerPhoto == nil {
            viewerPhoto = photo ?? selectedPhoto ?? order[0]
        }
        slideshow.onAdvance = { [weak self] in self?.navigate(1) }
        slideshow.start()
    }

    /// Space-bar behavior in the viewer: start, pause, or resume.
    func toggleSlideshow() {
        switch slideshow.phase {
        case .idle:
            startSlideshow()
        case .playing, .paused:
            slideshow.toggle()
        }
    }

    // MARK: Recents persistence

    private func rememberRecent(_ url: URL) {
        recentFolders.removeAll { $0 == url }
        recentFolders.insert(url, at: 0)
        if recentFolders.count > 8 {
            recentFolders = Array(recentFolders.prefix(8))
        }
        persistRecents()
    }

    private func persistRecents() {
        UserDefaults.standard.set(
            recentFolders.map(\.path),
            forKey: Self.recentFoldersKey
        )
    }
}
