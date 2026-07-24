import Foundation
import CoreGraphics

/// One planted word (Design Direction §7): derived 100% from a
/// `WordProgressRecord`'s state -- `fluent` words are sprouts, `mastered`
/// words are one of four flowers or a tree -- with NO persistence of its
/// own. Both `GardenView` (the full garden scene) and `SessionCompleteView`
/// (the single bloom-in moment for a word that just crossed to `mastered`)
/// need the exact same word -> art mapping, so it lives here rather than
/// being duplicated in each view.
struct GardenPlant: Identifiable, Equatable {
    let word: String
    let mastered: Bool

    var id: String { word }

    /// Stable across app launches (unlike `String.hashValue`, which is
    /// randomized per process) -- §7 requires "no new persistence beyond a
    /// per-word planted-variant seed," i.e. the seed has to be re-derivable
    /// from the word text alone every time, not stored. A plain FNV-1a-64
    /// over the lowercased UTF-8 bytes is enough: this only ever needs to
    /// scatter a few dozen words across a handful of slots/variants, not
    /// resist adversarial collisions.
    var seed: UInt64 { Self.seed(for: word) }

    static func seed(for word: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325   // FNV offset basis
        for byte in word.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3         // FNV prime
        }
        return hash
    }

    /// 0-3 = flower-1..4, 4 = tree. Only meaningful once `mastered` -- a
    /// `fluent`-only word always renders as the plain sprout regardless of
    /// this value.
    static func variant(for word: String) -> Int {
        Int(seed(for: word) % 5)
    }

    /// The `Art.exists`-checked imageset name for this plant's current
    /// state: sprout while merely `fluent`, one of 4 flowers or the tree
    /// once `mastered` (picked deterministically by `variant(for:)` so the
    /// same word always grows the same plant).
    static func assetName(word: String, mastered: Bool) -> String {
        guard mastered else { return "garden-sprout" }
        switch variant(for: word) {
        case 0: return "garden-flower-1"
        case 1: return "garden-flower-2"
        case 2: return "garden-flower-3"
        case 3: return "garden-flower-4"
        default: return "garden-tree"
        }
    }

    var assetName: String { Self.assetName(word: word, mastered: mastered) }

    /// The tree variant reads as a bigger plant than the flower/sprout art
    /// (Design Direction art inventory: it's meant to anchor the row rather
    /// than blend in as one more small bloom).
    var isTree: Bool { mastered && Self.variant(for: word) == 4 }
}

// MARK: - Deterministic soil-row layout

/// Scatters `plants` across fixed soil rows with no overlap, keyed by each
/// plant's own `seed` -- so a given word always lands in the same spot
/// across app launches (Design Direction §7: "deterministic position...
/// from word-text hash"), and reflowing the same word list never produces a
/// visibly different garden between one session and the next.
enum GardenLayout {
    /// `size` is the garden scene's own bounds; the returned points are in
    /// that same coordinate space. `rows` matches `garden-bed`'s art (a
    /// handful of layered soil/hill bands) rather than scaling with plant
    /// count, so more plants pack rows tighter instead of inventing new
    /// bands the backdrop art doesn't have.
    static func positions(for plants: [GardenPlant], in size: CGSize, rows: Int = 3) -> [String: CGPoint] {
        guard !plants.isEmpty, size.width > 0, size.height > 0 else { return [:] }
        let perRow = max(4, Int(ceil(Double(plants.count) / Double(rows))))
        var occupied = Set<Int>()
        var result: [String: CGPoint] = [:]

        for plant in plants {
            var probe = plant.seed
            var attempts = 0
            let maxSlots = rows * perRow
            while attempts < maxSlots {
                let slot = Int(probe % UInt64(maxSlots))
                if occupied.insert(slot).inserted {
                    let row = slot / perRow
                    let col = slot % perRow
                    let xFrac = (Double(col) + 0.5) / Double(perRow)
                    // A little sub-cell jitter (from higher bits of the same
                    // seed) so plants don't read as a rigid grid.
                    let jitter = (Double((probe >> 16) % 1000) / 1000 - 0.5) * (0.6 / Double(perRow))
                    let clampedXFrac = min(max(xFrac + jitter, 0.04), 0.96)
                    let x = size.width * clampedXFrac
                    // `garden-bed`'s actual art is a diagonal dune sloping
                    // from high-on-the-left to low-on-the-right, NOT a flat
                    // horizontal band -- a fixed row->y mapping independent
                    // of x put plants at x~0.9 well above the soil (measured
                    // against the real asset: its hill line sits at ~55% of
                    // the frame height on the left third, ~83% on the right
                    // two-thirds). `soilTopFraction` reproduces that same
                    // slope in closed form so every row/column combination
                    // still lands ON soil, not floating in the sky.
                    let top = soilTopFraction(atXFraction: clampedXFrac)
                    let band = 0.94 - (top + 0.04)
                    let rowFrac = top + 0.04 + band * (Double(row) / Double(max(rows - 1, 1)))
                    let y = size.height * rowFrac
                    result[plant.word] = CGPoint(x: x, y: y)
                    break
                }
                probe = probe &* 6364136223846793005 &+ 1442695040888963407
                attempts += 1
            }
        }
        return result
    }

    /// Fraction of the scene's height where `garden-bed`'s soil/hill line
    /// sits at a given horizontal fraction -- a closed-form fit of the real
    /// asset's diagonal dune (measured directly from the art: ~0.55 for
    /// x<0.15, ramping up to ~0.83 by x~0.5, flat from there to the right
    /// edge), used so plant placement always lands below that line
    /// regardless of which column a word's hash happens to pick.
    private static func soilTopFraction(atXFraction xFrac: Double) -> Double {
        let t = min(max((xFrac - 0.15) / 0.35, 0), 1)
        return 0.55 + t * (0.83 - 0.55)
    }
}
