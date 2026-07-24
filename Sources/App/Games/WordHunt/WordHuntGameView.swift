import SwiftUI
import SwiftData

/// `GameCatalog`'s registered destination for `.wordHunt` (Games Spec §2/
/// §3.1). Per the registration contract atop `GameCatalog.swift`, this view
/// "takes no parameters deliberately" -- it pulls `\.modelContext` and the
/// active profile from the environment itself, same as every other
/// session-launching view in this app.
struct WordHuntGameView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]
    @Query(sort: \Profile.createdAt) private var allProfiles: [Profile]

    private var profile: Profile? { activeProfiles.first ?? allProfiles.first }

    var body: some View {
        if let profile {
            WordHuntGameContentView(profile: profile, context: context)
        } else {
            // Defensive only: every real path into a `GameEntry.destination`
            // (the guided session, the Games shelf) already requires an
            // onboarded active profile to exist first.
            Color.clear
        }
    }
}

/// The actual game screen: builds its own `WordHuntCoordinator` (needing
/// `profile`/`context` as plain init params, not `@Environment`/`@Query`
/// reads inside a `@StateObject` initializer -- those aren't resolved yet at
/// that point; same reason `SessionView` takes them as init params too) and
/// hosts it in `GameScaffold`.
struct WordHuntGameContentView: View {
    @StateObject private var coordinator: WordHuntCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    init(profile: Profile, context: ModelContext) {
        let service = LearningService(context: context)
        var tierOverride: GameTier?
        #if DEBUG
        tierOverride = Self.demoTierOverride()
        #endif
        _coordinator = StateObject(wrappedValue: WordHuntCoordinator(profile: profile, service: service,
                                                                      tierOverride: tierOverride))
    }

    var body: some View {
        GameScaffold(
            instruction: GameInstruction(.findTheWords),
            gameID: .wordHunt,
            currentRound: coordinator.currentRoundIndex,
            totalRounds: coordinator.totalRounds,
            onExit: { dismiss() }
        ) {
            boardContent
        }
        .successMoment(word: successBinding) { coordinator.onSuccessMomentSettled() }
        .overlay { WordHuntVoiceBeatOverlay(coordinator: coordinator) }
        .overlay {
            if coordinator.showRoundCelebration {
                RoundCelebration(gameID: .wordHunt, onNext: { dismiss() })
            }
        }
        .onDisappear { coordinator.tearDown() }
    }

    private var successBinding: Binding<String?> {
        Binding(get: { coordinator.successWord }, set: { coordinator.successWord = $0 })
    }

    /// iPad landscape (regular): grid left, word list right (Games Spec
    /// §3.1: "3-5 list words shown right panel"). iPhone compact: grid on
    /// top, list below (this worker's brief for functional-not-broken
    /// compact layout) -- the grid still scales via `WordHuntBoardView`'s
    /// own `GeometryReader`.
    @ViewBuilder
    private var boardContent: some View {
        if isCompact {
            VStack(spacing: Theme.Metric.gap) {
                WordHuntBoardView(coordinator: coordinator)
                    .aspectRatio(1, contentMode: .fit)
                ScrollView {
                    WordHuntWordListView(coordinator: coordinator)
                }
            }
        } else {
            HStack(spacing: Theme.Metric.gap) {
                WordHuntBoardView(coordinator: coordinator)
                    .aspectRatio(1, contentMode: .fit)
                ScrollView {
                    WordHuntWordListView(coordinator: coordinator)
                }
                .frame(width: 240)
            }
        }
    }

    #if DEBUG
    /// `-demoGame wordHunt [tier]`: the tier arg (`t1`/`t2`/`t3`) after the
    /// game id is optional -- omitting it just plays whatever tier the
    /// profile's real ladder is currently at.
    private static func demoTierOverride() -> GameTier? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-demoGame"), idx + 1 < args.count, args[idx + 1] == "wordHunt" else { return nil }
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
