import SwiftUI

/// Word Garden (Design Direction §7): a paper garden scene where every
/// `fluent`/`mastered` word this profile has ever reached is a small planted
/// sprout/flower/tree, positioned and varied deterministically from its own
/// word-text hash (`GardenPlant`/`GardenLayout`) -- no new persistence, no
/// currency, nothing to lose (plants never die once grown). Reached from
/// Home's `gardenChip`, next to the profile chip.
struct GardenView: View {
    let profile: Profile
    var onClose: () -> Void = {}

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isCompact: Bool { hSizeClass == .compact }

    /// Every word this profile has grown so far, oldest-mastered-looking
    /// first isn't tracked (no timestamp needed) -- sorted by text purely so
    /// the layout is stable render-to-render rather than reshuffling on
    /// every SwiftData re-fetch.
    private var plants: [GardenPlant] {
        profile.wordProgress
            .filter { $0.stateRaw == WordState.fluent.rawValue || $0.stateRaw == WordState.mastered.rawValue }
            .map { GardenPlant(word: $0.wordText, mastered: $0.stateRaw == WordState.mastered.rawValue) }
            .sorted { $0.word < $1.word }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                gardenBackdrop

                if plants.isEmpty {
                    emptyState
                } else {
                    let positions = GardenLayout.positions(for: plants, in: geo.size)
                    ForEach(plants) { plant in
                        if let point = positions[plant.word] {
                            GardenPlantBadge(plant: plant)
                                .position(point)
                        }
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        HoldToExitButton(onExit: onClose)
                    }
                    Spacer()
                    counterChip
                        .padding(.bottom, isCompact ? 18 : 30)
                }
                .padding(isCompact ? Theme.Metric.gap : Theme.Metric.pad)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            // Design Direction §7: the garden greets with its own clip.
            SpeechService.shared.speak(segments: [.phrase(.gardenGrow)])
        }
    }

    @ViewBuilder
    private var gardenBackdrop: some View {
        if Art.exists("garden-bed") {
            GeometryReader { geo in
                Image("garden-bed")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
        } else {
            SceneBackdrop()
        }
    }

    /// Empty state (§7): no words have reached `fluent` yet -- one static
    /// sprout, centered, with an encouraging line instead of a bare scene.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Group {
                if Art.exists("garden-sprout") {
                    Image("garden-sprout").resizable().scaledToFit().frame(width: 84, height: 84)
                } else {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(PaperTheme.leafGreen.accent)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 3)
            Text("Your garden is just starting!")
                .font(Theme.Font.label(isCompact ? 17 : 20))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    /// "N words growing" (§7) -- counts every planted word, sprout or bloom.
    private var counterChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill").font(.system(size: 13, weight: .semibold))
            Text("\(plants.count) word\(plants.count == 1 ? "" : "s") growing")
                .font(Theme.Font.label(14))
        }
        .foregroundStyle(Theme.Color.ink)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(PaperTheme.cream.adaptive(night: TimeOfDayService.shared.mode == .night).surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 2))
        .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
    }
}

// MARK: - GardenPlantBadge

/// One tappable plant (§7): tap -> hears the word + a small bounce. Sizing
/// leans on `GardenPlant.isTree` so the occasional tree anchors its row
/// instead of reading as an oversized flower.
private struct GardenPlantBadge: View {
    let plant: GardenPlant
    @State private var bounced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGFloat { plant.isTree ? 96 : 66 }

    var body: some View {
        Button {
            SpeechService.shared.speakWord(plant.word)
            guard !reduceMotion else { return }
            withAnimation(Theme.Motion.tileLift) { bounced = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(Theme.Motion.tileLift) { bounced = false }
            }
        } label: {
            Group {
                if Art.exists(plant.assetName) {
                    Image(plant.assetName).resizable().scaledToFit()
                } else {
                    Image(systemName: plant.mastered ? "sparkles" : "leaf.fill")
                        .foregroundStyle(plant.mastered ? PaperTheme.sunshineGold.accent : PaperTheme.leafGreen.accent)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
            .scaleEffect(bounced ? 1.16 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plant.word)
        .accessibilityHint("Say the word")
    }
}
