import Foundation

// MARK: - SayMatchRoundKind

/// Which beat one round is (Games Spec §3.2): Round A is "hear it, find the
/// tile"; Round B is "see it, say it" (voice).
enum SayMatchRoundKind: Equatable {
    case hearFind
    case seeSay
}

// MARK: - SayMatchRound

/// One built round's fixed content -- the target word (engine id + display
/// text) plus, for `.hearFind` only, the other tiles on the board in their
/// final shuffled order (target included). `id` gives every round a stable
/// identity distinct from its index so `.id(round.id)` can force a fresh
/// view (and fresh `@State`) each time the game advances, even if a later
/// round happens to reuse the same target word.
struct SayMatchRound: Identifiable {
    let id: String
    let kind: SayMatchRoundKind
    let targetID: String
    let targetDisplay: String
    /// `.hearFind` only: every tile's engine id, target included, already
    /// shuffled -- empty for `.seeSay` (single tile, no choices).
    let tileIDs: [String]

    init(index: Int, kind: SayMatchRoundKind, targetID: String, targetDisplay: String, tileIDs: [String] = []) {
        self.id = "\(index)-\(kind)-\(targetID)"
        self.kind = kind
        self.targetID = targetID
        self.targetDisplay = targetDisplay
        self.tileIDs = tileIDs
    }
}

// MARK: - SayMatchModel

/// Owns one Say & Match set end to end (Games Spec §3.2): builds the 6 (or
/// 4, voice-off) rounds up front, tracks which round is showing, and
/// aggregates the whole set's `RoundReport` counters for one
/// `recordGameRound` call when the set ends -- "tier changes only between
/// rounds" (`GameTiers.swift`) means between full played *sets* here, not
/// between each individual A/B beat, mirroring how Word Hunt/Memory Match
/// only call `RoundCelebration` once at their own set's end too.
@MainActor
final class SayMatchModel: ObservableObject {
    let profile: Profile
    let service: LearningService
    let speech = SpeechService.shared
    let voiceCheck = VoiceCheckService.shared
    let tier: GameTier

    @Published private(set) var rounds: [SayMatchRound] = []
    @Published private(set) var roundIndex = 0
    @Published private(set) var currentInstruction: GameInstruction = GameInstruction(.whichWord)
    @Published private(set) var isComplete = false

    private var hasStarted = false
    private var wrongAttempts = 0
    private var timeoutHints = 0

    var totalRounds: Int { rounds.count }
    var currentRound: SayMatchRound? {
        rounds.indices.contains(roundIndex) ? rounds[roundIndex] : nil
    }

    /// Games Spec §1: voice steps require `profile.voiceCheckOn` and a
    /// currently-available recognizer; the DEBUG mock force-enables exactly
    /// like `SessionCoordinator.voiceCheckEligible` so screenshot runs don't
    /// need a real profile edit first.
    var voiceAvailable: Bool {
        #if DEBUG
        if Self.demoVoiceForced || VoiceCheckService.isMockActive { return true }
        #endif
        return profile.voiceCheckOn && voiceCheck.isAvailable()
    }

    #if DEBUG
    /// "-demoSayMatchVoice"/"-demoSayMatchVoiceConfirm": a Say & Match-only
    /// voice mock, independent of `VoiceCheckService.isMockActive`'s
    /// `-mockVoiceCheck*` family. Needed because `HomeView`'s own
    /// (pre-existing, unrelated) debug hook also keys off that same family
    /// to auto-launch a solo card session for *its* voice-check screenshots
    /// -- reusing it here would race that hook's `fullScreenCover` against
    /// this game's `-demoGame` one on the same launch. `SayMatchRoundBView`
    /// checks this same flag to fake transcripts locally instead of ever
    /// touching the real `VoiceCheckService` pipeline.
    static var demoVoiceForced: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-demoSayMatchVoice") || args.contains("-demoSayMatchVoiceConfirm")
    }
    #endif

    init(profile: Profile, service: LearningService) {
        self.profile = profile
        self.service = service
        self.tier = Self.resolveTier(service: service, profile: profile)
        buildRounds()
    }

    // MARK: Round building

    private func buildRounds() {
        #if DEBUG
        Self.seedDemoExposureIfNeeded(service: service, profile: profile)
        #endif
        let pool = service.pool(for: profile)
        let kinds: [SayMatchRoundKind] = voiceAvailable
            ? [.hearFind, .seeSay, .hearFind, .seeSay, .hearFind, .seeSay]
            : [.hearFind, .hearFind, .hearFind, .hearFind]

        let words = pickGameWords(pool: pool, count: kinds.count)
        guard !words.isEmpty else { rounds = []; return }

        let homophoneGroups = Self.homophoneGroups
        var built: [SayMatchRound] = []
        for (i, kind) in kinds.enumerated() where i < words.count {
            let target = words[i]
            let targetDisplay = service.displayText(forID: target.id)
            switch kind {
            case .hearFind:
                let tileCount = tier == .t3 ? 4 : 3
                let distractors = Self.distractorWords(for: target.id, tier: tier, pool: pool,
                                                        homophoneGroups: homophoneGroups,
                                                        needed: tileCount - 1)
                let tileIDs = ([target.id] + distractors).shuffled()
                built.append(SayMatchRound(index: i, kind: .hearFind, targetID: target.id,
                                           targetDisplay: targetDisplay, tileIDs: tileIDs))
            case .seeSay:
                built.append(SayMatchRound(index: i, kind: .seeSay, targetID: target.id,
                                           targetDisplay: targetDisplay))
            }
        }
        rounds = built
    }

    /// Games Spec §3.2 distractor rule: "T1 dissimilar (picker pool minus
    /// confusables), T2+ from confusables(for:target) padded with pool."
    /// T1 actively excludes every confusable from its candidate pool (not
    /// just skips seeking them out) so tier-1 choices are guaranteed
    /// dissimilar; if a tiny pool leaves too few non-confusable words to
    /// fill `needed`, confusables are allowed back in as a last resort
    /// rather than rendering a short-handed board.
    static func distractorWords(for target: String, tier: GameTier, pool: [WordSnapshot],
                                homophoneGroups: [[String]], needed: Int) -> [String] {
        guard needed > 0 else { return [] }
        let targetLower = target.lowercased()
        var used = Set<String>([targetLower])
        var chosen: [String] = []

        func take(from candidates: [String]) {
            for c in candidates.shuffled() {
                guard chosen.count < needed else { return }
                let cl = c.lowercased()
                guard !used.contains(cl) else { continue }
                chosen.append(c); used.insert(cl)
            }
        }

        let confusableSet = confusables(for: target, pool: pool, homophoneGroups: homophoneGroups)
        if tier == .t1 {
            let confusableLower = Set(confusableSet.map { $0.lowercased() })
            take(from: pool.map { $0.id }.filter { !confusableLower.contains($0.lowercased()) })
        } else {
            take(from: confusableSet)
        }
        if chosen.count < needed {
            take(from: pool.map { $0.id })
        }
        return chosen
    }

    // MARK: Round lifecycle

    /// Speaks nothing itself -- `GameScaffold`'s own `onAppear` already
    /// speaks round 0's instruction (Games Spec §1: every scaffold speaks
    /// its `instruction` once on appear), since `currentInstruction` is
    /// already set to round 0's line before that view is ever shown.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard let round = currentRound else { finishSet(); return }
        beginRound(round, speak: false)
    }

    /// Called by a round view once its own beat resolves (a correct tap in
    /// Round A, a confident/confirmed voice match or the 12s rescue in
    /// Round B). Moves to the next round and speaks its instruction line
    /// (Games Spec §3.2's exact opener for each round), or ends the set.
    func advance() {
        roundIndex += 1
        guard let round = currentRound else { finishSet(); return }
        beginRound(round, speak: true)
    }

    private func beginRound(_ round: SayMatchRound, speak: Bool) {
        service.recordGameExposure(word: round.targetID, profile: profile)
        switch round.kind {
        case .hearFind: currentInstruction = GameInstruction(.whichWord, word: round.targetDisplay)
        case .seeSay: currentInstruction = GameInstruction(.readIt)
        }
        if speak { speech.speak(segments: currentInstruction.segments) }
    }

    func registerWrong() { wrongAttempts += 1 }
    func registerTimeoutHint() { timeoutHints += 1 }

    private func finishSet() {
        if !rounds.isEmpty {
            service.recordGameRound(for: .sayMatch, profile: profile,
                                    report: RoundReport(wrongAttempts: wrongAttempts, timeoutHints: timeoutHints))
        }
        isComplete = true
    }

    // MARK: Homophones (contextual-string biasing + match/near-miss, Round B)

    /// Same bundled `homophones.json` parse as `SessionCoordinator`'s two
    /// static loaders -- duplicated here rather than shared because that
    /// file lives outside this game's folder (per the game-worker
    /// registration contract, only `GameCatalog`'s destination line and
    /// this folder are touched).
    static let homophoneGroups: [[String]] = {
        guard let url = Bundle.main.url(forResource: "homophones", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let groups = try? JSONDecoder().decode([[String]].self, from: data) else { return [] }
        return groups
    }()

    static let homophoneTable: HomophoneTable = {
        guard let url = Bundle.main.url(forResource: "homophones", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return HomophoneTable(json: Data("[]".utf8)) }
        return HomophoneTable(json: data)
    }()

    /// The contextual-string bias set for `target` (mirrors
    /// `SessionCoordinator.contextualStrings(for:)`): its whole homophone
    /// group if it's in one, else just the target.
    static func contextualStrings(for target: String) -> [String] {
        let lower = target.lowercased()
        if let group = homophoneGroups.first(where: { $0.contains { $0.lowercased() == lower } }) {
            return group
        }
        return [target]
    }

    // MARK: DEBUG demo hooks

    /// "-demoGame sayMatch [tier]" (Games Spec §6): an optional trailing
    /// tier digit (1/2/3) forces the tile-count/distractor-style tier for
    /// this one demo session without touching the profile's real persisted
    /// `TierLadder` -- `finishSet()` still records against the real ladder,
    /// so tier progression itself is unaffected by a demo override.
    private static func resolveTier(service: LearningService, profile: Profile) -> GameTier {
        #if DEBUG
        if let forced = demoForcedTier() { return forced }
        #endif
        return service.gameTier(for: .sayMatch, profile: profile)
    }

    #if DEBUG
    private static func demoForcedTier() -> GameTier? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-demoGame"), idx + 1 < args.count,
              args[idx + 1] == "sayMatch" else { return nil }
        guard idx + 2 < args.count, let raw = Int(args[idx + 2]), let t = GameTier(rawValue: raw) else { return nil }
        return t
    }

    /// "Games introduce nothing" (Games Spec §2) means `pickGameWords` only
    /// ever returns words with `timesSeen > 0` -- correct in the real app,
    /// but a fresh `-freshData` demo profile has NO word with `timesSeen >
    /// 0` at all, so a `-demoGame sayMatch` run on one would legitimately
    /// build zero rounds and jump straight to `RoundCelebration`. This is a
    /// QA-only bridge: on a `-demoGame` launch, if fewer than 10 pool words
    /// have ever been "seen", it records a light exposure (exactly what a
    /// normal card session would have already done) on enough words that a
    /// demo run has a real set to show. Never runs outside `-demoGame`, so
    /// it can't affect a real played session.
    private static func seedDemoExposureIfNeeded(service: LearningService, profile: Profile) {
        guard ProcessInfo.processInfo.arguments.contains("-demoGame") else { return }
        let pool = service.pool(for: profile)
        guard pool.filter({ $0.timesSeen > 0 }).count < 10 else { return }
        for snapshot in pool.prefix(12) {
            service.recordGameExposure(word: snapshot.id, profile: profile)
        }
    }
    #endif
}
