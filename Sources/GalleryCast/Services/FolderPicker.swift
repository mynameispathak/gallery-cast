import AppKit

/// Thin wrapper over NSOpenPanel so the app model stays AppKit-free.
enum FolderPicker {
    @MainActor
    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Photo Folder"
        panel.message = "Photos in this folder will be shown."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
