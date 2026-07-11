import SwiftUI

/// The core practice card (§6.4): top progress + exit, the word as hero, side
/// controls (speaker / sentence toggle), three big scoring keys on the bottom.
struct PracticeCardView: View {
    @ObservedObject var coordinator: SessionCoordinator
    let onExit: () -> Void
    @State private var showAnswerPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// Rule 4/5 (UX pass): the mic stays live through `.confirming` too (a
    /// clean repeat auto-accepts without a tap), so the indicator shows for
    /// both states — plus whenever a confident match just flashed green, even
    /// in the instant before the state resets to `.hidden` on card advance.
    @ViewBuilder
    private var voiceCheckIndicator: some View {
        if coordinator.voiceCheckUIState != .hidden || coordinator.micFlashCorrect {
            PulsingMicIndicator(level: coordinator.micLevel, flashCorrect: coordinator.micFlashCorrect)
                .padding(.trailing, 4)
                .transition(.opacity)
        }
    }

    /// Compact darkPlate bar above the bottom buttons: "I think you said…" +
    /// two BIG icon buttons (rule 1, UX pass) — a pre-reader can't reliably
    /// read "Yes"/"Try again" text, so the buttons are icon-first; the text
    /// stays for the parent looking over a shoulder. Manual Show-answer/
    /// self-score buttons stay visible and functional underneath the whole
    /// time (§6.8: manual always overrides).
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
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .frame(width: 110, height: 72)
                }
                .buttonStyle(ChunkyKeyStyle(base: Theme.Color.correct,
                                           deep: Theme.Color.correct.shaded(by: -0.35), corner: 16))
                .accessibilityLabel("Yes, I said it right")
                Button { coordinator.voiceCheckTryAgain() } label: {
                    Image(systemName: "arrow.circlepath")
                        .font(.system(size: 32, weight: .bold))
                        .frame(width: 110, height: 72)
                }
                .buttonStyle(ChunkyKeyStyle(base: Theme.Color.accent,
                                           deep: Theme.Color.accent.shaded(by: -0.35), corner: 16))
                .accessibilityLabel("Try again")
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
                .opacity(showAnswerOpacity)
                .scaleEffect(showAnswerScale)
                .onChange(of: coordinator.nudgeShowAnswer) { _, active in
                    if active {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            showAnswerPulse = true
                        }
                    } else {
                        withAnimation(Theme.Motion.quick) { showAnswerPulse = false }
                    }
                }
            }
        }
    }

    /// Rule 6 (UX pass): after two silence windows with no attempt, the
    /// Show-answer button gets a gentle repeating pulse — an obvious next
    /// step for a pre-reader alone, instead of waiting indefinitely. Scale
    /// under normal motion; opacity-only under Reduce Motion.
    private var showAnswerScale: CGFloat {
        guard !reduceMotion else { return 1.0 }
        return showAnswerPulse ? 1.05 : 1.0
    }
    private var showAnswerOpacity: Double {
        let base = coordinator.buttonsEnabled ? 1.0 : 0.5
        guard reduceMotion else { return base }
        return showAnswerPulse ? base * 0.7 : base
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

/// Small pulsing mic indicator (§6.8, rule 5 of the UX pass): darkPlate +
/// `mic.fill`, rendered so its scale/brightness follows the live `level`
/// (0-1, streamed from `VoiceCheckService`'s audio tap or mock) instead of a
/// fixed timer pulse. A subtle idle pulse is layered on top as a floor so it
/// never looks frozen even at silence, and on a confident match the plate
/// flashes correct-green for a beat (`flashCorrect`) before the card advances.
/// Reduce Motion: level/idle are conveyed via opacity instead of scale.
/// Purely decorative — no tap target; manual controls are the only
/// interactive path.
struct PulsingMicIndicator: View {
    var level: Float = 0
    var flashCorrect: Bool = false
    @State private var idlePulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedLevel: CGFloat { CGFloat(min(max(level, 0), 1)) }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1.0 }
        let levelScale = 1.0 + clampedLevel * 0.32
        let idleFloor: CGFloat = idlePulse ? 1.05 : 1.0
        return max(levelScale, idleFloor)
    }

    private var plateOpacity: Double {
        guard reduceMotion else { return 1.0 }
        let base = 0.55 + Double(clampedLevel) * 0.35
        let idleFloor: Double = idlePulse ? 0.1 : 0
        return min(1, base + idleFloor)
    }

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .darkPlate(corner: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Color.correct)
                    .opacity(flashCorrect ? 0.88 : 0)
                    .allowsHitTesting(false)
            )
            .scaleEffect(scale)
            .opacity(plateOpacity)
            .animation(Theme.Motion.quick, value: level)
            .animation(Theme.Motion.snappy, value: flashCorrect)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    idlePulse = true
                }
            }
            .accessibilityLabel(flashCorrect ? "Heard you!" : "Listening")
    }
}
