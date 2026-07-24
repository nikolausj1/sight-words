import SwiftUI

// MARK: - GameID

/// Stable identifiers for the 5 GameKit games (Games Spec §2/§3.1-3.5). Also
/// the key each game's `TierLadder` is stored under inside
/// `Profile.gameTierData` (see `GameSessionRecorder.swift`) -- never rename
/// a case once a game ships real persisted tier data; doing so would
/// silently orphan players' progress on that game.
enum GameID: String, Codable, CaseIterable {
    case wordHunt
    case sayMatch
    case memory
    case missingLetter
    case spellingBuilder
}

// MARK: - GameEntry

/// One Games-shelf tile: identity, display copy, icon, and the screen it
/// opens. Every entry starts wired to `PlaceholderGameView` so the app
/// compiles and the (not-yet-built) shelf has something real to push before
/// any individual game exists.
struct GameEntry: Identifiable {
    let id: GameID
    let title: String
    /// SF Symbol shown as the shelf-tile icon until real art lands at
    /// `artIconKey`.
    let symbolName: String
    /// Builds the full-screen destination for one round of this game. Takes
    /// no parameters deliberately -- like every other session-launching view
    /// in this app (see `PracticeCardView`/`SessionCoordinator`), the
    /// destination is expected to pull `\.modelContext` and build its own
    /// `LearningService` from the environment, not have it threaded through
    /// here.
    let destination: () -> AnyView

    /// Imageset name checked via `Art.exists` for the shelf-tile icon
    /// (Games Spec §4's per-game shelf icons), before falling back to
    /// `symbolName`.
    var artIconKey: String { "gameicon-\(id.rawValue)" }
}

// MARK: - GameCatalog
//
// REGISTRATION CONTRACT for game workers:
//
//   When your game is ready, edit ONLY the `destination` closure on YOUR
//   OWN `GameEntry` line below -- swap
//       destination: { AnyView(PlaceholderGameView(id: .wordHunt, title: "Word Hunt", symbolName: "magnifyingglass")) }
//   for
//       destination: { AnyView(WordHuntGameView()) }
//   (or whatever your real root view is called). That one-line swap is the
//   entire integration point.
//
//   Do NOT touch: any other entry's `destination`, the array's order, the
//   `id`/`title`/`symbolName` values (even your own -- ask if they need to
//   change), or add/remove entries. The Games shelf (WP-G8) and
//   `GameSessionRecorder`'s tier persistence both key off this exact fixed
//   5-entry roster, in this exact order.
//
//   Your real view can (and should) build its own `GameWordPicker` call,
//   read/write its own tier via `LearningService.gameTier(for:profile:)` /
//   `recordGameRound(for:profile:report:)`, and wrap its board in
//   `GameScaffold` -- none of that requires touching this file.
enum GameCatalog {
    static let games: [GameEntry] = [
        GameEntry(id: .wordHunt, title: "Word Hunt", symbolName: "magnifyingglass",
                  destination: { AnyView(PlaceholderGameView(id: .wordHunt, title: "Word Hunt", symbolName: "magnifyingglass")) }),
        GameEntry(id: .sayMatch, title: "Say & Match", symbolName: "ear",
                  destination: { AnyView(PlaceholderGameView(id: .sayMatch, title: "Say & Match", symbolName: "ear")) }),
        GameEntry(id: .memory, title: "Memory Match", symbolName: "rectangle.on.rectangle.angled",
                  destination: { AnyView(PlaceholderGameView(id: .memory, title: "Memory Match", symbolName: "rectangle.on.rectangle.angled")) }),
        GameEntry(id: .missingLetter, title: "Missing Letter", symbolName: "puzzlepiece",
                  destination: { AnyView(PlaceholderGameView(id: .missingLetter, title: "Missing Letter", symbolName: "puzzlepiece")) }),
        GameEntry(id: .spellingBuilder, title: "Spelling Builder", symbolName: "cube",
                  destination: { AnyView(PlaceholderGameView(id: .spellingBuilder, title: "Spelling Builder", symbolName: "cube")) }),
    ]

    static func entry(for id: GameID) -> GameEntry {
        // Force-unwrap is safe: `games` always has exactly one entry per
        // `GameID.allCases` member, enforced by inspection above (and by
        // every game worker's contract never adding/removing entries).
        games.first { $0.id == id }!
    }
}
