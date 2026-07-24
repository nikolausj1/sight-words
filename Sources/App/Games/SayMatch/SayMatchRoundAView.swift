import SwiftUI

/// Round A: "hear it, find the tile" (Games Spec §3.2). `model.currentInstruction`
/// has already spoken "Which word did you hear? … <target>" (either via
/// `GameScaffold`'s own on-appear speech for round 0, or `SayMatchModel.advance()`
/// for every later round) by the time this view appears -- this view only
/// renders the tiles and reacts to taps.
struct SayMatchRoundAView: View {
    @ObservedObject var model: SayMatchModel
    let round: SayMatchRound

    @State private var wrongTileID: String?
    @State private var correctTileID: String?
    @State private var driftedTileIDs: Set<String> = []
    @State private var successWord: String?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    /// T3 with voice off keeps 4 choices but bobs the tiles faster (Games
    /// Spec §3.2's T3 tier note) -- the only tile-motion difference tier
    /// makes; distractor *selection* already differs upstream in
    /// `SayMatchModel.buildRounds()`.
    private var fastBob: Bool { model.tier == .t3 && !model.voiceAvailable }

    var body: some View {
        boardContent
            .successMoment(word: $successWord) { model.advance() }
            .onAppear { maybeRunDemoAutoAnswer() }
    }

    @ViewBuilder private var boardContent: some View {
        Group {
            if isCompact {
                // Explicit `maximum:` caps each column regardless of how much
                // width an ancestor ends up proposing -- without it, an
                // iPhone-compact board (no GeometryReader in this chain)
                // could hand the grid an oversized proposed width, stretching
                // both columns out to the screen edges with the tile content
                // centered somewhere off-screen in between.
                LazyVGrid(columns: [GridItem(.flexible(maximum: 170)), GridItem(.flexible(maximum: 170))],
                         spacing: Theme.Metric.gap) {
                    tiles
                }
                .frame(maxWidth: 380)
            } else {
                HStack(spacing: Theme.Metric.gap * 1.5) {
                    tiles
                }
            }
        }
        .padding(Theme.Metric.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var tiles: some View {
        ForEach(round.tileIDs, id: \.self) { tileID in
            SayMatchTile(text: model.service.displayText(forID: tileID),
                        fastBob: fastBob,
                        isHighlighted: correctTileID == tileID,
                        isDrifted: driftedTileIDs.contains(tileID),
                        action: { handleTap(tileID) })
                .wrongShake(Binding(
                    get: { wrongTileID == tileID },
                    set: { firing in if !firing { wrongTileID = nil } }
                ))
        }
    }

    private func handleTap(_ tileID: String) {
        guard successWord == nil, correctTileID == nil else { return }
        if tileID == round.targetID {
            correctTileID = tileID
            SayMatchSFX.playWhoosh()
            driftedTileIDs = Set(round.tileIDs.filter { $0 != tileID })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                successWord = round.targetDisplay
            }
        } else {
            model.registerWrong()
            wrongTileID = tileID
            model.speech.speak(segments: model.currentInstruction.segments)
        }
    }

    // MARK: DEBUG demo hook

    /// "-demoSayMatchRound" (Games Spec §6): auto-taps the correct tile
    /// ~2.5s after any Round A appears, so a scripted sim run can play
    /// through a full set (and voice-off runs, which are all Round A) with
    /// no touch injection needed.
    private func maybeRunDemoAutoAnswer() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-demoSayMatchRound") else { return }
        let targetID = round.targetID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard successWord == nil, correctTileID == nil else { return }
            handleTap(targetID)
        }
        #endif
    }
}
