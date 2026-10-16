import SwiftUI

/// One square grid cell. Thumbnails decode off the main actor and cache
/// by path + modification time, so scrolling stays smooth and edits
/// invalidate correctly.
struct ThumbnailCellView: View {
    @Environment(AppModel.self) private var model
    let photo: Photo

    @State private var isHovered = false
    @State private var image: DecodedImage?

    private var isSelected: Bool { model.selectedPhoto == photo }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image {
                Image(decorative: image.cgImage, scale: 2)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: Token.Thumb.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }

            if isHovered {
                Text(photo.filename)
                    .font(.caption)
                    .foregroundStyle(Token.Ink.inverse)
                    .lineLimit(1)
                    .padding(.horizontal, Token.Space.sm)
                    .padding(.vertical, Token.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .frame(minWidth: Token.Thumb.minCell, maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Token.Thumb.cornerRadius, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Token.Thumb.cornerRadius, style: .continuous)
                    .strokeBorder(Token.Accent.primary, lineWidth: Token.Thumb.selectionWidth)
            }
        }
        .scaleEffect(isHovered ? Token.Thumb.hoverScale : 1)
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0), radius: Token.Space.md)
        .animation(.easeOut(duration: Token.Duration.fast), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .task(id: photo) {
            image = await ImageProvider.shared.thumbnail(for: photo, side: Token.Thumb.minCell)
        }
    }
}
