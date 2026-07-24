import SwiftUI
import SwiftData

/// The Tricky Words 6th-tile flow (Design Direction §6): instead of opening
/// the classic flash-card `SessionView` directly, rotates through the 5
/// GameKit games day-of-week style, each built from a `trickyOnly` deck
/// (needsReview/learning words only -- every coordinator's own `trickyOnly`
/// flag, threaded through its `GameXGameView`'s init the same way
/// `-demoGame`'s tier override already is). Falls back to the existing
/// card-session Tricky Words flow when there aren't enough tricky words to
/// make a real game deck.
///
/// PLUMBING NOTE for whoever wires the Home shelf's Tricky tile (out of this
/// worker's scope -- `HomeView`/`SessionView` are hands-off this pass):
/// `HomeView.trickyTile` currently sets `showTricky = true`, which presents
/// `SessionView(profile:, context:, kind: .tricky)` directly (see
/// `HomeView`'s `.fullScreenCover(isPresented: $showTricky)`). Swapping that
/// one destination for `TrickyGamesRotationView()` -- same no-param contract
/// as every other `GameEntry.destination` -- routes the tile through this
/// flow instead. Smallest viable change: one view swap, nothing else in
/// `HomeView` needs to know which mode it ended up in.
struct TrickyGamesRotationView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]
    @Query(sort: \Profile.createdAt) private var allProfiles: [Profile]

    private var profile: Profile? { activeProfiles.first ?? allProfiles.first }

    /// Below this many tricky (needsReview/learning) words, a real game round
    /// would be too thin/repetitive to be worth it -- falls back to the
    /// existing tricky flash-card session instead (per this pass's brief:
    /// "If <3 tricky words: falls back to the existing tricky card session").
    private static let minTrickyWordsForGame = 3

    var body: some View {
        if let profile {
            let service = LearningService(context: context)
            if service.countTricky(for: profile) >= Self.minTrickyWordsForGame {
                rotatedGame
            } else {
                SessionView(profile: profile, context: context, kind: .tricky)
            }
        } else {
            // Defensive only, mirrors every `GameXGameView`'s own fallback --
            // every real path here already requires an onboarded active
            // profile to exist first.
            Color.clear
        }
    }

    /// Day-of-week rotation over `GameCatalog`'s fixed 5-game roster (its own
    /// registration order), so Tricky Words opens a different game each day
    /// rather than always the same one. `Calendar.weekday` is 1...7 (Sunday
    /// = 1); reducing mod the roster size just cycles through it.
    @ViewBuilder
    private var rotatedGame: some View {
        let index = Calendar.current.component(.weekday, from: .now) % GameCatalog.games.count
        switch GameCatalog.games[index].id {
        case .wordHunt: WordHuntGameView(trickyOnly: true)
        case .sayMatch: SayMatchGameView(trickyOnly: true)
        case .memory: MemoryGameView(trickyOnly: true)
        case .missingLetter: MissingLetterGameView(trickyOnly: true)
        case .spellingBuilder: SpellingBuilderGameView(trickyOnly: true)
        }
    }
}
