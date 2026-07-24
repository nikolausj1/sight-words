import SwiftUI

/// Shared round-end celebration (Games Spec §1): "full-screen confetti +
/// rotating praise clip (4 variants, never same twice in a row) + pulsing
/// Next key (ChunkyKey accent)." Every GameKit game presents this the same
/// way when a round ends; only `onNext` differs (return to the Games shelf
/// vs. advancing the guided session into `SessionComplete`).
struct RoundCelebration: View {
    let onNext: () -> Void

    @State private var praise: PhraseClip = RoundCelebration.nextPraise()
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                GameConfettiBurst(particleCount: 90)
                    .ignoresSafeArea()
            }
            VStack(spacing: Theme.Metric.pad) {
                Text(praise.fallbackText)
                    .font(Theme.Font.display(40))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, Theme.Metric.pad)

                Button(action: onNext) {
                    Text("Next")
                        .font(Theme.Font.label(22))
                        .frame(width: 160, height: 64)
                }
                .buttonStyle(ChunkyKeyStyle(base: Theme.Color.accent,
                                            deep: Theme.Color.accent.shaded(by: -0.4)))
                .scaleEffect(pulse && !reduceMotion ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                .accessibilityLabel("Next")
            }
        }
        .onAppear {
            SpeechService.shared.speak(segments: [.phrase(praise)])
            pulse = true
        }
    }
}
