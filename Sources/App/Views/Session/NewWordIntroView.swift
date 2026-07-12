import SwiftUI

/// New-word introduction (§6.5): a soft "New word" tag, the word speaks itself,
/// then its sentence appears and is read aloud. Purely a beat — no scoring UI;
/// the coordinator flips this same card into a normal `PracticeCardView` when
/// the beat finishes.
struct NewWordIntroView: View {
    @ObservedObject var coordinator: SessionCoordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        VStack(spacing: Theme.Metric.gap * 1.5) {
            // Contract banner: "listening time" while the app teaches, then a
            // green "Your turn!" the moment the closing cue asks the child to
            // read — the visible half of the audio handoff.
            HStack(spacing: 8) {
                Image(systemName: coordinator.introYourTurn ? "mic.fill" : "ear.fill")
                Text(coordinator.introYourTurn ? "Your turn!" : "New word — listen!")
            }
            .font(Theme.Font.label(16))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Capsule().fill(coordinator.introYourTurn ? Theme.Color.correct : Theme.Color.primary))
            .animation(Theme.Motion.snappy, value: coordinator.introYourTurn)

            Text(coordinator.currentWord)
                .font(Theme.Font.display(140))
                .foregroundStyle(Theme.Color.ink)
                .minimumScaleFactor(0.12)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if coordinator.sentenceRevealed, let sentence = coordinator.currentSentence {
                Text(sentence)
                    .font(Theme.Font.body(20))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isCompact ? 24 : 60)
                    .transition(.opacity)
            }
        }
        .padding(Theme.Metric.pad)
        .animation(Theme.Motion.snappy, value: coordinator.sentenceRevealed)
    }
}
