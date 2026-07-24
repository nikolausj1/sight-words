import Foundation

// MARK: - MemoryTierConfig

/// Per-tier board shape (Games Spec §3.3's tier table): "T1 3 pairs (2×3).
/// T2 4 pairs (2×4). T3 5-6 pairs AND pairs become word↔speaker-icon cards."
/// This build's brief pins T3 to exactly 5 pairs (word↔speaker).
struct MemoryTierConfig {
    let pairCount: Int
    /// T3 only: one card of each pair shows the word, the other shows a
    /// speaker icon (tap = replay; match = print-to-sound) instead of two
    /// identical word cards.
    let usesSpeakerCards: Bool
}

func memoryConfig(for tier: GameTier) -> MemoryTierConfig {
    switch tier {
    case .t1: return MemoryTierConfig(pairCount: 3, usesSpeakerCards: false)
    case .t2: return MemoryTierConfig(pairCount: 4, usesSpeakerCards: false)
    case .t3: return MemoryTierConfig(pairCount: 5, usesSpeakerCards: true)
    }
}

// MARK: - MemoryCardFace

/// What one card instance actually shows once flipped face-up. At T1/T2
/// both cards of a pair are `.word` (classic pairs-of-identical-cards
/// memory match); at T3 one card of the pair is `.word` and its partner is
/// `.speaker` (Games Spec §3.3: "pairs become word↔speaker-icon cards").
enum MemoryCardFace: Equatable {
    case word
    case speaker
}

// MARK: - MemoryCard

/// One physical card on the board: a stable per-instance `id` (so SwiftUI
/// can track/animate it across matches/re-shuffles) plus the `pairID` its
/// partner card shares -- a match is just two face-up cards with equal
/// `pairID`s. `pairID` is unique per physical pair SLOT on the board (not
/// necessarily the engine word id): a small pool can reuse the same word
/// across more than one pair (Games Spec: acceptable for Memory), in which
/// case each slot still gets its own `pairID` so matching/board-clear math
/// stays correct -- `wordID` carries the real engine word id for those
/// slots (identical to `pairID` in the common, non-reused case).
struct MemoryCard: Identifiable, Equatable {
    let id: String
    let pairID: String
    let wordID: String
    let displayText: String
    let face: MemoryCardFace
}

// MARK: - Board building

enum MemoryBoardBuilder {
    /// Builds one round's shuffled card set: two cards per picked word (both
    /// `.word` at T1/T2, one `.word` + one `.speaker` at T3). `roundToken`
    /// is folded into every card id so a fresh round's cards never collide
    /// with (or get confused for) the previous round's, even if the same
    /// word is picked again. `pairID` is derived from the slot index (not
    /// `w.id`) so a caller that reused a word across multiple slots (small
    /// pool fallback) still gets one distinct pairID per physical pair.
    static func build(words: [(id: String, display: String)], usesSpeakerCards: Bool,
                       roundToken: String) -> [MemoryCard] {
        var cards: [MemoryCard] = []
        for (i, w) in words.enumerated() {
            let firstFace: MemoryCardFace = .word
            let secondFace: MemoryCardFace = usesSpeakerCards ? .speaker : .word
            let pairID = "\(roundToken)-\(i)"
            cards.append(MemoryCard(id: "\(pairID)-a", pairID: pairID, wordID: w.id, displayText: w.display, face: firstFace))
            cards.append(MemoryCard(id: "\(pairID)-b", pairID: pairID, wordID: w.id, displayText: w.display, face: secondFace))
        }
        return cards.shuffled()
    }
}
