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

    #if DEBUG
    private var mockWorkItem: DispatchWorkItem?
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
    func startListening(target: String,
                         onTranscript: @escaping (_ text: String, _ confidence: Float, _ isFinal: Bool) -> Void) {
        #if DEBUG
        if Self.isMockActive {
            startMockListening(target: target, onTranscript: onTranscript)
            return
        }
        #endif
        stopListening()
        guard let recognizer, recognizer.isAvailable else { return }

        do { try activateRecordingSession() } catch { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
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

    /// Stops listening and restores the `.ambient` session (§6.8: "stop on card
    /// end/reveal/session exit"; TTS/haptics must go back to their normal,
    /// non-recording behavior once listening ends).
    func stopListening() {
        #if DEBUG
        mockWorkItem?.cancel(); mockWorkItem = nil
        #endif
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
    /// True when either mock launch arg is present. `SessionCoordinator` also
    /// checks this to force `voiceCheckOn` for the session regardless of the
    /// profile's real setting, so the overlay's states are reachable in sim
    /// without hand-editing profile data first.
    static var isMockActive: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-mockVoiceCheck") || args.contains("-mockVoiceCheckConfirm")
    }

    /// Fakes the recognition pipeline: ~2.5s after the card appears, injects one
    /// transcript and never taps the real recognizer/audio engine at all.
    /// `-mockVoiceCheckConfirm` appends "s" to the target (Levenshtein distance
    /// 1) so the confirmation bar is reachable; `-mockVoiceCheck heard=<word>`
    /// injects an arbitrary word (pass the target itself for a confident match).
    private func startMockListening(target: String,
                                    onTranscript: @escaping (String, Float, Bool) -> Void) {
        isListening = true
        let args = ProcessInfo.processInfo.arguments
        let heard: String
        if args.contains("-mockVoiceCheckConfirm") {
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
    }
    #endif
}
