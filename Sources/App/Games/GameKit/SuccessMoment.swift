import SwiftUI

/// The shared "found/completed it" beat (Games Spec §1): the word zooms
/// large center-screen in the highlight color, Rachel speaks it, confetti
/// bursts -- ~1.4s, then settles. Same beat in every game.
struct SuccessMoment: View {
    let word: String
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                GameConfettiBurst()
                    .frame(width: 280, height: 240)
            }
            Text(word)
                .font(Theme.Font.display(72))
                .foregroundStyle(Theme.Color.correct)
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            SpeechService.shared.speakWord(word)
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(Theme.Motion.celebrate) { appeared = true }
            }
        }
    }
}

extension View {
    /// Presents `SuccessMoment` centered over this view whenever `word` is
    /// non-nil, then clears it back to `nil` after ~1.4s (Games Spec §1) and
    /// calls `onSettled`. Callers own advancing their own game state from
    /// `onSettled` -- this modifier only owns the presentation timing.
    func successMoment(word: Binding<String?>, onSettled: @escaping () -> Void = {}) -> some View {
        modifier(SuccessMomentModifier(word: word, onSettled: onSettled))
    }
}

private struct SuccessMomentModifier: ViewModifier {
    @Binding var word: String?
    let onSettled: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let w = word {
                    SuccessMoment(word: w)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                word = nil
                                onSettled()
                            }
                        }
                }
            }
            .animation(Theme.Motion.snappy, value: word)
    }
}
