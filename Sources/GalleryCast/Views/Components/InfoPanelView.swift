import SwiftUI

/// Trailing panel over the viewer with EXIF + file details.
/// Rows appear only when the photo actually has the data — no "—" walls.
struct InfoPanelView: View {
    @Environment(AppModel.self) private var model
    @State private var metadata: PhotoMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            if let photo = model.viewerPhoto {
                Text(photo.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Token.Ink.onChrome)
                    .lineLimit(2)

                Text(photo.filename)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Token.Ink.onChrome.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Divider()
                    .overlay(Color.white.opacity(0.15))

                ScrollView {
                    VStack(alignment: .leading, spacing: Token.Space.lg) {
                        captureSection
                        fileSection(photo: photo)
                    }
                }

                Spacer()
            }
        }
        .padding(Token.Space.lg)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                .fill(Token.Surface.viewerChrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task(id: model.viewerPhoto) {
            guard let photo = model.viewerPhoto else { return }
            metadata = await MetadataProvider.shared.metadata(for: photo)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var captureSection: some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            Text("CAPTURE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Token.Ink.onChrome.opacity(0.45))

            if let metadata, hasCaptureData(metadata) {
                if let camera = metadata.cameraModel { row("Camera", camera) }
                if let lens = metadata.lensModel { row("Lens", lens) }
                if let iso = metadata.iso { row("ISO", String(iso)) }
                if let aperture = metadata.aperture {
                    row("Aperture", "ƒ\(aperture.formatted(.number.precision(.fractionLength(1))))")
                }
                if let shutter = metadata.shutterSeconds {
                    row("Shutter", formatShutter(shutter))
                }
                if let focal = metadata.focalLengthMM {
                    row("Focal Length", "\(Int(focal)) mm")
                }
                if let taken = metadata.takenDate {
                    row("Taken", taken.formatted(date: .abbreviated, time: .shortened))
                }
            } else {
                Text("No EXIF data in this file.")
                    .font(.caption)
                    .foregroundStyle(Token.Ink.onChrome.opacity(0.5))
            }
        }
    }

    private func fileSection(photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            Text("FILE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Token.Ink.onChrome.opacity(0.45))

            row("Kind", photo.fileKind)
            row("Size", photo.formattedByteSize)
            if let width = metadata?.pixelWidth, let height = metadata?.pixelHeight {
                row("Dimensions", "\(width) × \(height) px")
            }
            if let megapixels = metadata?.megapixels {
                row("Megapixels",
                   "\(megapixels.formatted(.number.precision(.fractionLength(1)))) MP")
            }
            row("Modified", photo.modifiedDate.formatted(date: .abbreviated, time: .omitted))
        }
    }

    private func hasCaptureData(_ metadata: PhotoMetadata) -> Bool {
        metadata.cameraModel != nil || metadata.lensModel != nil
            || metadata.iso != nil || metadata.aperture != nil
            || metadata.shutterSeconds != nil || metadata.focalLengthMM != nil
            || metadata.takenDate != nil
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Token.Ink.onChrome.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Token.Ink.onChrome.opacity(0.85))
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 {
            return "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
        }
        return "1/\(Int((1 / seconds).rounded())) s"
    }
}
