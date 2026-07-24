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

        /// `WarmBackdrop`'s bottom stop: a subtly creamier tint of `bg`, not a new hue.
        static let bgWarm = SwiftUI.Color(red: 0.985, green: 0.97, blue: 0.945)

        /// Home streak chip (§CX): warm flame orange on soft cream.
        static let streakOrange = SwiftUI.Color(red: 0.93, green: 0.42, blue: 0.13)
        static let streakCream = SwiftUI.Color(red: 1.0, green: 0.95, blue: 0.88)
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

        // MARK: GameKit tokens
        //
        // Defined here for every GameKit game to adopt (Games Spec §1's
        // shared feel), but deliberately NOT retro-applied inside any
        // individual game folder as part of this pass -- each game already
        // has its own inline `.spring(...)`/`.easeInOut(duration:)` literals
        // doing the same jobs (tile lift-on-touch, card flips, drift-off
        // wrong answers, ~0.9s auto-advance beats, bridge transitions); a
        // follow-up pass swaps those call sites over to these tokens.

        /// Quick spring for a tile lifting under touch (Games Spec §1's
        /// lift-on-touch tile feel -- see `GameTileStyle`'s press/lift
        /// states). Snappier than `snappy` -- a per-touch response, not a
        /// round-level correctness beat.
        static let tileLift = Animation.spring(response: 0.22, dampingFraction: 0.65)

        /// A card's face-down/face-up flip (Memory Match's `MemoryCardView`,
        /// Spelling Builder's T3 look-say-cover-check memory mode).
        static let cardFlip = Animation.easeInOut(duration: 0.35)

        /// A tile/answer drifting away after it's been ruled out (e.g. Say &
        /// Match's wrong tiles drifting off-screen once the correct one is
        /// tapped).
        static let drift = Animation.easeIn(duration: 0.5)

        /// Standard pacing beat for auto-advance moments between rounds/
        /// steps (flip-back after a mismatch, glow pulses, etc.) -- a plain
        /// `TimeInterval`, not an `Animation`, so it works equally for
        /// `withAnimation(.easeInOut(duration: Theme.Motion.beat))` and for
        /// `DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.beat)`.
        /// ~0.9s is already the de facto pacing GameKit games use ad hoc for
        /// this beat (e.g. Memory's mismatch flip-back, the idle-hint glow
        /// pulse); this just names it.
        static let beat: TimeInterval = 0.9

        /// A screen/section bridging transition -- e.g. the guided seam's
        /// "Bonus round!" hand-off from the cards portion into an embedded
        /// game round (Games Spec §2, WP-G8 CX pass).
        static let bridge = Animation.easeInOut(duration: 0.6)
    }
}

/// Very subtle vertical warmth behind Home, Session, and SessionComplete
/// screens: `Theme.Color.bg` at the top blending into `bgWarm` (a creamier
/// tint, not a new hue) at the bottom, plus the existing noise texture at
/// low opacity so it reads as material rather than a flat fill. Deliberately
/// quiet — the practice word stays the focus. Not used inside the parent
/// area card or onboarding, which already have their own backdrops.
struct WarmBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.Color.bg, Theme.Color.bgWarm],
                           startPoint: .top, endPoint: .bottom)
            Textures.noise
                .opacity(0.02)
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
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
