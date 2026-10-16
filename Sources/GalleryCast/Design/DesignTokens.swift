import SwiftUI

/// GalleryCast design system.
///
/// Three layers, following the token architecture discipline:
///  1. Primitive  — raw, context-free values (scales, hues).
///  2. Semantic   — purpose aliases the UI refers to ("what is this for").
///  3. Component  — component-specific tokens derived from semantics.
///
/// Views must reference semantic or component tokens, never raw literals.
enum Token {

    // MARK: - 1. Primitive

    /// Spacing scale (4pt base grid).
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 48
        static let massive: CGFloat = 72
    }

    /// Corner radius scale.
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let pill: CGFloat = 999
    }

    /// Motion durations (seconds).
    enum Duration {
        static let fast: Double = 0.18
        static let base: Double = 0.28
        static let slow: Double = 0.45
        static let crossfade: Double = 0.6
        /// Idle delay before viewer chrome hides.
        static let chromeAutoHide: Double = 2.5
    }

    /// Raw palette. Only the amber accent is brandful; everything else
    /// leans on AppKit semantic colors for automatic light/dark parity.
    enum Palette {
        /// Warm amber — the single brand hue (comfort, warmth, memories).
        static let amber = Color(red: 1.00, green: 0.584, blue: 0.000) // #FF9500
        /// Near-black used behind photos so images, not chrome, dominate.
        static let viewerBlack = Color(red: 0.040, green: 0.040, blue: 0.049) // #0A0A0D
        /// Hairline separator.
        static let hairline = Color.primary.opacity(0.08)
    }

    // MARK: - 2. Semantic

    /// Backgrounds by purpose.
    enum Surface {
        /// Photo presentation is always dark, in both appearances.
        static let viewer = Palette.viewerBlack
        /// The translucent chrome floating over the viewer.
        static let viewerChrome = Color(nsColor: .black).opacity(0.55)
    }

    /// Accent by purpose.
    enum Accent {
        static let primary = Palette.amber
        static let onPrimary = Color.white
    }

    /// Foreground content by purpose (adaptive).
    enum Ink {
        static let primary = Color.primary
        static let secondary = Color.primary.opacity(0.62)
        static let tertiary = Color.primary.opacity(0.40)
        static let inverse = Color.white
        static let onChrome = Color.white.opacity(0.92)
    }

    // MARK: - 3. Component

    /// Grid thumbnail cells.
    enum Thumb {
        static let cornerRadius: CGFloat = Token.Radius.sm
        static let minCell: CGFloat = 148
        static let spacing: CGFloat = Token.Space.sm
        static let hoverScale: CGFloat = 1.02
        static let selectionWidth: CGFloat = 3
    }

    /// Floating controls over the viewer / slideshow.
    enum Chrome {
        static let cornerRadius: CGFloat = Token.Radius.lg
        static let padding: CGFloat = Token.Space.md
        static let opacityHidden: Double = 0
        static let opacityVisible: Double = 1
    }

    /// Slideshow timing options offered in the UI.
    enum Slideshow {
        static let intervals: [TimeInterval] = [2, 5, 10, 15]
        static let defaultInterval: TimeInterval = 5
    }
}
