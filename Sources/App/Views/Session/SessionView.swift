import SwiftUI
import SwiftData

/// Screen D — Practice Together (§6.4). Hosts the phase state machine owned by
/// `SessionCoordinator`; this view is just phase → subview routing.
struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator: SessionCoordinator

    init(profile: Profile, context: ModelContext, kind: SessionKind = .parentScored) {
        let service = LearningService(context: context)
        _coordinator = StateObject(wrappedValue: SessionCoordinator(service: service, speech: .shared,
                                                                     profile: profile, kind: kind))
    }

    var body: some View {
        ZStack {
            Theme.Color.bg.ignoresSafeArea()
            content
        }
        .onAppear {
            guard case .loading = coordinator.phase else { return }
            applyDemoArgsIfNeeded()
            coordinator.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .loading:
            ProgressView().tint(Theme.Color.primary)
        case .intro:
            NewWordIntroView(coordinator: coordinator)
        case .card, .feedback:
            PracticeCardView(coordinator: coordinator) { dismiss() }
        case .reteach:
            ReteachView(coordinator: coordinator)
        case .complete:
            SessionCompleteView(coordinator: coordinator) { dismiss() }
        }
    }

    private func applyDemoArgsIfNeeded() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoReteach") { coordinator.enableDemo(.reteach) }
        else if args.contains("-demoComplete") { coordinator.enableDemo(.complete) }
        else if args.contains("-demoSentence") { coordinator.enableDemo(.sentence) }
        #endif
    }
}
