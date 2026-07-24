import SwiftUI

/// Owns one Word Hunt play session end to end (Games Spec §3.1): builds each
/// round's word list + grid via the Engine bridge, tracks live
/// swipe-selection/found-word state, drives the 🎤 "Now you say it!" voice
/// beat per found word, and records tier/exposure data through
/// `LearningService`'s GameKit extension. Mirrors `SessionCoordinator`'s
/// shape (an `@MainActor` `ObservableObject` the view is a thin router over)
/// but is deliberately its own, much simpler type -- Word Hunt's voice beat
/// has no confirm-bar/near-miss retries; a game round just wants "confident
/// match, or move on after a few quiet seconds," per Games Spec §1's "never
/// blocks play on the mic."
@MainActor
final class WordHuntCoordinator: ObservableObject {
    // MARK: Published state the views read

    @Published private(set) var grid: WordHuntGrid
    /// This round's difficulty. Re-read from the profile's ladder at the
    /// start of every round (see `startRound`), so a mid-session promotion
    /// (Games Spec §2: "tier changes only between rounds") can take effect
    /// on round 2 of the same play session, not just the next time the game
    /// is opened.
    @Published private(set) var tier: GameTier
    /// Display-cased words for the current round's list panel, in the order
    /// they actually landed in the grid (`WordHuntGrid.placements` order).
    @Published private(set) var listWords: [String] = []
    @Published private(set) var foundWords: Set<String> = []
    /// Pastel trail color assigned to each found word (Games Spec §3.1:
    /// "Solved trails persist in pastel colors" -- rotates through 5).
    @Published private(set) var trailColor: [String: Color] = [:]
    /// The live swipe path, in swipe order (start first).
    @Published private(set) var selection: [WordHuntCellRef] = []
    /// The just-committed WRONG path, kept around only long enough to
    /// animate its fade (Games Spec §3.1: "wrong commit -> ribbon fades, no
    /// penalty" -- deliberately NOT the shared `wrongShake`/boing treatment;
    /// this game's own spec line calls for a softer, non-shaking miss).
    @Published private(set) var fadingWrongSelection: [WordHuntCellRef] = []
    /// Cells currently pulsing for a hint (idle auto-hint or a manual
    /// double-tap), and a toggle the board view animates against.
    @Published private(set) var hintingCells: Set<WordHuntCellRef> = []
    @Published private(set) var hintPulseOn = false

    @Published private(set) var currentRoundIndex = 0
    let totalRounds = 2
    @Published private(set) var showRoundCelebration = false

    /// Bound into `SuccessMoment` (Games Spec §1) by the hosting view.
    /// Non-private-set deliberately: `View.successMoment(word:onSettled:)`
    /// needs a live `Binding<String?>` it clears itself when the beat
    /// settles, same contract as every other GameKit screen.
    @Published var successWord: String?
    /// Drives the "Now you say it!" overlay (nil = hidden).
    @Published private(set) var voiceBeatWord: String?
    @Published private(set) var voiceListening = false
    @Published private(set) var voiceFlashCorrect = false

    // MARK: Dependencies

    private let profile: Profile
    private let service: LearningService
    private let voiceCheck: VoiceCheckService
    private let speech: SpeechService
    /// Fixed for a demo session (`-demoGame wordHunt t2`) so every round of
    /// it stays at the requested tier instead of re-reading (and
    /// potentially promoting/demoting) the profile's real ladder.
    private let demoTierOverride: GameTier?

    // MARK: Round bookkeeping

    private var wrongAttemptsThisRound = 0
    private var timeoutHintsThisRound = 0
    private var activeConfig: WordHuntTierConfig
    private var roundToken = UUID()
    private var currentVoiceToken = UUID()
    /// The word `successWord` was just showing -- `successWord` itself is
    /// already cleared back to `nil` (by `SuccessMomentModifier`) by the
    /// time `onSuccessMomentSettled()` runs, so this is what the voice beat
    /// actually targets.
    private var pendingVoiceWord: String?
    private var idleHintTimer: DispatchWorkItem?
    private var voiceSilenceTimer: DispatchWorkItem?
    private var lastTeacherSpeechAt: Date?

    /// Loaded once from the bundled JSON, the same parse `SessionCoordinator`
    /// does (kept as its own copy here rather than shared -- Word Hunt's
    /// voice beat is intentionally decoupled from solo-session state).
    private static let homophones: HomophoneTable = {
        guard let url = Bundle.main.url(forResource: "homophones", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return HomophoneTable(json: Data("[]".utf8)) }
        return HomophoneTable(json: data)
    }()

    private static let homophoneGroups: [[String]] = {
        guard let url = Bundle.main.url(forResource: "homophones", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let groups = try? JSONDecoder().decode([[String]].self, from: data) else { return [] }
        return groups
    }()

    private static func contextualStrings(for word: String) -> [String] {
        let lower = word.lowercased()
        if let group = homophoneGroups.first(where: { $0.contains { $0.lowercased() == lower } }) {
            return group
        }
        return [word]
    }

    /// 5 rotating theme pastels for solved-word trails (Games Spec §3.1).
    static let trailPastels: [Color] = [
        Color(red: 1.00, green: 0.85, blue: 0.85),   // pastel pink
        Color(red: 0.83, green: 0.92, blue: 1.00),   // pastel blue
        Color(red: 0.85, green: 0.96, blue: 0.85),   // pastel green
        Color(red: 1.00, green: 0.94, blue: 0.78),   // pastel yellow
        Color(red: 0.90, green: 0.85, blue: 1.00),   // pastel lavender
    ]

    // MARK: Init

    init(profile: Profile, service: LearningService, tierOverride: GameTier? = nil,
         voiceCheck: VoiceCheckService = .shared, speech: SpeechService = .shared) {
        self.profile = profile
        self.service = service
        self.voiceCheck = voiceCheck
        self.speech = speech
        self.demoTierOverride = tierOverride
        let resolvedTier = tierOverride ?? service.gameTier(for: .wordHunt, profile: profile)
        self.tier = resolvedTier
        self.activeConfig = wordHuntConfig(for: resolvedTier)
        self.grid = .blank(size: activeConfig.gridSize)
        startRound(speakOpening: false)
        #if DEBUG
        maybeScheduleAutoSolveAll()
        #endif
    }

    // MARK: Round lifecycle

    private func startRound(speakOpening: Bool = true) {
        roundToken = UUID()
        selection = []
        fadingWrongSelection = []
        foundWords = []
        trailColor = [:]
        wrongAttemptsThisRound = 0
        timeoutHintsThisRound = 0
        hintingCells = []
        successQueue = []
        pendingVoiceWord = nil
        voiceBeatWord = nil
        voiceListening = false
        cancelIdleHintTimer()
        cancelVoiceTimers()

        let resolvedTier = demoTierOverride ?? service.gameTier(for: .wordHunt, profile: profile)
        tier = resolvedTier
        let config = wordHuntConfig(for: resolvedTier)
        activeConfig = config

        let pool = service.pool(for: profile)
        let constraints = GameWordConstraints(maxLength: config.gridSize)
        var pickRng: RandomNumberGenerator = SystemRandomNumberGenerator()
        let picked = pickGameWords(pool: pool, count: config.wordCount, constraints: constraints, rng: &pickRng)
        let words = picked.map { service.displayText(forID: $0.id).uppercased() }

        var decoySource: [String] = []
        if resolvedTier == .t3 {
            for snapshot in picked {
                decoySource += confusables(for: snapshot.id, pool: pool, homophoneGroups: Self.homophoneGroups)
            }
        }

        var gridRng: RandomNumberGenerator = SystemRandomNumberGenerator()
        let generated = words.isEmpty ? nil
            : generateWordHuntGrid(size: config.gridSize, words: words, tier: resolvedTier,
                                   confusableDecoys: decoySource, rng: &gridRng)
        grid = generated ?? .blank(size: config.gridSize)
        listWords = grid.placements.map(\.word)

        for word in listWords {
            service.recordGameExposure(word: word.lowercased(), profile: profile)
        }

        if speakOpening {
            speech.speak(segments: [.phrase(.findTheWords)])
        }
        armIdleHintTimer()

        #if DEBUG
        maybeScheduleAutoSolve()
        #endif
    }

    // MARK: Selection (swipe-select)

    /// Called continuously while a finger drags across the board. `start` is
    /// fixed for the whole gesture (the cell the finger went down on);
    /// `current` is wherever it is now. Projects the raw (start -> current)
    /// vector onto whichever tier-allowed direction it's closest to, so a
    /// slightly wobbly swipe still resolves to a clean straight line.
    func selectionUpdated(start: WordHuntCellRef, current: WordHuntCellRef) {
        resetIdleHintTimer()
        guard let direction = bestDirection(from: start, to: current, allowed: WordHuntDirection.allowed(for: tier)) else {
            selection = [start]
            return
        }
        let (dr, dc) = direction.delta
        let len = max(1, min(projectedLength(from: start, to: current, dr: dr, dc: dc), grid.size))
        var cells: [WordHuntCellRef] = []
        for i in 0..<len {
            let r = start.row + dr * i, c = start.col + dc * i
            guard r >= 0, r < grid.size, c >= 0, c < grid.size else { break }
            cells.append(WordHuntCellRef(row: r, col: c))
        }
        selection = cells
    }

    /// Finger lift: a single-cell "selection" (finger never really moved) is
    /// treated as a tap-to-hear-the-letter (Games Spec §1), not a miss. A
    /// real multi-cell commit is checked against the round's unfound words.
    func commitSelection() {
        let committed = selection
        selection = []
        resetIdleHintTimer()
        guard committed.count > 1 else {
            if let only = committed.first {
                GameAudio.shared.playLetter(grid.letters[only.row][only.col])
            }
            return
        }
        let word = committed.map { String(grid.letters[$0.row][$0.col]) }.joined()
        if let match = listWords.first(where: { $0 == word }), !foundWords.contains(match) {
            markFound(match)
        } else {
            wrongAttemptsThisRound += 1
            fadingWrongSelection = committed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                withAnimation(.easeOut(duration: 0.35)) { self?.fadingWrongSelection = [] }
            }
        }
    }

    private func bestDirection(from start: WordHuntCellRef, to current: WordHuntCellRef,
                                allowed: [WordHuntDirection]) -> WordHuntDirection? {
        let dr = current.row - start.row, dc = current.col - start.col
        guard dr != 0 || dc != 0 else { return nil }
        let mag = (Double(dr * dr + dc * dc)).squareRoot()
        var best: (WordHuntDirection, Double)?
        for direction in allowed {
            let (vr, vc) = direction.delta
            let vmag = (Double(vr * vr + vc * vc)).squareRoot()
            let dot = (Double(dr) * Double(vr) + Double(dc) * Double(vc)) / (mag * vmag)
            if best == nil || dot > best!.1 { best = (direction, dot) }
        }
        guard let (direction, score) = best, score > 0.5 else { return nil }
        return direction
    }

    private func projectedLength(from start: WordHuntCellRef, to current: WordHuntCellRef, dr: Int, dc: Int) -> Int {
        let deltaR = current.row - start.row, deltaC = current.col - start.col
        let vmagSq = Double(dr * dr + dc * dc)
        guard vmagSq > 0 else { return 1 }
        let proj = (Double(deltaR * dr) + Double(deltaC * dc)) / vmagSq
        return Int(proj.rounded()) + 1
    }

    /// Which found word (if any) a cell belongs to -- drives the persistent
    /// pastel trail fill in the board view.
    func foundWord(containing cell: WordHuntCellRef) -> String? {
        for placement in grid.placements where foundWords.contains(placement.word) {
            if placement.cells.contains(cell) { return placement.word }
        }
        return nil
    }

    // MARK: Found word -> SuccessMoment -> voice beat -> next

    /// Words found but not yet SHOWN their `SuccessMoment` beat -- separate
    /// from `foundWords`/scoring (which happen immediately) because a fast
    /// player can commit a second correct swipe while the first word's
    /// ~1.4s `SuccessMoment` is still on screen. `SuccessMomentModifier`
    /// (GameKit, shared) mounts exactly one overlay per continuous non-nil
    /// stretch of its bound word and clears itself via a `.task(id:)` tied
    /// to that word's identity, calling back through `onSettled`. Queuing so
    /// only one word is ever "in flight" at a time keeps that straightforward
    /// regardless of how fast words are found.
    private var successQueue: [String] = []

    private func markFound(_ word: String) {
        foundWords.insert(word)
        trailColor[word] = Self.trailPastels[(foundWords.count - 1) % Self.trailPastels.count]
        Feedback.fire(.correct)
        service.recordGameExposure(word: word.lowercased(), profile: profile)
        successQueue.append(word)
        presentNextSuccessIfIdle()
    }

    /// Pops the next queued word into `successWord` iff nothing is currently
    /// showing (no `SuccessMoment` up, no voice beat up) -- called right
    /// after enqueuing a new find, and again every time the previous word's
    /// full found -> SuccessMoment -> voice-beat cycle finishes.
    private func presentNextSuccessIfIdle() {
        guard successWord == nil, voiceBeatWord == nil, !successQueue.isEmpty else { return }
        let next = successQueue.removeFirst()
        pendingVoiceWord = next
        successWord = next
    }

    /// Called by the hosting view's `.successMoment(word:onSettled:)` once
    /// the shared ~1.4s beat finishes. Games Spec §3.1: "voice confirm ->
    /// word checks off with a flourish; voice off -> checks off after
    /// SuccessMoment" -- both paths converge on `checkRoundComplete()`, just
    /// with or without the mic overlay in between.
    func onSuccessMomentSettled() {
        guard let word = pendingVoiceWord else {
            checkRoundComplete()
            return
        }
        pendingVoiceWord = nil
        beginVoiceBeat(for: word)
    }

    /// Voice steps require `profile.voiceCheckOn` (or the DEBUG mock forcing
    /// it on) AND a currently-available recognizer; otherwise the 🎤 step is
    /// skipped entirely and play is never blocked (Games Spec §1).
    private var voiceCheckEligible: Bool {
        #if DEBUG
        if VoiceCheckService.isMockActive { return voiceCheck.isAvailable() }
        // `-demoWordHuntSolve` forces the voice beat to show on its own,
        // independent of any `-mockVoiceCheck*` flag: those flags are ALSO
        // recognized by `HomeView`'s own (pre-existing, shared) demo dispatch
        // as "launch the On My Own solo session," which wins the
        // fullScreenCover presentation race over `-demoGame wordHunt`'s cover
        // -- combining them never actually shows Word Hunt in practice. This
        // keeps Word Hunt's own demo/screenshot path self-contained.
        if ProcessInfo.processInfo.arguments.contains("-demoWordHuntSolve") { return true }
        #endif
        return profile.voiceCheckOn && voiceCheck.isAvailable()
    }

    private func beginVoiceBeat(for word: String) {
        guard voiceCheckEligible else {
            checkRoundComplete()
            return
        }
        voiceBeatWord = word
        voiceListening = true
        speech.speak(segments: [.phrase(.nowYouSayIt)])
        let token = UUID()
        currentVoiceToken = token
        voiceCheck.startListening(target: word, contextualStrings: Self.contextualStrings(for: word)) { [weak self] heard, confidence, isFinal in
            self?.handleVoiceTranscript(heard, confidence: confidence, isFinal: isFinal, word: word, token: token)
        } onLevel: { _ in }
        armVoiceSilenceTimer(word: word, token: token)
    }

    private func handleVoiceTranscript(_ heard: String, confidence: Float, isFinal: Bool, word: String, token: UUID) {
        guard token == currentVoiceToken else { return }
        // Self-hearing guard (same rationale as SessionCoordinator): the
        // input tap has no echo cancellation, so drop anything heard while
        // our own voice is playing or within a short tail after.
        if speech.isSpeakingAloud { lastTeacherSpeechAt = Date(); return }
        if let last = lastTeacherSpeechAt, Date().timeIntervalSince(last) < 1.0 { return }

        let tokens = heard.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard tokens.contains(where: { Self.homophones.matches(heard: $0, target: word.lowercased()) }) else { return }
        guard isFinal || confidence >= 0.5 else { return }

        voiceCheck.stopListening()
        voiceSilenceTimer?.cancel()
        voiceFlashCorrect = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else { return }
            self.voiceFlashCorrect = false
            self.voiceBeatWord = nil
            self.voiceListening = false
            self.checkRoundComplete()
        }
    }

    /// Games Spec §3.1/§1: "silence >6s -> phrase-show-me + auto-advance"
    /// -- the voice beat NEVER blocks play; the word is already found either
    /// way, this timer only decides whether the mic overlay lingers.
    private func armVoiceSilenceTimer(word: String, token: UUID) {
        voiceSilenceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, token == self.currentVoiceToken else { return }
            self.voiceCheck.stopListening()
            self.speech.speak(segments: [.phrase(.showMe)])
            self.voiceBeatWord = nil
            self.voiceListening = false
            self.checkRoundComplete()
        }
        voiceSilenceTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: item)
    }

    /// Called at every point one word's found -> SuccessMoment -> voice-beat
    /// cycle finishes (voice-ineligible skip, confident-match accept, or the
    /// 6s silence timeout) -- first advances the success queue (Games Spec
    /// §3.1's celebration beats never overlap even if two words were found
    /// close together), then checks whether the whole round is done.
    private func checkRoundComplete() {
        presentNextSuccessIfIdle()
        guard !listWords.isEmpty, foundWords.count >= listWords.count else { return }
        let report = RoundReport(wrongAttempts: wrongAttemptsThisRound, timeoutHints: timeoutHintsThisRound)
        service.recordGameRound(for: .wordHunt, profile: profile, report: report)
        if currentRoundIndex + 1 < totalRounds {
            currentRoundIndex += 1
            startRound()
        } else {
            showRoundCelebration = true
        }
    }

    // MARK: Idle + manual hints

    private func armIdleHintTimer() {
        idleHintTimer?.cancel()
        guard let delay = activeConfig.hintDelay else { return }   // T3: on-demand only
        let token = roundToken
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.roundToken == token else { return }
            self.fireHint(counts: true)
            self.armIdleHintTimer()
        }
        idleHintTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func resetIdleHintTimer() { armIdleHintTimer() }
    private func cancelIdleHintTimer() { idleHintTimer?.cancel(); idleHintTimer = nil }

    /// T3's "hint on demand only" path: double-tapping a list word.
    func requestManualHint(for word: String) {
        guard !foundWords.contains(word) else { return }
        fireHint(word: word, counts: true)
    }

    private func fireHint(word: String? = nil, counts: Bool) {
        let target = word ?? listWords.first(where: { !foundWords.contains($0) })
        guard let target, let placement = grid.placements.first(where: { $0.word == target }) else { return }
        if counts { timeoutHintsThisRound += 1 }
        hintingCells = Set(placement.cells)
        pulseSequence(index: 0)
    }

    /// 3 on/off pulses (Games Spec §3.1: "letters pulse 3× in place").
    private func pulseSequence(index: Int) {
        guard index < 6 else {
            hintingCells = []
            hintPulseOn = false
            return
        }
        hintPulseOn = index % 2 == 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.pulseSequence(index: index + 1)
        }
    }

    // MARK: Teardown

    /// Called from the hosting view's `.onDisappear` (mid-round exit via the
    /// hold-to-exit gate, or after the round-celebration dismisses) so the
    /// mic is always released, mirroring `SessionCoordinator.tearDownVoiceCheck()`.
    func tearDown() {
        cancelIdleHintTimer()
        cancelVoiceTimers()
        voiceCheck.stopListening()
    }

    private func cancelVoiceTimers() {
        voiceSilenceTimer?.cancel(); voiceSilenceTimer = nil
    }

    // MARK: DEBUG demo hooks

    #if DEBUG
    /// `-demoWordHuntSolve`: auto-solves the first unfound word ~2s into a
    /// round, so a demo launch can capture the SuccessMoment + voice beat
    /// without simulating a real swipe. `voiceCheckEligible` also treats this
    /// flag as forcing the voice beat on by itself (see that property) --
    /// `-mockVoiceCheck` is deliberately NOT the pairing here even though the
    /// real `VoiceCheckService` mock exists: that flag is ALSO recognized by
    /// `HomeView`'s own (pre-existing, shared) demo dispatch as "launch the
    /// On My Own solo session," and that cover wins the presentation race
    /// over `-demoGame wordHunt`'s, so combining them never actually shows
    /// Word Hunt on screen in practice.
    private func maybeScheduleAutoSolve() {
        guard ProcessInfo.processInfo.arguments.contains("-demoWordHuntSolve") else { return }
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.roundToken == token else { return }
            self.debugAutoSolveFirstUnfoundWord()
        }
    }

    func debugAutoSolveFirstUnfoundWord() {
        guard let word = listWords.first(where: { !foundWords.contains($0) }) else { return }
        markFound(word)
    }

    /// `-demoWordHuntSolveAll`: repeatedly auto-finds whatever word is next
    /// (across both rounds) every 1.6s until `showRoundCelebration` fires --
    /// a verification-only convenience for reaching/screenshotting
    /// `RoundCelebration` without simulating ~8 real swipes. Scheduled once
    /// from `init`, not per-round, so it survives the round-1 -> round-2
    /// transition (which mints a new `roundToken`); it self-terminates the
    /// moment the celebration is showing.
    private func maybeScheduleAutoSolveAll() {
        guard ProcessInfo.processInfo.arguments.contains("-demoWordHuntSolveAll") else { return }
        scheduleNextAutoSolveAllStep()
    }

    private func scheduleNextAutoSolveAllStep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, !self.showRoundCelebration else { return }
            if let next = self.listWords.first(where: { !self.foundWords.contains($0) }) {
                self.markFound(next)
            }
            self.scheduleNextAutoSolveAllStep()
        }
    }
    #endif
}
