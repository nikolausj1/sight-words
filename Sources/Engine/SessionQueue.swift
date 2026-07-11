import Foundation

/// Result of scoring the current card: the updated snapshot plus what happened to
/// the queue as a consequence.
public struct ScoredEvent {
    public let snapshot: WordSnapshot
    public let reteachTriggered: Bool
    public let reenqueued: Bool
}

/// The within-session card queue. Owns reinsertion per PRD §6.9's table:
///
/// | Result | Reinsertion |
/// |---|---|
/// | Got it, fast | Done |
/// | Got it, slow (or any Almost) | 5-8 cards later |
/// | Not yet | 2-4 cards later |
/// | Not yet x2 (same word, same session) | Reteach, then 2-4 cards later |
/// | Not yet x3 (same word, same session) | No more reinsertions this session |
///
/// Displayed progress ("Word 7 of 12") counts unique words, not raw card draws:
/// reinsertions do not grow `totalWords`, and a word doesn't count toward
/// `completedCount` until it stops reappearing (fast-correct, or its third miss).
public final class SessionQueue {
    private var cards: [WordSnapshot]
    private var cursor: Int = 0
    private var missCounts: [String: Int] = [:]
    private var firstScored: Set<String> = []
    private var completedIds: Set<String> = []
    private var rng: RandomNumberGenerator

    /// Number of distinct words in the session at start. Fixed for the whole session.
    public let totalWords: Int

    public init(words: [WordSnapshot], rng: RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.cards = words
        self.totalWords = Set(words.map { $0.id }).count
        self.rng = rng
    }

    /// True once there is no current card left to show.
    public var isComplete: Bool { cursor >= cards.count }

    /// Unique words that have finished appearing (naturally or via 3rd-miss cutoff).
    public var completedCount: Int { completedIds.count }

    /// The card currently on screen, or nil if the session is complete.
    public func currentCard() -> WordSnapshot? {
        guard cursor < cards.count else { return nil }
        return cards[cursor]
    }

    /// Cards from (and including) the current one, in queue order. Exposed for
    /// inspection/testing of reinsertion placement.
    public var upcomingCards: [WordSnapshot] {
        guard cursor < cards.count else { return [] }
        return Array(cards[cursor...])
    }

    /// Scores the current card and applies reinsertion / state-machine rules.
    @discardableResult
    public func score(result: ScoreResult, responseMs: Int, sessionDate: Date, calendar: Calendar = Calendar.current) -> ScoredEvent {
        precondition(cursor < cards.count, "score() called with no current card")
        let card = cards[cursor]
        let firstTry = !firstScored.contains(card.id)
        firstScored.insert(card.id)

        let updated = applyScore(
            snapshot: card,
            result: result,
            responseMs: responseMs,
            firstTryThisSession: firstTry,
            sessionDate: sessionDate,
            calendar: calendar
        )
        cards[cursor] = updated
        cursor += 1

        var reteachTriggered = false
        var reenqueued = false

        switch result {
        case .gotIt:
            if SpeedBand(responseMs: responseMs) == .fast {
                // Done for the session.
            } else {
                reenqueued = true
                insertReinserted(updated, minOffset: 5, maxOffset: 8)
            }

        case .almost:
            reenqueued = true
            insertReinserted(updated, minOffset: 5, maxOffset: 8)

        case .notYet:
            let count = (missCounts[card.id] ?? 0) + 1
            missCounts[card.id] = count
            if count == 1 {
                reenqueued = true
                insertReinserted(updated, minOffset: 2, maxOffset: 4)
            } else if count == 2 {
                reteachTriggered = true
                reenqueued = true
                insertReinserted(updated, minOffset: 2, maxOffset: 4)
            }
            // count >= 3: no more reinsertions this session.
        }

        if !reenqueued {
            completedIds.insert(card.id)
        }

        return ScoredEvent(snapshot: updated, reteachTriggered: reteachTriggered, reenqueued: reenqueued)
    }

    private func insertReinserted(_ snapshot: WordSnapshot, minOffset: Int, maxOffset: Int) {
        let span = UInt64(maxOffset - minOffset + 1)
        let r = rng.next() % span
        let offset = minOffset + Int(r)
        let insertAt = min(cursor + offset, cards.count)
        cards.insert(snapshot, at: insertAt)
    }
}
