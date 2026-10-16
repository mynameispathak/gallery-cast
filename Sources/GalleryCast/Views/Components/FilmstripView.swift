import SwiftUI

/// Horizontal strip of thumbnails at the bottom of the viewer;
/// clicking jumps, the current photo stays centered.
struct FilmstripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Token.Space.xs) {
                    ForEach(model.filteredPhotos) { photo in
                        FilmstripCell(photo: photo, isCurrent: model.viewerPhoto == photo)
                            .id(photo)
                            .onTapGesture { model.jump(to: photo) }
                    }
                }
                .padding(.horizontal, Token.Space.md)
                .padding(.vertical, Token.Space.xs)
            }
            .background(
                RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                    .fill(Token.Surface.viewerChrome)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .onAppear {
                if let photo = model.viewerPhoto {
                    proxy.scrollTo(photo, anchor: .center)
                }
            }
            .onChange(of: model.viewerPhoto) { _, photo in
                guard let photo else { return }
                withAnimation(.easeInOut(duration: Token.Duration.fast)) {
                    proxy.scrollTo(photo, anchor: .center)
                }
            }
        }
    }
}

private struct FilmstripCell: View {
    let photo: Photo
    let isCurrent: Bool
    @State private var image: DecodedImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image.cgImage, scale: 2)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.06)
            }
        }
        .frame(width: 56, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.sm, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: Token.Radius.sm, style: .continuous)
                    .strokeBorder(Token.Accent.primary, lineWidth: 2)
            }
        }
        .task(id: photo) {
            image = await ImageProvider.shared.thumbnail(for: photo, side: 56)
        }
    }
}
