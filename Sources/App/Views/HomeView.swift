import SwiftUI
import SwiftData

/// Screen C — Home hub (§6.3). Landscape layout: profile chip upper-left, gear
/// upper-right, three big mode keys centered. All three modes open a real
/// session (Practice Together parent-scored, On My Own solo, Tricky Words the
/// needsReview/learning-only deck).
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    /// Idle "breathing" scale on the Play! hero (CX pass): gently invites a
    /// tap without being distracting. Only runs while Play! is actually
    /// enabled -- breathing a disabled/greyed key would read as broken.
    @State private var playBreathing = false
    /// "Play!" (Games Spec §5): the guided session -- cards then one embedded
    /// game round (`SessionKind.guided`).
    @State private var showGuided = false
    /// "Practice Together" (Games Spec §5): demoted to a smaller secondary
    /// button, but otherwise unchanged parent-scored session.
    @State private var showSession = false
    /// No home-screen button of its own anymore ("On My Own" folded into
    /// "Play!") -- kept solely so the `-demoSolo`/`-mockVoiceCheck*` debug
    /// hooks (still used by solo-mechanics screenshot runs) keep working.
    @State private var showSolo = false
    @State private var showTricky = false
    @State private var showKidProfile = false
    @State private var showParent = false
    /// Games shelf (Games Spec §5): which of the 5 `GameCatalog` games is
    /// currently pushed, if any.
    @State private var selectedGameID: GameID?

    private var profile: Profile? { profiles.first(where: { $0.isActive }) ?? profiles.first }
    private var service: LearningService { LearningService(context: context) }

    private var hasActiveWords: Bool {
        guard let profile else { return false }
        return service.hasActiveWords(for: profile)
    }
    private var readyCount: Int {
        guard let profile else { return 0 }
        return service.readyCount(for: profile)
    }
    private var trickyCount: Int {
        guard let profile else { return 0 }
        return service.countTricky(for: profile)
    }
    /// §6.3: "Tricky Words empty" disables the button regardless of the
    /// general empty/nothing-due state.
    private var trickyEnabled: Bool { hasActiveWords && trickyCount > 0 }

    var body: some View {
        ZStack {
            VStack {
                topBar
                Spacer()
            }

            // Games Spec §5 CX pass: a single centered composition instead of
            // Play! floating in dead space above a status line at the very
            // bottom. The greeting/ready-line now sits directly ABOVE Play!
            // (its natural "here's what's ready" lead-in), the hero group
            // (greeting + Play! + shelf) is vertically centered via matched
            // flexible spacers, and Practice Together is pushed down to sit
            // quietly near the bottom edge on its own.
            VStack(spacing: Theme.Metric.gap) {
                Spacer(minLength: 0)
                greetingLine
                playButton
                gamesShelf
                Spacer(minLength: 0)
                practiceSecondaryButton
                    .padding(.bottom, isCompact ? 4 : 8)
            }

            // In-hierarchy overlay (§6.11): NOT a fullScreenCover, so the
            // keyboard behaves normally while editing the name inline.
            if showKidProfile {
                KidProfileView(onClose: {
                    withAnimation(.easeOut(duration: 0.2)) { showKidProfile = false }
                })
                .zIndex(5)
            }
        }
        .padding(Theme.Metric.pad)
        .fullScreenCover(isPresented: $showGuided) {
            if let profile {
                SessionView(profile: profile, context: context, kind: .guided)
            }
        }
        .fullScreenCover(isPresented: $showSession) {
            if let profile {
                SessionView(profile: profile, context: context)
            }
        }
        .fullScreenCover(isPresented: $showSolo) {
            if let profile {
                SessionView(profile: profile, context: context, kind: .solo)
            }
        }
        .fullScreenCover(isPresented: $showTricky) {
            if let profile {
                SessionView(profile: profile, context: context, kind: .tricky)
            }
        }
        .fullScreenCover(item: $selectedGameID) { gameID in
            GameCatalog.entry(for: gameID).destination()
        }
        .fullScreenCover(isPresented: $showParent) {
            ParentAreaView()
        }
        .onAppear { applyDemoArgsIfNeeded() }
    }

    /// Greeting/ready-line (CX pass): sits directly above Play! as
    /// "Hi {name}! N words ready today" -- the "here's what's ready" lead-in
    /// to the hero button, not an orphaned status line at the screen bottom.
    /// §6.3: empty state (no active lists) keeps its own nudge to the parent
    /// area, unprefixed (nothing to greet into yet); nothing-due still greets
    /// by name with an invite to practice anyway.
    private var greetingLine: some View {
        Text(greetingText)
            .font(Theme.Font.label(isCompact ? 17 : 20))
            .foregroundStyle(Theme.Color.inkSoft)
            .multilineTextAlignment(.center)
    }

    private var greetingText: String {
        guard hasActiveWords else { return "Ask a grown-up to pick your word lists" }
        let name = profile?.name ?? "Player 1"
        return readyCount > 0 ? "Hi \(name)! \(readyCount) words ready today"
                              : "Hi \(name)! All caught up — want to practice anyway?"
    }

    private func applyDemoArgsIfNeeded() {
        #if DEBUG
        guard !showGuided, !showSession, !showSolo, !showTricky, !showKidProfile, !showParent,
              selectedGameID == nil else { return }
        let args = ProcessInfo.processInfo.arguments
        // Fixes a real collision: a game worker's own screenshot run passes
        // BOTH `-demoGame <id> [tier]` (handled by `RootView`, launching that
        // game's real root view directly) AND, when exercising a 🎤 step,
        // one of the shared `-mockVoiceCheck*` mock-pipeline args (Games Spec
        // §1/§6 — the SAME mock args solo card sessions use). Without this
        // guard, HomeView would ALSO see the `-mockVoiceCheck*` arg and stand
        // up a competing solo `SessionView` cover underneath `RootView`'s
        // `-demoGame` cover. Those mock args only ever imply a solo session
        // when no `-demoGame` launch is in play.
        let hasDemoGame = args.contains("-demoGame")
        if args.contains("-demoPractice") || args.contains("-demoReteach")
            || args.contains("-demoComplete") || args.contains("-demoSentence") {
            showSession = true
        } else if args.contains("-demoGuided") {
            showGuided = true
        } else if !hasDemoGame
            && (args.contains("-demoSolo") || args.contains("-demoSoloAnswer")
                || args.contains("-mockVoiceCheck") || args.contains("-mockVoiceCheckConfirm")
                || args.contains("-mockVoiceCheckConfirmRepeat") || args.contains("-mockVoiceCheckNudge")
                || args.contains("-demoHoldMic") || args.contains("-demoHoldMicHeld")) {
            // The voice-check mock args (§6.8) imply a solo session — that's
            // the only mode the overlay can appear in. The hold-mic demo args
            // (§ mic-mode) do too.
            showSolo = true
        } else if args.contains("-demoTricky") {
            if let profile { service.seedTrickyWordsIfNeeded(for: profile) }
            showTricky = true
        } else if args.contains("-demoKidProfile") {
            showKidProfile = true
        } else if args.contains("-demoParent") || args.contains("-demoDashboard") {
            showParent = true
        }
        #endif
    }

    /// Compact (iPhone portrait): same chip/gear content at a smaller scale so
    /// both corners clear the safe area on narrow widths. Regular (iPad):
    /// untouched — exact original sizes.
    private var isCompact: Bool { hSizeClass == .compact }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                profileChip
                if let profile, profile.streakDays >= 2 {
                    streakChip(days: profile.streakDays)
                }
            }
            Spacer()
            gearButton
        }
    }

    /// Home streak chip (§CX): only shown once there's something to celebrate
    /// (2+ days) — a lone day-1 chip would just be noise every single time.
    private func streakChip(days: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
            Text("\(days)-day streak")
                .font(Theme.Font.label(isCompact ? 12 : 14))
        }
        .foregroundStyle(Theme.Color.streakOrange)
        .padding(.vertical, isCompact ? 4 : 6)
        .padding(.horizontal, isCompact ? 10 : 12)
        .background(Theme.Color.streakCream)
        .clipShape(Capsule())
        .padding(.leading, isCompact ? 4 : 6)
    }

    private var profileChip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { showKidProfile = true }
        } label: {
            HStack(spacing: isCompact ? 8 : 10) {
                AvatarBadge(key: profile?.avatarSymbol ?? "avatar1", size: isCompact ? 32 : 40)
                Text(profile?.name ?? "Player 1")
                    .font(Theme.Font.label(isCompact ? 15 : 17))
                    .foregroundStyle(Theme.Color.ink)
            }
            .padding(.vertical, isCompact ? 6 : 8)
            .padding(.horizontal, isCompact ? 10 : 14)
        }
        .background(Theme.Color.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.Color.ink.opacity(0.08), lineWidth: 1))
        .buttonStyle(PopButtonStyle())
    }

    private var gearButton: some View {
        Button {
            showParent = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: isCompact ? 18 : 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)
        }
        .darkPlate()
        .overlay {
            // Gentle highlight nudging the parent toward list setup (§6.3 empty state).
            if !hasActiveWords {
                Circle().strokeBorder(Theme.Color.accent, lineWidth: 3)
            }
        }
        .buttonStyle(PopButtonStyle())
    }

    /// Games Spec §5 home redesign: a big primary "Play!" key (the guided
    /// session), the Games shelf below it, then "Practice Together" demoted
    /// to a small secondary button. Regular (iPad): Play! centered, shelf a
    /// single non-scrolling row that fits all 6 tiles. Compact (iPhone):
    /// Play! full-width, shelf a 2-row grid.
    private var playButton: some View {
        Button {
            Feedback.fire(.keyTap)
            showGuided = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: isCompact ? 28 : 40, weight: .bold))
                Text("Play!")
                    .font(Theme.Font.label(isCompact ? 24 : 30))
            }
            .frame(maxWidth: isCompact ? .infinity : nil)
            .frame(width: isCompact ? nil : 320, height: isCompact ? 84 : 120)
        }
        .buttonStyle(ChunkyKeyStyle(base: hasActiveWords ? Theme.Color.primary : Theme.Color.gentle,
                                    deep: (hasActiveWords ? Theme.Color.primary : Theme.Color.gentle).shaded(by: -0.35),
                                    corner: Theme.Metric.corner))
        .disabled(!hasActiveWords)
        .opacity(hasActiveWords ? 1 : 0.6)
        .scaleEffect(playBreathing ? 1.02 : 1.0)
        .onAppear { startPlayBreathingIfNeeded() }
        .onChange(of: hasActiveWords) { _, _ in startPlayBreathingIfNeeded() }
    }

    /// Gentle idle invite (CX pass): scale 1.0 -> 1.02 and back, 2.4s total
    /// round trip, eased. Only while enabled; skipped entirely under Reduce
    /// Motion.
    private func startPlayBreathingIfNeeded() {
        guard hasActiveWords, !reduceMotion else { playBreathing = false; return }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            playBreathing = true
        }
    }

    /// Games Spec §5: 5 `GameCatalog` games (their art icons via
    /// `Art.exists("gameicon-<id>")`, falling back to SF symbols) plus Tricky
    /// Words as a 6th tile with its existing behavior. Tier shown ONLY as
    /// subtle 1-3 dots under each game tile (never on the Tricky tile, which
    /// isn't a game and has no tier).
    ///
    /// Layout fix (design review, g8-home-ipad.png): the old iPad layout put
    /// all 6 tiles in a horizontal `ScrollView` sized narrower than their
    /// total width, so the 6th (Tricky) tile clipped at the screen edge with
    /// no visible affordance that more content existed. Fitting all 6 in a
    /// plain non-scrolling row with slightly tighter tiles reads far better
    /// on iPad's wide landscape canvas than a scroll a child has to discover.
    /// iPhone keeps its existing 2-row grid (already fits without scrolling).
    @ViewBuilder
    private var gamesShelf: some View {
        if isCompact {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(GameCatalog.games) { gameTile($0) }
                trickyTile
            }
        } else {
            HStack(spacing: 14) {
                ForEach(GameCatalog.games) { gameTile($0) }
                trickyTile
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private func gameTile(_ entry: GameEntry) -> some View {
        Button {
            Feedback.fire(.keyTap)
            selectedGameID = entry.id
        } label: {
            VStack(spacing: 6) {
                shelfIconPlate {
                    if Art.exists(entry.artIconKey) {
                        Image(entry.artIconKey)
                            .resizable()
                            .scaledToFit()
                            .frame(width: isCompact ? 46 : 50, height: isCompact ? 46 : 50)
                    } else {
                        Image(systemName: entry.symbolName)
                            .font(.system(size: isCompact ? 26 : 30, weight: .semibold))
                            .foregroundStyle(Theme.Color.primary)
                    }
                }
                Text(entry.title)
                    .font(Theme.Font.label(isCompact ? 12 : 13))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                tierDots(for: entry.id)
            }
            .frame(width: isCompact ? nil : 84)
            .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(ShelfTileButtonStyle())
    }

    /// Tricky Words as the shelf's 6th tile (Games Spec §5) — identical
    /// enable/disable rule and destination as the old standalone button.
    /// Disabled state (design review): a plain dimmed star + a single-line
    /// "All clear!" reads as "nothing to do here, nice job" instead of the
    /// old "No tricky\nwords" wrapping awkwardly across two lines.
    private var trickyTile: some View {
        Button {
            Feedback.fire(.keyTap)
            showTricky = true
        } label: {
            VStack(spacing: 6) {
                shelfIconPlate {
                    Image(systemName: "star.fill")
                        .font(.system(size: isCompact ? 26 : 30, weight: .semibold))
                        .foregroundStyle(trickyEnabled ? Theme.Color.accent : Theme.Color.gentle)
                        .opacity(trickyEnabled ? 1 : 0.6)
                }
                Text(trickyEnabled ? "Tricky Words" : "All clear!")
                    .font(Theme.Font.label(isCompact ? 12 : 13))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // Empty spacer keeps this tile's label baseline aligned with
                // the game tiles' tier-dots row below their title.
                Color.clear.frame(height: 5)
            }
            .frame(width: isCompact ? nil : 84)
            .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(ShelfTileButtonStyle())
        .disabled(!trickyEnabled)
        .opacity(trickyEnabled ? 1 : 0.55)
    }

    private func shelfIconPlate<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: isCompact ? 72 : 80, height: isCompact ? 72 : 80)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.Color.ink.opacity(0.08), lineWidth: 1))
    }

    /// 1-3 dots under a game tile showing `LearningService.gameTier` (Games
    /// Spec §5: "tier shown ONLY as subtle dots" — subtle meaning "not a
    /// number/badge", not "hard to see": filled + primary-tint for reached
    /// tiers, a light outline ring for the rest, slightly larger than the
    /// original low-opacity dots the design review flagged as too faint).
    private func tierDots(for id: GameID) -> some View {
        let tier = profile.map { service.gameTier(for: id, profile: $0) } ?? .t1
        return HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { i in
                Group {
                    if i <= tier.rawValue {
                        Circle().fill(Theme.Color.primary)
                    } else {
                        Circle().strokeBorder(Theme.Color.ink.opacity(0.25), lineWidth: 1.3)
                    }
                }
                .frame(width: 7, height: 7)
            }
        }
    }

    /// "Practice Together" (Games Spec §5): parents still need it, so it
    /// stays — just quieter, a small bordered button under the shelf instead
    /// of a big primary key.
    private var practiceSecondaryButton: some View {
        Button {
            Feedback.fire(.keyTap)
            showSession = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Practice Together")
                    .font(Theme.Font.label(14))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(Theme.Color.inkSoft)
        .disabled(!hasActiveWords)
        .opacity(hasActiveWords ? 1 : 0.5)
    }
}

#Preview {
    RootView()
}
