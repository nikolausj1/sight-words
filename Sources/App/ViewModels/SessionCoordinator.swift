import Foundation

/// Which kind of session this coordinator is running. Only `parentScored` is
/// wired up today; `solo`/`tricky` are next-worker territory (PRD §6.7/§6.9).
enum SessionKind: Equatable {
    case parentScored
    case solo
    case tricky

    var modeLabel: String {
        switch self {
        case .parentScored: return "parent"
        case .solo: return "solo"
        case .tricky: return "tricky"
        }
    }
}

/// The one-session state machine (PRD §6.4-6.6, §6.10). `WordSnapshot` isn't
/// Equatable (Engine is read-only), so this type deliberately isn't Equatable —
/// views/coordinator code pattern-matches with `if case` instead of `==`.
enum SessionPhase {
    case loading
    case intro(WordSnapshot)      // new-word introduction beat, no scoring yet
    case card                     // a scoreable card is on screen
    case feedback(ScoreResult)    // brief post-score beat; buttons disabled
    case reteach(WordSnapshot)    // second-miss interstitial
    case complete
}

/// Owns one Practice Together session end to end: builds the queue via the
/// Engine, tracks phase/timing, speaks the PRD's script, persists every scored
/// exposure immediately (so a mid-session exit never loses anything), and
/// writes the session summary + streak update at the end.
@MainActor
final class SessionCoordinator: ObservableObject {
    @Published private(set) var phase: SessionPhase = .loading
    @Published private(set) var currentWord: String = ""
    @Published private(set) var currentSentence: String?
    @Published var sentenceRevealed: Bool = false
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalWords: Int = 0
    @Published private(set) var pulseTick: Int = 0        // bumps every 5 completed cards
    @Published private(set) var missedWords: [String] = []
    @Published private(set) var buttonsEnabled: Bool = true
    @Published private(set) var reteachStep: Int = 0      // 0: word, 1: say-it pause, 2: spaced, 3: sentence

    private let service: LearningService
    private let speech: SpeechService
    private let profile: Profile
    private let kind: SessionKind
    private let sessionDate: Date
    private let sessionStart: Date

    private var queue: SessionQueue!
    private var currentWordID: String = ""
    private var cardAppearedAt: Date = .now
    private var introducedWords: Set<String> = []
    private var missedSet: Set<String> = []

    private var cardsPlayed = 0
    private var gotItCount = 0
    private var almostCount = 0
    private var notYetCount = 0

    init(service: LearningService, speech: SpeechService, profile: Profile,
         kind: SessionKind = .parentScored, now: Date = .now) {
        self.service = service
        self.speech = speech
        self.profile = profile
        self.kind = kind
        self.sessionDate = now
        self.sessionStart = now
    }

    // MARK: Session lifecycle

    func start() {
        guard case .loading = phase else { return }
        let snapshots = service.pool(for: profile)
        let mode: SessionMode = (kind == .tricky) ? .tricky : .standard
        let words = buildSession(pool: snapshots, size: max(1, profile.sessionSize),
                                 now: sessionDate, calendar: .current, mode: mode)
        queue = SessionQueue(words: words)
        totalWords = queue.totalWords
        advanceToCurrentCard()
    }

    /// Replays the current word's audio (speaker side control).
    func replayWord() { speech.speakWord(currentWord) }

    /// "In a sentence" side control — no-op for words without one.
    func toggleSentence() {
        guard currentSentence != nil else { return }
        sentenceRevealed.toggle()
    }

    // MARK: Scoring

    func score(_ result: ScoreResult) {
        guard case .card = phase, buttonsEnabled, let card = queue.currentCard() else { return }
        buttonsEnabled = false
        let responseMs = max(0, Int(Date().timeIntervalSince(cardAppearedAt) * 1000))
        let word = currentWord
        let wordID = card.id
        phase = .feedback(result)

        switch result {
        case .gotIt: Feedback.fire(.correct); gotItCount += 1
        case .almost: Feedback.fire(.almost); almostCount += 1
        case .notYet: Feedback.fire(.reteach); notYetCount += 1; missedSet.insert(wordID)
        }
        cardsPlayed += 1

        Task { [weak self] in
            guard let self else { return }
            await self.runFeedbackSpeech(result: result, word: word)
            let event = self.queue.score(result: result, responseMs: responseMs, sessionDate: self.sessionDate)
            self.service.recordScore(profile: self.profile, snapshot: event.snapshot)
            self.updateCompletedCount()
            if event.reteachTriggered {
                self.phase = .reteach(event.snapshot)
                self.onReteachEntered()
                await self.runReteach(snapshot: event.snapshot, word: word)
            }
            self.advanceToCurrentCard()
        }
    }

    private func runFeedbackSpeech(result: ScoreResult, word: String) async {
        switch result {
        case .gotIt:
            speech.speak(line: "Correct. \(word).")
            try? await Task.sleep(nanoseconds: 500_000_000)
        case .almost:
            speech.speakWord(word)
            try? await Task.sleep(nanoseconds: 500_000_000)
        case .notYet:
            speech.speak(line: "This word is \(word). Say \(word).")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            speech.speak(line: "Good. We'll see it again soon.")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    private func runReteach(snapshot: WordSnapshot, word: String) async {
        reteachStep = 0
        speech.speakWord(word)
        try? await Task.sleep(nanoseconds: 900_000_000)
        reteachStep = 1
        speech.speak(line: "Say \(word).")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        reteachStep = 2
        speech.speakWord(word)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        reteachStep = 3
        if let sentence = service.sentence(for: snapshot.id) {
            speech.speak(line: sentence)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        speech.speak(line: "Let's see it again soon.")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    private func updateCompletedCount() {
        let newCompleted = queue.completedCount
        guard newCompleted != completedCount else { return }
        completedCount = newCompleted
        if completedCount > 0, completedCount % 5 == 0 {
            pulseTick += 1
            speech.speak(line: "Nice work.")
        }
    }

    // MARK: Card flow

    private func advanceToCurrentCard() {
        guard let card = queue.currentCard() else { finish(); return }
        currentWordID = card.id
        currentWord = service.displayText(forID: card.id)
        currentSentence = service.sentence(for: card.id)
        sentenceRevealed = false
        if card.isNew, !introducedWords.contains(card.id) {
            introducedWords.insert(card.id)
            phase = .intro(card)
            runIntroTask()
        } else {
            enterCardPhase()
        }
    }

    private func runIntroTask() {
        let word = currentWord
        let sentence = currentSentence
        Task { [weak self] in
            guard let self else { return }
            await self.runIntro(word: word, sentence: sentence)
            self.enterCardPhase()
        }
    }

    private func runIntro(word: String, sentence: String?) async {
        speech.speakWord(word)
        try? await Task.sleep(nanoseconds: 900_000_000)
        speech.speak(line: "Say \(word).")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if let sentence {
            sentenceRevealed = true
            speech.speak(line: sentence)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            sentenceRevealed = false
        }
    }

    private func enterCardPhase() {
        phase = .card
        cardAppearedAt = .now
        buttonsEnabled = true
        demoStep()
    }

    private func finish() {
        let duration = Date().timeIntervalSince(sessionStart)
        let stats = LearningService.SessionStats(mode: kind.modeLabel, cardsPlayed: cardsPlayed,
                                                  gotIt: gotItCount, almost: almostCount,
                                                  notYet: notYetCount, durationSec: duration)
        service.sessionFinished(profile: profile, stats: stats, now: sessionDate)
        missedWords = missedSet.map { service.displayText(forID: $0) }.sorted()
        Feedback.fire(.sessionComplete)
        phase = .complete
    }

    // MARK: Debug / screenshot hooks

    #if DEBUG
    enum DemoMode { case reteach, complete, sentence }
    private var demoMode: DemoMode?
    private var demoTargetWordID: String?
    private var demoStop = false

    func enableDemo(_ mode: DemoMode) { demoMode = mode }

    private func onReteachEntered() {
        if demoMode == .reteach { demoStop = true }
    }

    private func demoStep() {
        guard let demoMode, !demoStop, case .card = phase else { return }
        switch demoMode {
        case .sentence:
            if currentSentence != nil, !sentenceRevealed { sentenceRevealed = true }
            demoStop = true   // one-shot: leave the card up for the screenshot
        case .reteach:
            if demoTargetWordID == nil { demoTargetWordID = currentWordID }
            let targetWordID = currentWordID
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, case .card = self.phase, self.currentWordID == targetWordID else { return }
                self.score(self.demoTargetWordID == targetWordID ? .notYet : .gotIt)
            }
        case .complete:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, case .card = self.phase else { return }
                self.score(.gotIt)
            }
        }
    }
    #else
    private func onReteachEntered() {}
    private func demoStep() {}
    #endif
}
