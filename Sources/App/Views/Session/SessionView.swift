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
            WarmBackdrop()
            content
        }
        .onAppear {
            guard case .loading = coordinator.phase else { return }
            applyDemoArgsIfNeeded()
            coordinator.start()
        }
        // Mid-session exit (X button dismiss, or the parent swiping the sheet
        // away) must always release the mic and restore `.ambient` (§6.8).
        .onDisappear { coordinator.tearDownVoiceCheck() }
        // Guided weave (Games Spec §2, WP-G8): the embedded game round is
        // hosted as its OWN nested full-screen cover -- not inline in
        // `content` -- so the pushed game's `@Environment(\.dismiss)` (its
        // round-celebration "Next", its hold-to-exit gate) resolves to
        // dismissing just this cover, never the guided session underneath.
        // Mirrors `RootView`'s `-demoGame` launch hook verbatim. `onDismiss`
        // is the completion signal back to the coordinator -- see
        // `SessionCoordinator.completeGuidedGameRound()`'s doc comment for
        // why this was chosen over a bespoke `onGuidedComplete` closure.
        .fullScreenCover(item: gameRoundItem, onDismiss: { coordinator.completeGuidedGameRound() }) { gameID in
            GameCatalog.entry(for: gameID).destination()
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
        case .gameRound:
            // Rendered by the `fullScreenCover(item:)` above instead -- this
            // is just what's briefly visible underneath while that cover
            // animates in/out.
            Color.clear
        case .complete:
            SessionCompleteView(coordinator: coordinator) { dismiss() }
        }
    }

    /// `Binding<GameID?>` view onto `coordinator.phase`'s `.gameRound` case,
    /// for the `fullScreenCover(item:)` above. The setter is intentionally a
    /// no-op: SwiftUI writes `nil` back through it the moment the presented
    /// game's own `dismiss()` fires, but the coordinator's phase transition
    /// is driven by `onDismiss` (-> `completeGuidedGameRound()`), not by this
    /// binding, so there's nothing additional to do here.
    private var gameRoundItem: Binding<GameID?> {
        Binding<GameID?>(
            get: {
                if case .gameRound(let id) = coordinator.phase { return id }
                return nil
            },
            set: { _ in }
        )
    }

    private func applyDemoArgsIfNeeded() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoReteach") { coordinator.enableDemo(.reteach) }
        else if args.contains("-demoComplete") { coordinator.enableDemo(.complete) }
        else if args.contains("-demoSentence") { coordinator.enableDemo(.sentence) }
        else if args.contains("-demoSoloAnswer") { coordinator.enableDemo(.soloAnswer) }
        // Guided weave screenshot hook (Games Spec §6/WP-G8): auto-plays
        // every card `.gotIt` (reusing the `.complete` demo mode's existing
        // fast-forward) so a guided session reaches its embedded game round
        // in a few seconds instead of ~8 real cards.
        else if args.contains("-demoGuided") { coordinator.enableDemo(.complete) }
        #endif
    }
}
