import SwiftUI
import AppKit

/// Sidebar: recent folders plus a live stats footer for the open folder.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Recent Folders") {
                if model.recentFolders.isEmpty {
                    Text("Folders you open will appear here.")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                }
                ForEach(model.recentFolders, id: \.self) { folder in
                    SidebarRow(folder: folder, isActive: model.currentFolder == folder)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let folder = model.currentFolder {
                HStack(spacing: Token.Space.xs) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(Token.Ink.tertiary)
                    Text("\(model.photoCountDescription) — \(folder.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, Token.Space.lg)
                .padding(.vertical, Token.Space.sm)
                .background(.bar)
            }
        }
    }
}

private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    let isActive: Bool

    var body: some View {
        Button {
            model.openFolder(folder)
        } label: {
            HStack(spacing: Token.Space.sm) {
                Image(systemName: isActive ? "folder.fill" : "folder")
                    .foregroundStyle(isActive ? Token.Accent.primary : Token.Ink.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.lastPathComponent)
                        .lineLimit(1)
                        .foregroundStyle(isActive ? Token.Ink.primary : Token.Ink.primary)
                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Forget This Folder") {
                model.forgetRecent(folder)
            }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        }
    }
}
