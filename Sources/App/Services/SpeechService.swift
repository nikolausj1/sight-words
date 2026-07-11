import Foundation
import AVFoundation

/// The teacher voice: speaks words and lines aloud. `speakWord` checks for a
/// bundled clip first (`words/<text>.m4a`, Phase 6 — none exist yet, so this
/// path never fires today) and falls back to AVSpeechSynthesizer. Speech always
/// plays; `profile.soundOn` gates SFX only (`Feedback.fire`), never the teacher
/// voice. `.ambient` session, coordinated with `Feedback`'s own setup.
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synth = AVSpeechSynthesizer()
    private var clipPlayer: AVAudioPlayer?
    private var sessionReady = false

    /// Speaks a single word: bundled clip if present, AVSpeech otherwise.
    func speakWord(_ text: String) {
        prepareSession()
        if let url = clipURL(for: text) {
            playClip(url: url, fallbackText: text)
        } else {
            speakText(text)
        }
    }

    /// Speaks a full line (feedback phrases, sentences) — always AVSpeech.
    func speak(line: String) {
        prepareSession()
        speakText(line)
    }

    private func clipURL(for text: String) -> URL? {
        Bundle.main.url(forResource: "words/\(text.lowercased())", withExtension: "m4a")
    }

    private func playClip(url: URL, fallbackText: String) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            speakText(fallbackText)
            return
        }
        clipPlayer = player
        player.prepareToPlay()
        player.play()
    }

    private func speakText(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        synth.speak(utterance)
    }

    private func prepareSession() {
        guard !sessionReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionReady = true
    }
}
