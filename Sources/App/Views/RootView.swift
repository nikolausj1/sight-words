import SwiftUI
import SwiftData

extension Notification.Name {
    /// Posted by the parent area's "Start over" so the root re-runs onboarding
    /// (§6.12/§6.13), mirroring Math Tutor's RootView.
    static let startOverRequested = Notification.Name("startOverRequested")
}

/// Debug/screenshot stopgap (Games Spec §6): "-demoGame <id> [tier]" launches
/// straight into that GameKit game's real root view, bypassing the Games
/// shelf (WP-G8's home redesign, not wired yet). Generic across every
/// `GameID` so each game worker's own overnight verification pass shares one
/// launch-arg convention instead of five bespoke ones -- delete this (and its
/// one `.fullScreenCover` in `RootView.body`) once WP-G8 lands real shelf
/// navigation.
private struct DemoGameLaunch: Identifiable {
    let id: GameID

    static func fromProcessArguments() -> DemoGameLaunch? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-demoGame"), idx + 1 < args.count,
              let gameID = GameID(rawValue: args[idx + 1]) else { return nil }
        return DemoGameLaunch(id: gameID)
    }
}

/// The app root (§6.1/§6.2, ported from Math Tutor's RootView): ZStack of
/// HomeView, an onboarding overlay while the active profile isn't onboarded,
/// the onboarding-finale avatar flight, and a top-layer splash. No splash art
/// exists yet (`Art.exists("splash")` is false), so `showSplash` starts false
/// and nothing shows — the 1.6s+0.6s timing and demo suppression are still
/// implemented so wiring in real art later needs zero view changes.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]

    @State private var showSplash = Art.exists("splash")
        && !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-demo") })

    // Any "-demo*"/"-freshData" launch skips straight past the first-run gate,
    // except the onboarding demo hooks themselves, which need it to show.
    @State private var gateSuppressed = ProcessInfo.processInfo.arguments.contains {
        ($0.hasPrefix("-demo") || $0 == "-freshData")
            && $0 != "-demoOnboarding" && $0 != "-demoOnboardingLevel"
    }

    /// Forced on by "Start over" so onboarding shows even if the @Query hasn't
    /// yet reflected the wiped profile; cleared when onboarding completes.
    @State private var forceOnboarding = false

    private var needsOnboarding: Bool {
        if forceOnboarding { return true }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoOnboarding") || args.contains("-demoOnboardingLevel") {
            return !(activeProfiles.first?.onboarded ?? false)
        }
        if gateSuppressed { return false }
        return !(activeProfiles.first?.onboarded ?? true)
    }

    /// After onboarding, the chosen avatar flies from the ready page to its
    /// home in HomeView's profile chip (upper left).
    @State private var flightKey: String?

    /// See `DemoGameLaunch` above.
    @State private var demoGameLaunch = DemoGameLaunch.fromProcessArguments()

    var body: some View {
        ZStack {
            WarmBackdrop()
            HomeView()
            if needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(10)
            }
            if let key = flightKey {
                AvatarFlight(key: key) { flightKey = nil }
                    .zIndex(15)
            }
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .animation(.easeOut(duration: 0.5), value: needsOnboarding)
        .fullScreenCover(item: $demoGameLaunch) { launch in
            GameCatalog.entry(for: launch.id).destination()
        }
        .onAppear {
            guard showSplash else { return }
            scheduleSplashDismiss()
        }
        // "Start over" (parent area) posts this explicitly rather than relying
        // solely on the @Query onboarded-flip, which can stay stale across the
        // parent cover's dismissal (Math Tutor's fix, ported verbatim).
        .onReceive(NotificationCenter.default.publisher(for: .startOverRequested)) { _ in
            forceOnboarding = true
            gateSuppressed = false
            if Art.exists("splash") {
                showSplash = true
                scheduleSplashDismiss()
            }
        }
        .onChange(of: activeProfiles.first?.onboarded) { old, onboarded in
            if onboarded == true {
                forceOnboarding = false
                if old == false { flightKey = activeProfiles.first?.avatarSymbol }
            }
            guard onboarded == false else { return }
            gateSuppressed = false
            if Art.exists("splash") {
                showSplash = true
                scheduleSplashDismiss()
            }
        }
    }

    private func scheduleSplashDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
        }
    }
}

/// The onboarding-finale hand-off: the chosen avatar sails from the ready
/// page's hero spot to the profile chip in the home hub's upper-left corner.
private struct AvatarFlight: View {
    let key: String
    let done: () -> Void
    @State private var arrived = false

    private let baseSize: CGFloat = 230
    private let chipSize: CGFloat = 40
    private let chipCenter = CGPoint(x: 57, y: 64)   // HomeView's profile chip avatar

    var body: some View {
        GeometryReader { geo in
            AvatarBadge(key: key, size: baseSize)
                .scaleEffect(arrived ? chipSize / baseSize : 1)
                .shadow(color: .black.opacity(0.3), radius: arrived ? 3 : 14,
                        y: arrived ? 2 : 6)
                .position(arrived ? chipCenter
                          : CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.33))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).delay(0.08)) { arrived = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) { done() }
        }
    }
}

/// Full-bleed splash art over black; only rendered while `Art.exists("splash")`
/// (§6.1) — placeholder-first, so nothing shows until real art lands.
private struct SplashView: View {
    var body: some View {
        Color.black
            .overlay(Image("splash").resizable().scaledToFill())
            .clipped()
            .ignoresSafeArea()
            .accessibilityLabel("Sight Words")
    }
}
