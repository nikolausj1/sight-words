import Foundation
import Speech
import AVFoundation

/// On-device speech recognition for the voice-check overlay (PRD §6.8). Always
/// `requiresOnDeviceRecognition = true` — nothing leaves the iPad, en-US only.
/// Permission requests happen only from the parent-area settings flow (never
/// mid-session, never triggered by the child) — see `ParentAreaView`.
///
/// Real on-device recognition does not verify meaningfully in the simulator
/// (Apple limitation, PRD §12/Phase 5) — the DEBUG-only mock path at the bottom
/// of this file lets the overlay's UI states be screenshot-tested there instead
/// of the real pipeline.
@MainActor
final class VoiceCheckService {
    static let shared = VoiceCheckService()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recordingSessionActive = false

    /// Smoothed 0-1 mic level, streamed to whoever's currently listening
    /// (`SessionCoordinator.micLevel`), throttled to ~10Hz — see `reportLevel`.
    private var onLevel: ((Float) -> Void)?
    private var smoothedLevel: Float = 0
    private var lastLevelReportAt: Date = .distantPast

    #if DEBUG
    private var mockWorkItem: DispatchWorkItem?
    private var mockFollowUpWorkItem: DispatchWorkItem?
    private var mockLevelTimer: DispatchSourceTimer?
    #endif

    private(set) var isListening = false

    private init() {}

    // MARK: Permissions — only ever called from the parent-area toggle (§6.8)

    /// Requests speech-recognition, then microphone, permission. Reports true
    /// only if both were granted.
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async { completion(micGranted) }
            }
        }
    }

    /// Static device/locale capability check, for the settings toggle's
    /// disabled state (§6.8) — deliberately independent of permission status
    /// (an unasked user should still see an enabled, tappable toggle).
    func recognizerSupported() -> Bool {
        #if DEBUG
        if Self.isMockActive { return true }
        #endif
        guard let recognizer else { return false }
        return recognizer.isAvailable
    }

    /// Full gate for actually starting a listening session: supported device +
    /// both permissions already granted. §6.8: unavailable at session start ->
    /// the caller runs the session exactly as if voice-check were off.
    func isAvailable() -> Bool {
        #if DEBUG
        if Self.isMockActive { return true }
        #endif
        guard recognizerSupported() else { return false }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return false }
        return AVAudioApplication.shared.recordPermission == .granted
    }

    // MARK: Listening lifecycle (one card at a time)

    /// Starts listening for the card currently showing `target`. `onTranscript`
    /// fires for every partial/final result with confidence + finality; all
    /// match/homophone/near-miss logic lives in the caller (`SessionCoordinator`)
    /// — this service only streams raw recognizer output.
    ///
    /// `contextualStrings` biases the recognizer toward the target word and
    /// its homophone-group members (always on, both mic modes) — no-op on
    /// the DEBUG mock path, which never touches a real request.
    func startListening(target: String,
                         contextualStrings: [String] = [],
                         onTranscript: @escaping (_ text: String, _ confidence: Float, _ isFinal: Bool) -> Void,
                         onLevel: @escaping (_ level: Float) -> Void = { _ in }) {
        #if DEBUG
        if Self.isMockActive {
            self.onLevel = onLevel
            startMockListening(target: target, onTranscript: onTranscript)
            return
        }
        #endif
        stopListening()
        self.onLevel = onLevel
        guard let recognizer, recognizer.isAvailable else { return }

        do { try activateRecordingSession() } catch { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.contextualStrings = contextualStrings
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            let level = Self.rmsLevel(of: buffer)
            Task { @MainActor in self?.reportLevel(level) }
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            request = nil
            deactivateRecordingSession()
            return
        }
        isListening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // Recognizer callbacks land off the main actor — hop back before
            // touching any state or invoking the (MainActor) coordinator closure.
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    let confidence = result.bestTranscription.segments.last?.confidence ?? 0
                    onTranscript(text, confidence, result.isFinal)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopListening()
                }
            }
        }
    }

    /// Hold-to-talk release (mic-mode "hold"): ends the audio input right away
    /// (stops the engine/tap — no more buffers needed) but deliberately does
    /// NOT cancel the recognition task or tear down the request. On-device
    /// recognition often needs a beat after `endAudio()` to deliver the FINAL
    /// transcript for whatever was already said; hard-cancelling here would
    /// drop it. The in-flight task's own callback (final result or error) —
    /// or the caller's short grace timer — still calls `stopListening()` to
    /// finish the teardown, same as Cookie Caper's release flow.
    func endHoldListening() {
        #if DEBUG
        if Self.isMockActive { return }   // mock's own timers self-manage; nothing to end early
        #endif
        guard isListening else { return }
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    /// Stops listening and restores the `.ambient` session (§6.8: "stop on card
    /// end/reveal/session exit"; TTS/haptics must go back to their normal,
    /// non-recording behavior once listening ends).
    func stopListening() {
        #if DEBUG
        mockWorkItem?.cancel(); mockWorkItem = nil
        mockFollowUpWorkItem?.cancel(); mockFollowUpWorkItem = nil
        mockLevelTimer?.cancel(); mockLevelTimer = nil
        #endif
        smoothedLevel = 0
        onLevel = nil
        guard isListening || audioEngine.isRunning || recordingSessionActive else { return }
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        deactivateRecordingSession()
    }

    /// Smooths + throttles raw per-buffer RMS to ~10Hz before handing it to the
    /// coordinator — the audio tap fires far faster than the UI needs to redraw.
    private func reportLevel(_ raw: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelReportAt) >= 0.1 else { return }
        lastLevelReportAt = now
        smoothedLevel = smoothedLevel * 0.6 + raw * 0.4
        onLevel?(smoothedLevel)
    }

    /// Rough 0-1 loudness estimate from one PCM buffer. Not calibrated to any
    /// spec — just needs to move plausibly with voice, for the pulsing-mic UI.
    private nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength { let s = samples[i]; sum += s * s }
        let rms = sqrt(sum / Float(frameLength))
        return min(max(rms * 8, 0), 1)
    }

    // MARK: Audio session coordination

    /// `SpeechService`/`Feedback` both use `.ambient` so the app never
    /// interrupts music/podcasts. Recording needs `.playAndRecord`, so a
    /// voice-check session switches categories for its duration and restores
    /// `.ambient` the moment it stops — `.mixWithOthers` + `.defaultToSpeaker`
    /// keep the teacher voice (TTS) audible over the speaker the whole time.
    private func activateRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        recordingSessionActive = true
    }

    private func deactivateRecordingSession() {
        guard recordingSessionActive else { return }
        recordingSessionActive = false
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: DEBUG mock (sim can't do on-device recognition — §6.8/Phase 5 note)

    #if DEBUG
    /// True when any mock launch arg is present. `SessionCoordinator` also
    /// checks this to force `voiceCheckOn` for the session regardless of the
    /// profile's real setting, so the overlay's states are reachable in sim
    /// without hand-editing profile data first.
    static var isMockActive: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-mockVoiceCheck") || args.contains("-mockVoiceCheckConfirm")
            || args.contains("-mockVoiceCheckConfirmRepeat") || args.contains("-mockVoiceCheckNudge")
            || args.contains("-demoHoldMic") || args.contains("-demoHoldMicHeld")
    }

    /// Fakes the recognition pipeline and never taps the real recognizer/audio
    /// engine at all. Always streams a plausible oscillating `onLevel` while
    /// "listening" (ux2 mic-level screenshot; rule 5), same as the real tap.
    /// Transcript behavior depends on the launch arg:
    /// - `-mockVoiceCheckConfirm`: ~2.5s in, appends "s" to the target
    ///   (Levenshtein distance 1) so the confirmation bar is reachable.
    /// - `-mockVoiceCheckConfirmRepeat`: same near-miss at ~2.5s, then a clean
    ///   repeat of the target itself at ~5s — exercises rule 4 (confident
    ///   match accepted while the confirm bar is still showing, mic never
    ///   stopped in between).
    /// - `-mockVoiceCheckNudge`: never emits a transcript at all, so both
    ///   silence timers (rule 6) get to fire; pair with the coordinator's
    ///   compressed nudge delays for screenshotting.
    /// - `-mockVoiceCheck heard=<word>`: injects an arbitrary word once
    ///   (pass the target itself for a confident match).
    private func startMockListening(target: String,
                                    onTranscript: @escaping (String, Float, Bool) -> Void) {
        isListening = true
        mockWorkItem?.cancel(); mockFollowUpWorkItem?.cancel()
        startMockLevelOscillation()
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("-mockVoiceCheckNudge") else { return }

        let heard: String
        if args.contains("-mockVoiceCheckConfirm") || args.contains("-mockVoiceCheckConfirmRepeat")
            || args.contains("-demoHoldMicHeld") {
            heard = target + "s"
        } else if let pair = args.first(where: { $0.hasPrefix("heard=") }) {
            heard = String(pair.dropFirst("heard=".count))
        } else {
            heard = target
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            onTranscript(heard, 0.9, true)
        }
        mockWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)

        if args.contains("-mockVoiceCheckConfirmRepeat") || args.contains("-demoHoldMicHeld") {
            // Re-emit the clean repeat every 3s (like a real kid repeating the
            // word) — a single shot can land inside the self-hearing guard's
            // window around the spoken "I heard …" question and vanish.
            scheduleMockRepeat(target: target, attempt: 0, onTranscript: onTranscript)
        }
    }

    private func scheduleMockRepeat(target: String, attempt: Int,
                                    onTranscript: @escaping (String, Float, Bool) -> Void) {
        guard attempt < 5 else { return }
        let followUp = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            onTranscript(target, 0.9, true)
            self.scheduleMockRepeat(target: target, attempt: attempt + 1, onTranscript: onTranscript)
        }
        mockFollowUpWorkItem = followUp
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 5.0 : 3.0), execute: followUp)
    }

    /// Oscillates `onLevel` at ~10Hz while the mock is "listening", so
    /// `PulsingMicIndicator` has something plausible to render (rule 5).
    private func startMockLevelOscillation() {
        mockLevelTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        var tick = 0
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self, self.isListening else { return }
            tick += 1
            let level = Float(0.5 + 0.45 * sin(Double(tick) * 0.5))
            self.onLevel?(max(0, min(1, level)))
        }
        mockLevelTimer = timer
        timer.resume()
    }
    #endif
}
