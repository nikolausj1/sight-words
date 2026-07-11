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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.Color.primary)
        }
        .modelContainer(container)
    }
}
