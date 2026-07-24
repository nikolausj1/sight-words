import SwiftUI
import SwiftData

/// Say & Match's real root view (Games Spec §3.2) -- what `GameCatalog`'s
/// `sayMatch` entry's `destination` closure swaps in for
/// `PlaceholderGameView`. Per the registration contract, this takes no
/// parameters: it pulls `\.modelContext` itself and builds its own
/// `LearningService`/`SayMatchModel`, exactly like every other
/// session-launching root view in the app.
struct SayMatchGameView: View {
    /// Tricky Words rotation mode (Design Direction §6) -- see
    /// `WordHuntGameView.trickyOnly`'s doc comment.
    var trickyOnly: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: SayMatchModel?

    var body: some View {
        Group {
            if let model {
                SayMatchContentView(model: model, onExit: { dismiss() })
            } else {
                Color.clear.onAppear(perform: setUpModelIfNeeded)
            }
        }
    }

    private func setUpModelIfNeeded() {
        guard model == nil else { return }
        let service = LearningService(context: modelContext)
        let profile = service.activeProfile()
        model = SayMatchModel(profile: profile, service: service, trickyOnly: trickyOnly)
    }
}

/// Hosts the shared `GameScaffold` chrome once `SayMatchModel` exists:
/// routes to whichever round is current, and layers `RoundCelebration` over
/// everything once the set is done.
private struct SayMatchContentView: View {
    @ObservedObject var model: SayMatchModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            GameScaffold(instruction: model.currentInstruction,
                        gameID: .sayMatch,
                        currentRound: model.roundIndex,
                        totalRounds: max(model.totalRounds, 1),
                        onExit: onExit) {
                roundContent
            }
            if model.isComplete {
                RoundCelebration(gameID: .sayMatch, canPlayAgain: model.canPlayAgain,
                                  onAgain: { model.startNewSet() }, onNext: onExit)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(Theme.Motion.snappy, value: model.isComplete)
        .onAppear { model.start() }
    }

    @ViewBuilder private var roundContent: some View {
        if let round = model.currentRound {
            Group {
                switch round.kind {
                case .hearFind:
                    SayMatchRoundAView(model: model, round: round)
                case .seeSay:
                    SayMatchRoundBView(model: model, round: round)
                }
            }
            .id(round.id)
        } else {
            Color.clear
        }
    }
}
