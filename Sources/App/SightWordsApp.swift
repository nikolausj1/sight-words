import SwiftUI
import SwiftData

@main
struct SightWordsApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Profile.self, WordRecord.self,
                                           WordProgressRecord.self, PracticeSession.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        let service = LearningService(context: container.mainContext)
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        // "-demoOnboarding"/"-demoOnboardingLevel" need a fresh, un-onboarded
        // profile so the first-run flow is guaranteed to show (§B demo hooks).
        if args.contains("-freshData") || args.contains("-demoOnboarding")
            || args.contains("-demoOnboardingLevel") {
            service.wipeStore()
        }
        #endif
        service.bootstrap()
        #if DEBUG
        // Seeds a visible streak on the active profile without opening any
        // overlay (unlike "-demoDashboard", which seeds a streak too but only
        // behind the parent area cover) — for screenshotting the Home streak
        // chip on its own.
        if ProcessInfo.processInfo.arguments.contains("-demoStreak") {
            let profile = service.activeProfile()
            profile.streakDays = 3
            profile.lastPracticeDate = .now
            profile.onboarded = true   // land on Home directly for screenshots
            try? container.mainContext.save()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.Color.primary)
        }
        .modelContainer(container)
    }
}
