import Foundation

// MARK: - Constraints

/// Shape constraints a game imposes on which pool words are even eligible,
/// before the weighting in `pickGameWords` runs.
public struct GameWordConstraints: Equatable {
    /// Longest allowed word length (grid-based games like Word Hunt/Memory
    /// need this to keep boards a sane size). `nil` = no length limit.
    public var maxLength: Int?

    public init(maxLength: Int? = nil) {
        self.maxLength = maxLength
    }
}

// MARK: - pickGameWords

/// Picks `count` words from `pool` for one game round, weighted per Games
/// Spec §2: 60% learning/developing, 30% fluent/mastered, 10% new-but-
/// already-introduced.
///
/// "Games introduce nothing" (Games Spec §2) is enforced structurally: a
/// `WordSnapshot` with `state == .new` is only eligible at all if
/// `timesSeen > 0` — i.e. it has already been shown to the child (via a
/// card session, or a prior game round's exposure-only recording) even
/// though it hasn't been scored yet. A word that has genuinely never been
/// seen (`timesSeen == 0`) is never selected, at any weight, full stop.
///
/// If a bucket comes up short (including because `constraints` filtered it
/// down), the shortfall backfills from the calmest/most-familiar words
/// first: fluent/mastered, then learning/developing, then more
/// already-introduced-new — in that order, and never from outside the
/// `constraints`-eligible slice of `pool`.
public func pickGameWords(
    pool: [WordSnapshot],
    count: Int,
    constraints: GameWordConstraints = GameWordConstraints()
) -> [WordSnapshot] {
    var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
    return pickGameWords(pool: pool, count: count, constraints: constraints, rng: &rng)
}

/// Seeded-RNG overload for deterministic tests.
public func pickGameWords(
    pool: [WordSnapshot],
    count: Int,
    constraints: GameWordConstraints = GameWordConstraints(),
    rng: inout RandomNumberGenerator
) -> [WordSnapshot] {
    guard count > 0 else { return [] }

    func fits(_ w: WordSnapshot) -> Bool {
        guard let maxLen = constraints.maxLength else { return true }
        return w.id.count <= maxLen
    }

    let eligible = pool.filter(fits)
    guard !eligible.isEmpty else { return [] }

    if eligible.count <= count {
        return shuffledArray(eligible, rng: &rng)
    }

    var learningDeveloping = shuffledArray(
        eligible.filter { $0.state == .learning || $0.state == .developing }, rng: &rng)
    var fluentMastered = shuffledArray(
        eligible.filter { $0.state == .fluent || $0.state == .mastered }, rng: &rng)
    var newIntroduced = shuffledArray(
        eligible.filter { $0.state == .new && $0.timesSeen > 0 }, rng: &rng)

    let newTarget = min(newIntroduced.count, Int((0.10 * Double(count)).rounded()))
    let fluentTarget = Int((0.30 * Double(count)).rounded())
    let learningTarget = max(0, count - newTarget - fluentTarget)

    var selected: [WordSnapshot] = []
    var usedIds = Set<String>()

    func take(_ bucket: inout [WordSnapshot], _ n: Int) {
        var taken = 0
        while taken < n, !bucket.isEmpty {
            let w = bucket.removeFirst()
            if !usedIds.contains(w.id) {
                selected.append(w)
                usedIds.insert(w.id)
                taken += 1
            }
        }
    }

    take(&learningDeveloping, learningTarget)
    take(&fluentMastered, fluentTarget)
    take(&newIntroduced, newTarget)

    // Fill-from-familiar fallback: backfill any shortfall starting with the
    // calmest/most-known words first.
    var remaining = count - selected.count
    if remaining > 0 { take(&fluentMastered, remaining); remaining = count - selected.count }
    if remaining > 0 { take(&learningDeveloping, remaining); remaining = count - selected.count }
    if remaining > 0 { take(&newIntroduced, remaining); remaining = count - selected.count }

    return selected
}

// MARK: - confusables

/// Returns confusable candidates for `word` (tier-2+ distractors, Games
/// Spec §2): every other member of `word`'s homophone group (from
/// `homophoneGroups`, the same `[[String]]` shape as `homophones.json`),
/// plus every same-length word in `pool` within edit distance ≤ 2. Matching
/// is case-insensitive; the target word itself is never included; order is
/// homophone-group members first, then pool neighbors, both de-duplicated.
public func confusables(
    for word: String,
    pool: [WordSnapshot],
    homophoneGroups: [[String]] = []
) -> [String] {
    let target = word.lowercased()
    var seen = Set<String>([target])
    var results: [String] = []

    if let group = homophoneGroups.first(where: { members in
        members.contains { $0.lowercased() == target }
    }) {
        for member in group {
            let m = member.lowercased()
            guard !seen.contains(m) else { continue }
            results.append(m)
            seen.insert(m)
        }
    }

    let sameLengthCandidates = pool.map { $0.id }.filter { $0.count == target.count }
    for candidate in sameLengthCandidates {
        guard !seen.contains(candidate) else { continue }
        if levenshteinDistance(target, candidate) <= 2 {
            results.append(candidate)
            seen.insert(candidate)
        }
    }

    return results
}

/// Standard Levenshtein edit distance (insert/delete/substitute, each cost 1).
func levenshteinDistance(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)
    let m = aChars.count
    let n = bChars.count
    if m == 0 { return n }
    if n == 0 { return m }

    var previousRow = Array(0...n)
    var currentRow = Array(repeating: 0, count: n + 1)

    for i in 1...m {
        currentRow[0] = i
        for j in 1...n {
            if aChars[i - 1] == bChars[j - 1] {
                currentRow[j] = previousRow[j - 1]
            } else {
                currentRow[j] = 1 + min(previousRow[j - 1], previousRow[j], currentRow[j - 1])
            }
        }
        previousRow = currentRow
    }
    return previousRow[n]
}
