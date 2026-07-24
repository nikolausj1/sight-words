import SwiftUI

// MARK: - SayMatchTile

/// One floating word tile (Games Spec §3.2: "simple floating ChunkyKey-ish
/// tiles... no balloons"). Bobs gently in place forever; a caller drives
/// `isHighlighted` (the correct tile, on a correct tap) and `isDrifted`
/// (every other tile, drifting off-screen) -- this view owns only its own
/// idle motion and appearance, never scoring.
struct SayMatchTile: View {
    let text: String
    var fastBob = false
    var isHighlighted = false
    var isDrifted = false
    /// 0-based position among this round's tiles (a plain board index, not
    /// an identity) -- phase-shifts this tile's bob so 3-4 tiles on the same
    /// board don't all rise and fall in lockstep.
    var bobIndex = 0
    var action: () -> Void = {}

    @State private var bobUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A fraction of the bob's own duration, unique-ish per index (mod 3 so
    /// a 4th+ tile just repeats an existing offset rather than growing
    /// unbounded) -- enough to visibly desync neighboring tiles without
    /// needing a real per-tile random seed.
    private var bobDelay: Double {
        Double(bobIndex % 3) * (fastBob ? 0.55 : 1.1) / 3
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Theme.Font.display(32))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        // Tap-to-choose tile, now a `PaperKeyButton` (Design Direction §4:
        // "SayMatch tiles adopt PaperKeyButton primary") instead of
        // `GameTileStyle` -- same tap-to-choose purpose `.pressDown` served,
        // folded into the one paper button system every kid-facing tap
        // target now shares.
        .buttonStyle(PaperKeyButton(fill: PaperTheme.skyBlue.accent, size: .primary))
        .frame(width: 130)
        .scaleEffect(isHighlighted && !reduceMotion ? 1.15 : 1.0)
        .opacity(isDrifted ? 0 : 1)
        .offset(x: isDrifted && !reduceMotion ? 260 : 0,
                y: (bobUp && !reduceMotion ? -6 : 0) + (isDrifted ? 30 : 0))
        .allowsHitTesting(!isDrifted && !isHighlighted)
        // Both beats share the "drift" token (Theme.Motion.drift's own doc
        // comment names this exact moment: "Say & Match's wrong tiles
        // drifting off-screen once the correct one is tapped") -- the
        // correct tile's own settle-into-focus move rides the same timing
        // so the two halves of this beat (everyone else drifting away, the
        // answer settling front-and-center) read as one coordinated motion
        // instead of two differently-timed animations.
        .animation(Theme.Motion.drift, value: isDrifted)
        .animation(Theme.Motion.drift, value: isHighlighted)
        .onAppear {
            guard !reduceMotion else { return }
            // Phase-shifted per tile (via `bobDelay`) so 3-4 tiles on the
            // same board don't bob in unison.
            withAnimation(.easeInOut(duration: fastBob ? 0.55 : 1.1).repeatForever(autoreverses: true).delay(bobDelay)) {
                bobUp = true
            }
        }
        .accessibilityLabel(text)
    }
}
