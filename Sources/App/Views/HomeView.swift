import SwiftUI
import SwiftData

/// Screen C — Home hub (§6.3). Landscape layout: profile chip upper-left, gear
/// upper-right, three big mode keys centered. Practice Together is wired to a
/// real session; On My Own / Tricky Words stay visually enabled but
/// non-functional until their phases land.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @State private var showSession = false

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

    var body: some View {
        ZStack {
            VStack {
                topBar
                Spacer()
            }

            VStack(spacing: Theme.Metric.gap) {
                HStack(spacing: Theme.Metric.gap * 1.5) {
                    modeButton(title: "Practice\nTogether", systemImage: "person.2.fill",
                               base: Theme.Color.primary, enabled: hasActiveWords) {
                        Feedback.fire(.keyTap)
                        showSession = true
                    }
                    modeButton(title: "On My Own", systemImage: "person.fill",
                               base: Theme.Color.correct, enabled: hasActiveWords) {
                        // Wired to a real session in a later phase.
                    }
                    modeButton(title: "Tricky\nWords", systemImage: "star.fill",
                               base: Theme.Color.accent, enabled: hasActiveWords) {
                        // Wired to a real session in a later phase.
                    }
                }

                Text(statusLine)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.Metric.gap / 2)
            }
        }
        .padding(Theme.Metric.pad)
        .fullScreenCover(isPresented: $showSession) {
            if let profile {
                SessionView(profile: profile, context: context)
            }
        }
        .onAppear { applyDemoArgsIfNeeded() }
    }

    /// §6.3: empty state (no active lists) disables everything with a nudge to
    /// the parent area; nothing-due keeps buttons enabled with an invite line.
    private var statusLine: String {
        guard hasActiveWords else { return "Ask a grown-up to pick your word lists" }
        return readyCount > 0 ? "\(readyCount) words ready today"
                              : "All caught up — want to practice anyway?"
    }

    private func applyDemoArgsIfNeeded() {
        #if DEBUG
        guard !showSession else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoPractice") || args.contains("-demoReteach")
            || args.contains("-demoComplete") || args.contains("-demoSentence") {
            showSession = true
        }
        #endif
    }

    private var topBar: some View {
        HStack {
            profileChip
            Spacer()
            gearButton
        }
    }

    private var profileChip: some View {
        Button {
            // Placeholder: opens the kid profile overlay in a later phase.
        } label: {
            HStack(spacing: 10) {
                AvatarBadge(key: profile?.avatarSymbol ?? "avatar1", size: 40)
                Text(profile?.name ?? "Player 1")
                    .font(Theme.Font.label(17))
                    .foregroundStyle(Theme.Color.ink)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
        }
        .background(Theme.Color.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.Color.ink.opacity(0.08), lineWidth: 1))
        .buttonStyle(PopButtonStyle())
    }

    private var gearButton: some View {
        Button {
            // Placeholder: opens the parent area in a later phase.
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
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

    private func modeButton(title: String, systemImage: String, base: Color, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .semibold))
                Text(title)
                    .font(Theme.Font.label(20))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 220, height: 180)
        }
        .buttonStyle(ChunkyKeyStyle(base: enabled ? base : Theme.Color.gentle,
                                    deep: (enabled ? base : Theme.Color.gentle).shaded(by: -0.35),
                                    corner: Theme.Metric.corner))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }
}

#Preview {
    RootView()
}
