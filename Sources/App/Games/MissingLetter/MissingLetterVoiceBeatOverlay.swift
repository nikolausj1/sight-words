import SwiftUI

/// The 🎤 "Now read it!" beat (Design Direction §6, added this pass): shown
/// after a completed word's own speak-and-wait beat settles, only when
/// voice-check is eligible (`MissingLetterCoordinator` skips straight past
/// this overlay otherwise). Purely presentational -- all of the
/// listening/timeout/self-hearing-guard logic lives in the coordinator, same
/// split as `WordHuntVoiceBeatOverlay`/`SpellingBuilderVoiceOverlay`.
struct MissingLetterVoiceBeatOverlay: View {
    @ObservedObject var coordinator: MissingLetterCoordinator
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
                    Text("Now read it!")
                        .font(Theme.Font.label(20))
                        .foregroundStyle(.white)
                    Text(word)
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
