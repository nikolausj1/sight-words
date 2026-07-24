import Foundation
#if canImport(Combine)
import Combine
#endif

/// Design Direction §8 (night mode): drives which of the day/evening/night
/// paper scenes (`SceneBackdrop`, `Theme.swift`) and which `PaperTheme.Family`
/// tone shift (`PaperTheme.swift`'s `nighted()`) every screen shows. A single
/// shared `@MainActor` singleton (mirrors `SpeechService.shared`/
/// `VoiceCheckService.shared`'s existing pattern) rather than per-view state,
/// since the mode has to stay in sync across Home, every game, and the
/// session screens at once -- a view flipping its OWN local state on appear
/// would drift out of sync with every other already-visible screen the
/// moment the clock crosses a boundary or a parent changes the override
/// mid-session.
@MainActor
final class TimeOfDayService: ObservableObject {
    static let shared = TimeOfDayService()

    /// What the backdrop/paper tones actually show right now.
    enum Mode: String {
        case day, evening, night
    }

    /// The parent's Settings choice (§8: "Auto / Always day / Always night"),
    /// persisted on `Profile.timeOfDayOverrideRaw`. Deliberately has no
    /// `.evening` case of its own -- evening only ever shows up as `Auto`'s
    /// clock-computed dusk window, never something a parent picks directly.
    enum Override: String, CaseIterable {
        case auto, day, night
    }

    @Published private(set) var mode: Mode = .day

    private var override: Override = .auto
    private var timer: Timer?

    private init() {
        recompute()
        // Auto mode's clock windows (17h/19h/07h) need re-evaluating as real
        // time passes during a long-lived session -- a 5-minute poll is
        // plenty granular for hour-wide boundaries without being wasteful.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    /// Called whenever the active profile's stored override is known/changes
    /// (`HomeView.onAppear`, and immediately when the parent picks a new
    /// value in Settings) -- re-derives `mode` right away rather than waiting
    /// for the next poll.
    func apply(override: Override) {
        self.override = override
        recompute()
    }

    private func recompute() {
        #if DEBUG
        if Self.debugForceNight { mode = .night; return }
        #endif
        switch override {
        case .day: mode = .day
        case .night: mode = .night
        case .auto: mode = Self.clockMode()
        }
    }

    /// Design Direction §8: evening 17-19h, night 19h-07h, day the rest.
    static func clockMode(now: Date = .now, calendar: Calendar = .current) -> Mode {
        let hour = calendar.component(.hour, from: now)
        if hour >= 19 || hour < 7 { return .night }
        if hour >= 17 { return .evening }
        return .day
    }

    #if DEBUG
    /// Screenshot/verification hook (WP-E4): forces night mode regardless of
    /// override or clock, so night mode is capturable without waiting for
    /// the real clock or flipping a profile setting first.
    static var debugForceNight: Bool {
        ProcessInfo.processInfo.arguments.contains("-forceNight")
    }
    #endif
}
