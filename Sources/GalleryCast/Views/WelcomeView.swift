import SwiftUI

/// First-run state: calm, centered, one obvious action.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Token.Space.xl) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Token.Accent.primary)
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(Token.Accent.onPrimary)
                }
                .padding(.bottom, Token.Space.xxs)

            Text("Gallery Cast")
                .font(.largeTitle.weight(.semibold))

            Text("Browse the photos in any folder and play them as a slideshow.")
                .font(.body)
                .foregroundStyle(Token.Ink.secondary)
                .multilineTextAlignment(.center)

            Button {
                model.chooseFolder()
            } label: {
                Label("Open a Folder", systemImage: "folder")
                    .padding(.horizontal, Token.Space.lg)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, Token.Space.sm)
        }
        .padding(Token.Space.massive)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
