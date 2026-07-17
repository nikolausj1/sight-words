import SwiftUI
import SwiftData

/// Screen C — Home hub (§6.3). Landscape layout: profile chip upper-left, gear
/// upper-right, three big mode keys centered. All three modes open a real
/// session (Practice Together parent-scored, On My Own solo, Tricky Words the
/// needsReview/learning-only deck).
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @State private var showSession = false
    @State private var showSolo = false
    @State private var showTricky = false
    @State private var showKidProfile = false
    @State private var showParent = false

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

            VStack(spacing: Theme.Metric.gap) {
                modeButtons

                Text(statusLine)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.Metric.gap / 2)
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
        .fullScreenCover(isPresented: $showParent) {
            ParentAreaView()
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
        guard !showSession, !showSolo, !showTricky, !showKidProfile, !showParent else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoPractice") || args.contains("-demoReteach")
            || args.contains("-demoComplete") || args.contains("-demoSentence") {
            showSession = true
        } else if args.contains("-demoSolo") || args.contains("-demoSoloAnswer")
            || args.contains("-mockVoiceCheck") || args.contains("-mockVoiceCheckConfirm")
            || args.contains("-mockVoiceCheckConfirmRepeat") || args.contains("-mockVoiceCheckNudge")
            || args.contains("-demoHoldMic") || args.contains("-demoHoldMicHeld") {
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

    /// Regular (iPad): the original centered row of three big square keys,
    /// pixel-for-pixel unchanged. Compact (iPhone portrait): the same three
    /// keys stacked full-width so nothing clips off the side edges (was the
    /// baseline overflow bug — see `_review/phone-baseline.png`).
    @ViewBuilder
    private var modeButtons: some View {
        if isCompact {
            VStack(spacing: Theme.Metric.gap) {
                compactModeButton(title: "Practice Together", systemImage: "person.2.fill",
                                  base: Theme.Color.primary, enabled: hasActiveWords) {
                    Feedback.fire(.keyTap)
                    showSession = true
                }
                compactModeButton(title: "On My Own", systemImage: "person.fill",
                                  base: Theme.Color.correct, enabled: hasActiveWords) {
                    Feedback.fire(.keyTap)
                    showSolo = true
                }
                compactModeButton(title: trickyEnabled ? "Tricky Words" : "No tricky words right now!",
                                  systemImage: "star.fill",
                                  base: Theme.Color.accent, enabled: trickyEnabled) {
                    Feedback.fire(.keyTap)
                    showTricky = true
                }
            }
        } else {
            HStack(spacing: Theme.Metric.gap * 1.5) {
                modeButton(title: "Practice\nTogether", systemImage: "person.2.fill",
                           base: Theme.Color.primary, enabled: hasActiveWords) {
                    Feedback.fire(.keyTap)
                    showSession = true
                }
                modeButton(title: "On My Own", systemImage: "person.fill",
                           base: Theme.Color.correct, enabled: hasActiveWords) {
                    Feedback.fire(.keyTap)
                    showSolo = true
                }
                modeButton(title: trickyEnabled ? "Tricky\nWords" : "No tricky\nwords right now!",
                           systemImage: "star.fill",
                           base: Theme.Color.accent, enabled: trickyEnabled) {
                    Feedback.fire(.keyTap)
                    showTricky = true
                }
            }
        }
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

    /// Phone portrait mode key: full-width row (icon left, label right) at a
    /// fixed ~92pt height instead of the iPad's centered square key — same
    /// colors/icon/ChunkyKeyStyle so it reads as the same button, just reflowed.
    private func compactModeButton(title: String, systemImage: String, base: Color, enabled: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .semibold))
                    .frame(width: 40)
                Text(title)
                    .font(Theme.Font.label(19))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
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
