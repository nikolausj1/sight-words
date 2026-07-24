import SwiftUI

/// Round B: "see it, say it" (Games Spec §3.2, 🎤). Only ever instantiated
/// when `model.voiceAvailable` was true at set-build time (voice-off sets
/// are all Round A) -- this view can assume the mic is usable and starts
/// listening immediately on appear.
struct SayMatchRoundBView: View {
    @ObservedObject var model: SayMatchModel
    let round: SayMatchRound

    private enum BState: Equatable {
        case listening
        case confirming(heard: String)
    }

    @State private var uiState: BState = .listening
    @State private var micLevel: Float = 0
    @State private var micFlashCorrect = false
    @State private var successWord: String?
    @State private var isActive = true   // guards stray callbacks after teardown
    @State private var lastTeacherSpeechAt: Date?
    @State private var gentleNudgeTimer: DispatchWorkItem?
    @State private var rescueTimer: DispatchWorkItem?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        VStack(spacing: Theme.Metric.pad) {
            Spacer(minLength: 0)
            SayMatchTile(text: round.targetDisplay, action: { model.speech.speakWord(round.targetDisplay) })
            PulsingMicIndicator(level: micLevel, flashCorrect: micFlashCorrect)
            Spacer(minLength: 0)
            confirmBar
        }
        .padding(Theme.Metric.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .successMoment(word: $successWord) { model.advance() }
        .onAppear { startRound() }
        .onDisappear { teardown() }
    }

    @ViewBuilder private var confirmBar: some View {
        if case .confirming(let heard) = uiState {
            let promptText = "I think you said “\(heard)”. Is that right?"
            let yesButton = Button {
                acceptMatch()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: isCompact ? nil : 100, height: 64)
                    .frame(maxWidth: isCompact ? .infinity : nil)
            }
            .buttonStyle(ChunkyKeyStyle(base: Theme.Color.correct,
                                       deep: Theme.Color.correct.shaded(by: -0.35), corner: 16))
            .accessibilityLabel("Yes, that's right")

            let tryAgainButton = Button {
                tryAgainTapped()
            } label: {
                Image(systemName: "arrow.circlepath")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: isCompact ? nil : 100, height: 64)
                    .frame(maxWidth: isCompact ? .infinity : nil)
            }
            .buttonStyle(ChunkyKeyStyle(base: Theme.Color.accent,
                                       deep: Theme.Color.accent.shaded(by: -0.35), corner: 16))
            .accessibilityLabel("Try again")

            Group {
                if isCompact {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(promptText).font(Theme.Font.label(16)).foregroundStyle(.white)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: Theme.Metric.gap) { yesButton; tryAgainButton }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                    HStack(spacing: Theme.Metric.gap) {
                        Text(promptText).font(Theme.Font.label(16)).foregroundStyle(.white)
                            .lineLimit(2).minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        yesButton
                        tryAgainButton
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                }
            }
            .darkPlate(corner: 16)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Lifecycle

    private func startRound() {
        isActive = true
        beginListening()
        armTimers()
    }

    private func teardown() {
        isActive = false
        model.voiceCheck.stopListening()
        gentleNudgeTimer?.cancel(); gentleNudgeTimer = nil
        rescueTimer?.cancel(); rescueTimer = nil
    }

    private func beginListening() {
        uiState = .listening
        let target = round.targetDisplay
        #if DEBUG
        if SayMatchModel.demoVoiceForced {
            runDemoVoiceMock(target: target)
            return
        }
        #endif
        model.voiceCheck.startListening(
            target: target,
            contextualStrings: SayMatchModel.contextualStrings(for: target),
            onTranscript: { heard, confidence, isFinal in
                handleTranscript(heard, confidence: confidence, isFinal: isFinal)
            },
            onLevel: { level in
                guard isActive else { return }
                micLevel = level
            }
        )
    }

    #if DEBUG
    /// See `SayMatchModel.demoVoiceForced` -- fakes a plausible mic level
    /// plus a single transcript ~2.5s in, entirely local to this view (never
    /// touches the real `VoiceCheckService`). `-demoSayMatchVoiceConfirm`
    /// emits a one-letter-off near-miss (exercises the confirm bar);
    /// anything else emits a clean match.
    private func runDemoVoiceMock(target: String) {
        micLevel = 0.55
        let heard = ProcessInfo.processInfo.arguments.contains("-demoSayMatchVoiceConfirm")
            ? target + "s" : target
        let item = DispatchWorkItem {
            guard isActive else { return }
            handleTranscript(heard, confidence: 0.9, isFinal: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }
    #endif

    /// Games Spec §3.2: "silence 6s → gentle prompt, 12s → phrase-show-me +
    /// word spoken + advance (counts as timeoutHint)". Both windows are
    /// anchored to round start, not to the most recent transcript activity.
    private func armTimers() {
        let gentle = DispatchWorkItem {
            guard isActive, successWord == nil else { return }
            model.speech.speak(segments: [.phrase(.giveItATry)])
        }
        gentleNudgeTimer = gentle
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: gentle)

        let rescue = DispatchWorkItem {
            guard isActive, successWord == nil else { return }
            runShowMeRescue()
        }
        rescueTimer = rescue
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: rescue)
    }

    private func runShowMeRescue() {
        model.voiceCheck.stopListening()
        model.registerTimeoutHint()
        model.speech.speak(segments: [.phrase(.showMe), .pause(0.2), .word(round.targetDisplay)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard isActive else { return }
            model.advance()
        }
    }

    // MARK: Transcript handling (mirrors SessionCoordinator's voice-check rules)

    private func handleTranscript(_ heard: String, confidence: Float, isFinal: Bool) {
        guard isActive, successWord == nil else { return }
        // Self-hearing guard (Games Spec §3.2): drop anything heard while
        // Rachel is talking, plus a short tail after she stops.
        if model.speech.isSpeakingAloud {
            lastTeacherSpeechAt = Date()
            return
        }
        if let last = lastTeacherSpeechAt, Date().timeIntervalSince(last) < 1.0 { return }

        let tokens = heard.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard let lastToken = tokens.last else { return }
        let target = round.targetDisplay.lowercased()

        let confidentMatch: Bool
        if target.count <= 3 {
            confidentMatch = tokens.count <= 2 && SayMatchModel.homophoneTable.matches(heard: lastToken, target: target)
        } else {
            confidentMatch = tokens.contains { SayMatchModel.homophoneTable.matches(heard: $0, target: target) }
        }

        if confidentMatch {
            if isFinal || confidence >= 0.5 { acceptMatch() }
            return
        }

        guard case .listening = uiState else { return }   // near-misses never re-enter/flicker the confirm bar

        if target.count >= 4, (1...2).contains(levenshteinDistance(lastToken, target)) {
            showNearMiss(heard: lastToken)
        } else if (2...3).contains(target.count), tokens.count == 1, levenshteinDistance(lastToken, target) == 1 {
            showNearMiss(heard: lastToken)
        }
    }

    private func showNearMiss(heard: String) {
        uiState = .confirming(heard: heard)
        model.speech.speak(segments: [.phrase(.wasThatIt)])
    }

    private func tryAgainTapped() {
        guard case .confirming = uiState else { return }
        model.registerWrong()
        beginListening()
    }

    /// A confident match (or a confirmed near-miss) flashes the mic
    /// correct-green for a beat before `SuccessMoment` takes over, then
    /// `model.advance()` fires from that overlay's `onSettled`.
    private func acceptMatch() {
        guard successWord == nil else { return }
        gentleNudgeTimer?.cancel(); rescueTimer?.cancel()
        model.voiceCheck.stopListening()
        micFlashCorrect = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard isActive else { return }
            micFlashCorrect = false
            successWord = round.targetDisplay
        }
    }
}
