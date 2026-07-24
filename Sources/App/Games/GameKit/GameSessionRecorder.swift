import Foundation

/// GameKit's persistence bridge (Games Spec §2): the `LearningService`
/// surface every game screen goes through to (a) record light word
/// exposures, and (b) read/advance its own per-game `TierLadder`. Kept
/// separate from `LearningService.swift` itself (which predates GameKit and
/// stays focused on the card-session engine) but is still just an extension
/// on that same `@MainActor` service -- one `ModelContext`, one save path.
extension LearningService {

    // MARK: Light exposures

    /// Records a game simply showing/saying a word to the child (a Word Hunt
    /// list item, a flipped Memory Match card, a Missing Letter worksheet
    /// blank, a Spelling Builder target, etc.) -- Games Spec §2: "records
    /// light exposures: `timesSeen`+1 and `lastSeenAt` only -- never state
    /// transitions/fluent days." This deliberately does NOT go through
    /// `WordSnapshot`/`StateMachine` the way `recordScore` does: a game round
    /// is not a scored card, so it must never move a word's `state`,
    /// `needsReview`, `dueDate`, or `recentResults`. Creates a
    /// `WordProgressRecord` lazily on a word's first-ever exposure, same as
    /// `recordScore`.
    func recordGameExposure(word: String, profile: Profile, now: Date = .now) {
        let text = displayText(forID: word)
        if let existing = profile.wordProgress.first(where: { $0.wordText == text }) {
            existing.timesSeen += 1
            existing.lastSeenAt = now
        } else {
            let wp = WordProgressRecord(wordText: text)
            wp.timesSeen = 1
            wp.lastSeenAt = now
            wp.firstSeenAt = now
            wp.profile = profile
            context.insert(wp)
        }
        try? context.save()
    }

    // MARK: Per-game tier ladder

    /// Current tier for one game (Games Spec §2's per-game staircase). A
    /// game never played yet reads as a fresh tier-1 ladder -- nothing is
    /// persisted until its first round is recorded. A parent-set lock
    /// (Games Spec §5's Settings "Games" section) overrides the ladder's own
    /// tier entirely when present -- see `gameTierLock(for:profile:)`.
    func gameTier(for id: GameID, profile: Profile) -> GameTier {
        if let lock = gameTierLock(for: id, profile: profile) { return lock }
        return gameTierLadders(for: profile)[id.rawValue]?.tier ?? .t1
    }

    // MARK: Per-game tier lock (Games Spec §5, WP-G8)

    /// The parent-set lock for one game, or `nil` for "Auto" (follow the
    /// ladder). Read by `gameTier(for:profile:)` above; games themselves
    /// never need to know whether a tier came from a lock or the ladder.
    func gameTierLock(for id: GameID, profile: Profile) -> GameTier? {
        gameTierLocks(for: profile)[id.rawValue]
    }

    /// Sets (or, with `nil`, clears back to "Auto") the parent-set tier lock
    /// for one game. The underlying `TierLadder` is untouched either way --
    /// it keeps recording rounds and staircasing on its own regardless of
    /// whether a lock is currently overriding what `gameTier` reports.
    func setGameTierLock(_ tier: GameTier?, for id: GameID, profile: Profile) {
        var locks = gameTierLocks(for: profile)
        locks[id.rawValue] = tier
        saveGameTierLocks(locks, to: profile)
        try? context.save()
    }

    private func gameTierLocks(for profile: Profile) -> [String: GameTier] {
        guard let data = profile.gameTierLockData,
              let map = try? JSONDecoder().decode([String: GameTier].self, from: data)
        else { return [:] }
        return map
    }

    private func saveGameTierLocks(_ map: [String: GameTier], to profile: Profile) {
        profile.gameTierLockData = try? JSONEncoder().encode(map)
    }

    /// Rounds played at a game's CURRENT tier (Games Spec §5's parent
    /// dashboard "Games" card: "current tier + rounds played"). `TierLadder`
    /// resets this count to 0 whenever a promotion/demotion fires (Games
    /// Spec §2), so it reads as "rounds since the last tier change," not a
    /// lifetime total -- which is the number that actually means something
    /// next to "current tier."
    ///
    /// `TierLadder.roundsAtTier` itself is `private` -- Engine files are
    /// frozen this pass -- but `TierLadder`'s `Codable` conformance has no
    /// custom `CodingKeys`, so Swift's auto-synthesis still encodes every
    /// stored property (private ones included) into the same JSON blob
    /// `gameTierLadders(for:)` decodes above. This decodes that identical
    /// `Profile.gameTierData` payload a second time into a tiny parallel
    /// shape exposing just the one field the dashboard needs, rather than
    /// adding a public accessor to the frozen Engine type.
    func gameRoundsAtCurrentTier(for id: GameID, profile: Profile) -> Int {
        struct LadderRoundsProbe: Decodable { let roundsAtTier: Int }
        guard let data = profile.gameTierData,
              let map = try? JSONDecoder().decode([String: LadderRoundsProbe].self, from: data)
        else { return 0 }
        return map[id.rawValue]?.roundsAtTier ?? 0
    }

    /// Records one just-finished round (Games Spec §2: "tier changes only
    /// between rounds" -- callers must only call this from a between-rounds
    /// point, never mid-round) and persists the updated ladder.
    /// `reviewBacklogGrowing` is derived from the profile's own rolling
    /// needsReview snapshot (see below) -- callers never compute or pass
    /// that themselves.
    func recordGameRound(for id: GameID, profile: Profile, report: RoundReport, now: Date = .now) {
        var ladders = gameTierLadders(for: profile)
        var ladder = ladders[id.rawValue] ?? TierLadder()
        ladder.record(report, reviewBacklogGrowing: reviewBacklogGrowing(for: profile, now: now))
        ladders[id.rawValue] = ladder
        saveGameTierLadders(ladders, to: profile)
        try? context.save()
    }

    /// Decodes the `[GameID.rawValue: TierLadder]` map from
    /// `Profile.gameTierData`. Never call this from outside `LearningService`
    /// -- `gameTier(for:profile:)` / `recordGameRound(for:profile:report:)`
    /// are the only supported entry points (per `gameTierData`'s doc comment
    /// in `Models.swift`).
    private func gameTierLadders(for profile: Profile) -> [String: TierLadder] {
        guard let data = profile.gameTierData,
              let map = try? JSONDecoder().decode([String: TierLadder].self, from: data)
        else { return [:] }
        return map
    }

    private func saveGameTierLadders(_ map: [String: TierLadder], to profile: Profile) {
        profile.gameTierData = try? JSONEncoder().encode(map)
    }

    // MARK: Review-backlog freeze (Games Spec §2)

    /// Whether the review backlog is growing: strictly more needsReview
    /// words today than ~7 days ago. Feeds `TierLadder.record`'s promotion
    /// freeze (Games Spec §2: "NEVER promote while `reviewBacklogGrowing`
    /// flag true"). Also takes care of appending today's snapshot to the
    /// profile's rolling history (at most once per calendar day) as a side
    /// effect, so callers never need to manage that themselves.
    func reviewBacklogGrowing(for profile: Profile, now: Date = .now, calendar: Calendar = .current) -> Bool {
        appendNeedsReviewSnapshotIfNeeded(for: profile, now: now, calendar: calendar)
        // Capped at 8 entries (today + 7 days back, oldest first) --
        // index 0 is the ~7-day-old reading once the window is full. With
        // less than a full week of history there's nothing yet to compare
        // against, so the backlog is never reported as growing.
        guard profile.needsReviewHistory.count >= 8 else { return false }
        let weekAgoCount = profile.needsReviewHistory[0]
        let todayCount = profile.needsReviewHistory[profile.needsReviewHistory.count - 1]
        return todayCount > weekAgoCount
    }

    /// Appends the profile's current needsReview count to its rolling
    /// history, gated to once per calendar day via
    /// `needsReviewHistoryUpdatedAt` (Models.swift). No-ops (and does not
    /// re-save) if today's snapshot has already been taken.
    private func appendNeedsReviewSnapshotIfNeeded(for profile: Profile, now: Date, calendar: Calendar) {
        if let last = profile.needsReviewHistoryUpdatedAt, calendar.isDate(last, inSameDayAs: now) {
            return
        }
        let count = pool(for: profile).filter { $0.needsReview }.count
        profile.needsReviewHistory.append(count)
        if profile.needsReviewHistory.count > 8 {
            profile.needsReviewHistory.removeFirst(profile.needsReviewHistory.count - 8)
        }
        profile.needsReviewHistoryUpdatedAt = now
        try? context.save()
    }
}
