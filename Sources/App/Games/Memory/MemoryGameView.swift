import SwiftUI
import SwiftData

/// `GameCatalog`'s registered destination for `.memory` (Games Spec §2/§3.3).
/// Per the registration contract atop `GameCatalog.swift`, this view takes no
/// parameters -- it pulls `\.modelContext` and the active profile from the
/// environment itself, same as every other session-launching root view.
struct MemoryGameView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]
    @Query(sort: \Profile.createdAt) private var allProfiles: [Profile]

    private var profile: Profile? { activeProfiles.first ?? allProfiles.first }

    var body: some View {
        if let profile {
            MemoryGameContentView(profile: profile, context: context)
        } else {
            // Defensive only: every real path into a `GameEntry.destination`
            // (the guided session, the Games shelf) already requires an
            // onboarded active profile to exist first.
            Color.clear
        }
    }
}

/// The actual game screen: builds its own `MemoryCoordinator` (needing
/// `profile`/`context` as plain init params -- `@Environment`/`@Query` reads
/// aren't resolved yet inside a `@StateObject` initializer, same reason
/// `WordHuntGameContentView` takes them the same way) and hosts it in
/// `GameScaffold`.
struct MemoryGameContentView: View {
    @StateObject private var coordinator: MemoryCoordinator
    @Environment(\.dismiss) private var dismiss

    init(profile: Profile, context: ModelContext) {
        let service = LearningService(context: context)
        var tierOverride: GameTier?
        #if DEBUG
        tierOverride = Self.demoTierOverride()
        #endif
        _coordinator = StateObject(wrappedValue: MemoryCoordinator(profile: profile, service: service,
                                                                     tierOverride: tierOverride))
    }

    var body: some View {
        GameScaffold(
            instruction: GameInstruction(.matchTheCards),
            currentRound: coordinator.currentRoundIndex,
            totalRounds: coordinator.totalRounds,
            onExit: { dismiss() }
        ) {
            MemoryBoardView(coordinator: coordinator)
        }
        .overlay {
            if coordinator.bankingPairID != nil {
                MemoryBankBeatOverlay(coordinator: coordinator)
            }
        }
        .overlay {
            if coordinator.showRoundCelebration {
                RoundCelebration(onNext: { dismiss() })
            }
        }
        .onDisappear { coordinator.tearDown() }
    }

    #if DEBUG
    /// "-demoGame memory [tier]": the tier arg (`t1`/`t2`/`t3`) after the
    /// game id is optional -- omitting it just plays whatever tier the
    /// profile's real ladder is currently at (mirrors
    /// `WordHuntGameContentView.demoTierOverride()`).
    private static func demoTierOverride() -> GameTier? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-demoGame"), idx + 1 < args.count, args[idx + 1] == "memory" else { return nil }
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
