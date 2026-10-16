import SwiftUI
import AppKit

/// The photo grid: adaptive square cells, double-click to open the viewer,
/// context menu for slideshow-from-here and Finder actions.
struct PhotoGridView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Group {
            if model.filteredPhotos.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle(model.currentFolder?.lastPathComponent ?? "Photos")
        .navigationSubtitle(model.photoCountDescription)
        .searchable(
            text: $model.searchQuery,
            prompt: Text("Search by name")
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                sortPicker
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
                Button {
                    model.startSlideshow()
                } label: {
                    Label("Slideshow", systemImage: "play.fill")
                }
                .disabled(model.filteredPhotos.isEmpty)
            }
        }
        .overlay {
            if model.isScanning {
                HStack(spacing: Token.Space.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .padding(Token.Space.md)
                .background(.regularMaterial, in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Token.Space.lg)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Pieces

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: Token.Thumb.minCell),
                        spacing: Token.Thumb.spacing
                    )
                ],
                spacing: Token.Thumb.spacing
            ) {
                ForEach(model.filteredPhotos) { photo in
                    ThumbnailCellView(photo: photo)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            model.openViewer(photo)
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded { model.selectedPhoto = photo }
                        )
                        .contextMenu {
                            Button("Open in Viewer") {
                                model.openViewer(photo)
                            }
                            Button("Slideshow from Here") {
                                model.startSlideshow(from: photo)
                            }
                            Divider()
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([photo.url])
                            }
                        }
                }
            }
            .padding(Token.Space.lg)
        }
    }

    private var emptyState: some View {
        let searching = !model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
        return EmptyStateView(
            icon: searching ? "magnifyingglass" : "photo.on.rectangle.angled",
            title: searching ? "No photos match “\(model.searchQuery)”" : "No photos found",
            message: searching
                ? "Try a different search term."
                : "This folder has no supported images (JPEG, PNG, HEIC, WebP, GIF, TIFF, BMP, AVIF)."
        )
    }

    private var sortPicker: some View {
        @Bindable var model = model
        return Picker("Sort", selection: $model.sortOrder) {
            ForEach(SortOrder.allCases) { order in
                Text(order.rawValue).tag(order)
            }
        }
        .pickerStyle(.menu)
    }
}
