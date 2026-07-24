import SwiftUI
import SwiftData

/// `GameCatalog`'s registered destination for `.spellingBuilder` (Games Spec
/// §2/§3.5). Per the registration contract atop `GameCatalog.swift`, this
/// view "takes no parameters deliberately" -- it pulls `\.modelContext` and
/// the active profile from the environment itself, same as
/// `MissingLetterGameView`.
struct SpellingBuilderGameView: View {
    /// Tricky Words rotation mode (Design Direction §6) -- see
    /// `WordHuntGameView.trickyOnly`'s doc comment.
    var trickyOnly: Bool = false

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]
    @Query(sort: \Profile.createdAt) private var allProfiles: [Profile]

    private var profile: Profile? { activeProfiles.first ?? allProfiles.first }

    var body: some View {
        if let profile {
            SpellingBuilderGameContentView(profile: profile, context: context, trickyOnly: trickyOnly)
        } else {
            // Defensive only -- every real path into a `GameEntry.destination`
            // already requires an onboarded active profile to exist first.
            Color.clear
        }
    }
}

/// The actual game screen: builds its own `SpellingBuilderCoordinator` and
/// hosts it in `GameScaffold`. The slots row and tray both live inside ONE
/// shared `.coordinateSpace(name:)` (in `SpellingBuilderBoardContent`) so
/// slot frames, tray-slot frames, and every drag gesture's `location` all
/// agree on the same coordinate system for hit-testing.
struct SpellingBuilderGameContentView: View {
    @StateObject private var coordinator: SpellingBuilderCoordinator
    @Environment(\.dismiss) private var dismiss

    init(profile: Profile, context: ModelContext, trickyOnly: Bool = false) {
        let service = LearningService(context: context)
        var tierOverride: GameTier?
        #if DEBUG
        tierOverride = Self.demoTierOverride()
        #endif
        _coordinator = StateObject(wrappedValue: SpellingBuilderCoordinator(profile: profile, service: service,
                                                                            tierOverride: tierOverride, trickyOnly: trickyOnly))
    }

    var body: some View {
        GameScaffold(
            instruction: coordinator.currentInstruction,
            gameID: .spellingBuilder,
            currentRound: coordinator.currentWordIndex,
            totalRounds: coordinator.totalRounds,
            onExit: { dismiss() }
        ) {
            SpellingBuilderBoardContent(coordinator: coordinator)
        }
        .overlay {
            if coordinator.showRoundCelebration {
                RoundCelebration(gameID: .spellingBuilder, canPlayAgain: coordinator.canPlayAgain,
                                  onAgain: { coordinator.startNewSet() }, onNext: { dismiss() })
            }
        }
        .onDisappear { coordinator.tearDown() }
    }

    #if DEBUG
    /// "-demoGame spellingBuilder [tier]": same convention as
    /// `MissingLetterGameContentView.demoTierOverride()` -- an optional
    /// trailing `t1`/`t2`/`t3` after the game id forces that tier for this
    /// one demo session without touching the profile's real persisted
    /// `TierLadder`.
    private static func demoTierOverride() -> GameTier? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-demoGame"), idx + 1 < args.count,
              args[idx + 1] == "spellingBuilder" else { return nil }
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
