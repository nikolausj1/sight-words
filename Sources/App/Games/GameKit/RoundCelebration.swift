import SwiftUI

/// Shared round-end celebration (Games Spec §1): "full-screen confetti +
/// rotating praise clip (4 variants, never same twice in a row) + pulsing
/// Next key." Every GameKit game presents this the same way when a round
/// ends; only `onNext` differs (return to the Games shelf vs. advancing the
/// guided session into `SessionComplete`). Confetti colors and the Next key
/// bias to `gameID`'s own accent family (Design Direction §3/§6) instead of
/// the old fixed gold/blue palette, so the celebration still reads as part
/// of the game the child was just playing.
///
/// "One more round?" (Design Direction §6): an "Again!" `PaperKeyButton`
/// (primary, game accent) sits beside "Done" (hero) whenever `canPlayAgain`
/// is true -- the calling game passes that in from its own coordinator's
/// 3-sets-per-sitting cap (each coordinator's `startNewSet()`/`canPlayAgain`
/// is this celebration's "restart hook"). Once the cap is hit, `canPlayAgain`
/// is false: no Again button, and the appear-speech ends on `phrase-all-done`
/// instead of `phrase-play-again`.
struct RoundCelebration: View {
    let gameID: GameID
    /// True iff this sitting hasn't yet hit the 3-set cap -- controls both
    /// whether "Again!" renders and which closing phrase plays.
    var canPlayAgain: Bool = false
    /// Starts a fresh round set on the SAME game screen (no dismiss) --
    /// nil-safe no-op default so existing call sites that haven't wired a
    /// restart hook yet still compile; every real game passes its
    /// coordinator's `startNewSet()`.
    var onAgain: () -> Void = {}
    let onNext: () -> Void

    @State private var praise: PhraseClip = RoundCelebration.nextPraise()
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var family: PaperTheme.Family { PaperTheme.family(for: gameID) }

    private static let variants: [PhraseClip] = [.praise1, .praise2, .praise3, .praise4]

    /// The praise clip most recently handed out, process-wide -- so any two
    /// back-to-back `RoundCelebration` presentations (same game, or a
    /// different one right after) never repeat the same line, per Games Spec
    /// §1's "never same twice in a row". `@State`'s default-value closure
    /// only runs once per view identity (when a round actually ends and this
    /// view is inserted), so this advances exactly once per celebration.
    private static var lastPraise: PhraseClip?

    private static func nextPraise() -> PhraseClip {
        let choice = variants.filter { $0.slug != lastPraise?.slug }.randomElement() ?? variants[0]
        lastPraise = choice
        return choice
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            if !reduceMotion {
                GameConfettiBurst(particleCount: 90,
                                  colors: [family.ring1, family.accent,
                                           Theme.Color.correct, family.ring2])
                    .ignoresSafeArea()
            }
            VStack(spacing: Theme.Metric.pad) {
                Text(praise.fallbackText)
                    .font(Theme.Font.display(40))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, Theme.Metric.pad)

                HStack(spacing: Theme.Metric.gap) {
                    if canPlayAgain {
                        Button(action: onAgain) {
                            Text("Again!")
                                .font(Theme.Font.label(20))
                        }
                        .buttonStyle(PaperKeyButton(fill: family.accent, size: .primary))
                        .accessibilityLabel("Play again")
                    }

                    Button(action: onNext) {
                        Text("Done")
                            .font(Theme.Font.label(22))
                    }
                    .buttonStyle(PaperKeyButton(fill: family.accent, size: .hero))
                    .frame(width: 200)
                    .scaleEffect(pulse && !reduceMotion ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .accessibilityLabel("Done")
                }
            }
        }
        .onAppear {
            // Praise line, then a short beat, then the play-again invite (or
            // the gentle close-out once the sitting's 3-set cap is hit) --
            // one chained line rather than two separate `speak` calls so it
            // reads as a single thought.
            SpeechService.shared.speak(segments: [
                .phrase(praise), .pause(0.3), .phrase(canPlayAgain ? .playAgain : .allDone),
            ])
            pulse = true
        }
    }
}
