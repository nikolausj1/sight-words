import SwiftUI

// MARK: - BlankFrameKey

/// Every open blank's own on-screen frame, reported in
/// `MissingLetterCoordinator.spaceName` so `MissingLetterCoordinator.dragEnded`
/// can hit-test a drop against it. Keyed by blank id (not word/position) —
/// simplest possible shape for a straight `[UUID: CGRect]` merge.
struct BlankFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - MissingLetterBoardView

/// The worksheet card (Games Spec §3.4): every round's words, each rendered
/// with its blank(s) in place. 2 columns on iPad (a real worksheet grid);
/// 1 column on iPhone compact per this worker's brief ("single column
/// words").
struct MissingLetterBoardView: View {
    @ObservedObject var coordinator: MissingLetterCoordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        let columns = isCompact ? [GridItem(.flexible())]
                                 : [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: Theme.Metric.gap) {
            ForEach(coordinator.words) { word in
                MissingLetterWordView(word: word, coordinator: coordinator)
            }
        }
    }
}

// MARK: - MissingLetterWordView

/// One worksheet word: its letters in a row, blanks rendered as glowing
/// underlines, already-locked letters just plain text. Shows its own
/// in-place mini-confetti the instant every blank on it locks (Games Spec
/// §3.4: "word reflows seamless, word spoken, mini-confetti" — deliberately
/// smaller/local, not the shared center-screen `SuccessMoment`).
private struct MissingLetterWordView: View {
    let word: MissingLetterWordSlot
    @ObservedObject var coordinator: MissingLetterCoordinator

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                ForEach(Array(word.text.enumerated()), id: \.offset) { index, _ in
                    if word.isOpenBlank(at: index) {
                        // Safe: `isOpenBlank` only returns true when exactly
                        // one unlocked blank owns this position.
                        let blank = word.blanks.first { $0.position == index && !$0.locked }!
                        MissingLetterBlankView(blank: blank, coordinator: coordinator)
                    } else {
                        let letter = word.character(at: index)
                        Text(String(letter))
                            .font(Theme.Font.display(34))
                            .foregroundStyle(Theme.Color.ink)
                            .frame(width: 30)
                            .transition(.scale.combined(with: .opacity))
                            .onTapGesture {
                                if coordinator.tier == .t1 {
                                    GameAudio.shared.playLetter(letter)
                                } else {
                                    GameAudio.shared.playLetterSound(letter)
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.gap)
            .padding(.vertical, Theme.Metric.gap * 0.7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                            .strokeBorder(Theme.Color.primary.opacity(0.22), lineWidth: 2)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                // Games Spec §1's "tap-to-hear everywhere" for a word that's
                // fully readable right now — a still-blank word has nothing
                // sensible to speak yet (see `MissingLetterBlankView`'s own
                // tap, which speaks just that blank's needed letter instead).
                guard word.isComplete else { return }
                SpeechService.shared.speakWord(word.text)
            }

            if coordinator.celebratingWordID == word.id {
                GameConfettiBurst(particleCount: 20)
                    .allowsHitTesting(false)
            }
        }
        .animation(Theme.Motion.snappy, value: word.blanks)
    }
}

// MARK: - MissingLetterBlankView

/// One glowing, softly-pulsing blank (Games Spec §3.4). Reports its own
/// on-screen frame every layout pass (`BlankFrameKey`) and wiggles via the
/// shared `wrongShake` modifier when `coordinator.wigglingBlankID` names it
/// (Games Spec §1/§3.4: "the blank wiggles side-to-side... NO voice line" —
/// `wrongShake` itself never speaks, only shakes + a soft SFX, so reusing it
/// here already satisfies that). Deliberately NOT tap-to-hear: the blank is
/// a hidden letter, not a rendered one — Games Spec §1's "tap any letter
/// tile says the letter name" is about already-visible tiles (the tray, and
/// locked worksheet letters), not a free hint for what's still missing.
private struct MissingLetterBlankView: View {
    let blank: MissingLetterBlank
    @ObservedObject var coordinator: MissingLetterCoordinator
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 3) {
            Color.clear.frame(width: 30, height: 34)   // reserves the same box a revealed letter will occupy
            Capsule()
                .fill(Theme.Color.accent)
                .frame(width: 26, height: 5)
                .opacity(glow || reduceMotion ? 1 : 0.45)
                .shadow(color: Theme.Color.accent.opacity(glow ? 0.65 : 0.15), radius: glow ? 6 : 2)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: BlankFrameKey.self,
                                        value: [blank.id: geo.frame(in: .named(MissingLetterCoordinator.spaceName))])
            }
        )
        .wrongShake(Binding(
            get: { coordinator.wigglingBlankID == blank.id },
            set: { firing in if !firing { coordinator.clearWiggle() } }
        ))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
