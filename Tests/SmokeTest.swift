import Foundation

// Top-level executable smoke test for Sources/Engine. Copied to /tmp and compiled
// alongside the Engine sources per the Build Guide's no-Xcode recipe:
//   xattr -cr Sources Tests
//   mkdir -p /tmp/sw_main && cp Tests/SmokeTest.swift /tmp/sw_main/main.swift
//   swiftc -O Sources/Engine/*.swift /tmp/sw_main/main.swift -o /tmp/sw_test && /tmp/sw_test

var passCount = 0
var failCount = 0

func check(_ cond: Bool, _ label: String) {
    if cond {
        passCount += 1
        print("PASS: \(label)")
    } else {
        failCount += 1
        print("FAIL: \(label)")
    }
}

// A small seeded RNG so builder/queue tests are reproducible.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!

func dateAt(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    var comps = DateComponents()
    comps.year = y; comps.month = m; comps.day = d; comps.hour = h
    return calendar.date(from: comps)!
}

// =====================================================================
// 1. Speed band boundaries
// =====================================================================
check(SpeedBand(responseMs: 1999) == .fast, "1999ms -> fast")
check(SpeedBand(responseMs: 2000) == .developing, "2000ms boundary -> developing")
check(SpeedBand(responseMs: 5000) == .developing, "5000ms boundary -> developing")
check(SpeedBand(responseMs: 5001) == .slow, "5001ms -> slow")

// =====================================================================
// 2. First-exposure-of-a-new-word rule
// =====================================================================
do {
    let day1 = dateAt(2026, 1, 1)
    let w = WordSnapshot(id: "The")
    check(w.id == "the", "WordSnapshot lowercases id")
    check(w.isNew, "brand new snapshot isNew")

    let afterGotItFast = applyScore(snapshot: w, result: .gotIt, responseMs: 500, firstTryThisSession: true, sessionDate: day1, calendar: calendar)
    check(afterGotItFast.state == .learning, "new word, gotIt+fast, first exposure -> learning (not fluent)")
    check(afterGotItFast.fluentDayCount == 0, "no fluent day credited on first-ever exposure")

    let afterNotYet = applyScore(snapshot: w, result: .notYet, responseMs: 3000, firstTryThisSession: true, sessionDate: day1, calendar: calendar)
    check(afterNotYet.state == .learning, "new word, notYet, first exposure -> learning")
    check(afterNotYet.needsReview == true, "new word notYet sets needsReview")

    let afterAlmost = applyScore(snapshot: w, result: .almost, responseMs: 1000, firstTryThisSession: true, sessionDate: day1, calendar: calendar)
    check(afterAlmost.state == .learning, "new word, almost, first exposure -> learning")
}

// =====================================================================
// 3. gotIt+fast+firstTry fluency path, once-per-day rule, 3-distinct-day mastery
// =====================================================================
do {
    var w = WordSnapshot(id: "because", state: .learning)
    let day1 = dateAt(2026, 1, 1)
    w = applyScore(snapshot: w, result: .gotIt, responseMs: 800, firstTryThisSession: true, sessionDate: day1, calendar: calendar)
    check(w.state == .fluent, "learning, gotIt+fast+firstTry -> fluent")
    check(w.fluentDayCount == 1, "1st fluent day credited")
    check(w.needsReview == false, "gotIt+fast clears needsReview")

    // Same day again, still fast+firstTry-of-a-different-session-call: should NOT double credit.
    let laterSameDay = dateAt(2026, 1, 1, 18)
    w = applyScore(snapshot: w, result: .gotIt, responseMs: 700, firstTryThisSession: true, sessionDate: laterSameDay, calendar: calendar)
    check(w.fluentDayCount == 1, "fluent day credited at most once per calendar day")
    check(w.state == .fluent, "still fluent (not yet mastered) after 1 distinct day")

    let day2 = dateAt(2026, 1, 2)
    w = applyScore(snapshot: w, result: .gotIt, responseMs: 600, firstTryThisSession: true, sessionDate: day2, calendar: calendar)
    check(w.fluentDayCount == 2, "2nd distinct fluent day credited")
    check(w.state == .fluent, "still fluent after 2 distinct days")

    let day3 = dateAt(2026, 1, 3)
    w = applyScore(snapshot: w, result: .gotIt, responseMs: 900, firstTryThisSession: true, sessionDate: day3, calendar: calendar)
    check(w.fluentDayCount == 3, "3rd distinct fluent day credited")
    check(w.state == .mastered, "3 distinct fluent days -> mastered")
}

// =====================================================================
// 4. correct-but-slow / Almost -> developing, including demoting mastered
// =====================================================================
do {
    let day = dateAt(2026, 2, 1)
    let learningWord = WordSnapshot(id: "said", state: .learning)
    let slowCorrect = applyScore(snapshot: learningWord, result: .gotIt, responseMs: 3000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(slowCorrect.state == .developing, "learning, gotIt+developing-speed -> developing")

    let fluentWord = WordSnapshot(id: "want", state: .fluent, fluentDayCount: 1)
    let almostFromFluent = applyScore(snapshot: fluentWord, result: .almost, responseMs: 1000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(almostFromFluent.state == .developing, "fluent word scored Almost demotes to developing")

    let masteredWord = WordSnapshot(id: "come", state: .mastered, fluentDayCount: 3)
    let slowFromMastered = applyScore(snapshot: masteredWord, result: .gotIt, responseMs: 6000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(slowFromMastered.state == .developing, "mastered word scored gotIt+slow demotes to developing")

    let almostFromMastered = applyScore(snapshot: masteredWord, result: .almost, responseMs: 1200, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(almostFromMastered.state == .developing, "mastered word scored Almost demotes to developing")

    // Ambiguity resolution: gotIt+fast but NOT first try this session -> developing, not fluent/mastered.
    let notFirstTry = applyScore(snapshot: learningWord, result: .gotIt, responseMs: 800, firstTryThisSession: false, sessionDate: day, calendar: calendar)
    check(notFirstTry.state == .developing, "gotIt+fast on a non-first-try card this session -> developing, not fluent")
}

// =====================================================================
// 5. notYet from any state -> learning, needsReview, fluent-day reset
// =====================================================================
do {
    let day = dateAt(2026, 2, 5)
    let masteredWord = WordSnapshot(id: "have", state: .mastered, fluentDayCount: 3, lastFluentDay: dateAt(2026, 1, 1))
    let missed = applyScore(snapshot: masteredWord, result: .notYet, responseMs: 4000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(missed.state == .learning, "notYet from mastered -> learning")
    check(missed.needsReview == true, "notYet sets needsReview")
    check(missed.fluentDayCount == 0, "notYet resets fluentDayCount")
    check(missed.lastFluentDay == nil, "notYet clears lastFluentDay")

    let developingWord = WordSnapshot(id: "like", state: .developing)
    let missed2 = applyScore(snapshot: developingWord, result: .notYet, responseMs: 2500, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(missed2.state == .learning, "notYet from developing -> learning")
}

// =====================================================================
// 6. Always-updated stats: timesSeen/Correct/Missed, lastResult, recentResults cap, avgResponseMs
// =====================================================================
do {
    var w = WordSnapshot(id: "play")
    let day = dateAt(2026, 3, 1)
    w = applyScore(snapshot: w, result: .gotIt, responseMs: 1000, firstTryThisSession: true, sessionDate: day, calendar: calendar) // -> learning
    w = applyScore(snapshot: w, result: .gotIt, responseMs: 2000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    w = applyScore(snapshot: w, result: .notYet, responseMs: 3000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(w.timesSeen == 3, "timesSeen increments every exposure")
    check(w.timesCorrect == 2, "timesCorrect counts gotIt (and almost)")
    check(w.timesMissed == 1, "timesMissed counts notYet")
    check(w.lastResult == "notYet", "lastResult reflects most recent score")
    check(w.avgResponseMs == 2000, "avgResponseMs is a running integer average (1000,2000,3000 -> 2000)")

    for _ in 0..<5 {
        w = applyScore(snapshot: w, result: .gotIt, responseMs: 500, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    }
    check(w.recentResults.count == 5, "recentResults capped at 5 entries")
    check(w.recentResults == ["gotIt", "gotIt", "gotIt", "gotIt", "gotIt"], "recentResults holds the most recent 5")
}

// =====================================================================
// 7. Due-date assignment per state
// =====================================================================
do {
    let day = dateAt(2026, 4, 1)
    let learningRes = applyScore(snapshot: WordSnapshot(id: "run", state: .learning), result: .notYet, responseMs: 3000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(calendar.isDate(learningRes.dueDate!, inSameDayAs: day), "learning word due same day")

    let developingRes = applyScore(snapshot: WordSnapshot(id: "jump", state: .learning), result: .almost, responseMs: 1000, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    let expectedDevDue = calendar.date(byAdding: .day, value: 1, to: day)!
    check(calendar.isDate(developingRes.dueDate!, inSameDayAs: expectedDevDue), "developing word due +1 day")

    let fluentRes = applyScore(snapshot: WordSnapshot(id: "big", state: .learning), result: .gotIt, responseMs: 900, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    let expectedFluentDue = calendar.date(byAdding: .day, value: 3, to: day)!
    check(calendar.isDate(fluentRes.dueDate!, inSameDayAs: expectedFluentDue), "fluent word due +3 days")

    var masteredSetup = WordSnapshot(id: "small", state: .fluent, fluentDayCount: 2, lastFluentDay: dateAt(2026, 3, 30))
    masteredSetup = applyScore(snapshot: masteredSetup, result: .gotIt, responseMs: 500, firstTryThisSession: true, sessionDate: day, calendar: calendar)
    check(masteredSetup.state == .mastered, "sanity: reaches mastered for due-date check")
    let expectedMasteredDue = calendar.date(byAdding: .day, value: 7, to: day)!
    check(calendar.isDate(masteredSetup.dueDate!, inSameDayAs: expectedMasteredDue), "mastered word due +7 days")
}

// =====================================================================
// 8. SessionQueue: reinsertion windows, reteach, 3rd-miss retirement, progress
// =====================================================================
do {
    let day = dateAt(2026, 5, 1)
    let words = ["cat", "dog", "bird", "fish", "frog", "duck"].map { WordSnapshot(id: $0, state: .learning) }
    let queue = SessionQueue(words: words, rng: SeededRNG(seed: 42))
    check(queue.totalWords == 6, "totalWords reflects unique starting words")
    check(queue.completedCount == 0, "no words completed at session start")

    // First card: score Almost -> reinsert 5-8 cards later.
    let firstWord = queue.currentCard()!.id
    let almostEvent = queue.score(result: .almost, responseMs: 1000, sessionDate: day, calendar: calendar)
    check(almostEvent.reenqueued == true, "Almost reenqueues the word")
    let upcoming = queue.upcomingCards
    let reinsertIndex = upcoming.firstIndex(where: { $0.id == firstWord })
    check(reinsertIndex != nil, "Almost-scored word reappears later in the queue")
    if let idx = reinsertIndex {
        check(idx >= 4 && idx <= 7, "Almost reinsertion lands 5-8 cards later (0-based offset 4...7), got offset \(idx)")
    }
    check(queue.completedCount == 0, "reinserted word does not count as completed yet")

    // Next card: score notYet -> reinsert 2-4 cards later.
    let secondWord = queue.currentCard()!.id
    let notYetEvent = queue.score(result: .notYet, responseMs: 3000, sessionDate: day, calendar: calendar)
    check(notYetEvent.reenqueued == true, "first notYet reenqueues the word")
    check(notYetEvent.reteachTriggered == false, "first notYet does not trigger reteach")
    let upcoming2 = queue.upcomingCards
    let reinsertIndex2 = upcoming2.firstIndex(where: { $0.id == secondWord })
    check(reinsertIndex2 != nil, "notYet-scored word reappears later in the queue")
    if let idx = reinsertIndex2 {
        check(idx >= 1 && idx <= 3, "notYet reinsertion lands 2-4 cards later (0-based offset 1...3), got offset \(idx)")
    }
}

do {
    // Dedicated queue to drive one word through 3 misses in a row.
    let day = dateAt(2026, 5, 2)
    var queue = SessionQueue(words: [WordSnapshot(id: "solo", state: .learning)], rng: SeededRNG(seed: 7))
    // Since there's only one word, keep re-adding filler so reinsertion has room; simpler:
    // build a queue with a handful of words, always score the target word's card each time it comes up.
    let words = ["target", "a", "b", "c", "d", "e", "f", "g"].map { WordSnapshot(id: $0, state: .learning) }
    queue = SessionQueue(words: words, rng: SeededRNG(seed: 7))

    func scoreUntilWeSee(_ id: String, result: ScoreResult) -> ScoredEvent {
        while queue.currentCard()!.id != id {
            _ = queue.score(result: .gotIt, responseMs: 500, sessionDate: day, calendar: calendar)
        }
        return queue.score(result: result, responseMs: 3000, sessionDate: day, calendar: calendar)
    }

    let miss1 = scoreUntilWeSee("target", result: .notYet)
    check(miss1.reteachTriggered == false, "1st miss: no reteach")
    check(miss1.reenqueued == true, "1st miss: reenqueued")

    let miss2 = scoreUntilWeSee("target", result: .notYet)
    check(miss2.reteachTriggered == true, "2nd miss (same word, same session): reteach triggered")
    check(miss2.reenqueued == true, "2nd miss: still reenqueued 2-4 later")

    let beforeThirdCompleted = queue.completedCount
    let miss3 = scoreUntilWeSee("target", result: .notYet)
    check(miss3.reenqueued == false, "3rd miss: no more reinsertion this session")
    check(queue.completedCount >= beforeThirdCompleted + 1, "3rd miss contributes to completedCount (fillers may also complete along the way)")
    check(!queue.upcomingCards.contains(where: { $0.id == "target" }), "3rd-miss word never reappears in the queue again")
}

// =====================================================================
// 9. Session builder: 70/20/10 mix, backfill, pool-smaller-than-size, tricky mode
// =====================================================================
do {
    let now = dateAt(2026, 6, 1)
    var pool: [WordSnapshot] = []
    // 40 due-familiar words (mix of developing/fluent/mastered), all overdue by varying amounts.
    for i in 0..<40 {
        let state: WordState = i % 3 == 0 ? .fluent : (i % 3 == 1 ? .developing : .mastered)
        let due = calendar.date(byAdding: .day, value: -i, to: now)!
        pool.append(WordSnapshot(id: "familiar\(i)", state: state, dueDate: due))
    }
    // 10 learning/needsReview words with varying miss counts.
    for i in 0..<10 {
        var w = WordSnapshot(id: "learn\(i)", state: .learning, timesMissed: i)
        w.needsReview = true
        pool.append(w)
    }
    // 15 new words.
    for i in 0..<15 {
        pool.append(WordSnapshot(id: "new\(i)", state: .new))
    }
    check(pool.count == 65, "rich pool built with 65 words")

    var rng: RandomNumberGenerator = SeededRNG(seed: 99)
    let session = buildSession(pool: pool, size: 12, now: now, calendar: calendar, mode: .standard, rng: &rng)
    check(session.count == 12, "standard 12-card session returns exactly 12 cards from a rich pool")

    let newCount = session.filter { $0.id.hasPrefix("new") }.count
    let learningCount = session.filter { $0.id.hasPrefix("learn") }.count
    let familiarCount = session.filter { $0.id.hasPrefix("familiar") }.count
    check(newCount <= 2, "hard cap: at most 2 new words in a 12-card session, got \(newCount)")
    check(newCount >= 1, "~10% of 12 rounds to at least 1 new word when new words exist, got \(newCount)")
    check(learningCount >= 2 && learningCount <= 3, "~20% of 12 is 2-3 learning/needsReview words, got \(learningCount)")
    check(familiarCount == 12 - newCount - learningCount, "remaining cards are familiar")
    check(familiarCount >= 7, "familiar bucket dominates the session (~70%), got \(familiarCount)")

    let uniqueIds = Set(session.map { $0.id })
    check(uniqueIds.count == session.count, "no duplicate words in a built session")
}

do {
    // Backfill: familiar bucket is short, so learning/new must fill the gap.
    let now = dateAt(2026, 6, 2)
    var pool: [WordSnapshot] = []
    for i in 0..<3 {
        pool.append(WordSnapshot(id: "familiar\(i)", state: .fluent, dueDate: calendar.date(byAdding: .day, value: -1, to: now)))
    }
    for i in 0..<20 {
        var w = WordSnapshot(id: "learn\(i)", state: .learning, timesMissed: 20 - i)
        w.needsReview = true
        pool.append(w)
    }
    for i in 0..<20 {
        pool.append(WordSnapshot(id: "new\(i)", state: .new))
    }
    check(pool.count == 43, "backfill-scenario pool has 43 words (plenty > session size)")

    var rng: RandomNumberGenerator = SeededRNG(seed: 5)
    let session = buildSession(pool: pool, size: 12, now: now, calendar: calendar, mode: .standard, rng: &rng)
    check(session.count == 12, "backfill scenario still fills a full 12-card session")
    let familiarUsed = session.filter { $0.id.hasPrefix("familiar") }.count
    check(familiarUsed == 3, "all 3 available familiar words are used when the familiar bucket is short")
    let newUsed = session.filter { $0.id.hasPrefix("new") }.count
    check(newUsed <= 2, "new-word cap of 2 is respected even during backfill")
    let learnUsed = session.filter { $0.id.hasPrefix("learn") }.count
    check(learnUsed == 12 - familiarUsed - newUsed, "learning bucket backfills the rest of the shortfall")
}

do {
    // Pool smaller than session size -> whole pool returned.
    let now = dateAt(2026, 6, 3)
    let smallPool = (0..<5).map { WordSnapshot(id: "w\($0)", state: .learning) }
    var rng: RandomNumberGenerator = SeededRNG(seed: 3)
    let session = buildSession(pool: smallPool, size: 12, now: now, calendar: calendar, mode: .standard, rng: &rng)
    check(session.count == 5, "pool smaller than session size returns the whole pool")
    check(Set(session.map { $0.id }) == Set(smallPool.map { $0.id }), "whole pool contents are preserved when short")
}

do {
    // Tricky mode: only needsReview/learning, no new, most-missed first, capped.
    let now = dateAt(2026, 6, 4)
    var pool: [WordSnapshot] = []
    pool.append(WordSnapshot(id: "fluentword", state: .fluent))
    pool.append(WordSnapshot(id: "newword", state: .new))
    var missy = WordSnapshot(id: "missy", state: .developing, timesMissed: 9)
    missy.needsReview = true
    pool.append(missy)
    var lessMissy = WordSnapshot(id: "lessmissy", state: .developing, timesMissed: 2)
    lessMissy.needsReview = true
    pool.append(lessMissy)
    pool.append(WordSnapshot(id: "learningword", state: .learning, timesMissed: 5))

    var rng: RandomNumberGenerator = SeededRNG(seed: 1)
    let tricky = buildSession(pool: pool, size: 10, now: now, calendar: calendar, mode: .tricky, rng: &rng)
    check(tricky.count == 3, "tricky mode only pulls needsReview/learning words (3 of 5 in pool)")
    check(!tricky.contains(where: { $0.id == "fluentword" }), "tricky mode excludes fluent words")
    check(!tricky.contains(where: { $0.id == "newword" }), "tricky mode never includes new words")
    check(tricky.first?.id == "missy", "tricky mode orders most-missed first")

    let cappedTricky = buildSession(pool: pool, size: 2, now: now, calendar: calendar, mode: .tricky, rng: &rng)
    check(cappedTricky.count == 2, "tricky mode caps at requested size")
}

// =====================================================================
// 10. Homophones
// =====================================================================
do {
    let json = """
    [["to","two","too"], ["there","their","they're"], ["be","bee"]]
    """.data(using: .utf8)!
    let table = HomophoneTable(json: json)
    check(table.matches(heard: "to", target: "to"), "homophone: identity match")
    check(table.matches(heard: "TWO", target: "to"), "homophone: case-insensitive identity/group match")
    check(table.matches(heard: "too", target: "to"), "homophone: to/two/too group match")
    check(table.matches(heard: "two", target: "too"), "homophone: two/too group match (reverse)")
    check(!table.matches(heard: "there", target: "to"), "homophone: negative case across unrelated groups")
    check(!table.matches(heard: "cat", target: "dog"), "homophone: negative case for unrelated words")
}

// =====================================================================
// Final tally
// =====================================================================
print("----")
print("TOTAL: \(passCount) passed, \(failCount) failed, \(passCount + failCount) checks")
if failCount > 0 {
    exit(1)
} else {
    exit(0)
}
