import SwiftUI

/// The core practice card (§6.4): top progress + exit, the word as hero, side
/// controls (speaker / sentence toggle), three big scoring keys on the bottom.
struct PracticeCardView: View {
    @ObservedObject var coordinator: SessionCoordinator
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: Theme.Metric.gap) {
            topBar
            Spacer(minLength: 0)
            wordArea
            Spacer(minLength: 0)
            voiceCheckConfirmBar
            scoringButtons
        }
        .padding(Theme.Metric.pad)
        .overlay(alignment: .topTrailing) { voiceCheckIndicator }
        .animation(Theme.Motion.snappy, value: coordinator.voiceCheckUIState)
    }

    // MARK: Voice-check overlay (§6.8) — solo sessions only, hidden entirely
    // when voice-check is off/unavailable (`voiceCheckUIState` stays `.hidden`).

    @ViewBuilder
    private var voiceCheckIndicator: some View {
        if case .listening = coordinator.voiceCheckUIState {
            PulsingMicIndicator()
                .padding(.trailing, 4)
                .transition(.opacity)
        }
    }

    /// Compact darkPlate bar above the bottom buttons: "I think you said…" +
    /// Yes / Try again. Manual Show-answer/self-score buttons stay visible and
    /// functional underneath the whole time (§6.8: manual always overrides).
    @ViewBuilder
    private var voiceCheckConfirmBar: some View {
        if case .confirming(let heard) = coordinator.voiceCheckUIState {
            HStack(spacing: Theme.Metric.gap) {
                Text("I think you said “\(heard)”. Is that right?")
                    .font(Theme.Font.label(16))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button { coordinator.voiceCheckConfirmYes() } label: {
                    Text("Yes").font(Theme.Font.label(15)).frame(width: 84, height: 44)
                }
                .buttonStyle(ChunkyKeyStyle(base: Theme.Color.correct,
                                           deep: Theme.Color.correct.shaded(by: -0.35), corner: 12))
                Button { coordinator.voiceCheckTryAgain() } label: {
                    Text("Try again").font(Theme.Font.label(15)).frame(width: 116, height: 44)
                }
                .buttonStyle(ChunkyKeyStyle(base: Theme.Color.gentle,
                                           deep: Theme.Color.gentle.shaded(by: -0.35), corner: 12))
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .darkPlate(corner: 16)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var topBar: some View {
        HStack(spacing: Theme.Metric.gap) {
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .darkPlate(corner: 14)
            .buttonStyle(PopButtonStyle())

            VStack(alignment: .leading, spacing: 6) {
                Text("Word \(min(coordinator.completedCount + 1, max(coordinator.totalWords, 1))) of \(coordinator.totalWords)")
                    .font(Theme.Font.label(15))
                    .foregroundStyle(Theme.Color.inkSoft)
                ProgressStrip(completed: coordinator.completedCount, total: coordinator.totalWords,
                             pulseTick: coordinator.pulseTick)
            }
        }
    }

    private var wordArea: some View {
        VStack(spacing: Theme.Metric.gap) {
            Text(coordinator.currentWord)
                .font(Theme.Font.display(140))
                .foregroundStyle(Theme.Color.ink)
                .minimumScaleFactor(0.12)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 80)   // keep clear of the side controls

            if coordinator.sentenceRevealed, let sentence = coordinator.currentSentence {
                Text(sentence)
                    .font(Theme.Font.body(20))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.snappy, value: coordinator.sentenceRevealed)
        .overlay(alignment: .trailing) { sideControls }
    }

    private var sideControls: some View {
        VStack(spacing: 12) {
            Button { coordinator.replayWord() } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .darkPlate(corner: 16)
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel("Replay word")

            if coordinator.currentSentence != nil {
                Button { coordinator.toggleSentence() } label: {
                    Image(systemName: "text.quote")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                }
                .darkPlate(corner: 16)
                .buttonStyle(PopButtonStyle())
                .accessibilityLabel("In a sentence")
            }
        }
    }

    /// Parent-scored gets three buttons (§6.4); solo gets Show-answer, which
    /// swaps into the two self-score buttons once tapped (§6.7). Tricky Words
    /// has no style of its own and renders whichever `controlStyle` it inherited.
    @ViewBuilder
    private var scoringButtons: some View {
        switch coordinator.controlStyle {
        case .parentScored:
            HStack(spacing: Theme.Metric.gap) {
                scoreButton(title: "Got it", systemImage: "checkmark", base: Theme.Color.correct) {
                    coordinator.score(.gotIt)
                }
                scoreButton(title: "Almost", systemImage: "circle", base: Theme.Color.accent) {
                    coordinator.score(.almost)
                }
                scoreButton(title: "Not yet", systemImage: "arrow.counterclockwise", base: Theme.Color.gentle) {
                    coordinator.score(.notYet)
                }
            }
            .disabled(!coordinator.buttonsEnabled)
            .opacity(coordinator.buttonsEnabled ? 1 : 0.5)

        case .solo:
            if coordinator.revealed {
                HStack(spacing: Theme.Metric.gap) {
                    scoreButton(title: "I got it", systemImage: "checkmark", base: Theme.Color.correct) {
                        coordinator.score(.gotIt)
                    }
                    scoreButton(title: "Not yet", systemImage: "arrow.counterclockwise", base: Theme.Color.gentle) {
                        coordinator.score(.notYet)
                    }
                }
                .disabled(!coordinator.buttonsEnabled)
                .opacity(coordinator.buttonsEnabled ? 1 : 0.5)
            } else {
                Button {
                    coordinator.revealAnswer()
                } label: {
                    Text("Show answer")
                        .font(Theme.Font.label(20))
                        .frame(maxWidth: .infinity)
                        .frame(height: 110)
                }
                .buttonStyle(ChunkyKeyStyle(base: Theme.Color.primary, deep: Theme.Color.primary.shaded(by: -0.35)))
                .disabled(!coordinator.buttonsEnabled)
                .opacity(coordinator.buttonsEnabled ? 1 : 0.5)
            }
        }
    }

    private func scoreButton(title: String, systemImage: String, base: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 30, weight: .bold))
                Text(title).font(Theme.Font.label(18))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
        }
        .buttonStyle(ChunkyKeyStyle(base: base, deep: base.shaded(by: -0.35)))
    }
}

/// The thin segmented "Word N of Total" strip. Pulses briefly every 5
/// completed cards (`pulseTick` bump) — never a screen takeover.
struct ProgressStrip: View {
    let completed: Int
    let total: Int
    let pulseTick: Int

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i < completed ? Theme.Color.primary : Theme.Color.ink.opacity(0.12))
                    .frame(height: 6)
            }
        }
        .frame(maxWidth: 240)
        .scaleEffect(y: pulse ? 1.8 : 1, anchor: .center)
        .animation(Theme.Motion.snappy, value: pulse)
        .onChange(of: pulseTick) { _, _ in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pulse = false }
        }
        .accessibilityLabel("\(completed) of \(total) words done")
    }
}

/// Small pulsing mic indicator (§6.8): darkPlate + `mic.fill`, a gentle scale
/// pulse while voice-check is actively listening. Purely decorative — no tap
/// target; manual controls are the only interactive path.
struct PulsingMicIndicator: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .darkPlate(corner: 14)
            .scaleEffect(pulse ? 1.12 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityLabel("Listening")
    }
}
