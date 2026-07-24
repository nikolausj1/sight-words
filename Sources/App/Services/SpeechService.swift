import Foundation
import AVFoundation

/// The 7 fixed feedback phrases that get bundled ElevenLabs clips
/// (`phrase-<slug>.m4a`, flat in the bundle root). Each phrase also knows its
/// spoken-text fallback, used both for a solo AVSpeech utterance of that
/// phrase and for composing the full fallback line in `speak(segments:)`.
enum PhraseClip {
    case correct
    case thisWordIs
    case say
    case goodSeeAgain
    case letsSeeAgain
    case niceWork
    case giveItATry
    case tapBlueButton
    case readOutLoud
    case wasThatIt
    case yourTurn

    // GameKit phrases (Games Spec §4). Clips may not exist yet -- every
    // case below has a `fallbackText`, so `speak(segments:)`'s all-clips-or-
    // AVSpeech rule still degrades cleanly.
    case findTheWords
    case whichWord
    case matchTheCards
    case nowYouSayIt
    case readIt
    case sayThenBuild
    case sayItToBankIt
    case praise1
    case praise2
    case praise3
    case praise4
    case showMe

    var slug: String {
        switch self {
        case .correct: return "correct"
        case .thisWordIs: return "this-word-is"
        case .say: return "say"
        case .goodSeeAgain: return "good-see-again"
        case .letsSeeAgain: return "lets-see-again"
        case .niceWork: return "nice-work"
        case .giveItATry: return "give-it-a-try"
        case .tapBlueButton: return "tap-blue-button"
        case .readOutLoud: return "read-out-loud"
        case .wasThatIt: return "was-that-it"
        case .yourTurn: return "your-turn"
        case .findTheWords: return "find-the-words"
        case .whichWord: return "which-word"
        case .matchTheCards: return "match-the-cards"
        case .nowYouSayIt: return "now-you-say-it"
        case .readIt: return "read-it"
        case .sayThenBuild: return "say-then-build"
        case .sayItToBankIt: return "say-it-to-bank-it"
        case .praise1: return "praise-1"
        case .praise2: return "praise-2"
        case .praise3: return "praise-3"
        case .praise4: return "praise-4"
        case .showMe: return "show-me"
        }
    }

    var fallbackText: String {
        switch self {
        case .correct: return "Correct."
        case .thisWordIs: return "This word is"
        case .say: return "Say"
        case .goodSeeAgain: return "Good. We'll see it again soon."
        case .letsSeeAgain: return "Let's see it again soon."
        case .niceWork: return "Nice work!"
        case .giveItATry: return "Give it a try, or tap Show answer."
        case .tapBlueButton: return "Tap the blue button to hear it."
        case .readOutLoud: return "Read each word out loud!"
        case .wasThatIt: return "Was that it? Tap the green check — or try again!"
        case .yourTurn: return "Your turn!"
        case .findTheWords: return "Find the words!"
        case .whichWord: return "Which word did you hear?"
        case .matchTheCards: return "Match the cards!"
        case .nowYouSayIt: return "Now you say it!"
        case .readIt: return "Read it!"
        case .sayThenBuild: return "Say the word, then build it!"
        case .sayItToBankIt: return "Say it to bank it!"
        case .praise1: return "Amazing!"
        case .praise2: return "You got it!"
        case .praise3: return "Wow, great reading!"
        case .praise4: return "That was awesome!"
        case .showMe: return "Here it is!"
        }
    }
}

/// One beat of a spoken line: a Dolch word, one of the fixed feedback
/// phrases, or a silent gap between beats (honored only on the all-clips
/// path — see `speak(segments:)`).
enum SpeechSegment {
    case word(String)
    case phrase(PhraseClip)
    case pause(TimeInterval)
}

/// The teacher voice: speaks words and lines aloud. Bundled ElevenLabs clips
/// are looked up flat in the bundle root (`word-<text>.m4a`,
/// `phrase-<slug>.m4a`); AVSpeechSynthesizer is the fallback whenever a clip
/// isn't there (custom words never have one). Speech always plays;
/// `profile.soundOn` gates SFX only (`Feedback.fire`), never the teacher
/// voice. `.ambient` session, coordinated with `Feedback`'s own setup, and
/// left alone the rest of the time so voice-check's temporary switch to
/// `.playAndRecord` (`.mixWithOthers`) doesn't get stomped on mid-listen.
@MainActor
final class SpeechService: NSObject {
    static let shared = SpeechService()

    private let synth = AVSpeechSynthesizer()
    private var clipPlayer: AVAudioPlayer?
    private var sessionReady = false

    /// Remaining steps of an in-flight all-clips `speak(segments:)` chain.
    private var playbackQueue: [PlaybackStep] = []

    /// True while the teacher voice is audible (clip, chain, or AVSpeech).
    /// Voice-check drops transcripts while this is true — with no echo
    /// cancellation on the plain input tap, the mic can hear the iPad's own
    /// speaker and would otherwise score the app's voice as the child's.
    var isSpeakingAloud: Bool {
        synth.isSpeaking || clipPlayer?.isPlaying == true || !playbackQueue.isEmpty
    }

    private enum PlaybackStep {
        case clip(URL)
        case pause(TimeInterval)
    }

    /// Speaks a single word: bundled clip if present, AVSpeech otherwise.
    /// Custom words (not in the Dolch list) never have a clip, so this always
    /// falls back to AVSpeech for them — same as before.
    func speakWord(_ text: String) {
        prepareSession()
        playbackQueue = []
        if let url = clipURL(word: text) {
            playClip(url: url, fallbackText: text)
        } else {
            speakText(text)
        }
    }

    /// Speaks a full line — always AVSpeech. The escape hatch for genuinely
    /// dynamic text; everything with a bundled clip should prefer
    /// `speakWord`/`speakSentence`/`speak(segments:)`.
    func speak(line: String) {
        prepareSession()
        playbackQueue = []
        speakText(line)
    }

    /// Speaks a word's example sentence: bundled clip (`sentence-<word>.m4a`)
    /// if present, AVSpeech reading of `text` otherwise (custom words have no
    /// sentence clip).
    func speakSentence(forWord word: String, text: String) {
        prepareSession()
        playbackQueue = []
        if let url = Bundle.main.url(forResource: "sentence-\(word.lowercased())", withExtension: "m4a") {
            playClip(url: url, fallbackText: text)
        } else {
            speakText(text)
        }
    }

    /// Speaks a composed line made of words/phrases (+ pauses). All-or-nothing:
    /// if every word/phrase segment has a bundled clip, plays them back-to-back
    /// via chained `AVAudioPlayer`s, honoring `.pause` gaps in between. If even
    /// one clip is missing, the whole line falls back to a single AVSpeech
    /// utterance instead — mixing a recorded voice with the synthesized one
    /// mid-line would be jarring, so it's all-clips or all-AVSpeech.
    func speak(segments: [SpeechSegment]) {
        prepareSession()
        if let steps = playbackSteps(for: segments) {
            playbackQueue = steps
            advancePlaybackQueue()
        } else {
            playbackQueue = []
            speakText(composedFallbackText(for: segments))
        }
    }

    private func clipURL(word text: String) -> URL? {
        Bundle.main.url(forResource: "word-\(text.lowercased())", withExtension: "m4a")
    }

    private func clipURL(phrase: PhraseClip) -> URL? {
        Bundle.main.url(forResource: "phrase-\(phrase.slug)", withExtension: "m4a")
    }

    /// Returns the clip/pause steps for `segments`, or nil if any word/phrase
    /// segment lacks a bundled clip (triggering the all-AVSpeech fallback).
    private func playbackSteps(for segments: [SpeechSegment]) -> [PlaybackStep]? {
        var steps: [PlaybackStep] = []
        for segment in segments {
            switch segment {
            case .word(let text):
                guard let url = clipURL(word: text) else { return nil }
                steps.append(.clip(url))
            case .phrase(let phrase):
                guard let url = clipURL(phrase: phrase) else { return nil }
                steps.append(.clip(url))
            case .pause(let interval):
                steps.append(.pause(interval))
            }
        }
        return steps
    }

    /// Approximates the segment sequence as one natural sentence for the
    /// AVSpeech fallback (e.g. `[.phrase(.thisWordIs), .word("cat"), .pause,
    /// .phrase(.say), .word("cat")]` -> "This word is cat. Say cat.").
    private func composedFallbackText(for segments: [SpeechSegment]) -> String {
        segments.compactMap { segment -> String? in
            switch segment {
            case .word(let text): return "\(text)."
            case .phrase(let phrase): return phrase.fallbackText
            case .pause: return nil
            }
        }.joined(separator: " ")
    }

    private func advancePlaybackQueue() {
        guard !playbackQueue.isEmpty else { clipPlayer = nil; return }
        let step = playbackQueue.removeFirst()
        switch step {
        case .pause(let interval):
            let item = DispatchWorkItem { [weak self] in self?.advancePlaybackQueue() }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
        case .clip(let url):
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                advancePlaybackQueue()   // shouldn't happen — steps() already confirmed the URL
                return
            }
            player.delegate = self
            clipPlayer = player
            player.prepareToPlay()
            player.play()
        }
    }

    private func playClip(url: URL, fallbackText: String) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            speakText(fallbackText)
            return
        }
        player.delegate = self
        clipPlayer = player
        player.prepareToPlay()
        player.play()
    }

    /// Best installed en-US voice, chosen once: premium > enhanced > default.
    /// The compact default is noticeably robotic; if Justin downloads a
    /// premium voice on a device (Settings > Accessibility > Spoken Content >
    /// Voices), the fallback path picks it up automatically on next launch.
    private static let fallbackVoice: AVSpeechSynthesisVoice? = {
        let enUS = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        return enUS.first { $0.quality == .premium }
            ?? enUS.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    private func speakText(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.fallbackVoice
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

extension SpeechService: AVAudioPlayerDelegate {
    /// Delegate callback arrives off the main thread; hop back to advance the
    /// (MainActor-owned) playback queue, whether this clip was a lone
    /// `speakWord`/`playClip` or one link in a `speak(segments:)` chain.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.advancePlaybackQueue()
        }
    }
}
