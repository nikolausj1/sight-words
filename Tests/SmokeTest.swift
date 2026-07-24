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
// Fresh-profile floor: all-new pool must yield a 5-card intro session
// =====================================================================
do {
    let now = dateAt(2026, 1, 1)
    var rng: RandomNumberGenerator = SeededRNG(seed: 77)
    let freshPool = (0..<92).map { WordSnapshot(id: "fresh\($0)") }
    let intro = buildSession(pool: freshPool, size: 12, now: now, calendar: calendar, mode: .standard, rng: &rng)
    check(intro.count == 5, "fresh profile: 12-card request over all-new pool yields 5-card intro session")
    check(intro.allSatisfy { $0.state == .new }, "fresh profile: intro session is all new words")

    var rng2: RandomNumberGenerator = SeededRNG(seed: 78)
    let tinyNewPool = (0..<3).map { WordSnapshot(id: "tiny\($0)") }
    let tiny = buildSession(pool: tinyNewPool, size: 12, now: now, calendar: calendar, mode: .standard, rng: &rng2)
    check(tiny.count == 3, "fresh profile: pool smaller than floor returns whole pool")

    // Rich pool must be unaffected by the floor (still 12 cards, still <= 2 new).
    var rng3: RandomNumberGenerator = SeededRNG(seed: 79)
    var richPool: [WordSnapshot] = (0..<40).map { i in
        var w = WordSnapshot(id: "familiar\(i)")
        w.state = .developing
        w.dueDate = dateAt(2025, 12, 30)
        return w
    }
    richPool += (0..<10).map { i in
        var w = WordSnapshot(id: "learn\(i)")
        w.state = .learning
        return w
    }
    richPool += (0..<10).map { WordSnapshot(id: "new\($0)") }
    let rich = buildSession(pool: richPool, size: 12, now: now, calendar: calendar, mode: .standard, rng: &rng3)
    check(rich.count == 12, "rich pool: floor does not shrink or grow a full session")
    check(rich.filter { $0.state == .new }.count <= 2, "rich pool: new-word cap still holds with floor in place")
}

// =====================================================================
// 11. GameTiers: RoundReport clean/rough boundaries
// =====================================================================
do {
    check(RoundReport(wrongAttempts: 0, timeoutHints: 0).isClean, "0 wrong/0 hints -> clean")
    check(RoundReport(wrongAttempts: 1, timeoutHints: 0).isClean, "1 wrong/0 hints -> still clean")
    check(!RoundReport(wrongAttempts: 2, timeoutHints: 0).isClean, "2 wrong/0 hints -> not clean")
    check(!RoundReport(wrongAttempts: 0, timeoutHints: 1).isClean, "0 wrong/1 hint -> not clean")
    check(!RoundReport(wrongAttempts: 3, timeoutHints: 0).isClean, "3 wrong -> not clean")
    check(RoundReport(wrongAttempts: 3, timeoutHints: 0).isRough, "3 wrong/0 hints -> rough")
    check(RoundReport(wrongAttempts: 0, timeoutHints: 2).isRough, "0 wrong/2 hints -> rough")
    check(!RoundReport(wrongAttempts: 2, timeoutHints: 1).isRough, "2 wrong/1 hint -> neither clean nor rough")
    check(!RoundReport(wrongAttempts: 2, timeoutHints: 1).isClean, "2 wrong/1 hint -> confirmed not clean")
}

// =====================================================================
// 12. GameTiers: TierLadder staircase rules
// =====================================================================
do {
    // Starts at t1.
    let fresh = TierLadder()
    check(fresh.tier == .t1, "TierLadder starts at t1")

    // 5-of-7 promote, achieved with fewer than 7 rounds played.
    var ladder = TierLadder()
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    for _ in 0..<4 {
        ladder.record(clean, reviewBacklogGrowing: false)
    }
    check(ladder.tier == .t1, "4 clean rounds alone do not promote (need 5)")
    ladder.record(clean, reviewBacklogGrowing: false)
    check(ladder.tier == .t2, "5th clean round (of only 5 played) promotes t1 -> t2")
}

do {
    // 5-of-7 with 2 non-clean rounds interspersed still promotes once the
    // 5th clean round lands, and NOT before.
    var ladder = TierLadder()
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    let mediocre = RoundReport(wrongAttempts: 2, timeoutHints: 1) // neither clean nor rough
    let sequence: [RoundReport] = [clean, mediocre, clean, clean, mediocre, clean, clean]
    var promotedAt: Int?
    for (i, r) in sequence.enumerated() {
        ladder.record(r, reviewBacklogGrowing: false)
        if ladder.tier == .t2 && promotedAt == nil { promotedAt = i }
    }
    check(promotedAt == 6, "promotion fires exactly on the 5th clean round within the trailing 7 (index 6), got \(String(describing: promotedAt))")
}

do {
    // Fewer than 5 clean of the last 7 never promotes.
    var ladder = TierLadder()
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    let mediocre = RoundReport(wrongAttempts: 2, timeoutHints: 1)
    for _ in 0..<4 {
        ladder.record(clean, reviewBacklogGrowing: false)
        ladder.record(mediocre, reviewBacklogGrowing: false)
    }
    check(ladder.tier == .t1, "4 clean out of 8 rounds (never 5 in the trailing 7) never promotes")
}

do {
    // 2 consecutive rough rounds demotes; starting from t2 so a demotion has
    // somewhere to go.
    var ladder = TierLadder(tier: .t2)
    let rough = RoundReport(wrongAttempts: 4, timeoutHints: 0)
    ladder.record(rough, reviewBacklogGrowing: false)
    check(ladder.tier == .t2, "1 rough round alone does not demote")
    ladder.record(rough, reviewBacklogGrowing: false)
    check(ladder.tier == .t1, "2 CONSECUTIVE rough rounds demote t2 -> t1")
}

do {
    // A non-rough round breaks the rough streak.
    var ladder = TierLadder(tier: .t2)
    let rough = RoundReport(wrongAttempts: 4, timeoutHints: 0)
    let ok = RoundReport(wrongAttempts: 1, timeoutHints: 0)
    ladder.record(rough, reviewBacklogGrowing: false)
    ladder.record(ok, reviewBacklogGrowing: false)
    ladder.record(rough, reviewBacklogGrowing: false)
    check(ladder.tier == .t2, "rough, ok, rough (not consecutive) does not demote")
}

do {
    // Floor/ceiling: demote from t1 stays at t1; promote from t3 stays at t3.
    var floor = TierLadder(tier: .t1)
    let rough = RoundReport(wrongAttempts: 4, timeoutHints: 0)
    floor.record(rough, reviewBacklogGrowing: false)
    floor.record(rough, reviewBacklogGrowing: false)
    check(floor.tier == .t1, "t1 has no floor below it: 2 rough rounds keep it at t1")

    var ceiling = TierLadder(tier: .t3)
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    for _ in 0..<5 {
        ceiling.record(clean, reviewBacklogGrowing: false)
    }
    check(ceiling.tier == .t3, "t3 has no ceiling above it: 5 clean rounds keep it at t3")
}

do {
    // 15-round >=90%-clean backstop. Note on these exact thresholds: 5-of-7
    // is ~71.4% while the backstop is 90% over >=15 rounds -- and it's
    // provable (pigeonhole over two disjoint 7-round halves of a 14-round
    // prefix) that ANY sequence reaching 90% clean over 15 rounds must also
    // satisfy the 5-of-7 window rule at or before that same round, since
    // >=90% clean over 15 rounds allows at most 1 non-clean round total, and
    // a single non-clean round cannot appear in both disjoint halves. So
    // this exercises the backstop's own numeric condition (>=15 rounds,
    // >=90% clean truly holds) without claiming to isolate it from 5-of-7 --
    // both are legitimately satisfied together, and either is a correct
    // reason to promote.
    var ladder = TierLadder(tier: .t1)
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    let mediocre = RoundReport(wrongAttempts: 2, timeoutHints: 1)
    var reports = Array(repeating: clean, count: 14)
    reports.insert(mediocre, at: 7) // exactly 1 non-clean round among 15 -> 14/15 ≈ 93.3% >= 90%
    check(reports.count == 15, "backstop test setup sanity: 15 rounds total")
    for r in reports {
        ladder.record(r, reviewBacklogGrowing: false)
    }
    check(ladder.tier != .t1, "a 15-round run at >=90% clean promotes at least one tier past t1")
}

do {
    // Below the backstop's ratio threshold, and never satisfying 5-of-7
    // either (0% clean throughout) -- never promotes, even well past 15
    // rounds at the same tier.
    var ladder = TierLadder(tier: .t1)
    let mediocre = RoundReport(wrongAttempts: 2, timeoutHints: 1)
    for _ in 0..<20 {
        ladder.record(mediocre, reviewBacklogGrowing: false)
    }
    check(ladder.tier == .t1, "20 rounds of all-mediocre (0% clean, never rough) never promotes via either rule")
}

do {
    // Freeze: reviewBacklogGrowing blocks promotion even when 5-of-7 is met.
    var ladder = TierLadder(tier: .t1)
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    for _ in 0..<5 {
        ladder.record(clean, reviewBacklogGrowing: true)
    }
    check(ladder.tier == .t1, "5 clean rounds with reviewBacklogGrowing=true never promotes")
    // Once the freeze lifts, the already-recorded clean history still counts.
    ladder.record(clean, reviewBacklogGrowing: false)
    check(ladder.tier == .t2, "freeze lifting on a later round promotes using the accumulated clean history")
}

do {
    // Freeze does NOT block demotion.
    var ladder = TierLadder(tier: .t2)
    let rough = RoundReport(wrongAttempts: 4, timeoutHints: 0)
    ladder.record(rough, reviewBacklogGrowing: true)
    ladder.record(rough, reviewBacklogGrowing: true)
    check(ladder.tier == .t1, "2 consecutive rough rounds demote even while reviewBacklogGrowing is true")
}

do {
    // Counters reset at a new tier: after promoting, it takes a fresh 5-of-7
    // (not carried-over clean count) to promote again.
    var ladder = TierLadder(tier: .t1)
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    for _ in 0..<5 { ladder.record(clean, reviewBacklogGrowing: false) }
    check(ladder.tier == .t2, "sanity: promoted to t2")
    let rough = RoundReport(wrongAttempts: 4, timeoutHints: 0)
    ladder.record(rough, reviewBacklogGrowing: false)
    ladder.record(clean, reviewBacklogGrowing: false)
    ladder.record(clean, reviewBacklogGrowing: false)
    ladder.record(clean, reviewBacklogGrowing: false)
    check(ladder.tier == .t2, "3 clean rounds right after a fresh promotion do not instantly re-promote (counters reset)")
}

do {
    // Counters also reset after a demotion.
    var ladder = TierLadder(tier: .t2)
    let rough = RoundReport(wrongAttempts: 4, timeoutHints: 0)
    ladder.record(rough, reviewBacklogGrowing: false)
    ladder.record(rough, reviewBacklogGrowing: false)
    check(ladder.tier == .t1, "sanity: demoted to t1")
    // Immediately record 1 more rough round: should NOT demote further (t1 has no floor),
    // and should not carry over any stale "consecutive rough" count into a phantom 3rd hit.
    ladder.record(rough, reviewBacklogGrowing: false)
    check(ladder.tier == .t1, "post-demotion rough streak is 1 fresh rough round, not a leftover 3rd -- still t1 (floor)")
}

do {
    // Tier changes only happen via `record` (between rounds) -- constructing
    // RoundReport values or simply reading `.tier` never mutates state.
    let ladder = TierLadder(tier: .t2)
    _ = RoundReport(wrongAttempts: 5, timeoutHints: 5)
    _ = ladder.tier
    _ = ladder.tier
    check(ladder.tier == .t2, "tier is untouched by constructing reports or repeated reads (record() is the only mutator)")
}

do {
    // Codable round-trip persists tier + in-progress counters faithfully.
    var ladder = TierLadder(tier: .t2)
    let clean = RoundReport(wrongAttempts: 0, timeoutHints: 0)
    let mediocre = RoundReport(wrongAttempts: 2, timeoutHints: 1)
    ladder.record(clean, reviewBacklogGrowing: false)
    ladder.record(mediocre, reviewBacklogGrowing: false)
    ladder.record(clean, reviewBacklogGrowing: false)

    let data = try? JSONEncoder().encode(ladder)
    check(data != nil, "TierLadder encodes to Data")
    let decoded = try? JSONDecoder().decode(TierLadder.self, from: data ?? Data())
    check(decoded != nil, "TierLadder decodes back from Data")
    check(decoded == ladder, "decoded TierLadder equals the original (tier + counters round-trip)")

    // And the decoded ladder continues the staircase exactly as if it had
    // never been serialized (proves the private counters, not just `tier`,
    // survived the round-trip).
    if var restored = decoded {
        restored.record(clean, reviewBacklogGrowing: false)
        var control = ladder
        control.record(clean, reviewBacklogGrowing: false)
        check(restored == control, "restored ladder behaves identically to the un-serialized control after another round")
    }
}

// =====================================================================
// 13. GameWordPicker: weights, constraints, fallback, "introduce nothing"
// =====================================================================
do {
    // Rich, evenly-stocked pool: 40 learning/developing, 40 fluent/mastered,
    // 20 already-introduced-new, all short enough to pass any maxLength.
    var pool: [WordSnapshot] = []
    for i in 0..<20 { pool.append(WordSnapshot(id: "learn\(i)", state: .learning)) }
    for i in 0..<20 { pool.append(WordSnapshot(id: "dev\(i)", state: .developing)) }
    for i in 0..<20 { pool.append(WordSnapshot(id: "fluent\(i)", state: .fluent)) }
    for i in 0..<20 { pool.append(WordSnapshot(id: "mastered\(i)", state: .mastered)) }
    for i in 0..<20 {
        var w = WordSnapshot(id: "new\(i)")
        w.timesSeen = 1 // already introduced
        pool.append(w)
    }

    var rng: RandomNumberGenerator = SeededRNG(seed: 11)
    let picked = pickGameWords(pool: pool, count: 20, rng: &rng)
    check(picked.count == 20, "picker returns exactly the requested count from a rich pool")
    let learningDevCount = picked.filter { $0.id.hasPrefix("learn") || $0.id.hasPrefix("dev") }.count
    let fluentMasteredCount = picked.filter { $0.id.hasPrefix("fluent") || $0.id.hasPrefix("mastered") }.count
    let newCount = picked.filter { $0.id.hasPrefix("new") }.count
    check(learningDevCount == 12, "60% of 20 -> 12 learning/developing words, got \(learningDevCount)")
    check(fluentMasteredCount == 6, "30% of 20 -> 6 fluent/mastered words, got \(fluentMasteredCount)")
    check(newCount == 2, "10% of 20 -> 2 already-introduced-new words, got \(newCount)")
    check(Set(picked.map { $0.id }).count == picked.count, "no duplicate words in a picked round")
}

do {
    // Games introduce nothing: a word with state .new and timesSeen == 0 is
    // NEVER selected, even when it's the only thing padding out the pool.
    var pool: [WordSnapshot] = []
    for i in 0..<3 { pool.append(WordSnapshot(id: "learn\(i)", state: .learning)) }
    for i in 0..<30 { pool.append(WordSnapshot(id: "untouched\(i)")) } // timesSeen == 0

    var rng: RandomNumberGenerator = SeededRNG(seed: 22)
    let picked = pickGameWords(pool: pool, count: 10, rng: &rng)
    check(!picked.contains { $0.id.hasPrefix("untouched") }, "never-seen new words are never picked, no matter how much padding they provide")
    check(picked.count == 3, "with only 3 truly-eligible words (padding excluded), picker returns just those 3")
}

do {
    // maxLength constraint filters the eligible pool before weighting.
    var pool: [WordSnapshot] = []
    pool.append(WordSnapshot(id: "cat", state: .fluent))      // len 3
    pool.append(WordSnapshot(id: "dog", state: .fluent))      // len 3
    pool.append(WordSnapshot(id: "elephant", state: .fluent)) // len 8, too long
    pool.append(WordSnapshot(id: "hippopotamus", state: .fluent)) // len 12, too long

    var rng: RandomNumberGenerator = SeededRNG(seed: 33)
    let picked = pickGameWords(pool: pool, count: 4,
                                constraints: GameWordConstraints(maxLength: 4), rng: &rng)
    check(picked.count == 2, "maxLength constraint excludes over-length words before selection")
    check(picked.allSatisfy { $0.id.count <= 4 }, "every picked word respects maxLength")
}

do {
    // Fill-from-familiar fallback: learning/developing bucket is short, so
    // fluent/mastered (checked first) backfills the shortfall.
    var pool: [WordSnapshot] = []
    pool.append(WordSnapshot(id: "onelearn", state: .learning))
    for i in 0..<20 { pool.append(WordSnapshot(id: "fluent\(i)", state: .fluent)) }

    var rng: RandomNumberGenerator = SeededRNG(seed: 44)
    let picked = pickGameWords(pool: pool, count: 10, rng: &rng)
    check(picked.count == 10, "fallback still fills the full requested count")
    check(picked.contains { $0.id == "onelearn" }, "the sole learning word is still included")
    let fluentUsed = picked.filter { $0.id.hasPrefix("fluent") }.count
    check(fluentUsed == 9, "fluent/mastered backfills the rest of the shortfall (9 of 10), got \(fluentUsed)")
}

do {
    // Pool (after constraints) smaller than count: whole eligible pool returned.
    let pool = (0..<4).map { WordSnapshot(id: "w\($0)", state: .fluent) }
    var rng: RandomNumberGenerator = SeededRNG(seed: 55)
    let picked = pickGameWords(pool: pool, count: 10, rng: &rng)
    check(picked.count == 4, "eligible pool smaller than count returns the whole eligible pool")
    check(Set(picked.map { $0.id }) == Set(pool.map { $0.id }), "whole pool contents preserved when short")
}

do {
    // Same seed -> same picks (determinism for tests/replay).
    var pool: [WordSnapshot] = []
    for i in 0..<10 { pool.append(WordSnapshot(id: "learn\(i)", state: .learning)) }
    for i in 0..<10 { pool.append(WordSnapshot(id: "fluent\(i)", state: .fluent)) }

    var rngA: RandomNumberGenerator = SeededRNG(seed: 66)
    let pickedA = pickGameWords(pool: pool, count: 8, rng: &rngA)
    var rngB: RandomNumberGenerator = SeededRNG(seed: 66)
    let pickedB = pickGameWords(pool: pool, count: 8, rng: &rngB)
    check(pickedA.map { $0.id } == pickedB.map { $0.id }, "same seed produces identical picks")
}

// =====================================================================
// 14. GameWordPicker: confusables (homophones + edit-distance neighbors)
// =====================================================================
do {
    let homophoneGroups = [["to", "two", "too"], ["there", "their", "they're"]]
    let pool = [WordSnapshot(id: "to"), WordSnapshot(id: "too"), WordSnapshot(id: "two")]
    let result = confusables(for: "to", pool: pool, homophoneGroups: homophoneGroups)
    check(Set(result) == Set(["too", "two"]), "confusables includes every OTHER homophone-group member, got \(result)")
    check(!result.contains("to"), "confusables never includes the target word itself")
}

do {
    // Edit-distance-<=2 same-length neighbors from the pool.
    let pool = [WordSnapshot(id: "cat"), WordSnapshot(id: "bat"), WordSnapshot(id: "cap"),
                WordSnapshot(id: "dog"), WordSnapshot(id: "elephant")]
    let result = confusables(for: "cat", pool: pool, homophoneGroups: [])
    check(result.contains("bat"), "1-edit same-length neighbor (cat/bat) included")
    check(result.contains("cap"), "1-edit same-length neighbor (cat/cap) included")
    check(!result.contains("dog"), "3-edit same-length word (cat/dog) excluded (distance > 2)")
    check(!result.contains("elephant"), "different-length word never included regardless of distance")
    check(!result.contains("cat"), "confusables never includes the target word itself (edit-distance path)")
}

do {
    // Case-insensitivity and combined homophone + edit-distance results, de-duplicated.
    let homophoneGroups = [["Be", "bee"]]
    let pool = [WordSnapshot(id: "bee"), WordSnapshot(id: "see"), WordSnapshot(id: "bea")]
    let result = confusables(for: "BE", pool: pool, homophoneGroups: homophoneGroups)
    check(result.contains("bee"), "confusables matches case-insensitively against the target")
    check(Set(result).count == result.count, "confusables never returns duplicates")
}

do {
    check(levenshteinDistance("cat", "cat") == 0, "levenshteinDistance: identical strings -> 0")
    check(levenshteinDistance("cat", "bat") == 1, "levenshteinDistance: 1 substitution -> 1")
    check(levenshteinDistance("cat", "dog") == 3, "levenshteinDistance: fully different 3-letter words -> 3")
    check(levenshteinDistance("", "cat") == 3, "levenshteinDistance: empty vs 3-letter word -> 3")
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
