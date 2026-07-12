import SwiftUI

/// Reteach interstitial (§6.6), triggered by a second miss of the same word in
/// one session: the word, a "say it" beat, spaced-out letters while it's said
/// again, then the sentence — all auto-paced by the coordinator's speech beats.
struct ReteachView: View {
    @ObservedObject var coordinator: SessionCoordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    private var spacedLetters: String {
        coordinator.currentWord.map(String.init).joined(separator: "  ")
    }

    var body: some View {
        VStack(spacing: Theme.Metric.gap * 1.5) {
            Text("Let's look closer")
                .font(Theme.Font.label(16))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Capsule().fill(Theme.Color.gentle))

            Text(coordinator.reteachStep >= 2 ? spacedLetters : coordinator.currentWord)
                .font(Theme.Font.display(coordinator.reteachStep >= 2 ? 84 : 140))
                .foregroundStyle(Theme.Color.ink)
                .minimumScaleFactor(0.12)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if coordinator.reteachStep >= 3, let sentence = coordinator.currentSentence {
                Text(sentence)
                    .font(Theme.Font.body(20))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isCompact ? 24 : 60)
                    .transition(.opacity)
            }
        }
        .padding(Theme.Metric.pad)
        .animation(Theme.Motion.snappy, value: coordinator.reteachStep)
    }
}
