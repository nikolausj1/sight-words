import SwiftUI

/// Screen F — Session complete (§6.10). Word-count summary in the child's
/// voice, an optional "practice again" list, one warm celebrate-spring — no
/// stars, no scores.
struct SessionCompleteView: View {
    @ObservedObject var coordinator: SessionCoordinator
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Metric.gap * 1.5) {
            Image(systemName: "star.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Color.accent)
                .scaleEffect(appeared ? 1 : 0.3)
                .rotationEffect(.degrees(appeared ? 0 : -25))

            Text("You read \(coordinator.totalWords) words!")
                .font(Theme.Font.display(44))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.center)

            if !coordinator.missedWords.isEmpty {
                Text("We'll practice these again: \(coordinator.missedWords.joined(separator: ", "))")
                    .font(Theme.Font.body(18))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }

            Button(action: onDone) {
                Text("Done")
                    .font(Theme.Font.label(20))
                    .frame(width: 200, height: 64)
            }
            .buttonStyle(ChunkyKeyStyle(base: Theme.Color.primary,
                                       deep: Theme.Color.primary.shaded(by: -0.35)))
            .padding(.top, Theme.Metric.gap)
        }
        .padding(Theme.Metric.pad)
        .onAppear {
            withAnimation(Theme.Motion.celebrate) { appeared = true }
        }
    }
}
