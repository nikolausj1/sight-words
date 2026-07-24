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
    /// Design Direction §8: drives `SceneBackdrop`'s day/evening/night art
    /// and every paper family's `.adaptive(night:)` tone shift on this
    /// screen. A plain `@ObservedObject` onto the shared singleton (not
    /// `@StateObject` -- this view doesn't own its lifecycle) so the whole
    /// screen redraws the moment the mode changes, whether from the clock,
    /// a parent's Settings override, or `-forceNight`.
    @ObservedObject private var timeOfDay = TimeOfDayService.shared
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
    /// Word Garden (Design Direction §7) entry point, next to the profile chip.
    @State private var showGarden = false
    /// Games shelf (Games Spec §5): which of the 5 `GameCatalog` games is
    /// currently pushed, if any.
    @State private var selectedGameID: GameID?

    // MARK: Home->game paper iris (Design Direction §4, WP-E4)
    //
    // A `fullScreenCover`'s own presentation is a fixed system animation
    // SwiftUI doesn't expose a way to replace outright, so the paper iris is
    // built from two halves that together read as one continuous motion:
    // this view grows an opaque paper circle from the tapped tile's on-screen
    // position until it fully covers the screen, THEN presents the cover
    // (invisibly, since the circle already hides the seam) -- and the
    // presented destination (`GameIrisRevealWrapper`, below) starts already
    // covered by that same circle and shrinks it back down to reveal the
    // game underneath. Reduce Motion drops the growing/shrinking circle for
    // a plain opacity crossfade on both halves.
    @State private var irisActive = false
    @State private var irisGrown = false
    @State private var irisOrigin: CGPoint = .zero
    @State private var irisColor: Color = Theme.Color.primary
    @State private var irisMaxDiameter: CGFloat = 0
    /// Each game tile's own on-screen frame (global coordinate space, so it
    /// stays comparable with the presented cover's own `GeometryReader`,
    /// which lives in a different view hierarchy entirely) -- captured live
    /// so the iris always grows from the ACTUAL tapped tile, not a guess.
    @State private var tileFrames: [GameID: CGRect] = [:]
    @State private var homeSize: CGSize = .zero
    /// This screen's own global frame -- lets `launchGame` convert a tile's
    /// global position into local coordinates for `irisMaxDiameter`'s
    /// same-space math, mirroring `irisOverlay`/`GameIrisRevealWrapper`'s own
    /// global -> local conversion.
    @State private var homeGlobalFrame: CGRect = .zero

    private var profile: Profile? { profiles.first(where: { $0.isActive }) ?? profiles.first }
    private var service: LearningService { LearningService(context: context) }
    private var nightActive: Bool { timeOfDay.mode == .night }

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
        GeometryReader { screenGeo in
            ZStack {
                // Design Direction §4/§8: full-bleed day/evening/night paper
                // scene -- THE backdrop, never a bare background color.
                SceneBackdrop()

                floraStrip

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
                        .padding(.bottom, 22)   // clear the pedestal ellipse (it rises above Play!)
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

                if irisActive {
                    irisOverlay(screenGeo: screenGeo)
                        .zIndex(50)
                }
            }
            .onAppear {
                homeSize = screenGeo.size
                homeGlobalFrame = screenGeo.frame(in: .global)
            }
            .onChange(of: screenGeo.size) { _, new in
                homeSize = new
                homeGlobalFrame = screenGeo.frame(in: .global)
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
            // Games Spec §6 tile: tricky words now rotate through the games
            // (needsReview deck); falls back to the card session internally
            // when the tricky pool is too small.
            TrickyGamesRotationView()
        }
        .fullScreenCover(item: $selectedGameID) { gameID in
            GameIrisRevealWrapper(origin: irisOrigin, color: irisColor) {
                GameCatalog.entry(for: gameID).destination()
            }
        }
        .fullScreenCover(isPresented: $showParent) {
            ParentAreaView()
        }
        .fullScreenCover(isPresented: $showGarden) {
            if let profile {
                GardenView(profile: profile, onClose: { showGarden = false })
            }
        }
        .onAppear {
            applyDemoArgsIfNeeded()
            syncTimeOfDay()
        }
    }

    private func syncTimeOfDay() {
        guard let profile else { return }
        TimeOfDayService.shared.apply(
            override: TimeOfDayService.Override(rawValue: profile.timeOfDayOverrideRaw) ?? .auto)
    }

    /// Greeting/ready-line (CX pass): sits directly above Play! as
    /// "Hi {name}! N words ready today" -- the "here's what's ready" lead-in
    /// to the hero button, not an orphaned status line at the screen bottom.
    /// §6.3: empty state (no active lists) keeps its own nudge to the parent
    /// area, unprefixed (nothing to greet into yet); nothing-due still greets
    /// by name with an invite to practice anyway. Design Direction §1/§4: now
    /// a paper chip (cream family) rather than bare text floating on the
    /// scene backdrop.
    private var greetingLine: some View {
        Text(greetingText)
            .font(Theme.Font.label(isCompact ? 17 : 20))
            .foregroundStyle(Theme.Color.ink)
            .multilineTextAlignment(.center)
            .padding(.vertical, isCompact ? 8 : 10)
            .padding(.horizontal, isCompact ? 18 : 24)
            .paperChipBackground(PaperTheme.cream, night: nightActive)
    }

    private var greetingText: String {
        guard hasActiveWords else { return "Ask a grown-up to pick your word lists" }
        let name = profile?.name ?? "Player 1"
        return readyCount > 0 ? "Hi \(name)! \(readyCount) words ready today"
                              : "Hi \(name)! All caught up — want to practice anyway?"
    }

    private func applyDemoArgsIfNeeded() {
        #if DEBUG
        guard !showGuided, !showSession, !showSolo, !showTricky, !showKidProfile, !showParent, !showGarden,
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
        } else if args.contains("-demoGarden") {
            // Word Garden (§7) screenshot hook: reuses `-demoDashboard`'s
            // existing seeding (a believable mix of fluent/mastered words)
            // rather than a bespoke garden-only seed routine — it already
            // no-ops once a profile has any progress at all, so it's safe to
            // call unconditionally here too.
            if let profile { service.seedDashboardDemoData(for: profile) }
            showGarden = true
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
                HStack(spacing: isCompact ? 6 : 8) {
                    profileChip
                    gardenChip
                }
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
    /// Design Direction §1: paper-chip edge treatment (white inner stroke +
    /// paper shadow) added around the existing flame-orange/cream palette,
    /// which already reads as warm/on-brand without needing a family swap.
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
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.75), lineWidth: 2))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
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
        .paperChipBackground(PaperTheme.cream, night: nightActive)
        .buttonStyle(PopButtonStyle())
    }

    /// Word Garden entry (Design Direction §7): a small leaf-green paper chip
    /// beside the profile chip. No dedicated garden-chip art exists, so this
    /// always uses the SF Symbol per §7's "small garden icon via SF symbol
    /// leaf.fill if no art" fallback.
    private var gardenChip: some View {
        Button {
            Feedback.fire(.keyTap)
            showGarden = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                if !isCompact {
                    Text("My Garden")
                        .font(Theme.Font.label(13))
                }
            }
            .padding(.vertical, isCompact ? 6 : 8)
            .padding(.horizontal, isCompact ? 10 : 14)
        }
        .foregroundStyle(PaperTheme.leafGreen.adaptive(night: nightActive).accent)
        .paperChipBackground(PaperTheme.leafGreen, night: nightActive)
        .buttonStyle(PopButtonStyle())
        .accessibilityLabel("My Garden")
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
    /// Play! full-width, shelf a 2-row grid. Design Direction §4: now sits on
    /// its own paper pedestal ring instead of floating bare on the backdrop.
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
        .background(playPedestal)
        .onAppear { startPlayBreathingIfNeeded() }
        .onChange(of: hasActiveWords) { _, _ in startPlayBreathingIfNeeded() }
    }

    /// The paper pedestal ring behind Play! (Design Direction §4): two
    /// concentric `PaperLayer`s in the shared `sky` family, sized bigger
    /// than the button itself so it reads as "Play! sits ON a paper disc"
    /// rather than the button merely getting a shadow.
    private var playPedestal: some View {
        let family = PaperTheme.sky.adaptive(night: nightActive)
        return ZStack {
            PaperLayer(fill: family.ring2, seed: 0x3001, variant: 0, jitter: 0.08)
            PaperLayer(fill: family.ring1, seed: 0x3001, variant: 1, jitter: 0.06, castsShadow: false)
        }
        .frame(width: isCompact ? 300 : 400, height: isCompact ? 130 : 190)
        .allowsHitTesting(false)
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

    /// Bottom-edge paper leaf/hill silhouette strip (Design Direction §5),
    /// sitting behind the hero group so the shelf tiles read as "floating on
    /// the flora strip" rather than on bare backdrop (§4's home composition
    /// rule). Purely decorative -- never intercepts touches. Only one
    /// (daytime-lit) art variant exists, so at night it's darkened toward
    /// the same deep-teal anchor `PaperTheme`'s night families use, rather
    /// than showing its bright cream/day coloring as a jarring seam under
    /// the night scene backdrop.
    @ViewBuilder
    private var floraStrip: some View {
        if Art.exists("paper-flora-strip") {
            VStack {
                Spacer(minLength: 0)
                Image("paper-flora-strip")
                    .resizable()
                    .scaledToFill()
                    .frame(height: isCompact ? 130 : 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(Color(red: 0.05, green: 0.16, blue: 0.19).opacity(nightActive ? 0.72 : 0))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
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
            launchGame(entry)
        } label: {
            VStack(spacing: 6) {
                shelfIconPlate(family: PaperTheme.family(for: entry.id)) {
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
        .background(tileFrameProbe(for: entry.id))
    }

    /// Home->game paper iris (§ above): grows an opaque paper circle (in the
    /// tapped game's own accent family, §3's wayfinding) from that tile's
    /// captured on-screen center until it fully covers the screen, then
    /// presents the real cover underneath the now-opaque circle. Reduce
    /// Motion drops the circle for a plain opacity crossfade instead (still
    /// gated the same way, just no growth/shrink).
    private func launchGame(_ entry: GameEntry) {
        Feedback.fire(.keyTap)
        let globalOrigin = tileFrames[entry.id].map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: homeGlobalFrame.midX, y: homeGlobalFrame.midY)
        irisOrigin = globalOrigin
        irisColor = PaperTheme.family(for: entry.id).adaptive(night: nightActive).ring1
        let localOrigin = CGPoint(x: globalOrigin.x - homeGlobalFrame.minX, y: globalOrigin.y - homeGlobalFrame.minY)
        irisMaxDiameter = Self.maxCornerDistance(from: localOrigin, in: homeSize) * 2.2
        irisGrown = false
        irisActive = true
        withAnimation(.easeInOut(duration: irisDuration)) { irisGrown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + irisDuration) {
            selectedGameID = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                irisActive = false
                irisGrown = false
            }
        }
    }

    private var irisDuration: TimeInterval { reduceMotion ? 0.3 : 0.45 }

    /// `irisOrigin` is captured in the `.global` coordinate space (see
    /// `tileFrameProbe`) so it stays meaningful once the destination cover
    /// presents in its own, entirely separate view hierarchy -- but that
    /// means it has to be converted back into THIS `ZStack`'s own local
    /// space (offset by this screen's own padding/safe-area inset) before
    /// `.position()` can use it here.
    @ViewBuilder
    private func irisOverlay(screenGeo: GeometryProxy) -> some View {
        let frame = screenGeo.frame(in: .global)
        let localOrigin = CGPoint(x: irisOrigin.x - frame.minX, y: irisOrigin.y - frame.minY)
        if reduceMotion {
            irisColor.opacity(irisGrown ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Circle()
                .fill(irisColor)
                .frame(width: 1, height: 1)
                .scaleEffect(irisGrown ? max(irisMaxDiameter, 1) : 0.001)
                .position(localOrigin)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// Live-captures one tile's on-screen frame (global coordinate space) so
    /// `launchGame` always grows the iris from where the tile ACTUALLY is,
    /// across both the iPad row layout and the iPhone grid layout, and
    /// across rotation.
    private func tileFrameProbe(for id: GameID) -> some View {
        GeometryReader { g in
            Color.clear
                .onAppear { tileFrames[id] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, new in tileFrames[id] = new }
        }
    }

    static func maxCornerDistance(from point: CGPoint, in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 2000 }
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                       CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        return corners.map { hypot($0.x - point.x, $0.y - point.y) }.max() ?? max(size.width, size.height)
    }

    /// Tricky Words as the shelf's 6th tile (Games Spec §5) — identical
    /// enable/disable rule and destination as the old standalone button.
    /// Disabled state (design review): a plain dimmed star + a single-line
    /// "All clear!" reads as "nothing to do here, nice job" instead of the
    /// old "No tricky\nwords" wrapping awkwardly across two lines. Not part
    /// of the home->game paper iris (§ above) -- it opens a `SessionView`,
    /// not a `GameCatalog` destination, so it keeps its plain `fullScreenCover`.
    private var trickyTile: some View {
        Button {
            Feedback.fire(.keyTap)
            showTricky = true
        } label: {
            VStack(spacing: 6) {
                shelfIconPlate(family: PaperTheme.warmRedOrange) {
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

    /// Shelf tile chrome (Design Direction §1/§3): a small paper chip in the
    /// tile's own game-accent family (Tricky gets `warmRedOrange`) instead of
    /// the old flat `Theme.Color.surface` plate -- white inner stroke + paper
    /// shadow, same "puffy paper" language as `PaperKeyButton`. Stays at its
    /// existing 72-80pt size (§1: "shelf tiles stay 84pt but adopt paper
    /// look" -- the icon plate itself is the ~80pt element within that).
    private func shelfIconPlate<Content: View>(family: PaperTheme.Family,
                                               @ViewBuilder content: () -> Content) -> some View {
        let f = family.adaptive(night: nightActive)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack { content() }
            .frame(width: isCompact ? 72 : 80, height: isCompact ? 72 : 80)
            .background(
                ZStack {
                    shape.fill(f.surface)
                    shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 3)
                }
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
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

// MARK: - Paper chip background (Home-local styling helper)

private extension View {
    /// Shared "paper chip" treatment for Home's small capsule chips
    /// (greeting, profile, garden) — Design Direction §1's white 3pt inner
    /// stroke + paper drop shadow, over the given family's `surface` tone
    /// (night-shifted when `night` is true, per §8's "no pure-white fills at
    /// night"). Kept local to `HomeView.swift` rather than added to
    /// `PaperTheme.swift` (this pass's edits there are scoped to the night
    /// families themselves, not new generic view helpers).
    func paperChipBackground(_ family: PaperTheme.Family, night: Bool) -> some View {
        let f = family.adaptive(night: night)
        return self
            .background(f.surface, in: Capsule())
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

// MARK: - GameIrisRevealWrapper

/// The presented-side half of the home->game paper iris (see `HomeView`'s
/// `launchGame`/`irisOverlay` doc comments): the destination starts already
/// covered by the same paper circle `HomeView` grew to fill the screen, then
/// shrinks it back down to reveal the real game underneath. Reduce Motion
/// swaps the shrinking circle for a plain opacity fade-out.
private struct GameIrisRevealWrapper<Content: View>: View {
    let origin: CGPoint
    let color: Color
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var maskDiameter: CGFloat = 4000
    @State private var crossfadeOpacity: Double = 1

    var body: some View {
        GeometryReader { geo in
            // `origin` arrived in the `.global` space captured back in
            // `HomeView` (a different view hierarchy entirely, since this is
            // a freshly presented `fullScreenCover` root) -- convert it into
            // THIS `GeometryReader`'s own local space the same way
            // `HomeView.irisOverlay` does, rather than assuming the two
            // hierarchies' local origins line up.
            let frame = geo.frame(in: .global)
            let localOrigin = CGPoint(x: origin.x - frame.minX, y: origin.y - frame.minY)
            ZStack {
                content()
                if reduceMotion {
                    color.opacity(crossfadeOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 1, height: 1)
                        .scaleEffect(maskDiameter)
                        .position(localOrigin)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                if reduceMotion {
                    withAnimation(.easeInOut(duration: 0.3)) { crossfadeOpacity = 0 }
                } else {
                    maskDiameter = HomeView.maxCornerDistance(from: localOrigin, in: geo.size) * 2.2
                    withAnimation(.easeInOut(duration: 0.45)) { maskDiameter = 0.001 }
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    RootView()
}
