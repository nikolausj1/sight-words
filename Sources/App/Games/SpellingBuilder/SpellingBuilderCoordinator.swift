import SwiftUI

/// Owns one Spelling Builder play session end to end (Games Spec §3.5):
/// builds the 4-word set, and per word drives the 🎤 T1+ opener (say it,
/// then the tray unlocks), the drag-to-slot build loop (mirrors
/// `MissingLetterCoordinator`'s frame-preference/tap-vs-drag approach, just
/// scoped to ONE word's slots instead of a worksheet of many), T3's
/// look-say-cover-check memory mode, and the fuse-into-a-pill completion
/// beat. Mirrors `SayMatchModel`'s shape for the set-level bookkeeping
/// (rounds built up front, one aggregated `RoundReport` at the end) since
/// this game is also "N words back to back, one shared celebration."
@MainActor
final class SpellingBuilderCoordinator: ObservableObject {
    /// Shared coordinate-space name every slot/tray-slot frame is reported in
    /// (via `updateSlotFrame`/`updateTrayFrame`) and every drag gesture reads
    /// its `location` in -- see `MissingLetterCoordinator.spaceName`'s own
    /// doc comment for why this needs to be one shared space.
    static let spaceName = "spellingBuilderBoard"

    // MARK: Published state the views read

    @Published private(set) var tier: GameTier
    @Published private(set) var words: [SpellingBuilderWord] = []
    @Published private(set) var currentWordIndex = 0
    @Published private(set) var showRoundCelebration = false

    @Published private(set) var slots: [SpellingBuilderSlot] = []
    @Published private(set) var tray: [SpellingBuilderTile] = []
    @Published private(set) var currentInstruction: GameInstruction = GameInstruction(.sayThenBuild)

    /// 🎤 opener state (Games Spec §3.5). While `voiceListening` is true the
    /// tray is visible but inert -- see `canInteractWithTray`.
    @Published private(set) var voiceListening = false
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var voiceFlashCorrect = false

    /// True once this word's tray/slots are draggable at all (voice-off
    /// skip, confident match, or the 6s silence rescue all set this).
    @Published private(set) var tilesUnlocked = false
    /// T3 only: true while the word is shown fully spelled in its slots
    /// without being "locked" -- the initial 2s look phase AND every Peek
    /// tap reuse this same flag/rendering (`SpellingBuilderSlotView` shows a
    /// slot's letter whenever `locked || showFullWordPreview || isPeeking`).
    @Published private(set) var showFullWordPreview = false
    @Published private(set) var isPeeking = false
    /// T3 only: Peek becomes available once the initial look phase ends.
    var showPeekButton: Bool { activeConfig.memoryMode && tilesUnlocked && !showFullWordPreview && !isFused }

    @Published private(set) var draggingTile: SpellingBuilderTile?
    @Published private(set) var dragLocation: CGPoint = .zero

    @Published private(set) var wigglingSlotID: UUID?
    /// True once every slot locks -- the segments fuse into one solid green
    /// pill (Games Spec §3.5's "best moment... keep").
    @Published private(set) var isFused = false

    /// Tiles are draggable only once the opener has resolved AND (T3) the
    /// look phase has finished AND the word isn't already fused.
    var canInteractWithTray: Bool { tilesUnlocked && !showFullWordPreview && !isFused }

    var totalRounds: Int { max(words.count, 1) }

    // MARK: Dependencies

    private let profile: Profile
    private let service: LearningService
    private let voiceCheck: VoiceCheckService
    private let speech: SpeechService
    /// Fixed for a demo session (`-demoGame spellingBuilder t2`), same
    /// contract as `WordHuntCoordinator.demoTierOverride`.
    private let demoTierOverride: GameTier?

    // MARK: Set/word bookkeeping

    private var activeConfig: SpellingBuilderTierConfig
    private var wrongAttempts = 0
    private var timeoutHints = 0
    private var slotFrames: [UUID: CGRect] = [:]
    private var trayFrames: [UUID: CGRect] = [:]
    /// One token per word; every async callback (voice transcript, silence
    /// timer, reveal/peek timers, tray-return animation, fuse-advance timer)
    /// checks this before touching state, so a word change (or `tearDown`)
    /// cleanly orphans anything still in flight from the previous word.
    private var wordToken = UUID()
    private var lastTeacherSpeechAt: Date?
    private var voiceSilenceTimer: DispatchWorkItem?
    private var wiggleResetTimer: DispatchWorkItem?
    private var fuseAdvanceTimer: DispatchWorkItem?
    private var revealTimer: DispatchWorkItem?
    private var peekResetTimer: DispatchWorkItem?

    /// Same bundled `homophones.json` parse every game's voice beat loads
    /// for itself (see `WordHuntCoordinator`/`SayMatchModel`'s own copies) --
    /// duplicated here rather than shared since that file lives outside this
    /// game's folder per the registration contract.
    private static let homophoneTable: HomophoneTable = {
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

    init(profile: Profile, service: LearningService, tierOverride: GameTier? = nil,
         voiceCheck: VoiceCheckService = .shared, speech: SpeechService = .shared) {
        self.profile = profile
        self.service = service
        self.voiceCheck = voiceCheck
        self.speech = speech
        self.demoTierOverride = tierOverride
        let resolvedTier = tierOverride ?? service.gameTier(for: .spellingBuilder, profile: profile)
        self.tier = resolvedTier
        self.activeConfig = spellingBuilderConfig(for: resolvedTier)
        buildWordSet()
        if !words.isEmpty {
            startWord(index: 0, speak: false)
        } else {
            showRoundCelebration = true
        }
        #if DEBUG
        maybeScheduleAutoSolve()
        #endif
    }

    // MARK: Word-set building

    private func buildWordSet() {
        #if DEBUG
        Self.seedDemoExposureIfNeeded(service: service, profile: profile)
        #endif
        let pool = service.pool(for: profile)
        // Games Spec §2 shape constraint applied at this game's own call
        // site, same pattern as `MissingLetterCoordinator.pickWords` --
        // `GameWordConstraints` only carries a max length, so the min-length
        // half of "length 3-6" is a pre-filter here, with a relax-the-
        // minimum fallback for a tiny/demo pool.
        let inWindow = pool.filter { $0.id.count >= 3 && $0.id.count <= 6 }
        let source = inWindow.count >= 4 ? inWindow : pool.filter { $0.id.count <= 6 }
        let constraints = GameWordConstraints(maxLength: 6)
        let picked = pickGameWords(pool: source, count: 4, constraints: constraints)
        words = picked.enumerated().map { index, snapshot in
            SpellingBuilderWord(index: index, engineID: snapshot.id, text: service.displayText(forID: snapshot.id))
        }
    }

    // MARK: Word lifecycle

    private func startWord(index: Int, speak: Bool) {
        guard words.indices.contains(index) else { return }
        let token = UUID()
        wordToken = token
        currentWordIndex = index
        cancelWordTimers()

        tilesUnlocked = false
        showFullWordPreview = false
        isPeeking = false
        isFused = false
        wigglingSlotID = nil
        draggingTile = nil
        voiceListening = false
        micLevel = 0
        voiceFlashCorrect = false
        slotFrames = [:]
        trayFrames = [:]

        let word = words[index]
        let chars = Array(word.text)
        slots = chars.enumerated().map { SpellingBuilderSlot(position: $0.offset, letter: $0.element) }

        var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
        let decoys = spellingBuilderDecoys(neededLetters: chars, count: activeConfig.decoyCount,
                                           preferConfusable: activeConfig.preferConfusableDecoys, rng: &rng)
        tray = (chars.map { SpellingBuilderTile(letter: $0) } + decoys.map { SpellingBuilderTile(letter: $0) })
            .shuffled(using: &rng)

        currentInstruction = GameInstruction(.sayThenBuild, word: word.text)
        if speak { speech.speak(segments: currentInstruction.segments) }

        beginVoiceOpener(token: token)
    }

    // MARK: 🎤 Voice opener (Games Spec §3.5/§1)

    /// Voice steps require `profile.voiceCheckOn` (or the DEBUG mock forcing
    /// it) AND a currently-available recognizer; otherwise the tray unlocks
    /// immediately and the 🎤 step is skipped entirely (Games Spec §1: "never
    /// block play on the mic").
    private var voiceCheckEligible: Bool {
        #if DEBUG
        if Self.demoVoiceForced { return true }
        if VoiceCheckService.isMockActive { return voiceCheck.isAvailable() }
        #endif
        return profile.voiceCheckOn && voiceCheck.isAvailable()
    }

    private func beginVoiceOpener(token: UUID) {
        guard voiceCheckEligible else {
            unlockTiles(sparkle: false, token: token)
            return
        }
        voiceListening = true
        let word = words[currentWordIndex].text
        #if DEBUG
        if Self.demoVoiceForced {
            runDemoVoiceMock(word: word, token: token)
            armVoiceSilenceTimer(token: token)
            return
        }
        #endif
        voiceCheck.startListening(
            target: word,
            contextualStrings: Self.contextualStrings(for: word),
            onTranscript: { [weak self] heard, confidence, isFinal in
                self?.handleVoiceTranscript(heard, confidence: confidence, isFinal: isFinal, word: word, token: token)
            },
            onLevel: { [weak self] level in
                guard let self, self.wordToken == token else { return }
                self.micLevel = level
            }
        )
        armVoiceSilenceTimer(token: token)
    }

    private func handleVoiceTranscript(_ heard: String, confidence: Float, isFinal: Bool, word: String, token: UUID) {
        guard wordToken == token, !tilesUnlocked else { return }
        // Self-hearing guard (same rationale as every other game's voice
        // beat): the input tap has no echo cancellation, so drop anything
        // heard while our own voice is playing or within a short tail after.
        if speech.isSpeakingAloud { lastTeacherSpeechAt = Date(); return }
        if let last = lastTeacherSpeechAt, Date().timeIntervalSince(last) < 1.0 { return }

        let tokens = heard.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard tokens.contains(where: { Self.homophoneTable.matches(heard: $0, target: word.lowercased()) }) else { return }
        guard isFinal || confidence >= 0.5 else { return }

        voiceCheck.stopListening()
        voiceSilenceTimer?.cancel()
        voiceFlashCorrect = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.wordToken == token else { return }
            self.voiceFlashCorrect = false
            self.voiceListening = false
            self.unlockTiles(sparkle: true, token: token)
        }
    }

    /// Games Spec §3.5: "silence 6s -> phrase-show-me + word spoken + unlock
    /// (counts timeoutHint)".
    private func armVoiceSilenceTimer(token: UUID) {
        voiceSilenceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.wordToken == token else { return }
            self.voiceCheck.stopListening()
            self.timeoutHints += 1
            self.voiceListening = false
            let word = self.words[self.currentWordIndex].text
            self.speech.speak(segments: [.phrase(.showMe), .pause(0.2), .word(word)])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.wordToken == token else { return }
                self.unlockTiles(sparkle: false, token: token)
            }
        }
        voiceSilenceTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: item)
    }

    private func unlockTiles(sparkle: Bool, token: UUID) {
        guard wordToken == token, !tilesUnlocked else { return }
        tilesUnlocked = true
        if sparkle { SpellingBuilderSFX.playSparkle() }
        if activeConfig.memoryMode {
            startReveal(token: token)
        }
    }

    // MARK: T3 memory mode (Games Spec §3.5: "look, say, cover, check")

    private func startReveal(token: UUID) {
        showFullWordPreview = true
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.wordToken == token else { return }
            self.showFullWordPreview = false
        }
        revealTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    /// "Peek" darkPlate button (counts as a timeoutHint, re-shows 1.5s).
    func peek() {
        guard showPeekButton, !isPeeking else { return }
        let token = wordToken
        isPeeking = true
        timeoutHints += 1
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.wordToken == token else { return }
            self.isPeeking = false
        }
        peekResetTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    // MARK: Frame reporting (from the views, via preference keys)

    func updateSlotFrame(_ id: UUID, frame: CGRect) { slotFrames[id] = frame }
    func updateTrayFrame(_ id: UUID, frame: CGRect) { trayFrames[id] = frame }

    // MARK: Drag lifecycle (mirrors MissingLetterCoordinator's approach)

    func dragChanged(tile: SpellingBuilderTile, location: CGPoint) {
        guard canInteractWithTray, slots.contains(where: { !$0.locked }) else { return }
        if draggingTile?.id != tile.id { draggingTile = tile }
        dragLocation = location
    }

    func dragEnded(tile: SpellingBuilderTile, location: CGPoint) {
        // See `MissingLetterCoordinator.dragEnded`'s own doc comment for why
        // `dragLocation` is deliberately not set here directly -- both exit
        // paths (`lockSlot`/`returnTileToTray`) already own it themselves.
        guard let slotIndex = openSlot(at: location) else {
            returnTileToTray(tile)
            return
        }
        let slot = slots[slotIndex]
        if Character(slot.letter.lowercased()) == Character(tile.letter.lowercased()) {
            lockSlot(index: slotIndex, tile: tile)
        } else {
            wrongAttempts += 1
            fireWiggle(slotID: slot.id)
            returnTileToTray(tile)
        }
    }

    private func openSlot(at point: CGPoint) -> Int? {
        for (i, slot) in slots.enumerated() where !slot.locked {
            guard let frame = slotFrames[slot.id] else { continue }
            if frame.insetBy(dx: -10, dy: -10).contains(point) { return i }
        }
        return nil
    }

    private func lockSlot(index: Int, tile: SpellingBuilderTile) {
        withAnimation(Theme.Motion.snappy) { slots[index].locked = true }
        tray.removeAll { $0.id == tile.id }
        draggingTile = nil
        SpellingBuilderSFX.playThunk()

        guard slots.allSatisfy(\.locked) else { return }
        fuseWord()
    }

    private func returnTileToTray(_ tile: SpellingBuilderTile) {
        let home = trayFrames[tile.id]
        let token = wordToken
        withAnimation(Theme.Motion.snappy) {
            if let home { dragLocation = CGPoint(x: home.midX, y: home.midY) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.wordToken == token, self.draggingTile?.id == tile.id else { return }
            self.draggingTile = nil
        }
    }

    /// `.wrongShake` (the shared modifier the view attaches) already fires
    /// `Feedback.fire(.boing)` itself the instant its bound trigger flips
    /// true, so this only owns picking which slot wiggles + auto-clearing
    /// the flag.
    private func fireWiggle(slotID: UUID) {
        wiggleResetTimer?.cancel()
        wigglingSlotID = slotID
        let item = DispatchWorkItem { [weak self] in self?.wigglingSlotID = nil }
        wiggleResetTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func clearWiggle() {
        wiggleResetTimer?.cancel()
        wigglingSlotID = nil
    }

    // MARK: Fuse + advance (Games Spec §3.5's "best moment")

    private func fuseWord() {
        let word = words[currentWordIndex]
        service.recordGameExposure(word: word.engineID, profile: profile)
        withAnimation(Theme.Motion.celebrate) { isFused = true }
        speech.speakWord(word.text)

        let token = wordToken
        fuseAdvanceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.wordToken == token else { return }
            self.advance()
        }
        fuseAdvanceTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: item)
    }

    private func advance() {
        if currentWordIndex + 1 < words.count {
            startWord(index: currentWordIndex + 1, speak: true)
        } else {
            finishSet()
        }
    }

    private func finishSet() {
        service.recordGameRound(for: .spellingBuilder, profile: profile,
                                report: RoundReport(wrongAttempts: wrongAttempts, timeoutHints: timeoutHints))
        showRoundCelebration = true
    }

    // MARK: Teardown

    private func cancelWordTimers() {
        voiceSilenceTimer?.cancel(); voiceSilenceTimer = nil
        wiggleResetTimer?.cancel(); wiggleResetTimer = nil
        fuseAdvanceTimer?.cancel(); fuseAdvanceTimer = nil
        revealTimer?.cancel(); revealTimer = nil
        peekResetTimer?.cancel(); peekResetTimer = nil
    }

    func tearDown() {
        cancelWordTimers()
        voiceCheck.stopListening()
    }

    // MARK: DEBUG demo hooks

    #if DEBUG
    /// "-demoSpellVoice" (per this worker's brief): a Spelling Builder-only
    /// voice mock, independent of `VoiceCheckService.isMockActive`'s
    /// `-mockVoiceCheck*` family -- that family is also recognized by
    /// `HomeView`'s own (pre-existing, unrelated) demo hook to auto-launch a
    /// solo card session, which would race this game's own `-demoGame`
    /// `fullScreenCover` on the same launch. Fakes a plausible oscillating
    /// mic level plus a single clean transcript ~2s in, entirely local to
    /// this coordinator -- never touches the real `VoiceCheckService`
    /// pipeline, same approach as `SayMatchModel.demoVoiceForced`.
    static var demoVoiceForced: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoSpellVoice")
    }

    private func runDemoVoiceMock(word: String, token: UUID) {
        scheduleDemoLevelOscillation(token: token, tick: 0)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.wordToken == token else { return }
            self.handleVoiceTranscript(word, confidence: 0.9, isFinal: true, word: word, token: token)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    private func scheduleDemoLevelOscillation(token: UUID, tick: Int) {
        guard wordToken == token, voiceListening else { return }
        micLevel = Float(max(0, min(1, 0.5 + 0.4 * sin(Double(tick) * 0.6))))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scheduleDemoLevelOscillation(token: token, tick: tick + 1)
        }
    }

    /// "Games introduce nothing" (Games Spec §2) means `pickGameWords` only
    /// ever returns words with `timesSeen > 0` -- a fresh `-freshData` demo
    /// profile has none, so a `-demoGame spellingBuilder` run on one would
    /// legitimately build zero words. QA-only bridge, mirrors
    /// `SayMatchModel.seedDemoExposureIfNeeded` exactly: never runs outside
    /// `-demoGame`, so it can't affect a real played session.
    private static func seedDemoExposureIfNeeded(service: LearningService, profile: Profile) {
        guard ProcessInfo.processInfo.arguments.contains("-demoGame") else { return }
        let pool = service.pool(for: profile)
        guard pool.filter({ $0.timesSeen > 0 }).count < 10 else { return }
        for snapshot in pool.prefix(12) {
            service.recordGameExposure(word: snapshot.id, profile: profile)
        }
    }

    /// "-demoSpellSolve": auto-drops the next correct tile onto the next open
    /// slot every ~1.2s ("with beats") once a word's tray is actually
    /// interactive, so a scripted sim run can play through the whole set (and
    /// reach `RoundCelebration`) with no touch injection needed -- mirrors
    /// `MissingLetterCoordinator.debugAutoSolveNextBlank`.
    private func maybeScheduleAutoSolve() {
        guard ProcessInfo.processInfo.arguments.contains("-demoSpellSolve") else { return }
        scheduleNextAutoSolveStep()
    }

    private func scheduleNextAutoSolveStep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.showRoundCelebration else { return }
            self.debugAutoSolveNextTile()
            self.scheduleNextAutoSolveStep()
        }
    }

    func debugAutoSolveNextTile() {
        guard canInteractWithTray else { return }
        for (i, slot) in slots.enumerated() where !slot.locked {
            guard let tile = tray.first(where: { Character($0.letter.lowercased()) == Character(slot.letter.lowercased()) }) else { continue }
            lockSlot(index: i, tile: tile)
            return
        }
    }
    #endif
}
