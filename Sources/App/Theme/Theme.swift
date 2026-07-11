import SwiftUI

/// The single design-token layer. Every colour, radius, font, and motion constant
/// routes through here so the v1 SwiftUI/SF-Symbols look can be swapped for custom
/// or generated art (the fast-follow) by editing tokens, not views.
enum Theme {

    // MARK: Palette (bright but restrained). Light-first; dark via semantic colors.
    enum Color {
        static let bg = SwiftUI.Color(red: 0.97, green: 0.98, blue: 1.0)
        static let surface = SwiftUI.Color.white
        static let ink = SwiftUI.Color(red: 0.12, green: 0.14, blue: 0.22)
        static let inkSoft = SwiftUI.Color(red: 0.42, green: 0.45, blue: 0.55)

        static let primary = SwiftUI.Color(red: 0.30, green: 0.45, blue: 0.98)   // friendly blue
        static let accent = SwiftUI.Color(red: 1.0, green: 0.72, blue: 0.20)     // warm gold
        static let correct = SwiftUI.Color(red: 0.20, green: 0.78, blue: 0.50)
        static let gentle = SwiftUI.Color(red: 0.62, green: 0.66, blue: 0.78)    // neutral wrong-answer

        /// Onboarding backdrop gradient stops.
        static let onboardTop = SwiftUI.Color(red: 0.11, green: 0.12, blue: 0.30)
        static let onboardBottom = SwiftUI.Color(red: 0.05, green: 0.05, blue: 0.14)
    }

    // MARK: Typography — SF Rounded; the practice word is the hero.
    enum Font {
        static func display(_ size: CGFloat) -> SwiftUI.Font { .system(size: size, weight: .heavy, design: .rounded) }
        static func number(_ size: CGFloat) -> SwiftUI.Font { .system(size: size, weight: .bold, design: .rounded) }
        static func body(_ size: CGFloat = 18) -> SwiftUI.Font { .system(size: size, weight: .medium, design: .rounded) }
        static func label(_ size: CGFloat = 15) -> SwiftUI.Font { .system(size: size, weight: .semibold, design: .rounded) }
    }

    enum Metric {
        static let corner: CGFloat = 22
        static let cornerSmall: CGFloat = 14
        static let gap: CGFloat = 16
        static let pad: CGFloat = 24
    }

    // MARK: Motion — calm in the loop, lavish at session end.
    enum Motion {
        /// In-loop feedback: fast and snappy (≤200ms) so it never slows the pace.
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.7)
        static let quick = Animation.easeOut(duration: 0.18)
        /// Session-end beats: bigger, bouncier.
        static let celebrate = Animation.spring(response: 0.5, dampingFraction: 0.6)
    }
}

extension View {
    /// Standard card surface used across the app: flat white with a hairline
    /// border (no drop shadow — not part of the design language).
    func cardSurface() -> some View {
        self
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                .strokeBorder(Theme.Color.ink.opacity(0.08), lineWidth: 1))
    }
}

/// Tactile press feedback for large kid-facing buttons (HIG: clear affordance +
/// immediate response). Shrinks slightly on press; respects Reduced Motion.
struct PopButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}
