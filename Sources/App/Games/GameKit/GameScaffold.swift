import SwiftUI

// MARK: - GameInstruction

/// One spoken instruction line for a game screen: a fixed `PhraseClip` (so it
/// gets a real Rachel clip when one exists, per Games Spec §4) plus an
/// optional trailing word (e.g. "Which word did you hear? … cat"). Every
/// `GameScaffold` speaks its `instruction` once on appear, and the
/// `InstructionSpeaker` replays it on tap (Games Spec §1: "tap → replays the
/// current instruction line").
struct GameInstruction: Equatable {
    let phrase: PhraseClip
    let word: String?

    init(_ phrase: PhraseClip, word: String? = nil) {
        self.phrase = phrase
        self.word = word
    }

    var segments: [SpeechSegment] {
        var segs: [SpeechSegment] = [.phrase(phrase)]
        if let word {
            segs.append(.pause(0.25))
            segs.append(.word(word))
        }
        return segs
    }

    static func == (lhs: GameInstruction, rhs: GameInstruction) -> Bool {
        lhs.phrase.slug == rhs.phrase.slug && lhs.word == rhs.word
    }
}

// MARK: - InstructionSpeaker

/// Fixed top-left darkPlate speaker button (Games Spec §1). Tap replays
/// `instruction`; the icon pulses while `SpeechService` is audible. Polls
/// `SpeechService.shared.isSpeakingAloud` on a light timer rather than
/// requiring a `@Published` hook -- that property is already a plain
/// (pollable) computed var, so no changes to `SpeechService` were needed.
struct InstructionSpeaker: View {
    let instruction: GameInstruction
    @State private var isSpeaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            SpeechService.shared.speak(segments: instruction.segments)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .scaleEffect(isSpeaking && !reduceMotion ? 1.12 : 1.0)
        }
        .darkPlate(corner: 26)
        .buttonStyle(PopButtonStyle())
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isSpeaking)
        .accessibilityLabel("Replay instructions")
        .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in
            let speaking = SpeechService.shared.isSpeakingAloud
            if speaking != isSpeaking { isSpeaking = speaking }
        }
    }
}

// MARK: - HoldToExitButton

/// Press-and-hold exit gate (Games Spec §1): ~0.6s hold with a radial fill
/// indicator, top-right X. A quick tap does nothing -- the child (or a
/// sibling) can't bail out of a round by accident.
struct HoldToExitButton: View {
    let onExit: () -> Void
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let holdDuration: TimeInterval = 0.6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .darkPlate(corner: 26)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 60) {
            progress = 0
            onExit()
        } onPressingChanged: { pressing in
            if pressing {
                withAnimation(reduceMotion ? nil : .linear(duration: holdDuration)) { progress = 1 }
            } else {
                withAnimation(Theme.Motion.quick) { progress = 0 }
            }
        }
        .accessibilityLabel("Exit game")
        .accessibilityHint("Press and hold to exit")
    }
}

// MARK: - RoundProgressDots

/// Round-progress indicator (Games Spec §1): one dot per round in the set,
/// filled through the current round.
struct RoundProgressDots: View {
    /// 0-based index of the round currently in progress.
    let currentRound: Int
    let totalRounds: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(totalRounds, 1), id: \.self) { i in
                Circle()
                    .fill(i <= currentRound ? Theme.Color.accent : Theme.Color.ink.opacity(0.15))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Board area size (environment)

/// The exact, bounded size available to a `GameBoardCard`'s `content()` --
/// i.e. the board slot's interior, inside its own padding. Zero until the
/// first layout pass measures it (see `GameBoardCard`). Reading this instead
/// of a game re-deriving its own board size (e.g. from `UIScreen.main.bounds`,
/// as `MemoryGameContentView` used to) is now safe: the root cause that made
/// a `GeometryReader` anywhere in this chain resolve to a wildly wrong size
/// (an inflated iPad-shaped `GameScaffold` on iPhone -- see `backdrop`'s doc
/// comment below) is fixed at the source, so this measurement is trustworthy
/// on every device/orientation GameKit supports.
private struct GameBoardAreaSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    var gameBoardAreaSize: CGSize {
        get { self[GameBoardAreaSizeKey.self] }
        set { self[GameBoardAreaSizeKey.self] = newValue }
    }
}

// MARK: - GameBoardCard

/// The orange-bordered rounded white card every game's board sits on (Games
/// Spec §1), over the warm backdrop.
struct GameBoardCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        // `GeometryReader` here measures the slot the surrounding VStack
        // actually proposes to this card (now trustworthy -- see `backdrop`'s
        // doc comment on `GameScaffold` for the layout bug this used to
        // inherit), then hands `content()` the exact, bounded interior size
        // (slot minus this card's own padding) via `gameBoardAreaSize` --
        // an explicit numeric `.frame()`, same pattern as the backdrop fix,
        // rather than a greedy `.frame(maxWidth: .infinity)` that a
        // misbehaving descendant could still blow past.
        GeometryReader { geo in
            let interior = CGSize(
                width: max(geo.size.width - Theme.Metric.pad * 2, 0),
                height: max(geo.size.height - Theme.Metric.pad * 2, 0)
            )
            content()
                .environment(\.gameBoardAreaSize, interior)
                .padding(Theme.Metric.pad)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                .strokeBorder(Theme.Color.accent, lineWidth: 3)
        )
    }
}

// MARK: - GameScaffold

/// Shared chrome for every GameKit game (Games Spec §1/§2): warm backdrop,
/// top row (InstructionSpeaker + hold-to-exit), the board card slot, and
/// round-progress dots. Speaks `instruction` once when the screen appears;
/// callers update `instruction` (e.g. between rounds) to change what the
/// speaker replays.
struct GameScaffold<Board: View>: View {
    let instruction: GameInstruction
    let currentRound: Int
    let totalRounds: Int
    let onExit: () -> Void
    @ViewBuilder var board: () -> Board

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: Theme.Metric.gap) {
                HStack {
                    InstructionSpeaker(instruction: instruction)
                    Spacer()
                    HoldToExitButton(onExit: onExit)
                }
                GameBoardCard(content: board)
                RoundProgressDots(currentRound: currentRound, totalRounds: totalRounds)
            }
            .padding(isCompact ? Theme.Metric.gap : Theme.Metric.pad)
        }
        // Belt-and-suspenders: makes this ZStack always claim exactly the
        // space it's proposed (the full screen, for a `fullScreenCover`
        // root), rather than leaving its own resolved size to whatever the
        // largest child reports. Does not by itself fix the backdrop bug
        // below (a plain `Image` still won by the same mechanism even with
        // this in place) but guards against a future oversized/unconstrained
        // sibling doing the same thing again.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            SpeechService.shared.speak(segments: instruction.segments)
        }
    }

    @ViewBuilder private var backdrop: some View {
        if Art.exists("game-backdrop") {
            // Root cause of the "chrome missing on iPhone" bug (Games Spec
            // §1): `game-backdrop`'s asset has only one (universal-scale)
            // representation, so a bare `Image(...).resizable().scaledToFill()`
            // -- with no explicit numeric frame -- reports its own *raw pixel
            // dimensions* (1184x864) as this ZStack's resolved size whenever
            // this ZStack's parent asks for it (confirmed by direct
            // measurement: `.frame(maxWidth: .infinity, maxHeight: .infinity)`
            // does NOT fix this -- greedy modifiers only affect concrete
            // proposals, and 1184x864 still wins). On any iPhone (narrower
            // than 1184pt) that inflated the WHOLE GameScaffold body -- not
            // just the backdrop -- so the InstructionSpeaker/HoldToExitButton
            // row and RoundProgressDots were laid out ~350pt outside the
            // visible screen (still in the view tree, just off-screen, which
            // is why they read as "missing" rather than mis-styled). iPads
            // are wide enough that 1184pt never exceeded the real screen
            // width, so it never surfaced there. `GameBoardCard`'s board-area
            // measurement was corrupted by this exact same inflation --
            // that's why `MemoryGameContentView` had to bypass SwiftUI
            // layout entirely and read `UIScreen.main.bounds` directly (see
            // its `boardAreaSize` doc comment).
            //
            // Fix: read the ACTUAL proposed size via `GeometryReader` and
            // force the image to those exact numeric points with `.frame`,
            // instead of trusting `.scaledToFill()`/`.frame(max:)` to shrink
            // an oversized intrinsic report on their own.
            GeometryReader { geo in
                Image("game-backdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
        } else {
            WarmBackdrop()
        }
    }
}

// MARK: - "Backdrop/chrome intermittently missing in screenshots" (investigated)
//
// Design review flagged screenshots where the backdrop/chrome sometimes
// didn't show up. Investigated by launching a game (`-demoGame wordHunt`) 5x
// on the iPad sim, screenshotting each launch, and comparing: all 5 came
// back pixel-consistent (backdrop, InstructionSpeaker, HoldToExitButton,
// RoundProgressDots all present every time) -- NOT reproducible in-app on
// iPad. The most likely explanation is the iPhone-only bug fixed above
// (`backdrop`'s doc comment): a design pass that screenshotted a mix of
// iPad and iPhone sims would have seen exactly this "chrome sometimes
// missing" pattern, entirely explained by device rather than by
// intermittency. Leaving this as a comment rather than a fix, per this
// pass's scope, since nothing further reproduced.
