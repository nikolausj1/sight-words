import SwiftUI

// MARK: - SpellingSlotFrameKey

/// Every open slot's own on-screen frame, reported in
/// `SpellingBuilderCoordinator.spaceName` so `dragEnded` can hit-test a drop
/// against it. Mirrors `MissingLetter`'s `BlankFrameKey`.
struct SpellingSlotFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - SpellingBuilderBoardContent

/// The board itself (Games Spec §3.5): the current word's slots row, the
/// (T3-only) Peek button, and the tray -- plus the floating drag tile and the
/// 🎤 opener overlay, both top-level so they sit above everything else.
struct SpellingBuilderBoardContent: View {
    @ObservedObject var coordinator: SpellingBuilderCoordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        ZStack {
            VStack(spacing: isCompact ? Theme.Metric.gap : Theme.Metric.gap * 1.5) {
                Spacer(minLength: 0)
                SpellingBuilderSlotsRow(coordinator: coordinator)
                if coordinator.showPeekButton {
                    peekButton
                }
                Spacer(minLength: 0)
                SpellingBuilderTrayView(coordinator: coordinator)
            }
            .padding(Theme.Metric.gap)

            // The one tile currently airborne, floating above the slots row
            // and the tray -- see `MissingLetterCoordinator.draggingTile`'s
            // doc comment for why this is a top-level overlay duplicate.
            if let tile = coordinator.draggingTile {
                SpellingBuilderTileFace(letter: tile.letter, lifted: true)
                    .position(coordinator.dragLocation)
                    .allowsHitTesting(false)
            }

            if coordinator.voiceListening {
                SpellingBuilderVoiceOverlay(coordinator: coordinator)
            }
        }
        .coordinateSpace(name: SpellingBuilderCoordinator.spaceName)
        .onPreferenceChange(SpellingSlotFrameKey.self) { frames in
            for (id, frame) in frames { coordinator.updateSlotFrame(id, frame: frame) }
        }
        .onPreferenceChange(SpellingTrayFrameKey.self) { frames in
            for (id, frame) in frames { coordinator.updateTrayFrame(id, frame: frame) }
        }
    }

    private var peekButton: some View {
        Button(action: { coordinator.peek() }) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                Text("Peek")
            }
            .font(Theme.Font.label(16))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .darkPlate(corner: 16)
        .buttonStyle(PopButtonStyle())
        .disabled(coordinator.isPeeking)
        .opacity(coordinator.isPeeking ? 0.5 : 1)
        .accessibilityLabel("Peek at the word")
    }
}

// MARK: - SpellingBuilderSlotsRow

/// The target word's slots row (Games Spec §3.5): outlined cells while the
/// word is being built, fusing into one solid green pill the instant every
/// slot locks -- "their best moment... dividing lines vanish, single rounded
/// pill." The fuse is a crossfade (per-cell borders fading out, one shared
/// pill background fading in) plus the row's own spacing collapsing to 0, not
/// a geometry morph -- simplest way to sell "the dividers disappear" without
/// needing a bespoke shape animation.
struct SpellingBuilderSlotsRow: View {
    @ObservedObject var coordinator: SpellingBuilderCoordinator

    var body: some View {
        // The green fill is a `.background` on the HStack itself (sized to
        // the row's own frame after padding) rather than a sibling ZStack
        // layer -- an unconstrained `Shape` in a ZStack expands to fill
        // whatever space the parent proposes, which stretched the pill to
        // the whole board card instead of hugging the word.
        HStack(spacing: coordinator.isFused ? 0 : 10) {
            ForEach(coordinator.slots) { slot in
                SpellingBuilderSlotView(slot: slot, coordinator: coordinator)
            }
        }
        .padding(.horizontal, coordinator.isFused ? 22 : 4)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                .fill(Theme.Color.correct)
                .opacity(coordinator.isFused ? 1 : 0)
        )
        .animation(Theme.Motion.celebrate, value: coordinator.isFused)
        .contentShape(Rectangle())
        .onTapGesture {
            // Games Spec §1's "tap any rendered word says the word" -- only
            // meaningful once the word is actually readable (fused); an
            // in-progress word has nothing sensible to speak as a whole (a
            // single locked letter is tap-to-hear on its own, see below).
            guard coordinator.isFused, coordinator.words.indices.contains(coordinator.currentWordIndex) else { return }
            SpeechService.shared.speakWord(coordinator.words[coordinator.currentWordIndex].text)
        }
    }
}

private struct SpellingBuilderSlotView: View {
    let slot: SpellingBuilderSlot
    @ObservedObject var coordinator: SpellingBuilderCoordinator
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A slot shows its letter whenever it's actually locked, OR during a
    /// temporary "look" preview -- T3's initial 2s reveal and every Peek tap
    /// both reuse this exact same rendering (Games Spec §3.5).
    private var showsLetter: Bool {
        slot.locked || coordinator.showFullWordPreview || coordinator.isPeeking
    }

    var body: some View {
        ZStack {
            if showsLetter {
                Text(String(slot.letter))
                    .font(Theme.Font.display(38))
                    .foregroundStyle(coordinator.isFused ? .white : Theme.Color.ink)
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture {
                        guard slot.locked else { return }
                        GameAudio.shared.playLetter(slot.letter)
                    }
            } else {
                emptyOutline
            }
        }
        .frame(width: 42, height: 50)
        .background(
            Group {
                if !coordinator.isFused {
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                        .fill(Theme.Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                                .strokeBorder(Theme.Color.primary.opacity(0.3), lineWidth: 2)
                        )
                }
            }
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SpellingSlotFrameKey.self,
                                        value: [slot.id: geo.frame(in: .named(SpellingBuilderCoordinator.spaceName))])
            }
        )
        .wrongShake(Binding(
            get: { coordinator.wigglingSlotID == slot.id },
            set: { firing in if !firing { coordinator.clearWiggle() } }
        ))
        .animation(Theme.Motion.snappy, value: showsLetter)
    }

    private var emptyOutline: some View {
        Capsule()
            .fill(Theme.Color.accent)
            .frame(width: 28, height: 5)
            .opacity(glow || reduceMotion ? 1 : 0.45)
            .shadow(color: Theme.Color.accent.opacity(glow ? 0.65 : 0.15), radius: glow ? 6 : 2)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

// MARK: - SpellingBuilderVoiceOverlay

/// The 🎤 opener beat (Games Spec §3.5): "Say the word, then build it!" --
/// shown while `coordinator.voiceListening`, mirrors
/// `WordHuntVoiceBeatOverlay`'s look. Purely presentational; all of the
/// listening/timeout/self-hearing-guard logic lives in the coordinator.
struct SpellingBuilderVoiceOverlay: View {
    @ObservedObject var coordinator: SpellingBuilderCoordinator
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(coordinator.voiceFlashCorrect ? Theme.Color.correct : .white)
                    .scaleEffect(pulse && !reduceMotion ? 1.15 : 1.0)
                Text("Say it!")
                    .font(Theme.Font.label(20))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .darkPlate(corner: 26)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
    }
}
