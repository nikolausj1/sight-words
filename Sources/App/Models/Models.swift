import Foundation
import SwiftData

// MARK: - Profile

/// A learner profile. Exactly one is active at a time; each owns its own word
/// progress and session history (cascade deletes, Math Tutor pattern).
@Model
final class Profile {
    var id: UUID
    var name: String
    var avatarSymbol: String
    var level: String              // "PreK" | "K" | "1" | "2" | "3"
    var onboarded: Bool
    var isActive: Bool
    var createdAt: Date

    var soundOn: Bool = true
    var voiceCheckOn: Bool = false
    /// Mic input style for voice-check (`MicMode` in `SessionCoordinator.swift`):
    /// "auto" (always-listening, the original/default behavior) or "hold"
    /// (big hold-to-talk button, solo sessions only). Additive field —
    /// lightweight SwiftData migration; existing rows just read "auto".
    var micModeRaw: String = "auto"
    var sessionSize: Int = 12

    /// Additive field (lightweight SwiftData migration): the parent's
    /// Design Direction §8 night-mode override -- `TimeOfDayService.Override`
    /// raw value ("auto" | "day" | "night"), read/written by
    /// `ParentAreaView`'s Settings card. Existing rows read "auto" (clock-
    /// driven, the default), matching every other freshly-added *Raw field
    /// in this model (see `micModeRaw` just above).
    var timeOfDayOverrideRaw: String = "auto"

    /// Control style ("parent" | "solo") of the last Practice Together/On My Own
    /// session — Tricky Words (§6.3) has no controls of its own and mirrors this.
    var lastUsedControlStyle: String = "parent"

    var streakDays: Int = 0
    var lastPracticeDate: Date?

    /// Dolch list IDs (+ "custom") active for this profile.
    var activeListIDs: [String] = []

    /// Additive field (lightweight SwiftData migration): JSON-encoded
    /// `[GameID.rawValue: TierLadder]` map, one staircase state per GameKit
    /// game (Games Spec §2). Existing rows read `nil` (no game played yet);
    /// `LearningService.gameTier(for:profile:)` treats that as a fresh
    /// tier-1 ladder for every game. Never decode/encode this directly --
    /// go through `GameSessionRecorder.swift`'s `LearningService` extension.
    var gameTierData: Data?

    /// Additive fields backing `reviewBacklogGrowing` (Games Spec §2: tier
    /// promotion freezes while the review backlog is growing). A rolling
    /// window of daily `needsReview` counts, oldest first, capped at 8
    /// entries (today + 7 days back) so index 0 is always ~7 days old once
    /// full; `needsReviewHistoryUpdatedAt` gates the append to once per
    /// calendar day. See `GameSessionRecorder.swift`.
    var needsReviewHistory: [Int] = []
    var needsReviewHistoryUpdatedAt: Date?

    /// Additive field (lightweight SwiftData migration): JSON-encoded
    /// `[GameID.rawValue: GameTier]` map of parent-set tier locks (Games Spec
    /// §5's Settings "Games" section: Auto/1/2/3 per game). A game absent
    /// from the map (or the whole field `nil`) reads as "Auto" -- the
    /// ladder's own current tier is used unchanged. A present entry pins
    /// `LearningService.gameTier(for:profile:)`'s return value to that fixed
    /// tier regardless of ladder state; the ladder keeps recording rounds
    /// underneath the whole time, so switching back to Auto resumes wherever
    /// it actually is. Never decode/encode this directly -- go through
    /// `GameSessionRecorder.swift`'s `LearningService` extension.
    var gameTierLockData: Data?

    @Relationship(deleteRule: .cascade, inverse: \WordProgressRecord.profile)
    var wordProgress: [WordProgressRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \PracticeSession.profile)
    var sessions: [PracticeSession] = []

    init(name: String = "Player 1", avatarSymbol: String = "avatar1", level: String = "K",
         onboarded: Bool = false, isActive: Bool = true, activeListIDs: [String] = []) {
        self.id = UUID()
        self.name = name
        self.avatarSymbol = avatarSymbol
        self.level = level
        self.onboarded = onboarded
        self.isActive = isActive
        self.createdAt = .now
        self.activeListIDs = activeListIDs
    }
}

// MARK: - WordRecord

/// A single sight word. `text` is globally unique ("I" stays capitalized,
/// everything else lowercase — see `LearningService.normalize`). Dolch words
/// are seeded at bootstrap; custom words come from the parent area (later phase).
@Model
final class WordRecord {
    var text: String
    var listID: String             // dolchPrePrimer | dolchPrimer | dolchFirst | dolchSecond | dolchThird | custom
    var sentence: String?
    var isCustom: Bool

    init(text: String, listID: String, sentence: String? = nil, isCustom: Bool = false) {
        self.text = text
        self.listID = listID
        self.sentence = sentence
        self.isCustom = isCustom
    }
}

// MARK: - WordProgressRecord

/// Per-profile, per-word learning state — the persisted mirror of Engine's
/// `WordSnapshot`. Created lazily: a profile only gets one of these for a word
/// once it's introduced or scored; until then the pool treats it as `.new`.
@Model
final class WordProgressRecord {
    var wordText: String
    var profile: Profile?

    var stateRaw: String
    var needsReview: Bool
    var timesSeen: Int
    var timesCorrect: Int
    var timesMissed: Int
    var lastResult: String?
    var lastSeenAt: Date?
    var dueDate: Date?
    var avgResponseMs: Int
    var recentResults: [String]
    var fluentDayCount: Int
    var lastFluentDay: Date?

    /// Additive field (lightweight SwiftData migration): stamped the first time
    /// this profile is ever exposed to the word (dashboard word-detail popover).
    /// Existing rows predating this field simply read `nil`.
    var firstSeenAt: Date?

    init(wordText: String) {
        self.wordText = wordText
        self.stateRaw = WordState.new.rawValue
        self.needsReview = false
        self.timesSeen = 0
        self.timesCorrect = 0
        self.timesMissed = 0
        self.recentResults = []
        self.avgResponseMs = 0
        self.fluentDayCount = 0
        self.firstSeenAt = nil
    }

    /// Bridges to the pure engine's value type. Note: `WordSnapshot.init`
    /// lowercases `id` — callers that need the display text (e.g. "I") should
    /// go through `LearningService.displayText(forID:)`, not this snapshot.
    var snapshot: WordSnapshot {
        WordSnapshot(
            id: wordText,
            state: WordState(rawValue: stateRaw) ?? .new,
            needsReview: needsReview,
            timesSeen: timesSeen,
            timesCorrect: timesCorrect,
            timesMissed: timesMissed,
            lastResult: lastResult,
            lastSeenAt: lastSeenAt,
            dueDate: dueDate,
            avgResponseMs: avgResponseMs,
            recentResults: recentResults,
            fluentDayCount: fluentDayCount,
            lastFluentDay: lastFluentDay
        )
    }

    func apply(_ s: WordSnapshot) {
        stateRaw = s.state.rawValue
        needsReview = s.needsReview
        timesSeen = s.timesSeen
        timesCorrect = s.timesCorrect
        timesMissed = s.timesMissed
        lastResult = s.lastResult
        lastSeenAt = s.lastSeenAt
        dueDate = s.dueDate
        avgResponseMs = s.avgResponseMs
        recentResults = s.recentResults
        fluentDayCount = s.fluentDayCount
        lastFluentDay = s.lastFluentDay
    }
}

// MARK: - PracticeSession

/// One completed (or stopped) practice session — backs the future dashboard.
@Model
final class PracticeSession {
    var profile: Profile?
    var date: Date
    var mode: String                // "parent" | "solo" | "tricky"
    var cardsPlayed: Int
    var gotIt: Int
    var almost: Int
    var notYet: Int
    var durationSec: Double

    init(date: Date = .now, mode: String, cardsPlayed: Int, gotIt: Int, almost: Int,
         notYet: Int, durationSec: Double) {
        self.date = date
        self.mode = mode
        self.cardsPlayed = cardsPlayed
        self.gotIt = gotIt
        self.almost = almost
        self.notYet = notYet
        self.durationSec = durationSec
    }
}
