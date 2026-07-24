import SwiftUI

/// Owns one Memory Match play session end to end (Games Spec §3.3): builds
/// each round's shuffled card board, tracks flip/compare/match state, drives
/// the optional 🎤 "Say it to bank it!" beat on a match, and records
/// tier/exposure data through `LearningService`'s GameKit extension. Shape
/// mirrors `WordHuntCoordinator` (2 boards == 2 "rounds" per set, one
/// `recordGameRound` call per board, `RoundCelebration` once both are
/// clear) -- but unlike Word Hunt/Say & Match, a match's own celebration is
/// a small local confetti burst at the two cards, never the shared
/// full-screen `SuccessMoment` (Games Spec §3.3 keeps this game's matches
/// lightweight so rapid-fire flipping never queues/blocks).
@MainActor
final class MemoryCoordinator: ObservableObject {
    // MARK: Published board state

    @Published private(set) var cards: [MemoryCard] = []
    /// Face-up cards: either mid-compare (0-2 cards, not yet resolved) or
    /// permanently up once matched.
    @Published private(set) var faceUpIDs: Set<String> = []
    @Published private(set) var matchedPairIDs: Set<String> = []
    /// Pairs that earned the optional voice-confirm star badge (Games Spec
    /// §3.3: "pure bonus, no penalty").
    @Published private(set) var bankedPairIDs: Set<String> = []
    /// The two cards of a just-resolved mismatch, shaking via `.wrongShake`.
    @Published private(set) var wrongCardIDs: Set<String> = []
    /// The two cards of a just-resolved match, showing their small local
    /// confetti burst for a beat.
    @Published private(set) var justMatchedCardIDs: Set<String> = []
    /// True while the just-cleared board is animating out (Games Spec
    /// §3.3: "bloop-out cards") before the next round's board appears.
    @Published private(set) var clearingBoard = false

    @Published private(set) var tier: GameTier
    @Published private(set) var currentRoundIndex = 0
    let totalRounds = 2
    @Published private(set) var showRoundCelebration = false

    // MARK: Published bank-beat (🎤 "Say it to bank it!") state

    @Published private(set) var bankingPairID: String?
    @Published private(set) var bankListening = false
    @Published private(set) var bankFlashCorrect = false
    @Published private(set) var bankMicLevel: Float = 0

    var pairCount: Int { memoryConfig(for: tier).pairCount }
    var usesSpeakerCards: Bool { memoryConfig(for: tier).usesSpeakerCards }

    /// The word currently being banked, for the overlay's prompt text.
    var bankingDisplayText: String? {
        guard let pairID = bankingPairID else { return nil }
        return cards.first(where: { $0.pairID == pairID })?.displayText
    }

    // MARK: Dependencies

    private let profile: Profile
    private let service: LearningService
    private let voiceCheck: VoiceCheckService
    private let speech: SpeechService
    /// Fixed for a demo session (`-demoGame memory t2`) so every round of it
    /// stays at the requested tier instead of re-reading (and potentially
    /// promoting/demoting) the profile's real ladder.
    private let demoTierOverride: GameTier?

    // MARK: Round bookkeeping

    private var roundToken = UUID()
    private var pendingCompareIDs: [String] = []
    private var mismatchesThisRound = 0
    private var bankQueue: [(pairID: String, cardIDs: [String])] = []
    private var currentBankToken = UUID()
    private var bankSilenceTimer: DispatchWorkItem?
    private var lastTeacherSpeechAt: Date?

    /// Same bundled `homophones.json` parse `WordHuntCoordinator`/
    /// `SayMatchModel` each keep their own copy of -- duplicated here rather
    /// than shared per the game-worker registration contract (only this
    /// folder is touched).
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

    init(profile: Profile, service: LearningService, tierOverride: GameTier? = nil,
         voiceCheck: VoiceCheckService = .shared, speech: SpeechService = .shared) {
        self.profile = profile
        self.service = service
        self.voiceCheck = voiceCheck
        self.speech = speech
        self.demoTierOverride = tierOverride
        let resolvedTier = tierOverride ?? service.gameTier(for: .memory, profile: profile)
        self.tier = resolvedTier
        startRound(speakOpening: false)
        #if DEBUG
        maybeScheduleAutoSolveAll()
        #endif
    }

    // MARK: Round lifecycle

    private func startRound(speakOpening: Bool = true) {
        roundToken = UUID()
        pendingCompareIDs = []
        mismatchesThisRound = 0
        faceUpIDs = []
        matchedPairIDs = []
        bankedPairIDs = []
        wrongCardIDs = []
        justMatchedCardIDs = []
        clearingBoard = false
        bankQueue = []
        bankingPairID = nil
        bankListening = false
        bankFlashCorrect = false
        cancelBankTimers()
        voiceCheck.stopListening()

        let resolvedTier = demoTierOverride ?? service.gameTier(for: .memory, profile: profile)
        tier = resolvedTier
        let config = memoryConfig(for: resolvedTier)

        let pool = service.pool(for: profile)
        var pickRng: RandomNumberGenerator = SystemRandomNumberGenerator()
        let picked = pickGameWords(pool: pool, count: config.pairCount, rng: &pickRng)
        let words = picked.map { (id: $0.id, display: service.displayText(forID: $0.id)) }
        cards = MemoryBoardBuilder.build(words: words, usesSpeakerCards: config.usesSpeakerCards,
                                         roundToken: roundToken.uuidString)

        if speakOpening {
            speech.speak(segments: [.phrase(.matchTheCards)])
        }

        #if DEBUG
        maybeSeedDemoExposureIfNeeded()
        #endif
    }

    // MARK: Flip / compare / match

    /// A tap on any card: a face-down card flips (and speaks its word --
    /// Games Spec §3.3: "every flip speaks its word"); a card that's
    /// already face-up (mid-compare, or a permanently-matched pair) just
    /// replays its word (Games Spec §1's tap-to-hear-everywhere, and §3.3's
    /// "tap [speaker card] while face-up = replay").
    func flipCard(_ id: String) {
        guard let card = cards.first(where: { $0.id == id }) else { return }
        if matchedPairIDs.contains(card.pairID) || faceUpIDs.contains(id) {
            speech.speakWord(card.displayText)
            return
        }
        guard !clearingBoard, pendingCompareIDs.count < 2 else { return }
        faceUpIDs.insert(id)
        speech.speakWord(card.displayText)
        pendingCompareIDs.append(id)
        if pendingCompareIDs.count == 2 {
            resolvePendingCompare()
        }
    }

    private func resolvePendingCompare() {
        let ids = pendingCompareIDs
        pendingCompareIDs = []
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.roundToken == token, ids.count == 2,
                  let c0 = self.cards.first(where: { $0.id == ids[0] }),
                  let c1 = self.cards.first(where: { $0.id == ids[1] }) else { return }
            if c0.pairID == c1.pairID {
                self.handleMatch(pairID: c0.pairID, cardIDs: ids)
            } else {
                self.handleMismatch(cardIDs: ids)
            }
        }
    }

    private func handleMatch(pairID: String, cardIDs: [String]) {
        matchedPairIDs.insert(pairID)
        Feedback.fire(.correct)
        service.recordGameExposure(word: pairID, profile: profile)
        justMatchedCardIDs.formUnion(cardIDs)
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.roundToken == token else { return }
            self.justMatchedCardIDs.subtract(cardIDs)
        }
        maybeBeginBankBeat(pairID: pairID, cardIDs: cardIDs)
        checkBoardClear()
    }

    private func handleMismatch(cardIDs: [String]) {
        mismatchesThisRound += 1
        wrongCardIDs = Set(cardIDs)
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.roundToken == token else { return }
            for id in cardIDs { self.faceUpIDs.remove(id) }
        }
    }

    /// Called by `.wrongShake`'s trigger binding once its own ~0.4s shake
    /// settles -- separate from (and shorter than) the 0.9s flip-back above.
    func clearWrongFlag(_ id: String) {
        wrongCardIDs.remove(id)
    }

    // MARK: Board clear -> next round / RoundCelebration

    private func checkBoardClear() {
        guard bankingPairID == nil, bankQueue.isEmpty else { return }
        guard !clearingBoard, !cards.isEmpty, matchedPairIDs.count * 2 >= cards.count else { return }
        clearingBoard = true
        let report = RoundReport(wrongAttempts: mismatchesThisRound, timeoutHints: 0)
        service.recordGameRound(for: .memory, profile: profile, report: report)
        GameAudio.shared.playSFX("sfx_bloop")
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.roundToken == token else { return }
            if self.currentRoundIndex + 1 < self.totalRounds {
                self.currentRoundIndex += 1
                self.startRound()
            } else {
                self.showRoundCelebration = true
            }
        }
    }

    // MARK: Bank beat (🎤 "Say it to bank it!", Games Spec §3.3 -- pure bonus)

    private var bankVoiceEligible: Bool {
        #if DEBUG
        if Self.demoVoiceForced { return true }
        if VoiceCheckService.isMockActive { return voiceCheck.isAvailable() }
        #endif
        return profile.voiceCheckOn && voiceCheck.isAvailable()
    }

    private func maybeBeginBankBeat(pairID: String, cardIDs: [String]) {
        guard bankVoiceEligible else { return }
        bankQueue.append((pairID, cardIDs))
        advanceBankQueueIfIdle()
    }

    private func advanceBankQueueIfIdle() {
        guard bankingPairID == nil, !bankQueue.isEmpty else { return }
        let next = bankQueue.removeFirst()
        bankingPairID = next.pairID
        bankListening = true
        bankMicLevel = 0
        speech.speak(segments: [.phrase(.sayItToBankIt)])
        let token = UUID()
        currentBankToken = token
        guard let target = cards.first(where: { $0.pairID == next.pairID })?.displayText else {
            finishBankBeat(pairID: next.pairID, token: token, banked: false)
            return
        }
        #if DEBUG
        if Self.demoVoiceForced {
            runDemoBankVoiceMock(pairID: next.pairID, target: target, token: token)
        } else {
            startRealBankListening(pairID: next.pairID, target: target, token: token)
        }
        #else
        startRealBankListening(pairID: next.pairID, target: target, token: token)
        #endif
        armBankSilenceTimer(pairID: next.pairID, token: token)
    }

    private func startRealBankListening(pairID: String, target: String, token: UUID) {
        voiceCheck.startListening(
            target: target,
            contextualStrings: Self.contextualStrings(for: target),
            onTranscript: { [weak self] heard, confidence, isFinal in
                self?.handleBankTranscript(heard, confidence: confidence, isFinal: isFinal,
                                           pairID: pairID, target: target, token: token)
            },
            onLevel: { [weak self] level in
                guard let self, self.currentBankToken == token else { return }
                self.bankMicLevel = level
            }
        )
    }

    private func handleBankTranscript(_ heard: String, confidence: Float, isFinal: Bool,
                                       pairID: String, target: String, token: UUID) {
        guard currentBankToken == token, bankingPairID == pairID else { return }
        // Self-hearing guard, same rationale as every other game's voice
        // beat: the input tap has no echo cancellation.
        if speech.isSpeakingAloud { lastTeacherSpeechAt = Date(); return }
        if let last = lastTeacherSpeechAt, Date().timeIntervalSince(last) < 1.0 { return }

        let tokens = heard.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard tokens.contains(where: { Self.homophones.matches(heard: $0, target: target.lowercased()) }) else { return }
        guard isFinal || confidence >= 0.5 else { return }
        acceptBank(pairID: pairID, token: token)
    }

    private func acceptBank(pairID: String, token: UUID) {
        guard bankingPairID == pairID else { return }
        bankSilenceTimer?.cancel()
        voiceCheck.stopListening()
        bankedPairIDs.insert(pairID)
        bankFlashCorrect = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.currentBankToken == token else { return }
            self.bankFlashCorrect = false
            self.finishBankBeat(pairID: pairID, token: token, banked: true)
        }
    }

    /// Games Spec §3.3: "pure bonus, no penalty" -- silence just moves on
    /// (4s, shorter than the 6/12s solo-card voice windows since nothing
    /// here is required for the child to keep playing).
    private func armBankSilenceTimer(pairID: String, token: UUID) {
        bankSilenceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.currentBankToken == token, self.bankingPairID == pairID else { return }
            self.voiceCheck.stopListening()
            self.finishBankBeat(pairID: pairID, token: token, banked: false)
        }
        bankSilenceTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: item)
    }

    private func finishBankBeat(pairID: String, token: UUID, banked: Bool) {
        guard currentBankToken == token, bankingPairID == pairID else { return }
        bankListening = false
        bankingPairID = nil
        advanceBankQueueIfIdle()
        checkBoardClear()
    }

    private func cancelBankTimers() {
        bankSilenceTimer?.cancel(); bankSilenceTimer = nil
    }

    // MARK: Teardown

    func tearDown() {
        voiceCheck.stopListening()
        cancelBankTimers()
    }

    // MARK: DEBUG demo hooks

    #if DEBUG
    /// "-demoMemoryVoice" (Games Spec §6): a Memory-only voice mock,
    /// independent of `VoiceCheckService.isMockActive`'s `-mockVoiceCheck*`
    /// family -- that family is ALSO recognized by `HomeView`'s own
    /// (pre-existing, unrelated) demo dispatch as "launch the On My Own
    /// solo session," whose `fullScreenCover` wins the presentation race
    /// against `-demoGame memory`'s on the same launch (same known quirk
    /// documented on Say & Match's `demoVoiceForced`).
    static var demoVoiceForced: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoMemoryVoice")
    }

    /// Fakes a clean transcript ~1.2s into a bank beat, entirely local to
    /// this coordinator -- never touches the real `VoiceCheckService`.
    private func runDemoBankVoiceMock(pairID: String, target: String, token: UUID) {
        bankMicLevel = 0.55
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.currentBankToken == token, self.bankingPairID == pairID else { return }
            self.handleBankTranscript(target, confidence: 0.9, isFinal: true, pairID: pairID, target: target, token: token)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    /// "-demoMemorySolve" (Games Spec §6): "auto-plays pairs with 1s
    /// beats" -- repeatedly flips whatever pair is next (across both
    /// rounds) roughly once a second until `showRoundCelebration` fires.
    /// Scheduled once from `init` (not per-round) so it survives the
    /// round-1 -> round-2 transition, mirroring
    /// `WordHuntCoordinator.maybeScheduleAutoSolveAll`.
    private func maybeScheduleAutoSolveAll() {
        guard ProcessInfo.processInfo.arguments.contains("-demoMemorySolve") else { return }
        scheduleNextAutoSolveStep()
    }

    private func scheduleNextAutoSolveStep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.showRoundCelebration else { return }
            self.autoSolveNextPair()
            self.scheduleNextAutoSolveStep()
        }
    }

    private func autoSolveNextPair() {
        guard pendingCompareIDs.isEmpty, !clearingBoard else { return }
        let unmatched = cards.filter { !matchedPairIDs.contains($0.pairID) && !faceUpIDs.contains($0.id) }
        guard let firstCard = unmatched.first,
              let secondCard = unmatched.first(where: { $0.pairID == firstCard.pairID && $0.id != firstCard.id })
        else { return }
        let token = roundToken
        flipCard(firstCard.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.roundToken == token else { return }
            self.flipCard(secondCard.id)
        }
    }

    /// "Games introduce nothing" (Games Spec §2) means `pickGameWords` only
    /// returns already-seen words -- a fresh `-freshData` demo profile has
    /// none, so a `-demoGame memory` run would legitimately build zero
    /// pairs. Same QA-only bridge `SayMatchModel` uses: seeds a light
    /// exposure on enough pool words that a demo run has a real board.
    private func maybeSeedDemoExposureIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-demoGame") else { return }
        let pool = service.pool(for: profile)
        guard pool.filter({ $0.timesSeen > 0 }).count < 10 else { return }
        for snapshot in pool.prefix(12) {
            service.recordGameExposure(word: snapshot.id, profile: profile)
        }
        // Rebuild this round's cards now that the pool has exposures.
        let config = memoryConfig(for: tier)
        let newPool = service.pool(for: profile)
        var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
        let picked = pickGameWords(pool: newPool, count: config.pairCount, rng: &rng)
        guard !picked.isEmpty else { return }
        let words = picked.map { (id: $0.id, display: service.displayText(forID: $0.id)) }
        cards = MemoryBoardBuilder.build(words: words, usesSpeakerCards: config.usesSpeakerCards,
                                         roundToken: roundToken.uuidString)
    }
    #endif
}
