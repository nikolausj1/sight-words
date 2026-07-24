import SwiftUI

/// Owns one Missing Letter play session end to end (Games Spec §3.4): builds
/// each board's words + blanks + tray via the Engine bridge, tracks live
/// drag-and-drop state (which tile is airborne, where every blank/tray-slot
/// actually sits on screen), drives the optional 🎤 "Now read it!" beat after
/// each completed word (Design Direction §6, added this pass -- mirrors
/// `WordHuntCoordinator`'s per-found-word voice beat/`SayMatchRoundBView`'s
/// confident-match rules), and records tier/exposure data through
/// `LearningService`'s GameKit extension. Mirrors `WordHuntCoordinator`'s
/// overall shape — an `@MainActor` `ObservableObject` the view is a thin
/// router over.
@MainActor
final class MissingLetterCoordinator: ObservableObject {
    /// Shared coordinate-space name every blank/tray-slot frame is reported
    /// in (via `updateBlankFrame`/`updateTrayFrame`) and every drag gesture
    /// reads its `location` in — all three need to agree on the same space
    /// for hit-testing to line up.
    static let spaceName = "missingLetterBoard"

    // MARK: Published state the views read

    @Published private(set) var tier: GameTier
    @Published private(set) var words: [MissingLetterWordSlot] = []
    @Published private(set) var tray: [MissingLetterTile] = []
    @Published private(set) var currentRoundIndex = 0
    let totalRounds = 2
    @Published private(set) var showRoundCelebration = false

    /// "One more round?" (Design Direction §6) -- see
    /// `WordHuntCoordinator.setsPlayedThisSitting`'s doc comment.
    @Published private(set) var setsPlayedThisSitting = 1
    var canPlayAgain: Bool { setsPlayedThisSitting < 3 }

    /// 🎤 "Now read it!" beat (Design Direction §6, `phrase-now-you-say-it`):
    /// the word currently prompting for a voice confirm, or nil when hidden.
    @Published private(set) var voiceBeatWord: String?
    @Published private(set) var voiceListening = false
    @Published private(set) var voiceFlashCorrect = false

    /// The tile currently airborne (nil = nothing being dragged). Its source
    /// slot in `tray` renders at `opacity(0)` (still laid out, so
    /// `updateTrayFrame`'s "home" frame keeps tracking correctly) while a
    /// floating duplicate follows `dragLocation` in a top-level overlay —
    /// see `MissingLetterGameView`. This sidesteps `GameBoardCard`'s own
    /// `.clipShape` entirely not mattering here (drag never needs to leave
    /// the card), but does avoid any z-order ambiguity between the tray
    /// (declared after the word grid) and the grid itself.
    @Published private(set) var draggingTile: MissingLetterTile?
    @Published private(set) var dragLocation: CGPoint = .zero
    /// The open blank a drag is currently hovering over, if any -- drives
    /// `MissingLetterBlankView`'s soft glow-while-hovered highlight (Games
    /// Spec's shared drag-and-drop polish pass). Recomputed on every
    /// `dragChanged`, cleared the instant the drag ends (drop, miss, or a
    /// fresh round starting).
    @Published private(set) var hoveredBlankID: UUID?

    /// The blank that should wiggle right now (Games Spec §3.4: "wrong →
    /// tile returns + the blank wiggles side-to-side"), and the word that
    /// should show its mini in-place confetti (a just-completed word — see
    /// §3.4: "word reflows seamless, word spoken, mini-confetti" — this is
    /// deliberately NOT the shared center-screen `SuccessMoment`; the spec
    /// line for this game calls out its own smaller, in-place beat).
    @Published private(set) var wigglingBlankID: UUID?
    @Published private(set) var celebratingWordID: UUID?

    // MARK: Dependencies

    private let profile: Profile
    private let service: LearningService
    private let speech: SpeechService
    private let voiceCheck: VoiceCheckService
    /// Fixed for a demo session (`-demoGame missingLetter t2`), same
    /// contract as `WordHuntCoordinator.demoTierOverride`.
    private let demoTierOverride: GameTier?
    /// Tricky Words rotation mode (Design Direction §6) -- see
    /// `WordHuntCoordinator.trickyOnly`'s doc comment.
    private let trickyOnly: Bool

    // MARK: Round/frame bookkeeping

    private var wrongAttemptsThisRound = 0
    private var activeConfig: MissingLetterTierConfig
    private var blankFrames: [UUID: CGRect] = [:]
    private var trayFrames: [UUID: CGRect] = [:]
    private var roundToken = UUID()
    private var wiggleResetTimer: DispatchWorkItem?
    private var celebrationResetTimer: DispatchWorkItem?

    // MARK: 🎤 voice-beat bookkeeping

    /// Guards against two word-completion beats overlapping (see
    /// `handleWordCompletion`'s doc comment) -- practically never happens
    /// (one drag gesture resolves at a time), but keeps the flow well-defined
    /// if it ever did.
    private var isHandlingWordCompletion = false
    private var currentVoiceToken = UUID()
    private var voiceSilenceTimer: DispatchWorkItem?
    private var lastTeacherSpeechAt: Date?

    /// Same bundled `homophones.json` parse every game's voice beat loads for
    /// itself (see `WordHuntCoordinator`/`SayMatchModel`'s own copies) --
    /// duplicated here rather than shared per the game-worker registration
    /// contract (only this folder is touched).
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

    // MARK: Init

    init(profile: Profile, service: LearningService, tierOverride: GameTier? = nil, trickyOnly: Bool = false,
         voiceCheck: VoiceCheckService = .shared, speech: SpeechService = .shared) {
        self.profile = profile
        self.service = service
        self.speech = speech
        self.voiceCheck = voiceCheck
        self.demoTierOverride = tierOverride
        self.trickyOnly = trickyOnly
        let resolvedTier = tierOverride ?? service.gameTier(for: .missingLetter, profile: profile)
        self.tier = resolvedTier
        self.activeConfig = missingLetterConfig(for: resolvedTier)
        startRound()
        #if DEBUG
        maybeScheduleAutoSolveAll()
        #endif
    }

    // MARK: Round lifecycle

    /// "One more round?" restart hook (Design Direction §6) -- see
    /// `WordHuntCoordinator.startNewSet()`'s doc comment.
    func startNewSet() {
        guard canPlayAgain else { return }
        setsPlayedThisSitting += 1
        currentRoundIndex = 0
        showRoundCelebration = false
        startRound()
    }

    private func startRound() {
        roundToken = UUID()
        wrongAttemptsThisRound = 0
        draggingTile = nil
        hoveredBlankID = nil
        wigglingBlankID = nil
        celebratingWordID = nil
        blankFrames = [:]
        trayFrames = [:]
        voiceBeatWord = nil
        voiceListening = false
        voiceFlashCorrect = false
        isHandlingWordCompletion = false
        voiceCheck.stopListening()
        voiceSilenceTimer?.cancel()

        let resolvedTier = demoTierOverride ?? service.gameTier(for: .missingLetter, profile: profile)
        tier = resolvedTier
        let config = missingLetterConfig(for: resolvedTier)
        activeConfig = config

        var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
        let picked = pickWords(config: config, rng: &rng)

        // T3: roughly `twoBlankFraction` of the board's words get a second
        // blank; the rest get one. Which specific words get the extra blank
        // is randomized per board rather than fixed by position.
        let twoBlankCount = Int((Double(picked.count) * config.twoBlankFraction).rounded())
        let twoBlankIndices = Set(Array(picked.indices.shuffled(using: &rng)).prefix(twoBlankCount))

        var builtWords: [MissingLetterWordSlot] = []
        var neededLetters: [Character] = []
        for (index, snapshot) in picked.enumerated() {
            let text = service.displayText(forID: snapshot.id)
            let chars = Array(text)
            let blankCount = twoBlankIndices.contains(index) ? 2 : 1
            let positions = missingLetterBlankPositions(wordLength: chars.count, count: blankCount, rng: &rng)
            let blanks = positions.map { MissingLetterBlank(position: $0, letter: chars[$0]) }
            neededLetters += blanks.map(\.letter)
            builtWords.append(MissingLetterWordSlot(engineID: snapshot.id, text: text, blanks: blanks))
        }
        words = builtWords

        let decoys = missingLetterDecoys(neededLetters: neededLetters, count: config.decoyCount,
                                         preferConfusable: config.preferConfusableDecoys, rng: &rng)
        tray = (neededLetters.map { MissingLetterTile(letter: $0) }
                + decoys.map { MissingLetterTile(letter: $0) }).shuffled(using: &rng)

        for word in builtWords {
            service.recordGameExposure(word: word.engineID, profile: profile)
        }
    }

    /// Games Spec §2 shape constraints, applied at this game's own call
    /// site (`GameWordConstraints` only carries `maxLength` — Engine files
    /// are frozen, so the min-length half of "T1/T2 length 3-5; T3 3-6" is
    /// enforced here by pre-filtering `pool` before handing it to
    /// `pickGameWords`, not by extending that struct). If the profile's real
    /// pool is too small to fill the min-length window (a tiny/demo pool),
    /// falls back to relaxing just the minimum — `pickGameWords`'s own
    /// `constraints.maxLength` still holds as a hard cap either way.
    private func pickWords(config: MissingLetterTierConfig, rng: inout RandomNumberGenerator) -> [WordSnapshot] {
        let pool = Self.trickyFiltered(service.pool(for: profile), trickyOnly: trickyOnly)
        let inWindow = pool.filter { $0.id.count >= config.minWordLength && $0.id.count <= config.maxWordLength }
        let maxOnly = pool.filter { $0.id.count <= config.maxWordLength }
        let source = inWindow.count >= config.wordCount ? inWindow : maxOnly
        let constraints = GameWordConstraints(maxLength: config.maxWordLength)
        return pickGameWords(pool: source, count: config.wordCount, constraints: constraints, rng: &rng)
    }

    /// Tricky Words rotation mode (Design Direction §6) -- see
    /// `WordHuntCoordinator.trickyFiltered(_:trickyOnly:)`'s doc comment.
    private static func trickyFiltered(_ pool: [WordSnapshot], trickyOnly: Bool) -> [WordSnapshot] {
        guard trickyOnly else { return pool }
        let filtered = pool.filter { $0.needsReview || $0.state == .learning }
        return filtered.isEmpty ? pool : filtered
    }

    // MARK: Frame reporting (from the views, via preference keys)

    func updateBlankFrame(_ id: UUID, frame: CGRect) { blankFrames[id] = frame }
    func updateTrayFrame(_ id: UUID, frame: CGRect) { trayFrames[id] = frame }

    // MARK: Drag lifecycle

    func dragChanged(tile: MissingLetterTile, location: CGPoint) {
        guard wordsHaveOpenBlank else { return }
        if draggingTile?.id != tile.id { draggingTile = tile }
        dragLocation = location
        hoveredBlankID = openBlank(at: location).map { words[$0.wordIndex].blanks[$0.blankIndex].id }
    }

    private var wordsHaveOpenBlank: Bool {
        words.contains { !$0.isComplete }
    }

    func dragEnded(tile: MissingLetterTile, location: CGPoint) {
        // Deliberately does NOT set `dragLocation = location` here: both
        // exit paths already own that themselves -- `lockBlank` clears
        // `draggingTile` outright (the floating tile just disappears, no
        // further position needed), and `returnTileToTray` animates
        // `dragLocation` back to the tile's tray "home" frame. Setting it to
        // the raw drop point here as well (a `defer`, originally) would run
        // AFTER `returnTileToTray`'s animated assignment and silently
        // overwrite it back to the drop point with no animation, making the
        // "tile returns" beat (Games Spec §3.4) snap instead of glide.
        hoveredBlankID = nil
        guard let (wordIndex, blankIndex) = openBlank(at: location) else {
            returnTileToTray(tile)
            return
        }
        let blank = words[wordIndex].blanks[blankIndex]
        if Character(blank.letter.lowercased()) == Character(tile.letter.lowercased()) {
            lockBlank(wordIndex: wordIndex, blankIndex: blankIndex, tile: tile)
        } else {
            wrongAttemptsThisRound += 1
            fireWiggle(blankID: blank.id)
            returnTileToTray(tile)
        }
    }

    /// Which open (unlocked) blank, if any, contains `point` — `blankFrames`
    /// is populated by every `MissingLetterBlankView` reporting its own
    /// on-screen bounds (see `MissingLetterBoardView`), inset slightly larger
    /// than the visible glyph so a slightly-off drop still lands (kid
    /// fingers, not a mouse pointer).
    private func openBlank(at point: CGPoint) -> (wordIndex: Int, blankIndex: Int)? {
        for (wi, word) in words.enumerated() {
            for (bi, blank) in word.blanks.enumerated() where !blank.locked {
                guard let frame = blankFrames[blank.id] else { continue }
                if frame.insetBy(dx: -10, dy: -10).contains(point) { return (wi, bi) }
            }
        }
        return nil
    }

    private func lockBlank(wordIndex: Int, blankIndex: Int, tile: MissingLetterTile) {
        withAnimation(Theme.Motion.snappy) {
            words[wordIndex].blanks[blankIndex].locked = true
        }
        tray.removeAll { $0.id == tile.id }
        draggingTile = nil
        Feedback.fire(.correct)

        guard words[wordIndex].isComplete else { return }
        let word = words[wordIndex]
        service.recordGameExposure(word: word.engineID, profile: profile)
        fireWordCelebration(wordID: word.id)
        handleWordCompletion(word)
    }

    /// Speaks the just-completed word and waits for it to actually finish
    /// (Design Direction §6's speech-length-aware pacing -- replaces a fixed
    /// `Task.sleep` guess with `SpeechService.speakWordAndWait`, floored at
    /// `Theme.Motion.beat`), then offers the optional 🎤 "Now read it!" beat
    /// before finally checking whether the whole board is done. A second
    /// word completing while one of these is still in flight (two blanks
    /// locking in the same instant -- not expected from a real drag, but not
    /// impossible) skips straight to `checkBoardComplete()` rather than
    /// overlapping two beats.
    private func handleWordCompletion(_ word: MissingLetterWordSlot) {
        guard !isHandlingWordCompletion else { checkBoardComplete(); return }
        isHandlingWordCompletion = true
        let token = roundToken
        Task { [weak self] in
            guard let self else { return }
            await self.speech.speakWordAndWait(word.text)
            guard self.roundToken == token else { return }
            self.beginVoiceBeat(for: word, roundToken: token)
        }
    }

    // MARK: 🎤 "Now read it!" beat (Design Direction §6)

    /// Voice steps require `profile.voiceCheckOn` (or the DEBUG mock forcing
    /// it) AND a currently-available recognizer; otherwise the 🎤 step is
    /// skipped entirely and play is never blocked (Games Spec §1), same rule
    /// every other GameKit voice beat follows.
    private var voiceCheckEligible: Bool {
        #if DEBUG
        if VoiceCheckService.isMockActive { return voiceCheck.isAvailable() }
        #endif
        return profile.voiceCheckOn && voiceCheck.isAvailable()
    }

    private func beginVoiceBeat(for word: MissingLetterWordSlot, roundToken: UUID) {
        guard voiceCheckEligible else {
            isHandlingWordCompletion = false
            checkBoardComplete()
            return
        }
        voiceBeatWord = word.text
        voiceListening = true
        speech.speak(segments: [.phrase(.nowYouSayIt)])
        let token = UUID()
        currentVoiceToken = token
        voiceCheck.startListening(target: word.text, contextualStrings: Self.contextualStrings(for: word.text)) { [weak self] heard, confidence, isFinal in
            self?.handleVoiceTranscript(heard, confidence: confidence, isFinal: isFinal, word: word.text,
                                        voiceToken: token, roundToken: roundToken)
        } onLevel: { _ in }
        armVoiceSilenceTimer(voiceToken: token, roundToken: roundToken)
    }

    private func handleVoiceTranscript(_ heard: String, confidence: Float, isFinal: Bool, word: String,
                                        voiceToken: UUID, roundToken: UUID) {
        guard voiceToken == currentVoiceToken else { return }
        // Self-hearing guard (same rationale as every other game's voice
        // beat): the input tap has no echo cancellation, so drop anything
        // heard while our own voice is playing or within a short tail after.
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
            guard let self, self.roundToken == roundToken else { return }
            self.voiceFlashCorrect = false
            self.voiceBeatWord = nil
            self.voiceListening = false
            self.isHandlingWordCompletion = false
            self.checkBoardComplete()
        }
    }

    /// Games Spec §1/§3.1-3.5's shared voice-beat rule: "silence >6s ->
    /// phrase-show-me + auto-advance" -- never blocks play. Speech-length-
    /// aware (Design Direction §6): waits for "show me" to actually finish
    /// before clearing the overlay and moving on.
    private func armVoiceSilenceTimer(voiceToken: UUID, roundToken: UUID) {
        voiceSilenceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, voiceToken == self.currentVoiceToken else { return }
            self.voiceCheck.stopListening()
            Task { [weak self] in
                guard let self else { return }
                await self.speech.speakAndWait(segments: [.phrase(.showMe)])
                guard self.roundToken == roundToken else { return }
                self.voiceBeatWord = nil
                self.voiceListening = false
                self.isHandlingWordCompletion = false
                self.checkBoardComplete()
            }
        }
        voiceSilenceTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: item)
    }

    /// Animates the airborne tile back to its tray "home" frame, then clears
    /// `draggingTile` once it arrives (Games Spec §3.4: "tile returns").
    private func returnTileToTray(_ tile: MissingLetterTile) {
        let home = trayFrames[tile.id]
        withAnimation(Theme.Motion.snappy) {
            if let home { dragLocation = CGPoint(x: home.midX, y: home.midY) }
        }
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.roundToken == token, self.draggingTile?.id == tile.id else { return }
            self.draggingTile = nil
        }
    }

    /// Deliberately does NOT call `Feedback.fire(.boing)` here -- the view's
    /// own `.wrongShake` (bound to `wigglingBlankID`, see
    /// `MissingLetterBlankView`) already fires it itself the instant its
    /// trigger flips true, same contract `SpellingBuilderCoordinator`
    /// documents at its own wrong-shake call site. Firing it here too would
    /// double the boing SFX/haptic on every miss.
    private func fireWiggle(blankID: UUID) {
        wiggleResetTimer?.cancel()
        wigglingBlankID = blankID
        let item = DispatchWorkItem { [weak self] in self?.wigglingBlankID = nil }
        wiggleResetTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Clears a wiggle early if a view's own `wrongShake` binding settles
    /// first — mirrors `SayMatchRoundAView`'s `wrongTileID` binding pattern.
    func clearWiggle() {
        wiggleResetTimer?.cancel()
        wigglingBlankID = nil
    }

    private func fireWordCelebration(wordID: UUID) {
        celebrationResetTimer?.cancel()
        celebratingWordID = wordID
        let item = DispatchWorkItem { [weak self] in self?.celebratingWordID = nil }
        celebrationResetTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: item)
    }

    // MARK: Board/round completion

    /// Called once every completed word's own speak-and-wait -> optional 🎤
    /// beat cycle settles (see `handleWordCompletion`) -- by the time this
    /// runs, that pacing has ALREADY held the screen for at least as long as
    /// the last word's own speech (Design Direction §6), so this no longer
    /// needs its own additional fixed delay before advancing.
    private func checkBoardComplete() {
        guard !words.isEmpty, words.allSatisfy(\.isComplete) else { return }
        let report = RoundReport(wrongAttempts: wrongAttemptsThisRound, timeoutHints: 0)
        service.recordGameRound(for: .missingLetter, profile: profile, report: report)
        if currentRoundIndex + 1 < totalRounds {
            currentRoundIndex += 1
            startRound()
        } else {
            showRoundCelebration = true
        }
    }

    // MARK: Teardown

    func tearDown() {
        wiggleResetTimer?.cancel()
        celebrationResetTimer?.cancel()
        voiceSilenceTimer?.cancel()
        voiceCheck.stopListening()
    }

    // MARK: DEBUG demo hooks

    #if DEBUG
    /// "-demoMissingLetterSolve": auto-drops the next correct tile onto the
    /// next open blank every ~1.5s ("with beats"), so a scripted sim run can
    /// play through both boards and reach `RoundCelebration` with no touch
    /// injection needed — mirrors `WordHuntCoordinator`'s
    /// `-demoWordHuntSolveAll`.
    private func maybeScheduleAutoSolveAll() {
        guard ProcessInfo.processInfo.arguments.contains("-demoMissingLetterSolve") else { return }
        scheduleNextAutoSolveStep()
    }

    private func scheduleNextAutoSolveStep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.showRoundCelebration else { return }
            self.debugAutoSolveNextBlank()
            self.scheduleNextAutoSolveStep()
        }
    }

    /// Finds the first open blank with a matching tile still in the tray and
    /// locks it in directly — same end-state `lockBlank` produces from a
    /// real drag, just without simulating the gesture itself.
    func debugAutoSolveNextBlank() {
        for (wi, word) in words.enumerated() {
            for (bi, blank) in word.blanks.enumerated() where !blank.locked {
                guard let tile = tray.first(where: { Character($0.letter.lowercased()) == Character(blank.letter.lowercased()) }) else { continue }
                lockBlank(wordIndex: wi, blankIndex: bi, tile: tile)
                return
            }
        }
    }
    #endif
}
