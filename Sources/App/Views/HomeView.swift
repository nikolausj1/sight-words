import SwiftUI

/// Screen C — Home hub (§6.3). Landscape layout: profile chip upper-left, gear
/// upper-right, three big mode keys centered. Buttons and chrome are placeholders
/// that don't do anything yet — later phases wire them to real sessions/screens.
struct HomeView: View {
    var body: some View {
        ZStack {
            VStack {
                topBar
                Spacer()
            }

            VStack(spacing: Theme.Metric.gap) {
                HStack(spacing: Theme.Metric.gap * 1.5) {
                    modeButton(title: "Practice\nTogether", systemImage: "person.2.fill",
                               base: Theme.Color.primary)
                    modeButton(title: "On My Own", systemImage: "person.fill",
                               base: Theme.Color.correct)
                    modeButton(title: "Tricky\nWords", systemImage: "star.fill",
                               base: Theme.Color.accent)
                }

                Text("12 words ready today")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.inkSoft)
                    .padding(.top, Theme.Metric.gap / 2)
            }
        }
        .padding(Theme.Metric.pad)
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
                AvatarBadge(key: "avatar1", size: 40)
                Text("Kiddo")
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
        .buttonStyle(PopButtonStyle())
    }

    private func modeButton(title: String, systemImage: String, base: Color) -> some View {
        Button {
            // Placeholder: wired to a real session in a later phase.
        } label: {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .semibold))
                Text(title)
                    .font(Theme.Font.label(20))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 220, height: 180)
        }
        .buttonStyle(ChunkyKeyStyle(base: base, deep: base.shaded(by: -0.35),
                                    corner: Theme.Metric.corner))
    }
}

#Preview {
    RootView()
}
