import Foundation

/// Which kind of session this coordinator is running: which deck the Engine
/// builds (parent/solo both use `SessionMode.standard`; tricky uses
/// `SessionMode.tricky`, PRD §6.9) and which control style the view defaults to.
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

/// Which bottom-control layout a session shows: parent-scored's three buttons
/// (Got it/Almost/Not yet) or solo's Show-answer -> self-score flow (§6.7).
/// Tricky Words has no style of its own — it mirrors whichever was last used
/// (§6.3), stored on `Profile.lastUsedControlStyle`.
enum ControlStyle: String {
    case parentScored = "parent"
    case solo = "solo"
}

/// Voice-check overlay UI state for the current card (§6.8). `.hidden` covers
/// both "off/unavailable" and "not currently listening" — `PracticeCardView`
/// renders nothing in that case.
enum VoiceCheckUIState: Equatable {
    case hidden
    case listening
    case confirming(heard: String)
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
    @Published private(set) var revealed: Bool = false    // On My Own (§6.7): Show-answer has been tapped

    /// Voice-check overlay state for the card on screen (§6.8). Structurally
    /// only reachable in solo (On My Own) sessions — see `voiceCheckEligible`.
    @Published private(set) var voiceCheckUIState: VoiceCheckUIState = .hidden

    /// Fixed for the whole session — see `ControlStyle`.
    let controlStyle: ControlStyle

    private let service: LearningService
    private let speech: SpeechService
    private let voiceCheck: VoiceCheckService
    private let profile: Profile
    private let kind: SessionKind
    private let sessionDate: Date
    private let sessionStart: Date

    /// Loaded once from the bundled JSON (§6.8) — parses to an empty table if
    /// the resource is missing, which just disables homophone-set matching.
    private static let homophones: HomophoneTable = {
        guard let url = Bundle.main.url(forResource: "homophones", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return HomophoneTable(json: Data("[]".utf8)) }
        return HomophoneTable(json: data)
    }()

    private var voiceCheckTries = 0
    private var voiceCheckCardToken = UUID()
    private var voiceCheckSilenceTimer: DispatchWorkItem?

    private var queue: SessionQueue!
    private var currentWordID: String = ""
    private var cardAppearedAt: Date = .now
    private var revealedResponseMs: Int?
    private var introducedWords: Set<String> = []
    private var missedSet: Set<String> = []

    private var cardsPlayed = 0
    private var gotItCount = 0
    private var almostCount = 0
    private var notYetCount = 0

    init(service: LearningService, speech: SpeechService, profile: Profile,
         kind: SessionKind = .parentScored, now: Date = .now, voiceCheck: VoiceCheckService = .shared) {
        self.service = service
        self.speech = speech
        self.voiceCheck = voiceCheck
        self.profile = profile
        self.kind = kind
        self.sessionDate = now
        self.sessionStart = now
        switch kind {
        case .parentScored: self.controlStyle = .parentScored
        case .solo: self.controlStyle = .solo
        case .tricky: self.controlStyle = ControlStyle(rawValue: profile.lastUsedControlStyle) ?? .parentScored
        }
    }

    // MARK: Session lifecycle

    func start() {
        guard case .loading = phase else { return }
        if kind != .tricky {
            service.recordControlStyleUsed(profile: profile, style: controlStyle.rawValue)
        }
        let snapshots = service.pool(for: profile)
        let mode: SessionMode = (kind == .tricky) ? .tricky : .standard
        let words = buildSession(pool: snapshots, size: max(1, profile.sessionSize),
                                 now: sessionDate, calendar: .current, mode: mode)
        queue = SessionQueue(words: words)
        totalWords = queue.totalWords
        advanceToCurrentCard()
    }

    /// On My Own (§6.7): reveals the word aloud and swaps the Show-answer
    /// button for the two self-score buttons. Response time is captured now
    /// (word-appear -> this tap), not at the later self-score tap.
    func revealAnswer() {
        guard case .card = phase, controlStyle == .solo, buttonsEnabled, !revealed else { return }
        revealed = true
        revealedResponseMs = max(0, Int(Date().timeIntervalSince(cardAppearedAt) * 1000))
        stopVoiceCheck()   // §6.8: stop listening on reveal; manual path takes over
        speech.speakWord(currentWord)
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
        if controlStyle == .solo, !revealed { return }
        stopVoiceCheck()   // §6.8: stop listening on card end, however it was scored
        buttonsEnabled = false
        // Solo mode passes the Show-answer tap time (word-appear -> reveal),
        // per §6.7 — not the later self-score tap.
        let responseMs = revealedResponseMs ?? max(0, Int(Date().timeIntervalSince(cardAppearedAt) * 1000))
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
            speech.speak(segments: [.phrase(.correct), .pause(0.15), .word(word)])
            try? await Task.sleep(nanoseconds: 500_000_000)
        case .almost:
            speech.speakWord(word)
            try? await Task.sleep(nanoseconds: 500_000_000)
        case .notYet:
            speech.speak(segments: [.phrase(.thisWordIs), .word(word), .pause(0.3), .phrase(.say), .word(word)])
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            speech.speak(segments: [.phrase(.goodSeeAgain)])
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    private func runReteach(snapshot: WordSnapshot, word: String) async {
        reteachStep = 0
        speech.speakWord(word)
        try? await Task.sleep(nanoseconds: 900_000_000)
        reteachStep = 1
        speech.speak(segments: [.phrase(.say), .word(word)])
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        reteachStep = 2
        speech.speakWord(word)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        reteachStep = 3
        if let sentence = service.sentence(for: snapshot.id) {
            speech.speak(line: sentence)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        speech.speak(segments: [.phrase(.letsSeeAgain)])
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    private func updateCompletedCount() {
        let newCompleted = queue.completedCount
        guard newCompleted != completedCount else { return }
        completedCount = newCompleted
        if completedCount > 0, completedCount % 5 == 0 {
            pulseTick += 1
            speech.speak(segments: [.phrase(.niceWork)])
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
        speech.speak(segments: [.phrase(.say), .word(word)])
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
        revealed = false
        revealedResponseMs = nil
        resetVoiceCheckForNewCard()
        if voiceCheckEligible { beginVoiceCheckListening() }
        demoStep()
    }

    private func finish() {
        tearDownVoiceCheck()
        let duration = Date().timeIntervalSince(sessionStart)
        let stats = LearningService.SessionStats(mode: kind.modeLabel, cardsPlayed: cardsPlayed,
                                                  gotIt: gotItCount, almost: almostCount,
                                                  notYet: notYetCount, durationSec: duration)
        service.sessionFinished(profile: profile, stats: stats, now: sessionDate)
        missedWords = missedSet.map { service.displayText(forID: $0) }.sorted()
        Feedback.fire(.sessionComplete)
        phase = .complete
    }

    // MARK: Voice-check (§6.8, On My Own only)

    /// Structurally excludes every non-solo session (parent-scored, tricky) —
    /// the toggle and permissions only ever matter here. Also folds in the
    /// DEBUG mock's force-enable so screenshot runs don't need a real profile
    /// edit first.
    private var voiceCheckEligible: Bool {
        guard kind == .solo else { return false }
        #if DEBUG
        if VoiceCheckService.isMockActive { return voiceCheck.isAvailable() }
        #endif
        return profile.voiceCheckOn && voiceCheck.isAvailable()
    }

    private func resetVoiceCheckForNewCard() {
        voiceCheckSilenceTimer?.cancel(); voiceCheckSilenceTimer = nil
        voiceCheck.stopListening()
        voiceCheckTries = 0
        voiceCheckUIState = .hidden
        voiceCheckCardToken = UUID()
    }

    /// Stops any in-flight listening/timer and hides the overlay — called on
    /// card end (any score), reveal, and session exit (§6.8).
    private func stopVoiceCheck() {
        voiceCheckSilenceTimer?.cancel(); voiceCheckSilenceTimer = nil
        voiceCheck.stopListening()
        voiceCheckUIState = .hidden
    }

    /// Public teardown for the view layer (`.onDisappear`) so a mid-session
    /// exit via the X button always releases the mic + restores `.ambient`.
    func tearDownVoiceCheck() { stopVoiceCheck() }

    private func beginVoiceCheckListening() {
        voiceCheckUIState = .listening
        let token = voiceCheckCardToken
        let target = currentWord
        voiceCheck.startListening(target: target) { [weak self] heard, confidence, isFinal in
            self?.handleVoiceTranscript(heard, confidence: confidence, isFinal: isFinal, token: token)
        }
        armVoiceCheckSilencePrompt(token: token)
    }

    /// ~6s of silence -> gentle spoken nudge, still listening passively (§6.8).
    private func armVoiceCheckSilencePrompt(token: UUID) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.voiceCheckCardToken == token,
                  case .listening = self.voiceCheckUIState else { return }
            self.speech.speak(segments: [.phrase(.giveItATry)])
        }
        voiceCheckSilenceTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: item)
    }

    /// Tokenizes the transcript and applies the match rules from §6.8:
    /// confident (exact/homophone + decent confidence or final) -> auto score;
    /// near-miss (low confidence match, or last token within edit distance 1-2
    /// for words >=4 letters) -> confirmation state; otherwise keep listening.
    /// Never auto-scores `.notYet` — silence/mismatch only ever falls back to
    /// the manual controls.
    private func handleVoiceTranscript(_ heard: String, confidence: Float, isFinal: Bool, token: UUID) {
        guard token == voiceCheckCardToken, case .card = phase, buttonsEnabled else { return }
        guard case .listening = voiceCheckUIState else { return }   // ignore late callbacks once confirming
        let tokens = heard.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard let lastToken = tokens.last else { return }
        let target = currentWord.lowercased()

        let confidentMatch = tokens.contains { Self.homophones.matches(heard: $0, target: target) }
        if confidentMatch {
            if isFinal || confidence >= 0.5 {
                acceptVoiceMatch()
            }
            return   // heard but not yet confident/final — wait for more
        }
        if target.count >= 4, (1...2).contains(Self.levenshtein(lastToken, target)) {
            handleVoiceNearMiss(heard: lastToken)
        }
        // Otherwise: no match yet, keep listening — never auto-scores wrong.
    }

    /// Up to 2 total confirmation attempts (§6.8); the 3rd near-miss falls back
    /// to passive listening + the gentle prompt instead of asking again.
    private func handleVoiceNearMiss(heard: String) {
        voiceCheckTries += 1
        voiceCheck.stopListening()
        if voiceCheckTries > 2 {
            voiceCheckUIState = .listening
            speech.speak(segments: [.phrase(.giveItATry)])
            let token = voiceCheckCardToken
            voiceCheck.startListening(target: currentWord) { [weak self] h, c, f in
                self?.handleVoiceTranscript(h, confidence: c, isFinal: f, token: token)
            }
        } else {
            voiceCheckUIState = .confirming(heard: heard)
        }
    }

    /// "Yes" on the confirmation bar (§6.8).
    func voiceCheckConfirmYes() {
        guard case .confirming = voiceCheckUIState else { return }
        acceptVoiceMatch()
    }

    /// "Try again" on the confirmation bar: relistens for the same card.
    func voiceCheckTryAgain() {
        guard case .confirming = voiceCheckUIState else { return }
        voiceCheckUIState = .listening
        let token = voiceCheckCardToken
        voiceCheck.startListening(target: currentWord) { [weak self] h, c, f in
            self?.handleVoiceTranscript(h, confidence: c, isFinal: f, token: token)
        }
        armVoiceCheckSilencePrompt(token: token)
    }

    /// A confident voice match (or a confirmed near-miss) auto-scores `.gotIt`
    /// with the response time measured word-appear -> match, per §6.8. Reuses
    /// the normal solo-mode scoring path by first marking the card "revealed"
    /// with that captured time, exactly as a manual Show-answer tap would.
    private func acceptVoiceMatch() {
        guard case .card = phase, buttonsEnabled else { return }
        if !revealed {
            revealed = true
            revealedResponseMs = max(0, Int(Date().timeIntervalSince(cardAppearedAt) * 1000))
        }
        score(.gotIt)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let (m, n) = (aChars.count, bChars.count)
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = aChars[i - 1] == bChars[j - 1]
                    ? dp[i - 1][j - 1]
                    : 1 + min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1])
            }
        }
        return dp[m][n]
    }

    // MARK: Debug / screenshot hooks

    #if DEBUG
    enum DemoMode { case reteach, complete, sentence, soloAnswer }
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
        case .soloAnswer:
            demoStop = true   // one-shot: leave the self-score buttons up for the screenshot
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, case .card = self.phase, !self.revealed else { return }
                self.revealAnswer()
            }
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
