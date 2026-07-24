import SwiftUI
import SwiftData

/// `GameCatalog`'s registered destination for `.missingLetter` (Games Spec
/// §2/§3.4). Per the registration contract atop `GameCatalog.swift`, this
/// view "takes no parameters deliberately" -- it pulls `\.modelContext` and
/// the active profile from the environment itself, same as every other
/// session-launching view in this app (mirrors `WordHuntGameView`).
struct MissingLetterGameView: View {
    /// Tricky Words rotation mode (Design Direction §6) -- see
    /// `WordHuntGameView.trickyOnly`'s doc comment.
    var trickyOnly: Bool = false

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]
    @Query(sort: \Profile.createdAt) private var allProfiles: [Profile]

    private var profile: Profile? { activeProfiles.first ?? allProfiles.first }

    var body: some View {
        if let profile {
            MissingLetterGameContentView(profile: profile, context: context, trickyOnly: trickyOnly)
        } else {
            // Defensive only -- every real path into a `GameEntry.destination`
            // already requires an onboarded active profile to exist first.
            Color.clear
        }
    }
}

/// The actual game screen: builds its own `MissingLetterCoordinator` and
/// hosts it in `GameScaffold`. The worksheet (word grid) and tray both live
/// inside ONE shared `.coordinateSpace(name:)` so blank frames, tray-slot
/// frames, and every drag gesture's `location` all agree on the same
/// coordinate system for hit-testing (see `MissingLetterCoordinator`'s own
/// doc comment on `spaceName`).
struct MissingLetterGameContentView: View {
    @StateObject private var coordinator: MissingLetterCoordinator
    @Environment(\.dismiss) private var dismiss

    init(profile: Profile, context: ModelContext, trickyOnly: Bool = false) {
        let service = LearningService(context: context)
        var tierOverride: GameTier?
        #if DEBUG
        tierOverride = Self.demoTierOverride()
        #endif
        _coordinator = StateObject(wrappedValue: MissingLetterCoordinator(profile: profile, service: service,
                                                                          tierOverride: tierOverride, trickyOnly: trickyOnly))
    }

    var body: some View {
        GameScaffold(
            // No dedicated Missing Letter opener exists in `PhraseClip`
            // (Games Spec §4's fixed phrase list has none for this game) --
            // Dedicated instruction phrase (clip: phrase-fill-the-blanks).
            // line, and is the same choice `PlaceholderGameView` already
            // made for this game's id before this worker built the real
            // screen, so this keeps that established mapping rather than
            // picking a different approximate fit.
            instruction: GameInstruction(.fillTheBlanks),
            gameID: .missingLetter,
            currentRound: coordinator.currentRoundIndex,
            totalRounds: coordinator.totalRounds,
            onExit: { dismiss() }
        ) {
            boardContent
        }
        .overlay { MissingLetterVoiceBeatOverlay(coordinator: coordinator) }
        .overlay {
            if coordinator.showRoundCelebration {
                RoundCelebration(gameID: .missingLetter, canPlayAgain: coordinator.canPlayAgain,
                                  onAgain: { coordinator.startNewSet() }, onNext: { dismiss() })
            }
        }
        .onDisappear { coordinator.tearDown() }
    }

    @ViewBuilder
    private var boardContent: some View {
        ZStack {
            VStack(spacing: Theme.Metric.gap) {
                MissingLetterBoardView(coordinator: coordinator)
                Divider().opacity(0.15)
                MissingLetterTrayView(coordinator: coordinator)
            }

            // The one tile currently airborne, floating above both the
            // worksheet and the tray -- see `MissingLetterCoordinator.draggingTile`'s
            // own doc comment for why this is a top-level overlay duplicate
            // rather than transforming the tray tile in place.
            if let tile = coordinator.draggingTile {
                MissingLetterTileFace(letter: tile.letter, lifted: true)
                    .position(coordinator.dragLocation)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: MissingLetterCoordinator.spaceName)
        .onPreferenceChange(BlankFrameKey.self) { frames in
            for (id, frame) in frames { coordinator.updateBlankFrame(id, frame: frame) }
        }
        .onPreferenceChange(TrayFrameKey.self) { frames in
            for (id, frame) in frames { coordinator.updateTrayFrame(id, frame: frame) }
        }
    }

    #if DEBUG
    /// `-demoGame missingLetter [tier]`: same convention as
    /// `WordHuntGameView.demoTierOverride()` -- an optional trailing
    /// `t1`/`t2`/`t3` after the game id forces that tier for this one demo
    /// session without touching the profile's real persisted `TierLadder`.
    private static func demoTierOverride() -> GameTier? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-demoGame"), idx + 1 < args.count,
              args[idx + 1] == "missingLetter" else { return nil }
        guard idx + 2 < args.count else { return nil }
        switch args[idx + 2] {
        case "t1": return .t1
        case "t2": return .t2
        case "t3": return .t3
        default: return nil
        }
    }
    #endif
}
