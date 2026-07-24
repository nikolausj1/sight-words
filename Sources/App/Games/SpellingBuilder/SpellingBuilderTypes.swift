import Foundation

// MARK: - Tier configuration

/// Per-tier tray/mode shape (Games Spec §3.5): how many extra distractor
/// letters ride along in the tray beyond the word's own needed letters,
/// whether those distractors prefer confusable partners, and whether the
/// round runs in "build from memory" mode (T3's look-say-cover-check: the
/// word shows briefly, fully spelled, before every slot goes blank again).
struct SpellingBuilderTierConfig {
    let decoyCount: Int
    let preferConfusableDecoys: Bool
    let memoryMode: Bool
}

func spellingBuilderConfig(for tier: GameTier) -> SpellingBuilderTierConfig {
    switch tier {
    case .t1:
        return SpellingBuilderTierConfig(decoyCount: 0, preferConfusableDecoys: false, memoryMode: false)
    case .t2:
        return SpellingBuilderTierConfig(decoyCount: 2, preferConfusableDecoys: true, memoryMode: false)
    case .t3:
        // Games Spec §3.5's T3 line is entirely about the memory mechanic
        // (no stated change to tray size) -- this worker's judgment call is
        // to keep T2's tray shape (own letters + 2 confusable-preferring
        // decoys) and let the memory mechanic itself carry T3's extra
        // difficulty, rather than inventing an unstated tray-size bump.
        return SpellingBuilderTierConfig(decoyCount: 2, preferConfusableDecoys: true, memoryMode: true)
    }
}

// MARK: - Board content

/// One slot in the target word's row: the character position it covers, the
/// correct letter for that position (same casing as the word's display
/// text, so tile-vs-slot comparison is a plain `==`), and whether it's been
/// filled yet.
struct SpellingBuilderSlot: Identifiable, Equatable {
    let id = UUID()
    let position: Int
    let letter: Character
    var locked = false
}

/// One tray tile: a candidate letter, either one of the word's own letters
/// or a decoy. Tiles are plain values (no "which slot am I for" link) --
/// matching is purely by letter equality against whichever unlocked slot the
/// child drops it on, so a word needing the same letter twice (e.g. "book")
/// is satisfied by any tile bearing that letter, same as Missing Letter.
struct SpellingBuilderTile: Identifiable, Equatable {
    let id = UUID()
    let letter: Character
}

/// One word the child builds this set. `id` is unique per position in the
/// set (not just the engine id) so `.id(word.id)` can force a fresh child
/// view/state each time the game advances, even if a later word in the set
/// happens to repeat an earlier one's text.
struct SpellingBuilderWord: Identifiable {
    let id: String
    let engineID: String
    let text: String

    init(index: Int, engineID: String, text: String) {
        self.id = "\(index)-\(engineID)"
        self.engineID = engineID
        self.text = text
    }
}

// MARK: - Confusable-letter pairs (Games Spec §3.5/§4)

/// Kept local to this folder (own small copy) rather than reaching into
/// `MissingLetter`'s own types -- same rationale as `SayMatchSFX`/`MemorySFX`
/// keeping their one-off SFX local: each game worker's folder is its own
/// silo, and another game's internal files aren't a frozen contract this one
/// can lean on.
enum SpellingBuilderConfusables {
    private static let pairs: [(Character, Character)] = [("b", "d"), ("p", "q"), ("m", "n"), ("n", "u")]

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

/// Builds `count` decoy tile letters for one word's tray. `neededLetters` is
/// every letter the word's own slots require (case as it appears in the
/// word) -- decoys never duplicate one of those, so a decoy tile can never
/// accidentally satisfy a slot it wasn't meant for. When `preferConfusable`
/// is set, each needed letter's confusable partner(s) are tried first (Games
/// Spec §3.5: "distractor letters... confusable-preferring"); any shortfall
/// pads with random letters from the rest of the alphabet.
func spellingBuilderDecoys(neededLetters: [Character], count: Int, preferConfusable: Bool,
                           rng: inout RandomNumberGenerator) -> [Character] {
    guard count > 0 else { return [] }
    var used = Set(neededLetters.map { Character($0.lowercased()) })
    var decoys: [Character] = []

    if preferConfusable {
        for letter in neededLetters.shuffled(using: &rng) {
            guard decoys.count < count else { break }
            let candidates = SpellingBuilderConfusables.partners(of: letter).filter { !used.contains($0) }
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
