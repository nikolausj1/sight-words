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

/// Fixed top-left `SpeakerButton` (Games Spec §1 / Design Direction §2). Tap
/// replays `instruction`; the badge wobbles + sound-arc petals fan out while
/// `SpeechService` is audible (`SpeakerButton` itself owns that polling).
/// Thin wrapper kept as its own named type so every existing `GameScaffold`
/// call site (and any future one) keeps using "the game's instruction
/// speaker" as a concept, even though the visual is now the shared paper
/// `SpeakerButton`.
struct InstructionSpeaker: View {
    let instruction: GameInstruction

    var body: some View {
        SpeakerButton(action: { SpeechService.shared.speak(segments: instruction.segments) },
                      accessibilityLabel: "Replay instructions")
    }
}

// MARK: - HoldToExitButton

/// Press-and-hold exit gate (Games Spec §1 / Design Direction §2): the
/// shared paper `CloseButton` -- ~0.6s hold "unrolling ring" fill, brief-tap
/// teach wiggle. A quick tap alone still can't bail a child out of a round
/// by accident. Thin wrapper (see `InstructionSpeaker`'s doc comment for why
/// this stays a named type rather than every call site using `CloseButton`
/// directly).
struct HoldToExitButton: View {
    let onExit: () -> Void

    var body: some View {
        CloseButton(onClose: onExit)
    }
}

// MARK: - RoundProgressDots

/// Round-progress indicator (Games Spec §1): one small paper dot per round
/// in the set, filled through the current round with the game's own accent
/// family so the dots read as part of that game's paper palette rather than
/// the old generic gold/ink pair.
struct RoundProgressDots: View {
    /// 0-based index of the round currently in progress.
    let currentRound: Int
    let totalRounds: Int
    var family: PaperTheme.Family = PaperTheme.cream

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(totalRounds, 1), id: \.self) { i in
                Circle()
                    .fill(i <= currentRound ? family.accent : Color.white.opacity(0.5))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
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

/// The board container every game's board sits on (Games Spec §1), now a
/// `PaperWindow` in the game's own accent family (Design Direction §1/§3)
/// instead of a flat white card -- kills the "floating white card on empty
/// background" look everywhere a `GameScaffold` game is played.
struct GameBoardCard<Content: View>: View {
    var family: PaperTheme.Family = PaperTheme.cream
    @ViewBuilder let content: () -> Content

    /// `PaperWindow`'s own fixed content inset (two 16pt ring insets plus its
    /// extra 20pt content padding -- see `PaperWindow`'s `ringInset`).
    /// Duplicated here as a named constant (rather than wrapping
    /// `PaperWindow` opaquely with no visibility into its insets) so
    /// `gameBoardAreaSize` keeps reporting the REAL interior size content
    /// will get -- the same contract this environment key has always had.
    private let contentInset: CGFloat = 16 * 2 + 20

    var body: some View {
        // `GeometryReader` here measures the slot the surrounding VStack
        // actually proposes to this card (now trustworthy -- see `backdrop`'s
        // doc comment on `GameScaffold` for the layout bug this used to
        // inherit), then hands `content()` the exact, bounded interior size
        // (slot minus `PaperWindow`'s own ring insets) via `gameBoardAreaSize`
        // -- an explicit numeric `.frame()`, same pattern as the backdrop
        // fix, rather than a greedy `.frame(maxWidth: .infinity)` that a
        // misbehaving descendant could still blow past.
        GeometryReader { geo in
            let interior = CGSize(
                width: max(geo.size.width - contentInset * 2, 0),
                height: max(geo.size.height - contentInset * 2, 0)
            )
            PaperWindow(family: family) {
                content()
                    .environment(\.gameBoardAreaSize, interior)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - GameScaffold

/// Shared chrome for every GameKit game (Games Spec §1/§2, folded into the
/// Design Direction paper system): full-bleed backdrop, top row
/// (`InstructionSpeaker` + hold-to-exit `CloseButton`), the board window, and
/// round-progress dots -- all tinted in `gameID`'s own accent family (§3).
/// Speaks `instruction` once when the screen appears; callers update
/// `instruction` (e.g. between rounds) to change what the speaker replays.
struct GameScaffold<Board: View>: View {
    let instruction: GameInstruction
    let gameID: GameID
    let currentRound: Int
    let totalRounds: Int
    let onExit: () -> Void
    @ViewBuilder var board: () -> Board

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }
    private var family: PaperTheme.Family { PaperTheme.family(for: gameID) }

    var body: some View {
        // Outer `GeometryReader` gives the board window a real number to cap
        // itself against (Design Direction §4: "PaperWindow fills ~80% of
        // the safe area's smaller dimension... remaining margins show
        // backdrop") -- capped via `maxWidth/maxHeight` rather than forced
        // into a hard square, so a wide iPad-landscape board (Word Hunt's
        // grid + side word-list) can still use whatever aspect ratio its own
        // content needs, up to that cap, instead of being squeezed into a
        // square it was never laid out for.
        //
        // iPad (regular width) only: on a compact iPhone the screen's own
        // "minor dimension" IS its width, so 80% of it is already a small
        // number -- capping BOTH width and height to that same small number
        // starves vertically-stacked compact layouts (Word Hunt's grid-above-
        // list column, Games Spec §3.1) of the height they need, clipping
        // the word list against the window's own edge. iPhone screens are
        // small enough already that the "margins show backdrop" goal isn't
        // worth that regression -- the window can use the full available
        // space there instead.
        GeometryReader { screenGeo in
            let minorSide = min(screenGeo.size.width, screenGeo.size.height) * 0.8
            ZStack {
                backdrop
                VStack(spacing: Theme.Metric.gap) {
                    HStack {
                        InstructionSpeaker(instruction: instruction)
                        Spacer()
                        HoldToExitButton(onExit: onExit)
                    }
                    GameBoardCard(family: family, content: board)
                        .frame(maxWidth: isCompact ? .infinity : minorSide,
                               maxHeight: isCompact ? .infinity : minorSide)
                    RoundProgressDots(currentRound: currentRound, totalRounds: totalRounds, family: family)
                }
                .padding(isCompact ? Theme.Metric.gap : Theme.Metric.pad)
            }
            .frame(width: screenGeo.size.width, height: screenGeo.size.height)
        }
        // Belt-and-suspenders: makes this view always claim exactly the
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
