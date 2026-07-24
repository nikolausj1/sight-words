import Foundation

// MARK: - WordHuntDirection

/// One of the straight-line directions a Word Hunt word can be placed in
/// (Games Spec §3.1). Every case reads forward (left-to-right / top-to-
/// bottom) -- "NO reversed words ever" is enforced structurally by this enum
/// simply never having a reversed/backward case, not by a runtime check.
enum WordHuntDirection: CaseIterable {
    case across             // (row, col) -> (row, col+1) -- all tiers
    case down                // (row, col) -> (row+1, col) -- all tiers
    case diagonalDownRight   // (row, col) -> (row+1, col+1) -- T2+
    case diagonalUpRight     // (row, col) -> (row-1, col+1) -- T2+

    var delta: (dr: Int, dc: Int) {
        switch self {
        case .across:              return (0, 1)
        case .down:                return (1, 0)
        case .diagonalDownRight:   return (1, 1)
        case .diagonalUpRight:     return (-1, 1)
        }
    }

    /// Directions available at each tier (Games Spec §3.1 tier table):
    /// T1 across/down only; T2+ adds both diagonals.
    static func allowed(for tier: GameTier) -> [WordHuntDirection] {
        switch tier {
        case .t1: return [.across, .down]
        case .t2, .t3: return [.across, .down, .diagonalDownRight, .diagonalUpRight]
        }
    }
}

// MARK: - WordHuntCellRef

/// A single grid coordinate. `Hashable` so selections/placements can live in
/// `Set`s (found-word trail lookups, hint pulsing).
struct WordHuntCellRef: Hashable {
    var row: Int
    var col: Int
}

// MARK: - WordHuntPlacement

/// One word actually written into the grid: its cell path in reading order
/// (start -> end along the placement direction). A swipe selection is a
/// correct find iff its letters, read in swipe order, spell the word --
/// callers don't need to compare against `cells` directly (see
/// `WordHuntCoordinator.commitSelection`), but `cells` is kept for hint
/// pulsing and decoy seeding.
struct WordHuntPlacement: Equatable {
    let word: String   // uppercase, matches `WordHuntGrid.letters`
    let cells: [WordHuntCellRef]
}

// MARK: - WordHuntGrid

/// One generated board (Games Spec §3.1): the letters (including every
/// placed word plus fill), and where each requested word actually landed.
struct WordHuntGrid {
    let size: Int
    let letters: [[Character]]   // size x size, uppercase
    let placements: [WordHuntPlacement]
    /// T3-only: cells seeded with a visually-confusable letter near a
    /// placed word's start (Games Spec §3.1: "confusable decoy letters
    /// seeded near targets"). Not rendered differently -- just fill letters
    /// chosen adversarially instead of randomly.
    let decoyCells: Set<WordHuntCellRef>

    /// A blank placeholder grid -- used only as a defensive fallback if
    /// `generateWordHuntGrid` ever exhausts its retry budget (should not
    /// happen for any tier's real word list/grid-size pairing; see that
    /// function's doc comment).
    static func blank(size: Int) -> WordHuntGrid {
        WordHuntGrid(size: size,
                     letters: Array(repeating: Array(repeating: Character("a"), count: size), count: size),
                     placements: [], decoyCells: [])
    }
}

// MARK: - Tier configuration

/// Per-tier board shape (Games Spec §3.1's tier table).
struct WordHuntTierConfig {
    let gridSize: Int
    let wordCount: Int
    /// Idle-hint delay in seconds; `nil` means no automatic idle hint at all
    /// (T3: "hint on demand only", via double-tapping a list word).
    let hintDelay: TimeInterval?
}

func wordHuntConfig(for tier: GameTier) -> WordHuntTierConfig {
    switch tier {
    case .t1: return WordHuntTierConfig(gridSize: 5, wordCount: 3, hintDelay: 8)
    case .t2: return WordHuntTierConfig(gridSize: 6, wordCount: 4, hintDelay: 12)
    case .t3: return WordHuntTierConfig(gridSize: 7, wordCount: 5, hintDelay: nil)
    }
}
