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
    @Environment(\.horizontalSizeClass) private var hSizeClass

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
            MemoryBoardView(coordinator: coordinator, availableSize: boardAreaSize)
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

    /// Estimates `GameBoardCard`'s own interior size from `UIScreen.main.bounds`
    /// -- deliberately NOT a `GeometryReader` anywhere in this chain. Confirmed
    /// by direct measurement/isolation (temporary debug overlays and a
    /// hardcoded-fixed-size test view) that wrapping `GameScaffold` in a
    /// `GeometryReader` -- or nesting one inside `GameBoardCard`'s content, at
    /// any depth, in any shape (`LazyVGrid` vs. plain `ZStack`, with/without
    /// `.aspectRatio`, with/without a second VStack sibling) -- can make
    /// `GameScaffold`/`GameBoardCard` itself resolve to a wildly wrong size on
    /// some devices (an iPad-sized ~1098x686 board on an iPhone's real
    /// ~430pt-wide screen, or completely invisible content). A plain fixed-size
    /// view given directly as `GameScaffold`'s board content, with NO
    /// `GeometryReader` anywhere above it, renders correctly -- so this reads
    /// the device's real screen bounds directly instead. `UIScreen.main.bounds`
    /// is always reported in the device's native (portrait) point space
    /// regardless of interface orientation, so the larger dimension is used as
    /// width / smaller as height on iPad (landscape-locked) and vice versa on
    /// iPhone (portrait-locked) -- see `project.yml`'s
    /// `UISupportedInterfaceOrientations_iPad/iPhone` keys. Chrome overhead
    /// (outer VStack padding, the ~52pt instruction/exit button row, the
    /// ~10pt round-progress-dots row, `GameBoardCard`'s own inner padding) is
    /// then subtracted the same way `WordHuntBoardView`'s own board area is
    /// implicitly bounded by its `.aspectRatio` wrapping. Not pixel-exact, but
    /// it only needs to keep the board safely within the real card area.
    private var boardAreaSize: CGSize {
        let screenBounds = UIScreen.main.bounds.size
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let rootSize = isPad
            ? CGSize(width: max(screenBounds.width, screenBounds.height),
                     height: min(screenBounds.width, screenBounds.height))
            : CGSize(width: min(screenBounds.width, screenBounds.height),
                     height: max(screenBounds.width, screenBounds.height))

        let outerPad: CGFloat = hSizeClass == .compact ? Theme.Metric.gap : Theme.Metric.pad
        let buttonRowHeight: CGFloat = 52
        let dotsRowHeight: CGFloat = 10
        let cardInnerPad = Theme.Metric.pad
        let horizontalOverhead = outerPad * 2 + cardInnerPad * 2
        let verticalOverhead = outerPad * 2 + buttonRowHeight + Theme.Metric.gap + dotsRowHeight
            + Theme.Metric.gap + cardInnerPad * 2
        return CGSize(width: max(rootSize.width - horizontalOverhead, 100),
                      height: max(rootSize.height - verticalOverhead, 100))
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
