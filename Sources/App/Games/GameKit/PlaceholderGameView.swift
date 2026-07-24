import SwiftUI

/// Temporary destination every `GameEntry.destination` in `GameCatalog`
/// starts wired to (Games Spec §2) -- lets the app compile and gives the
/// (not-yet-built) Games shelf something real to push to before any
/// individual game exists. A game worker's entire integration is swapping
/// their own `GameEntry.destination` closure for their real root view (see
/// the registration contract atop `GameCatalog.swift`); this file is never
/// touched by that swap, and never referenced once every game has landed.
struct PlaceholderGameView: View {
    let id: GameID
    let title: String
    let symbolName: String
    @Environment(\.dismiss) private var dismiss

    /// Each game's real §3 opening line, where a clip/fallback already
    /// exists (Games Spec §4) -- just so the placeholder screen previews the
    /// right voice moment, not a generic one.
    private var openingLine: GameInstruction {
        switch id {
        case .wordHunt:        return GameInstruction(.findTheWords)
        case .sayMatch:        return GameInstruction(.whichWord)
        case .memory:          return GameInstruction(.matchTheCards)
        case .missingLetter:   return GameInstruction(.fillTheBlanks)
        case .spellingBuilder: return GameInstruction(.sayThenBuild)
        }
    }

    var body: some View {
        GameScaffold(
            instruction: openingLine,
            gameID: id,
            currentRound: 0,
            totalRounds: 1,
            onExit: { dismiss() }
        ) {
            VStack(spacing: Theme.Metric.gap) {
                Image(systemName: symbolName)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                Text(title)
                    .font(Theme.Font.display(28))
                    .foregroundStyle(Theme.Color.ink)
                Text("Coming soon!")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.inkSoft)
            }
        }
    }
}
