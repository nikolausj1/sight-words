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
    case fillTheBlanks

    // "One more round?" end-of-game flow (Design Direction §6): offered
    // after every `RoundCelebration` where the sitting's 3-set cap hasn't
    // been hit yet, or the gentle close-out once it has.
    case playAgain
    case allDone
    case gardenGrow
    case newFlower

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
        case .fillTheBlanks: return "fill-the-blanks"
        case .playAgain: return "play-again"
        case .allDone: return "all-done"
        case .gardenGrow: return "garden-grow"
        case .newFlower: return "new-flower"
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
        case .fillTheBlanks: return "Fill in the missing letters!"
        case .gardenGrow: return "Look at your garden grow!"
        case .newFlower: return "A new flower!"
        case .playAgain: return "Want to play again?"
        case .allDone: return "All done for now!"
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

    /// Fires exactly once, whenever whatever the most recent `speak*` call
    /// started (a lone clip, a full `speak(segments:)` chain, or the
    /// AVSpeech fallback) actually finishes -- the hook every
    /// `speakAndWait`/`speakWordAndWait` call awaits via a continuation, and
    /// also directly available as a plain completion callback for call sites
    /// that aren't `async` themselves. A second overlapping `speak*` call
    /// before this fires replaces it without invoking the stale one -- every
    /// caller in this app already sequences its own speech (never fires two
    /// beats at once), so this is a documented constraint, not a queue.
    private var pendingCompletion: (() -> Void)?

    private func finishSpeaking() {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
    }

    override init() {
        super.init()
        synth.delegate = self
    }

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
    /// falls back to AVSpeech for them — same as before. `completion` (new,
    /// optional, defaults to nil so every existing fire-and-forget call site
    /// is unaffected) fires once this word actually finishes playing — the
    /// hook `speakWordAndWait` awaits.
    func speakWord(_ text: String, completion: (() -> Void)? = nil) {
        prepareSession()
        playbackQueue = []
        pendingCompletion = completion
        if let url = clipURL(word: text) {
            playClip(url: url, fallbackText: text)
        } else {
            speakText(text)
        }
    }

    /// Speaks a full line — always AVSpeech. The escape hatch for genuinely
    /// dynamic text; everything with a bundled clip should prefer
    /// `speakWord`/`speakSentence`/`speak(segments:)`.
    func speak(line: String, completion: (() -> Void)? = nil) {
        prepareSession()
        playbackQueue = []
        pendingCompletion = completion
        speakText(line)
    }

    /// Speaks a word's example sentence: bundled clip (`sentence-<word>.m4a`)
    /// if present, AVSpeech reading of `text` otherwise (custom words have no
    /// sentence clip).
    func speakSentence(forWord word: String, text: String, completion: (() -> Void)? = nil) {
        prepareSession()
        playbackQueue = []
        pendingCompletion = completion
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
    /// mid-line would be jarring, so it's all-clips or all-AVSpeech. `completion`
    /// fires once the whole chain (or the AVSpeech fallback) finishes.
    func speak(segments: [SpeechSegment], completion: (() -> Void)? = nil) {
        prepareSession()
        pendingCompletion = completion
        if let steps = playbackSteps(for: segments) {
            playbackQueue = steps
            advancePlaybackQueue()
        } else {
            playbackQueue = []
            speakText(composedFallbackText(for: segments))
        }
    }

    // MARK: Speech-length-aware beats (Design Direction §6)
    //
    // `async` wrappers over the completion-callback API above: a beat that
    // needs to wait for a word/line to actually finish (instead of guessing
    // with a fixed `Task.sleep`) awaits one of these. Both enforce
    // `Theme.Motion.beat` as a floor -- "never shorter than the speech," per
    // this pass's brief, cuts the other way too: a very short clip (e.g. a
    // 2-letter word) still holds the beat for at least one calm moment
    // instead of feeling clipped.

    /// Speaks `text` and suspends until it finishes, at least `minimumBeat`.
    @discardableResult
    func speakWordAndWait(_ text: String, minimumBeat: TimeInterval = Theme.Motion.beat) async -> Void {
        let start = Date()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            speakWord(text) { continuation.resume() }
        }
        await holdRemainingBeat(since: start, minimumBeat: minimumBeat)
    }

    /// Speaks `segments` and suspends until the whole line finishes, at
    /// least `minimumBeat`.
    func speakAndWait(segments: [SpeechSegment], minimumBeat: TimeInterval = Theme.Motion.beat) async {
        let start = Date()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            speak(segments: segments) { continuation.resume() }
        }
        await holdRemainingBeat(since: start, minimumBeat: minimumBeat)
    }

    private func holdRemainingBeat(since start: Date, minimumBeat: TimeInterval) async {
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed < minimumBeat else { return }
        try? await Task.sleep(nanoseconds: UInt64((minimumBeat - elapsed) * 1_000_000_000))
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
        // Covers both a lone `playClip` (never populated `playbackQueue` to
        // begin with) and a `speak(segments:)` chain that just finished its
        // last step -- either way, playback is now genuinely done.
        guard !playbackQueue.isEmpty else { clipPlayer = nil; finishSpeaking(); return }
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
        guard !text.isEmpty else { finishSpeaking(); return }
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

extension SpeechService: AVSpeechSynthesizerDelegate {
    /// The AVSpeech-fallback half of `finishSpeaking()` -- fires whenever a
    /// `speakText` utterance (word/line/segments fallback) actually finishes
    /// or is interrupted, same hop-to-MainActor pattern as the audio-player
    /// delegate above.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }
}
