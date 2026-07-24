import SwiftUI

/// The 🎤 "Now you say it!" beat (Games Spec §3.1): shown after a found
/// word's `SuccessMoment` settles, only when voice-check is eligible
/// (`WordHuntCoordinator` skips straight past this overlay otherwise). Purely
/// presentational -- all of the listening/timeout/self-hearing-guard logic
/// lives in the coordinator; this view just reflects `voiceBeatWord`/
/// `voiceListening`/`voiceFlashCorrect`.
struct WordHuntVoiceBeatOverlay: View {
    @ObservedObject var coordinator: WordHuntCoordinator
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let word = coordinator.voiceBeatWord {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(coordinator.voiceFlashCorrect ? Theme.Color.correct : .white)
                        .scaleEffect(pulse && coordinator.voiceListening && !reduceMotion ? 1.15 : 1.0)
                    Text("Now you say it!")
                        .font(Theme.Font.label(20))
                        .foregroundStyle(.white)
                    Text(word.capitalized)
                        .font(Theme.Font.display(36))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                }
                .padding(28)
                .darkPlate(corner: 26)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .onAppear { pulse = true }
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
        }
    }
}
