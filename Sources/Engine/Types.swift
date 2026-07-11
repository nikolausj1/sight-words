import Foundation

// MARK: - WordState

/// The lifecycle state of a word for a given profile.
/// new -> learning -> developing -> fluent -> mastered
public enum WordState: String, Codable, Equatable {
    case new
    case learning
    case developing
    case fluent
    case mastered
}

// MARK: - ScoreResult

/// The outcome a parent (or the child, self-scoring) records for one exposure of a word.
public enum ScoreResult: Equatable {
    case gotIt
    case almost
    case notYet

    /// Stable string form, used for `lastResult` / `recentResults`.
    public var label: String {
        switch self {
        case .gotIt: return "gotIt"
        case .almost: return "almost"
        case .notYet: return "notYet"
        }
    }
}

// MARK: - SpeedBand

/// Response-time band measured from word-appear to score/reveal tap.
/// fast < 2000ms; developing 2000...5000ms; slow > 5000ms.
public enum SpeedBand: Equatable {
    case fast
    case developing
    case slow

    public init(responseMs: Int) {
        if responseMs < 2000 {
            self = .fast
        } else if responseMs <= 5000 {
            self = .developing
        } else {
            self = .slow
        }
    }
}

// MARK: - WordSnapshot

/// Pure-value mirror of a profile's `WordProgress` for one word. The app layer maps
/// this to/from SwiftData; nothing in this type touches SwiftData or UIKit.
public struct WordSnapshot {
    /// Word identity: lowercased word text, used as the stable key everywhere in the engine.
    public var id: String

    public var state: WordState
    public var needsReview: Bool

    public var timesSeen: Int
    public var timesCorrect: Int
    public var timesMissed: Int

    public var lastResult: String?
    public var lastSeenAt: Date?
    public var dueDate: Date?

    public var avgResponseMs: Int
    /// Most recent results, oldest first, capped at 5 entries.
    public var recentResults: [String]

    public var fluentDayCount: Int
    public var lastFluentDay: Date?

    public var isNew: Bool { state == .new }

    public init(
        id: String,
        state: WordState = .new,
        needsReview: Bool = false,
        timesSeen: Int = 0,
        timesCorrect: Int = 0,
        timesMissed: Int = 0,
        lastResult: String? = nil,
        lastSeenAt: Date? = nil,
        dueDate: Date? = nil,
        avgResponseMs: Int = 0,
        recentResults: [String] = [],
        fluentDayCount: Int = 0,
        lastFluentDay: Date? = nil
    ) {
        self.id = id.lowercased()
        self.state = state
        self.needsReview = needsReview
        self.timesSeen = timesSeen
        self.timesCorrect = timesCorrect
        self.timesMissed = timesMissed
        self.lastResult = lastResult
        self.lastSeenAt = lastSeenAt
        self.dueDate = dueDate
        self.avgResponseMs = avgResponseMs
        self.recentResults = recentResults
        self.fluentDayCount = fluentDayCount
        self.lastFluentDay = lastFluentDay
    }
}
