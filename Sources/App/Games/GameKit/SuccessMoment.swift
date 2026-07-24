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
                    // .id + .task(id:) give each word its own presentation
                    // lifecycle: back-to-back successes (word set A -> B with
                    // no nil in between) refire the entrance and speech, and
                    // the previous word's dismiss timer is auto-cancelled --
                    // a DispatchQueue timer here could either never schedule
                    // for B or dismiss B early with A's stale timer.
                    SuccessMoment(word: w)
                        .id(w)
                        .transition(.opacity)
                        .task(id: w) {
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            guard !Task.isCancelled else { return }
                            word = nil
                            onSettled()
                        }
                }
            }
            .animation(Theme.Motion.snappy, value: word)
    }
}
