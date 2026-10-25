import Foundation
import Observation
import os

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
    private(set) var viewerPhoto: Photo? {
        // The single funnel for every viewer change — open, jump,
        // navigate, close — so casting always stays in sync with it.
        didSet { casting.mirror(viewerPhoto) }
    }
    var showFilmstrip = false
    var showInfoPanel = false

    let slideshow = SlideshowController()

    /// Casting: the TV mirrors whatever the viewer shows.
    let casting = CastSessionController()
    let castDiscovery = CastDiscoveryService()

    private var scanGeneration = 0
    private static let recentFoldersKey = "recentFolders"

    /// Viewer index to open once the initial scan finishes (set by
    /// launch arguments: `GalleryCast /path/to/folder [index] [info]`).
    private var pendingViewerIndex: Int?
    private var pendingInfoPanel = false

    /// Cast target requested by launch arguments
    /// (`GalleryCast /path/to/folder cast [deviceName]`): `nil` means
    /// none, `""` means any discovered device, otherwise a
    /// case-insensitive substring of the device's Bonjour name.
    private var pendingCastDeviceName: String?
    private var castPickTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.aniketpathak.gallerycast", category: "app")

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
        castPickTask?.cancel()
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
            startPendingCastIfPossible()
        }
    }

    // MARK: Launch arguments

    /// Opens a folder from launch arguments, and optionally the viewer
    /// or a cast session: `GalleryCast /path/to/folder [index] [info]`
    /// or `GalleryCast /path/to/folder cast [deviceName]`. Enables
    /// shell and automation workflows, such as:
    /// `open GalleryCast.app --args ~/Pictures/vacation 4`
    func handleLaunchArgumentsIfNeeded() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let rawPath = args.first, !rawPath.hasPrefix("-") else { return }
        let path = (rawPath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }

        let rest = args.dropFirst()
        if rest.first?.lowercased() == "cast" {
            pendingCastDeviceName = rest.dropFirst().first ?? ""
        } else {
            if let indexText = rest.first,
               let index = Int(indexText), index >= 0 {
                pendingViewerIndex = index
            }
            pendingInfoPanel = rest.dropFirst().first?.lowercased() == "info"
        }
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

    /// Starts the cast requested by launch arguments once the scan has
    /// photos to mirror. Waits up to 10 s for discovery to surface a
    /// matching device; falls back to just opening the viewer.
    private func startPendingCastIfPossible() {
        guard let wanted = pendingCastDeviceName else { return }
        pendingCastDeviceName = nil
        castDiscovery.start()
        castPickTask?.cancel()
        castPickTask = Task {
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if Task.isCancelled { return }
                if let device = pendingCastMatch(named: wanted, in: castDiscovery.devices) {
                    Self.log.info("app: launch-arg cast matched \(device.name, privacy: .public)")
                    startCasting(device)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            Self.log.error("app: launch-arg cast found no matching device")
            if viewerPhoto == nil, !filteredPhotos.isEmpty {
                openViewer(selectedPhoto ?? filteredPhotos[0])
            }
        }
    }

    /// `""` accepts any device; otherwise a case-insensitive substring
    /// of the Bonjour name ("BRAVIA" matches "BRAVIA-VU2-cc…").
    private func pendingCastMatch(named wanted: String, in devices: [CastDevice]) -> CastDevice? {
        if wanted.isEmpty { return devices.first }
        return devices.first { $0.name.localizedCaseInsensitiveContains(wanted) }
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

    // MARK: Casting

    /// Starts mirroring the viewer to a Cast device. Casting needs
    /// something to mirror, so the viewer opens first if necessary.
    ///
    /// `useTLS` is CASTV2's transport in production; tests pass `false`
    /// to talk to a loopback receiver over plain TCP.
    func startCasting(_ device: CastDevice, useTLS: Bool = true) {
        guard let folder = currentFolder, !filteredPhotos.isEmpty else { return }
        if viewerPhoto == nil {
            openViewer(selectedPhoto ?? filteredPhotos[0])
        }
        casting.start(device: device, folder: folder, currentPhoto: viewerPhoto, useTLS: useTLS)
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
