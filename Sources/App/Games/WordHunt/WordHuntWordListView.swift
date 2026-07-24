import SwiftUI

/// The list panel (Games Spec §3.1): "tap any word = hear it, found = grayed
/// + check. T3 hint only via double-tap on list word" -- tap-to-hear is
/// never gated, even on an already-found word (Games Spec §1: "tap-to-hear
/// everywhere ... never gated").
struct WordHuntWordListView: View {
    @ObservedObject var coordinator: WordHuntCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(coordinator.listWords, id: \.self) { word in
                row(for: word)
            }
        }
    }

    private func row(for word: String) -> some View {
        WordHuntListRow(word: word, found: coordinator.foundWords.contains(word))
            // T3's "hint on demand only" (Games Spec §3.1): double-tapping an
            // unfound word pulses its letters, same as the idle auto-hint at
            // T1/T2 -- harmless to also offer this at lower tiers, it's just
            // redundant with the timer there.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                coordinator.requestManualHint(for: word)
            })
    }
}

/// One list row, its own tiny view so it can privately track "did I just get
/// found" and pop -- `WordHuntWordListView.row(for:)` only knows this word's
/// current `found` state, not the transition, so the pop has to live here.
private struct WordHuntListRow: View {
    let word: String
    let found: Bool
    @State private var justFound = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            SpeechService.shared.speakWord(word)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: found ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(found ? Theme.Color.correct : Theme.Color.inkSoft.opacity(0.4))
                Text(word)
                    .font(Theme.Font.label(18))
                    .strikethrough(found)
                    .foregroundStyle(found ? Theme.Color.inkSoft : Theme.Color.ink)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(found ? Theme.Color.correct.opacity(0.12) : Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PopButtonStyle())
        .scaleEffect(justFound ? 1.05 : 1.0)
        .animation(Theme.Motion.tileLift, value: justFound)
        .onChange(of: found) { wasFoundBefore, isFoundNow in
            guard isFoundNow, !wasFoundBefore, !reduceMotion else { return }
            justFound = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { justFound = false }
        }
    }
}
