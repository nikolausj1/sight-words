import Foundation

// MARK: - Tier configuration

/// Per-tier worksheet shape (Games Spec §3.4's tier table + this worker's own
/// brief on exact counts): word count per board, the length window
/// `GameWordPicker` is constrained to, how many extra decoy tiles ride along
/// in the tray beyond the board's own needed letters, and what fraction of a
/// T3 board's words get a SECOND blank instead of one.
struct MissingLetterTierConfig {
    let wordCount: Int
    let minWordLength: Int
    let maxWordLength: Int
    let decoyCount: Int
    /// T2/T3 only: prefer confusable-letter partners (b/d, p/q, m/n/u) when
    /// generating decoys, padding with genuinely random letters if a needed
    /// letter has no partner or the partner's already spoken for. T1 skips
    /// this — its "+1 random" decoy per Games Spec §3.4 is deliberately not
    /// aimed at any particular confusion.
    let preferConfusableDecoys: Bool
    /// T3 only ("two blanks on some words"): roughly this fraction of the
    /// board's words get a second blank; 0 elsewhere.
    let twoBlankFraction: Double
}

func missingLetterConfig(for tier: GameTier) -> MissingLetterTierConfig {
    switch tier {
    case .t1:
        return MissingLetterTierConfig(wordCount: 4, minWordLength: 3, maxWordLength: 5,
                                        decoyCount: 1, preferConfusableDecoys: false, twoBlankFraction: 0)
    case .t2:
        return MissingLetterTierConfig(wordCount: 4, minWordLength: 3, maxWordLength: 5,
                                        decoyCount: 2, preferConfusableDecoys: true, twoBlankFraction: 0)
    case .t3:
        return MissingLetterTierConfig(wordCount: 6, minWordLength: 3, maxWordLength: 6,
                                        decoyCount: 3, preferConfusableDecoys: true, twoBlankFraction: 0.5)
    }
}

// MARK: - Board content

/// One blank on the worksheet: the character position it covers within its
/// word's `text`, the correct letter for that position (same casing as
/// `MissingLetterWordSlot.text`, so tile-vs-blank comparison is a plain `==`),
/// and whether it's been filled yet.
struct MissingLetterBlank: Identifiable, Equatable {
    let id = UUID()
    let position: Int
    let letter: Character
    var locked = false
}

/// One worksheet word: its engine id (lowercase, for `recordGameExposure`),
/// display text (natural casing, matching every other game's reading-copy
/// convention), and its blank(s). Blanks are always stored sorted by
/// `position` so views can render left-to-right without re-sorting.
struct MissingLetterWordSlot: Identifiable {
    let id = UUID()
    let engineID: String
    let text: String
    var blanks: [MissingLetterBlank]

    var isComplete: Bool { blanks.allSatisfy(\.locked) }

    /// The character at `position`, honoring any already-locked blank there
    /// (a locked blank reveals its letter same as any other already-visible
    /// character) — views read this instead of indexing `text` directly so a
    /// completed word (all blanks locked) is trivially "just the word".
    func character(at position: Int) -> Character {
        Array(text)[position]
    }

    /// True at `position` iff it's a blank that hasn't been filled in yet —
    /// the one thing a `MissingLetterWordView` needs to decide "render a
    /// glowing blank" vs "render a plain letter".
    func isOpenBlank(at position: Int) -> Bool {
        blanks.contains { $0.position == position && !$0.locked }
    }
}

/// One tray tile: a candidate letter, either one of the board's actually-needed
/// letters or a decoy. Tiles are plain values (no "which blank am I for" link)
/// — matching is purely by letter equality against whichever unlocked blank
/// the child drops it on, so two different words needing the same letter
/// (e.g. two blanks both wanting "a") are satisfied by any tile bearing that
/// letter, exactly as a child would expect.
struct MissingLetterTile: Identifiable, Equatable {
    let id = UUID()
    let letter: Character
}

// MARK: - Confusable-letter pairs (Games Spec §3.4/§4)

enum MissingLetterConfusables {
    private static let pairs: [(Character, Character)] = [("b", "d"), ("p", "q"), ("m", "n"), ("n", "u")]

    /// Every letter visually confusable with `letter` (case-insensitive in,
    /// lowercase out). `n` maps to both `m` and `u` since it appears in two
    /// pairs; every other letter here maps to exactly one partner. Letters
    /// outside the four pairs return empty.
    static func partners(of letter: Character) -> [Character] {
        let target = Character(letter.lowercased())
        var result: [Character] = []
        for (a, b) in pairs {
            if a == target { result.append(b) }
            if b == target { result.append(a) }
        }
        return result
    }
}

// MARK: - Pure generation helpers (testable, no LearningService/SwiftData dependency)

/// Picks `count` distinct character positions in a word of `wordLength` to
/// leave blank. Never blanks every letter (at least one position stays
/// visible for context) even if `count` is requested that high — in
/// practice `count` is 1 or 2 against words of length ≥3, so this floor never
/// actually binds, but it's a cheap invariant to hold structurally rather
/// than trust every caller to keep it true.
func missingLetterBlankPositions(wordLength: Int, count: Int, rng: inout RandomNumberGenerator) -> [Int] {
    let capped = min(max(count, 1), max(1, wordLength - 1))
    let shuffled = Array(0..<wordLength).shuffled(using: &rng)
    return Array(shuffled.prefix(capped)).sorted()
}

/// Builds `count` decoy tile letters for one board's tray. `neededLetters` is
/// every letter actually required by some blank on the board (case as it
/// appears in the word) — decoys never duplicate one of those, so a decoy
/// tile can never accidentally satisfy a blank it wasn't meant for. When
/// `preferConfusable` is set, each needed letter's confusable partner(s) are
/// tried first (Games Spec §3.4: "confusable-letter decoys"); any shortfall
/// (including the whole thing, when `preferConfusable` is false) pads with
/// random letters from the rest of the alphabet.
func missingLetterDecoys(neededLetters: [Character], count: Int, preferConfusable: Bool,
                         rng: inout RandomNumberGenerator) -> [Character] {
    guard count > 0 else { return [] }
    var used = Set(neededLetters.map { Character($0.lowercased()) })
    var decoys: [Character] = []

    if preferConfusable {
        for letter in neededLetters.shuffled(using: &rng) {
            guard decoys.count < count else { break }
            let candidates = MissingLetterConfusables.partners(of: letter).filter { !used.contains($0) }
            guard let pick = candidates.randomElement(using: &rng) else { continue }
            decoys.append(pick)
            used.insert(pick)
        }
    }

    let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
    while decoys.count < count {
        let remaining = alphabet.filter { !used.contains($0) }
        guard let pick = remaining.randomElement(using: &rng) else { break }
        decoys.append(pick)
        used.insert(pick)
    }
    return decoys
}
