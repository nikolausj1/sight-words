import Foundation

// MARK: - GameTier

/// The three difficulty tiers every GameKit game is built around (Games Spec
/// §3). Raw `Int` so a tier round-trips cleanly through the JSON persisted in
/// `Profile.gameTierData` (see `GameSessionRecorder.swift`).
public enum GameTier: Int, Codable, Equatable, CaseIterable {
    case t1 = 1
    case t2 = 2
    case t3 = 3

    /// The next tier up, or nil at the ceiling (t3).
    public var promoted: GameTier? {
        switch self {
        case .t1: return .t2
        case .t2: return .t3
        case .t3: return nil
        }
    }

    /// The next tier down, or nil at the floor (t1).
    public var demoted: GameTier? {
        switch self {
        case .t1: return nil
        case .t2: return .t1
        case .t3: return .t2
        }
    }
}

// MARK: - RoundReport

/// One completed game round's raw counters, fed into `TierLadder.record`.
/// Everything a game needs to report is just these two numbers — the ladder
/// itself derives "clean"/"rough" from them.
public struct RoundReport: Codable, Equatable {
    public var wrongAttempts: Int
    public var timeoutHints: Int

    public init(wrongAttempts: Int, timeoutHints: Int) {
        self.wrongAttempts = wrongAttempts
        self.timeoutHints = timeoutHints
    }

    /// Games Spec §2: "clean = 0 timeout-hints and ≤1 wrong attempt".
    public var isClean: Bool { timeoutHints == 0 && wrongAttempts <= 1 }

    /// Games Spec §2: "rough = ≥3 wrong attempts or ≥2 timeout-hints".
    public var isRough: Bool { wrongAttempts >= 3 || timeoutHints >= 2 }
}

// MARK: - TierLadder

/// Per-game staircase state machine (Games Spec §2). A pure value type —
/// the app layer is responsible for persisting it (JSON, one `TierLadder`
/// per game id, inside `Profile.gameTierData`) and for calling `record`
/// exactly once **between rounds**, never mid-round; this type has no notion
/// of "mid-round" itself, so that invariant is entirely on the caller.
///
/// Staircase rules, all evaluated against the tier the child is CURRENTLY
/// at (every counter resets whenever the tier changes):
/// - Promote once at least 5 of the last (up to) 7 rounds were clean.
/// - Demote after 2 CONSECUTIVE rough rounds (a non-rough round in between
///   resets that streak back to 0, even if it wasn't clean either).
/// - Backstop-promote after 15 rounds at the same tier with ≥90% clean
///   overall, even if the 5-of-7 window never lined up (e.g. steady 3/7 for
///   a long stretch still clears 90% given enough rounds).
/// - Promotion (never demotion) is frozen while `reviewBacklogGrowing` is
///   true — a demote can still fire in the same round a promotion would
///   otherwise have been frozen; the two conditions are mutually exclusive
///   in practice since a rough round can never also be clean.
public struct TierLadder: Codable, Equatable {
    public private(set) var tier: GameTier

    /// Clean/rough flags for rounds at the CURRENT tier, oldest first,
    /// capped at the last 7 (only the trailing window matters for the
    /// 5-of-7 rule; the 15-round backstop is tracked separately below so it
    /// isn't limited by this cap).
    private var recentClean: [Bool]
    private var roundsAtTier: Int
    private var cleanCountAtTier: Int
    private var consecutiveRough: Int

    public init(tier: GameTier = .t1) {
        self.tier = tier
        self.recentClean = []
        self.roundsAtTier = 0
        self.cleanCountAtTier = 0
        self.consecutiveRough = 0
    }

    /// Records one just-finished round and applies the staircase rules,
    /// mutating `tier` in place if a promotion/demotion fires. Call this
    /// only between rounds.
    public mutating func record(_ report: RoundReport, reviewBacklogGrowing: Bool) {
        let clean = report.isClean
        let rough = report.isRough

        recentClean.append(clean)
        if recentClean.count > 7 {
            recentClean.removeFirst(recentClean.count - 7)
        }
        roundsAtTier += 1
        if clean { cleanCountAtTier += 1 }
        consecutiveRough = rough ? consecutiveRough + 1 : 0

        // Demotion is checked first and is never blocked by the backlog
        // freeze — that freeze only guards promotion.
        if consecutiveRough >= 2, let lower = tier.demoted {
            tier = lower
            resetAtTier()
            return
        }

        guard !reviewBacklogGrowing else { return }

        let cleanOfWindow = recentClean.filter { $0 }.count
        let fiveOfSevenPromote = cleanOfWindow >= 5
        let backstopPromote = roundsAtTier >= 15
            && Double(cleanCountAtTier) / Double(roundsAtTier) >= 0.90

        if (fiveOfSevenPromote || backstopPromote), let higher = tier.promoted {
            tier = higher
            resetAtTier()
        }
    }

    private mutating func resetAtTier() {
        recentClean = []
        roundsAtTier = 0
        cleanCountAtTier = 0
        consecutiveRough = 0
    }
}
