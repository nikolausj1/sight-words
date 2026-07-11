import Foundation

/// Which kind of session to build.
public enum SessionMode: Equatable {
    case standard
    case tricky
}

/// Deterministic Fisher-Yates shuffle driven by an injected RNG so tests can seed it.
func shuffledArray<T>(_ array: [T], rng: inout RandomNumberGenerator) -> [T] {
    var a = array
    guard a.count > 1 else { return a }
    for i in stride(from: a.count - 1, to: 0, by: -1) {
        let span = UInt64(i + 1)
        let r = rng.next() % span
        a.swapAt(i, Int(r))
    }
    return a
}

/// Convenience overload: uses `SystemRandomNumberGenerator` when the caller doesn't
/// need a seeded/deterministic draw.
public func buildSession(
    pool: [WordSnapshot],
    size: Int,
    now: Date,
    calendar: Calendar,
    mode: SessionMode
) -> [WordSnapshot] {
    var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
    return buildSession(pool: pool, size: size, now: now, calendar: calendar, mode: mode, rng: &rng)
}

/// Builds one session's word list per PRD §6.9.
///
/// Standard mode targets ~70% familiar (developing/fluent/mastered, due) / ~20%
/// learning-or-needsReview / ~10% new (hard cap 2 new). Shortfalls in any bucket are
/// backfilled in "next most familiar" order: extra due-familiar, then extra
/// learning, then extra new (still capped at 2), then not-yet-due familiar words --
/// this generalizes the PRD's explicit "familiar shortfall -> learning -> new ->
/// not-yet-due familiar" chain to shortfalls that originate in any bucket.
///
/// Tricky mode draws only `needsReview` or `learning` words, most-missed first, no
/// new words, capped at `size`.
///
/// If the whole pool is smaller than `size`, the entire (shuffled) pool is returned.
public func buildSession(
    pool: [WordSnapshot],
    size: Int,
    now: Date,
    calendar: Calendar,
    mode: SessionMode,
    rng: inout RandomNumberGenerator
) -> [WordSnapshot] {
    guard size > 0 else { return [] }

    if mode == .tricky {
        let candidates = pool.filter { $0.needsReview || $0.state == .learning }
        let sorted = candidates.sorted { $0.timesMissed > $1.timesMissed }
        return Array(sorted.prefix(size))
    }

    if pool.count < size {
        return shuffledArray(pool, rng: &rng)
    }

    func isDue(_ w: WordSnapshot) -> Bool {
        guard let due = w.dueDate else { return true }
        return due <= now
    }
    func isFamiliarState(_ state: WordState) -> Bool {
        state == .developing || state == .fluent || state == .mastered
    }

    var learningBucket = pool.filter { $0.state == .learning || $0.needsReview }
    var familiarBucket = pool.filter {
        !($0.state == .learning || $0.needsReview) && isFamiliarState($0.state) && isDue($0)
    }
    var notYetDueFamiliar = pool.filter {
        !($0.state == .learning || $0.needsReview) && isFamiliarState($0.state) && !isDue($0)
    }
    var newBucket = pool.filter { $0.state == .new }

    // Priority within each bucket.
    learningBucket.sort { $0.timesMissed > $1.timesMissed }
    familiarBucket.sort { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) } // most-overdue first
    notYetDueFamiliar.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) } // soonest-due first
    newBucket = shuffledArray(newBucket, rng: &rng)

    let anyNew = !newBucket.isEmpty
    let newRounded = Int((0.1 * Double(size)).rounded())
    let newBaseline = (anyNew && size >= 10) ? 1 : 0
    let newTarget = anyNew ? min(2, max(newBaseline, newRounded)) : 0
    let learningTarget = Int((0.2 * Double(size)).rounded())
    let familiarTarget = max(0, size - newTarget - learningTarget)

    var selected: [WordSnapshot] = []
    var usedIds = Set<String>()
    var newTakenCount = 0

    func take(_ bucket: inout [WordSnapshot], _ count: Int, isNewBucket: Bool = false) {
        var taken = 0
        while taken < count, !bucket.isEmpty {
            let w = bucket.removeFirst()
            if !usedIds.contains(w.id) {
                selected.append(w)
                usedIds.insert(w.id)
                taken += 1
                if isNewBucket { newTakenCount += 1 }
            }
        }
    }

    take(&familiarBucket, familiarTarget)
    take(&learningBucket, learningTarget)
    take(&newBucket, newTarget, isNewBucket: true)

    var remaining = size - selected.count

    // Backfill chain: more familiar -> more learning -> more new (cap 2) -> not-yet-due familiar.
    if remaining > 0 {
        take(&familiarBucket, remaining)
        remaining = size - selected.count
    }
    if remaining > 0 {
        take(&learningBucket, remaining)
        remaining = size - selected.count
    }
    if remaining > 0 {
        let capRoom = max(0, 2 - newTakenCount)
        if capRoom > 0 {
            take(&newBucket, min(remaining, capRoom), isNewBucket: true)
            remaining = size - selected.count
        }
    }
    if remaining > 0 {
        take(&notYetDueFamiliar, remaining)
        remaining = size - selected.count
    }

    // Fresh-profile floor: with no familiar/learning words yet, the 2-new cap would
    // produce a 2-card first session. An introduction session of up to 5 new words
    // is the intended day-one experience, so the cap yields to a 5-card floor.
    let floorCount = min(5, size)
    if selected.count < floorCount {
        take(&newBucket, floorCount - selected.count, isNewBucket: true)
    }

    return selected
}
