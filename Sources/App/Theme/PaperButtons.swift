import SwiftUI

// MARK: - PaperKeyButton

/// Kid-scale paper button (Design Direction §2), replacing `ChunkyKeyStyle`
/// on kid-facing screens: bold saturated fill, a white 3pt inner stroke, and
/// the shared paper drop shadow. Three sizes -- `hero` (88pt min-height:
/// Play!, Show answer, Next), `primary` (72pt: scoring, game actions),
/// `chip` (60pt: shelf/tray chips) -- each a MINIMUM height so a caller's
/// own `.frame(height:)` can still go bigger, never smaller than the
/// kid-scale floor.
///
/// Corner radius: 20pt continuous (one of the two options §2 explicitly
/// allows -- "organic-blob or 20pt continuous"). A per-button organic blob
/// was judged not worth the readability/hit-testing risk at this small a
/// size across dozens of call sites; the flat fill + white inner stroke +
/// paper shadow already read as "paper" without it.
///
/// Touch response (§2, shared across every button in this file): press ->
/// scale 0.92 + shadow flattens (y 4 -> 1) + a small ±1° tilt (a fresh random
/// direction chosen at the start of each press, so repeated taps don't all
/// lean the same way); release -> a bouncy spring naturally overshoots past
/// 1.0 before settling (`Theme.Motion` doesn't have a dedicated "overshoot"
/// token, so this uses its own low-damping spring tuned for that overshoot
/// rather than hand-staging a two-step animation). `Feedback.fire(.keyTap)`
/// fires once per press-down. Reduce Motion: opacity dip only, no
/// scale/rotation.
struct PaperKeyButton: ButtonStyle {
    enum Size {
        case hero, primary, chip
        var minHeight: CGFloat {
            switch self {
            case .hero: return 88
            case .primary: return 72
            case .chip: return 60
            }
        }
    }

    var fill: Color
    var size: Size = .primary
    var corner: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tiltSign: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        // Deliberately does NOT force `.frame(maxWidth: .infinity)` here (the
        // way `ChunkyKeyStyle` never did either): callers vary between
        // "fill the row" (scoring buttons, Show answer, Next) and "fixed
        // width beside other siblings" (the voice-check confirm bar's
        // Yes/Try-again pair on iPad) -- forcing greedy width here would
        // silently override whichever one a caller's own label frame chose.
        return configuration.label
            .foregroundStyle(.white)
            .frame(minHeight: size.minHeight)
            .padding(.horizontal, 20)
            .background(
                ZStack {
                    shape.fill(fill)
                    Textures.noise
                        .opacity(0.04)
                        .blendMode(.overlay)
                        .clipShape(shape)
                    shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 3)
                }
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.16), radius: pressed ? 2 : 6, y: pressed ? 1 : 4)
            .scaleEffect(pressed ? 0.92 : 1.0)
            .rotationEffect(.degrees(pressed ? tiltSign : 0))
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1.0)
            .animation(pressed ? Theme.Motion.tileLift : .spring(response: 0.4, dampingFraction: 0.55),
                       value: pressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard isPressed else { return }
                tiltSign = Bool.random() ? 1 : -1
                Feedback.fire(.keyTap)
            }
    }
}

// MARK: - SpeakerButton

/// The persistent replay affordance everywhere (§2): a 64pt round warm-gold
/// paper badge on a small paper ring, white speaker glyph. While
/// `SpeechService.shared.isSpeakingAloud`: a gentle wobble plus 3 "sound arc"
/// petals fanning out to the upper-right, appearing in sequence. Polls the
/// same way `InstructionSpeaker` already did (that property is a plain
/// pollable computed var, not `@Published`), so this is a drop-in
/// replacement for it and for `PracticeCardView`'s speaker buttons alike --
/// callers just supply what tapping it should do.
struct SpeakerButton: View {
    let action: () -> Void
    var diameter: CGFloat = 64
    var accessibilityLabel: String = "Replay"

    @State private var isSpeaking = false
    @State private var wobbleUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gold = PaperTheme.sunshineGold.accent

    var body: some View {
        Button(action: action) {
            ZStack {
                // Small paper ring behind the badge.
                Circle()
                    .fill(PaperTheme.sunshineGold.surface)
                    .frame(width: diameter + 16, height: diameter + 16)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 3)

                Circle()
                    .fill(LinearGradient(colors: [gold.shaded(by: 0.16), gold],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: diameter, height: diameter)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 3))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 4)

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: diameter * 0.32, weight: .bold))
                    .foregroundStyle(.white)

                if !reduceMotion {
                    ForEach(0..<3) { i in
                        SoundArcPetal(index: i, isActive: isSpeaking, color: gold, baseDiameter: diameter)
                    }
                }
            }
        }
        .buttonStyle(PopButtonStyle(scale: 0.94))
        .rotationEffect(.degrees(isSpeaking && !reduceMotion ? (wobbleUp ? 4 : -4) : 0))
        .animation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true), value: wobbleUp)
        .onChange(of: isSpeaking) { _, speaking in wobbleUp = speaking }
        .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in
            let speaking = SpeechService.shared.isSpeakingAloud
            if speaking != isSpeaking { isSpeaking = speaking }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// One "sound arc" petal (§2's SpeakerButton wobble): a short arc stroke at
/// an increasing radius, fanning toward the upper-right of the badge,
/// fading/scaling in with a per-index stagger and looping while `isActive`.
private struct SoundArcPetal: View {
    let index: Int
    let isActive: Bool
    let color: Color
    let baseDiameter: CGFloat

    @State private var appear = false

    var body: some View {
        Circle()
            .trim(from: 0.60, to: 0.82)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: baseDiameter * 0.55 + CGFloat(index) * 16,
                   height: baseDiameter * 0.55 + CGFloat(index) * 16)
            .rotationEffect(.degrees(-45))
            .opacity(appear ? 0.9 : 0)
            .scaleEffect(appear ? 1 : 0.7)
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.easeOut(duration: 0.3).delay(Double(index) * 0.15)
                        .repeatForever(autoreverses: true)) {
                        appear = true
                    }
                } else {
                    withAnimation(.easeIn(duration: 0.15)) { appear = false }
                }
            }
    }
}

// MARK: - CloseButton

/// The redesigned exit affordance everywhere (§2): a 64pt round soft-coral
/// paper badge, white ✕. Press-and-hold (0.6s, retained from the previous
/// `HoldToExitButton`) fills a ring around the badge -- styled as a paper
/// ring "unrolling" rather than a thin progress stroke -- before firing
/// `onClose`. A brief tap that releases before the hold completes teaches
/// the gesture with a single wiggle (reuses GameKit's existing
/// `wrongShake` -- same shake primitive already used for wrong-answer
/// feedback, just borrowed here as a "not yet, hold me" cue) instead of
/// doing nothing.
struct CloseButton: View {
    let onClose: () -> Void
    var diameter: CGFloat = 64

    @State private var progress: CGFloat = 0
    @State private var teachWiggle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let holdDuration: TimeInterval = 0.6
    private let coral = PaperTheme.coral.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 6)
                .frame(width: diameter + 14, height: diameter + 14)
            // The "unrolling paper ring": a thick coral-tinted stroke that
            // sweeps around the badge as the hold progresses.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(coral, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: diameter + 14, height: diameter + 14)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(LinearGradient(colors: [coral.shaded(by: 0.14), coral],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 4)

            Image(systemName: "xmark")
                .font(.system(size: diameter * 0.3, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: diameter + 14, height: diameter + 14)
        .contentShape(Circle())
        .wrongShake(Binding(get: { teachWiggle }, set: { teachWiggle = $0 }))
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 60) {
            progress = 0
            onClose()
        } onPressingChanged: { pressing in
            if pressing {
                withAnimation(reduceMotion ? nil : .linear(duration: holdDuration)) { progress = 1 }
            } else {
                if progress > 0.02 && progress < 0.98 {
                    teachWiggle = true
                }
                withAnimation(Theme.Motion.quick) { progress = 0 }
            }
        }
        .accessibilityLabel("Close")
        .accessibilityHint("Press and hold to close")
    }
}
