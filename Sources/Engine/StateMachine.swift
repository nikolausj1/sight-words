import Foundation

/// Implements PRD §6.9's state-transition table exactly, plus the always-on stat
/// bookkeeping and the cross-session due-date assignment.
///
/// Ambiguity resolutions made here (beyond the two pre-resolved in the spec):
///
/// 1. A `gotIt` scored **fast** but on a **non-first** try within the same session
///    (i.e. the card was already reinserted once this session because of a prior
///    slow/almost/miss) is NOT treated as fluency evidence. The PRD table only
///    credits a fluent day for "correct + fast, first try of the session"; it is
///    silent on a fast-correct read on a *later* try. We fold that case into the
///    same bucket as "correct but slow, or Almost" -> `developing`, since only the
///    very first read of the session is evidence the word is automatic.
public func applyScore(
    snapshot: WordSnapshot,
    result: ScoreResult,
    responseMs: Int,
    firstTryThisSession: Bool,
    sessionDate: Date,
    calendar: Calendar
) -> WordSnapshot {
    var s = snapshot
    let wasNew = snapshot.state == .new

    // --- Always-on bookkeeping -------------------------------------------------
    let previousSeen = s.timesSeen
    s.timesSeen += 1
    switch result {
    case .gotIt, .almost:
        s.timesCorrect += 1
    case .notYet:
        s.timesMissed += 1
    }
    s.lastResult = result.label
    s.lastSeenAt = sessionDate
    s.recentResults.append(result.label)
    if s.recentResults.count > 5 {
        s.recentResults.removeFirst(s.recentResults.count - 5)
    }
    let totalMs = s.avgResponseMs * previousSeen + responseMs
    s.avgResponseMs = totalMs / s.timesSeen

    // --- State transition --------------------------------------------------
    var newState = s.state
    var needsReview = s.needsReview
    var fluentDayCount = s.fluentDayCount
    var lastFluentDay = s.lastFluentDay

    if wasNew {
        // A brand-new word's very first scored exposure always lands in
        // `learning`, regardless of result -- one good read isn't fluency, and
        // the intro flow already happened. Stats above are still recorded.
        newState = .learning
        if result == .notYet {
            needsReview = true
            fluentDayCount = 0
            lastFluentDay = nil
        }
    } else {
        switch result {
        case .notYet:
            newState = .learning
            needsReview = true
            fluentDayCount = 0
            lastFluentDay = nil

        case .almost:
            // Correct-but-hesitant demotes even a fluent/mastered word: a read
            // that isn't fast+first-try isn't evidence of continued mastery.
            newState = .developing

        case .gotIt:
            let band = SpeedBand(responseMs: responseMs)
            if band == .fast {
                needsReview = false
                if firstTryThisSession {
                    let sameDay = lastFluentDay.map { calendar.isDate($0, inSameDayAs: sessionDate) } ?? false
                    if !sameDay {
                        fluentDayCount += 1
                        lastFluentDay = sessionDate
                    }
                    newState = fluentDayCount >= 3 ? .mastered : .fluent
                } else {
                    // See ambiguity resolution #1 above.
                    newState = .developing
                }
            } else {
                // correct but slow -> developing (demotes mastered too)
                newState = .developing
            }
        }
    }

    s.state = newState
    s.needsReview = needsReview
    s.fluentDayCount = fluentDayCount
    s.lastFluentDay = lastFluentDay

    // --- Cross-session due date --------------------------------------------
    switch newState {
    case .new, .learning:
        s.dueDate = sessionDate
    case .developing:
        s.dueDate = calendar.date(byAdding: .day, value: 1, to: sessionDate)
    case .fluent:
        s.dueDate = calendar.date(byAdding: .day, value: 3, to: sessionDate)
    case .mastered:
        s.dueDate = calendar.date(byAdding: .day, value: 7, to: sessionDate)
    }

    return s
}
