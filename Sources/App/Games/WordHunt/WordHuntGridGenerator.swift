import Foundation

// MARK: - generateWordHuntGrid
//
// Pure grid-generation logic (Games Spec §3.1) -- no SwiftUI/UIKit
// dependency, deterministic given a seeded `RandomNumberGenerator`, so this
// is unit-testable in-file exactly like `Sources/Engine/GameWordPicker.swift`
// (which this mirrors the RNG-injection style of, down to the manual
// `rng.next() % span` picks instead of `Array.randomElement(using:)` --
// the stdlib's `using:` overloads take a concrete `<T: RandomNumberGenerator>`
// generic, which an existential `RandomNumberGenerator` value doesn't
// satisfy without an extra wrapper; see `Sources/Engine/SessionBuilder.swift`'s
// `shuffledArray` for the same workaround already established in this repo).

/// Generates one Word Hunt board.
///
/// **Solvability is guaranteed structurally, not verified after the fact**:
/// every word in `words` is written into `letters` at a real, in-bounds cell
/// path *before* any fill/decoy/profanity-guard pass ever runs. There is no
/// "lay out board, then check if words are findable" step -- a `WordHuntGrid`
/// this function returns always contains every successfully-placed word
/// along one of `tier`'s allowed directions, because that placement is how
/// the letters got there in the first place. If a word can't be placed after
/// `maxAttemptsPerWord` random (direction, start-cell) tries, the WHOLE grid
/// (all placements so far) is discarded and restarted from empty -- up to
/// `maxGridAttempts` times -- rather than silently dropping that one word
/// from the round. Returns `nil` only if every restart still fails, which in
/// practice means the caller passed word lengths/counts that don't fit
/// `size` at all (the tier table in `WordHuntTypes.swift` always keeps
/// `maxLength == size`, so this is not expected to happen in real play).
///
/// Longest words are placed first (tightest fit, so placing them while the
/// grid is emptiest minimizes forced restarts); shorter words fill in after.
func generateWordHuntGrid(
    size: Int,
    words: [String],
    tier: GameTier,
    confusableDecoys: [String] = [],
    rng: inout RandomNumberGenerator
) -> WordHuntGrid? {
    guard size > 0, !words.isEmpty else { return nil }
    let directions = WordHuntDirection.allowed(for: tier)
    let maxGridAttempts = 40
    let maxAttemptsPerWord = 300
    // Design Direction §6/§4: sight words are learned lowercase, so the grid
    // (and the list panel reading it back) render lowercase, same as every
    // other game -- `words` already arrives in its natural stored casing
    // (lowercase, except "I") from `WordHuntCoordinator`, so this no longer
    // forces it upper.
    let ordered = words.sorted { $0.count > $1.count }

    gridAttempt: for _ in 0..<maxGridAttempts {
        var grid: [[Character?]] = Array(repeating: Array(repeating: nil, count: size), count: size)
        var placements: [WordHuntPlacement] = []

        for word in ordered {
            guard !word.isEmpty, word.count <= size else { continue gridAttempt }
            var placed = false

            attemptLoop: for _ in 0..<maxAttemptsPerWord {
                guard let direction = pick(from: directions, rng: &rng) else { break attemptLoop }
                let (dr, dc) = direction.delta
                let len = word.count
                let rowRange = startRange(delta: dr, len: len, size: size)
                let colRange = startRange(delta: dc, len: len, size: size)
                let startRow = pick(from: rowRange, rng: &rng)
                let startCol = pick(from: colRange, rng: &rng)

                var cells: [WordHuntCellRef] = []
                cells.reserveCapacity(len)
                var fits = true
                for (i, ch) in word.enumerated() {
                    let r = startRow + dr * i
                    let c = startCol + dc * i
                    if let existing = grid[r][c], existing != ch { fits = false; break }
                    cells.append(WordHuntCellRef(row: r, col: c))
                }
                guard fits else { continue attemptLoop }

                for (i, ch) in word.enumerated() {
                    grid[cells[i].row][cells[i].col] = ch
                }
                placements.append(WordHuntPlacement(word: word, cells: cells))
                placed = true
                break attemptLoop
            }

            guard placed else { continue gridAttempt }
        }

        var decoyCells = Set<WordHuntCellRef>()
        if tier == .t3 {
            decoyCells = seedConfusableDecoys(grid: &grid, placements: placements)
        }
        fillRemaining(grid: &grid, weightedTo: words.joined(), rng: &rng)
        guaranteeNoProfanity(grid: &grid,
                             protected: Set(placements.flatMap(\.cells)).union(decoyCells),
                             rng: &rng)

        let finalLetters = grid.map { row in row.map { $0 ?? "a" } }
        return WordHuntGrid(size: size, letters: finalLetters, placements: placements, decoyCells: decoyCells)
    }

    return nil
}

// MARK: - RNG pick helpers

/// Manual RNG-driven picks (see the file-header note on why this repo avoids
/// the stdlib's `randomElement(using:)`/`shuffled(using:)` against an
/// existential `RandomNumberGenerator`).
private func pick<T>(from array: [T], rng: inout RandomNumberGenerator) -> T? {
    guard !array.isEmpty else { return nil }
    return array[Int(rng.next() % UInt64(array.count))]
}

private func pick(from range: ClosedRange<Int>, rng: inout RandomNumberGenerator) -> Int {
    let span = UInt64(range.upperBound - range.lowerBound + 1)
    return range.lowerBound + Int(rng.next() % span)
}

/// The valid start-coordinate range along one axis for a word of length
/// `len` moving by `delta` (-1/0/1) per step, so the whole word stays
/// in-bounds for a `size x size` grid.
private func startRange(delta: Int, len: Int, size: Int) -> ClosedRange<Int> {
    if delta == 0 { return 0...(size - 1) }
    if delta > 0 { return 0...(size - len) }
    return (len - 1)...(size - 1)
}

// MARK: - Fill letters (Games Spec §3.1: "decoy fill letters random weighted to target letters")

private func fillRemaining(grid: inout [[Character?]], weightedTo words: String, rng: inout RandomNumberGenerator) {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
    var weights = Dictionary(uniqueKeysWithValues: alphabet.map { ($0, 1) })
    for ch in words.lowercased() where weights[ch] != nil {
        weights[ch, default: 1] += 4
    }
    let pool = alphabet.flatMap { ch in Array(repeating: ch, count: weights[ch] ?? 1) }
    guard !pool.isEmpty else { return }
    for r in 0..<grid.count {
        for c in 0..<grid[r].count where grid[r][c] == nil {
            grid[r][c] = pick(from: pool, rng: &rng)
        }
    }
}

// MARK: - T3 confusable decoys (Games Spec §3.1: "confusable decoy letters seeded near targets")

/// Visually-similar letter pairs a beginning reader commonly mixes up.
private let confusableLetterMap: [Character: Character] = [
    "b": "d", "d": "b", "p": "q", "q": "p", "m": "n", "n": "m", "u": "n", "w": "m",
]

/// For each placed word (T3 only), tries to drop a visually-confusable
/// letter into an empty cell adjacent to the word's first letter -- a small,
/// deliberate trap next to (not inside) each target, rather than a whole
/// decoy word. Returns the set of cells it touched so the fill and
/// profanity passes both leave them alone.
private func seedConfusableDecoys(grid: inout [[Character?]], placements: [WordHuntPlacement]) -> Set<WordHuntCellRef> {
    var seeded = Set<WordHuntCellRef>()
    let size = grid.count
    for placement in placements {
        guard let firstCell = placement.cells.first,
              let firstChar = grid[firstCell.row][firstCell.col],
              let confusable = confusableLetterMap[Character(String(firstChar).lowercased())] else { continue }
        for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let r = firstCell.row + dr, c = firstCell.col + dc
            guard r >= 0, r < size, c >= 0, c < size, grid[r][c] == nil else { continue }
            grid[r][c] = confusable
            seeded.insert(WordHuntCellRef(row: r, col: c))
            break
        }
    }
    return seeded
}

// MARK: - Profanity guard (Games Spec §3.1: "no accidental profanity")

/// Small denylist checked (both forward and backward) along every allowed
/// reading direction, over any run of 3-5 letters anywhere in the finished
/// grid. Not exhaustive -- a best-effort net over the fill/decoy letters,
/// which is all that's actually random here (placed words come from our own
/// curated Dolch pool, so they're never the problem). Any hit gets one
/// non-target-word cell in the run re-rolled and the whole grid is
/// re-scanned, up to a small bounded number of passes.
private let profanityDenylist: Set<String> = [
    "ass", "fuk", "fuck", "shit", "sex", "damn", "crap", "cock", "dick", "piss", "fart", "hell",
]

private func guaranteeNoProfanity(grid: inout [[Character?]], protected: Set<WordHuntCellRef>, rng: inout RandomNumberGenerator) {
    let size = grid.count
    let directions: [(Int, Int)] = [(0, 1), (1, 0), (1, 1), (-1, 1)]
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz")

    for _ in 0..<10 {
        var badCell: WordHuntCellRef?

        scan: for r in 0..<size {
            for c in 0..<size {
                for (dr, dc) in directions {
                    for len in 3...5 {
                        var chars: [Character] = []
                        var cells: [WordHuntCellRef] = []
                        var ok = true
                        for i in 0..<len {
                            let rr = r + dr * i, cc = c + dc * i
                            guard rr >= 0, rr < size, cc >= 0, cc < size, let ch = grid[rr][cc] else { ok = false; break }
                            chars.append(ch)
                            cells.append(WordHuntCellRef(row: rr, col: cc))
                        }
                        guard ok else { continue }
                        let forward = String(chars).lowercased()
                        let backward = String(chars.reversed()).lowercased()
                        guard profanityDenylist.contains(forward) || profanityDenylist.contains(backward) else { continue }
                        if let target = cells.first(where: { !protected.contains($0) }) {
                            badCell = target
                            break scan
                        }
                    }
                }
            }
        }

        guard let cellToFix = badCell else { return }
        grid[cellToFix.row][cellToFix.col] = pick(from: alphabet, rng: &rng)
    }
}
