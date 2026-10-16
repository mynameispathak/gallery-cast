import SwiftUI

/// Reusable empty / no-results state, tuned for dark and light.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Token.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Token.Ink.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(Token.Ink.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Token.Space.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
