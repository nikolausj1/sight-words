import SwiftUI
import SwiftData

/// First-run flow (§6.2, near-clone of Math Tutor's OnboardingView): welcome ->
/// name -> level -> avatar -> ready. Shown by `RootView` under the splash until
/// `profile.onboarded` flips true. Profiles created from the parent area skip
/// this entirely (`onboarded = true` at creation).
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]

    private enum Step: Int, CaseIterable { case welcome, name, level, avatar, ready }
    @State private var step: Step = .welcome
    @State private var name = ""
    @State private var level = ""
    // The shield explorer opens front and center (carouselOrder puts him mid-row).
    @State private var avatarKey = "avatar1"
    @FocusState private var nameFocused: Bool

    /// Display label -> `Profile.level` code ("Pre-K" -> "PreK", "3+" -> "3").
    private let grades: [(label: String, code: String)] =
        [("Pre-K", "PreK"), ("K", "K"), ("1", "1"), ("2", "2"), ("3+", "3")]

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                Group {
                    switch step {
                    case .welcome: welcomePage
                    case .name:   namePage
                    case .level:  levelPage
                    case .avatar: avatarPage
                    case .ready:  readyPage
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing),
                                        removal: .move(edge: .leading))
                            .combined(with: .opacity))
                // Content lives in the upper half so the landscape keyboard
                // (bottom ~45%) never covers the name field.
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .padding(Theme.Metric.pad)
        }
        .animation(Theme.Motion.snappy, value: step)
        .onAppear {
            // Debug: jump straight to the level step for screenshots.
            if ProcessInfo.processInfo.arguments.contains("-demoOnboardingLevel") {
                name = name.isEmpty ? "Reader" : name
                step = .level
            }
        }
    }

    // Solid night-sky backdrop (§6.2/§7): the home hub stays a surprise until
    // onboarding finishes.
    private var backdrop: some View {
        LinearGradient(colors: [Theme.Color.onboardTop, Theme.Color.onboardBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).darkPlate(corner: 22)
            }
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
            // Progress: one capsule segment per step (welcome doesn't count).
            HStack(spacing: 6) {
                ForEach(Step.allCases.filter { $0 != .welcome }, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Theme.Color.accent : .white.opacity(0.2))
                        .frame(height: 8)
                }
            }
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: Pages

    /// A calm landing beat — no keyboard on the first beat (§6.2).
    private var welcomePage: some View {
        VStack(spacing: 24) {
            Text("Ready to become a word wizard?")
                .font(Theme.Font.display(44)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(radius: 4)
            Text("Big words. Short practice. You've got this.")
                .font(Theme.Font.body(22)).foregroundStyle(.white.opacity(0.85))
            Button {
                advance()
            } label: {
                Text("Let's go!")
                    .font(Theme.Font.display(28))
                    .padding(.horizontal, 48).padding(.vertical, 20)
            }
            .buttonStyle(ChunkyKeyStyle(base: Theme.Color.correct,
                                        deep: Theme.Color.correct.shaded(by: -0.35),
                                        corner: Theme.Metric.corner))
            .padding(.top, 12)
        }
    }

    private var namePage: some View {
        VStack(spacing: 22) {
            Text("What's your name, reader?")
                .font(Theme.Font.display(30)).foregroundStyle(.white)
                .shadow(radius: 4)
            TextField("", text: $name, prompt: Text("Your name")
                .foregroundStyle(.white.opacity(0.35)))
                .font(Theme.Font.display(26)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($nameFocused)
                .submitLabel(.next)
                .onSubmit { if canAdvance { advance() } }
                .onChange(of: name) { _, new in
                    if new.count > 12 { name = String(new.prefix(12)) }
                }
                .frame(maxWidth: 340)
                .padding(.vertical, 14).padding(.horizontal, 20)
                .darkPlate(corner: 18)
            nextButton
        }
        .onAppear { nameFocused = true }
    }

    private var levelPage: some View {
        VStack(spacing: 26) {
            Text("What grade are you in?")
                .font(Theme.Font.display(30)).foregroundStyle(.white)
                .shadow(radius: 4)
            HStack(spacing: 16) {
                ForEach(grades, id: \.code) { g in
                    Button {
                        level = g.code
                        Feedback.fire(.keyTap)
                    } label: {
                        Text(g.label)
                            .font(Theme.Font.display(g.label.count > 1 ? 20 : 28))
                            .foregroundStyle(.white)
                            .frame(width: 88, height: 88)
                    }
                    .buttonStyle(ChunkyKeyStyle(base: Theme.Color.primary,
                                                deep: Theme.Color.primary.shaded(by: -0.35),
                                                corner: 44))
                    .overlay {
                        if level == g.code {
                            Circle().strokeBorder(Theme.Color.accent, lineWidth: 4)
                                .shadow(color: Theme.Color.accent.opacity(0.7), radius: 8)
                        }
                    }
                    .scaleEffect(level == g.code ? 1.12 : 1)
                    .animation(Theme.Motion.celebrate, value: level)
                }
            }
            nextButton
        }
    }

    private var avatarPage: some View {
        VStack(spacing: 18) {
            Text("Pick your reader!")
                .font(Theme.Font.display(30)).foregroundStyle(.white)
                .shadow(radius: 4)
            AvatarCarousel(selected: $avatarKey, itemSize: 230)
            nextButton
                .padding(.top, 20)
        }
    }

    private var readyPage: some View {
        VStack(spacing: 24) {
            AvatarBadge(key: avatarKey, size: 230)
                .shadow(color: Theme.Color.accent.opacity(0.4), radius: 20)
            Text("You're ready, \(name.trimmingCharacters(in: .whitespaces))!")
                .font(Theme.Font.display(46)).foregroundStyle(.white)
                .shadow(radius: 4)
            Button {
                finish()
            } label: {
                Text("Start reading!")
                    .font(Theme.Font.display(28))
                    .padding(.horizontal, 48).padding(.vertical, 20)
            }
            .buttonStyle(ChunkyKeyStyle(base: Theme.Color.accent,
                                        deep: Theme.Color.accent.shaded(by: -0.35),
                                        corner: Theme.Metric.corner))
        }
    }

    private var nextButton: some View {
        Button {
            advance()
        } label: {
            Text("Next")
                .font(Theme.Font.display(26))
                .padding(.horizontal, 64).padding(.vertical, 18)
        }
        .buttonStyle(ChunkyKeyStyle(base: Theme.Color.correct,
                                    deep: Theme.Color.correct.shaded(by: -0.35),
                                    corner: Theme.Metric.corner))
        .disabled(!canAdvance)
        .opacity(canAdvance ? 1 : 0.4)
    }

    private var canAdvance: Bool {
        switch step {
        case .name:  return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .level: return !level.isEmpty
        default:     return true
        }
    }

    private func advance() {
        nameFocused = false
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    private func finish() {
        guard let p = activeProfiles.first else { return }
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.level = level
        p.avatarSymbol = avatarKey
        p.activeListIDs = LearningService.activeListIDs(forLevel: level)
        withAnimation(.easeOut(duration: 0.5)) { p.onboarded = true }
        try? context.save()
        // No sound here — the avatar-flight transition plays silently.
    }
}
