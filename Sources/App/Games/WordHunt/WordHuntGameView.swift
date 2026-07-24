import SwiftUI
import SwiftData

/// `GameCatalog`'s registered destination for `.wordHunt` (Games Spec §2/
/// §3.1). Per the registration contract atop `GameCatalog.swift`, this view
/// "takes no parameters deliberately" -- it pulls `\.modelContext` and the
/// active profile from the environment itself, same as every other
/// session-launching view in this app.
struct WordHuntGameView: View {
    /// Tricky Words rotation mode (Design Direction §6): defaults to false so
    /// every existing call site (`GameCatalog`'s shelf destination) is
    /// unaffected -- only `TrickyGamesRotationView` passes `true`.
    var trickyOnly: Bool = false

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]
    @Query(sort: \Profile.createdAt) private var allProfiles: [Profile]

    private var profile: Profile? { activeProfiles.first ?? allProfiles.first }

    var body: some View {
        if let profile {
            WordHuntGameContentView(profile: profile, context: context, trickyOnly: trickyOnly)
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

    init(profile: Profile, context: ModelContext, trickyOnly: Bool = false) {
        let service = LearningService(context: context)
        var tierOverride: GameTier?
        #if DEBUG
        tierOverride = Self.demoTierOverride()
        #endif
        _coordinator = StateObject(wrappedValue: WordHuntCoordinator(profile: profile, service: service,
                                                                      tierOverride: tierOverride, trickyOnly: trickyOnly))
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
                RoundCelebration(gameID: .wordHunt, canPlayAgain: coordinator.canPlayAgain,
                                  onAgain: { coordinator.startNewSet() }, onNext: { dismiss() })
            }
        }
        .onDisappear { coordinator.tearDown() }
    }

    private var successBinding: Binding<String?> {
        Binding(get: { coordinator.successWord }, set: { coordinator.successWord = $0 })
    }

    /// iPad landscape (regular): grid centered left, word list right in its
    /// OWN small `PaperWindow` -- fixes the lead-review flag on
    /// `e2-scaffold.png` (the list used to render as bare white rows
    /// floating past the board window's edge, over open backdrop, which
    /// Design Direction §4 explicitly calls out as banned: "word lists/trays
    /// sit in their own smaller PaperWindows"). Both windows nest inside
    /// `GameScaffold`'s own outer board `PaperWindow`, so the whole board
    /// area still reads as one continuous stack of cut paper. iPhone
    /// compact: grid on top, list window below (this worker's brief for
    /// functional-not-broken compact layout) -- the grid still scales via
    /// `WordHuntBoardView`'s own `GeometryReader`.
    @ViewBuilder
    private var boardContent: some View {
        if isCompact {
            VStack(spacing: Theme.Metric.gap) {
                WordHuntBoardView(coordinator: coordinator)
                    .aspectRatio(1, contentMode: .fit)
                wordListWindow
                    .frame(maxHeight: 170)
            }
        } else {
            HStack(spacing: Theme.Metric.gap) {
                Spacer(minLength: 0)
                WordHuntBoardView(coordinator: coordinator)
                    .aspectRatio(1, contentMode: .fit)
                Spacer(minLength: 0)
                VStack {
                    Spacer(minLength: 0)
                    wordListWindow
                        .frame(width: 200, height: 280)
                    Spacer(minLength: 0)
                }
                .padding(.trailing, Theme.Metric.gap)
            }
        }
    }

    /// The word list's own small paper container (Design Direction §1/§4):
    /// same `leafGreen` accent family as the board window, offset-seeded so
    /// its blob outline doesn't trace identically to the outer window's.
    /// Fixed (not stretched to the full board height) and vertically
    /// centered by its caller -- letting it stretch as tall/narrow as the
    /// square board made its own organic blob wobble badly enough to visibly
    /// cross the outer board window's own edge near the top/bottom corners.
    private var wordListWindow: some View {
        PaperWindow(family: PaperTheme.leafGreen, seedOffset: 7) {
            ScrollView {
                WordHuntWordListView(coordinator: coordinator)
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
