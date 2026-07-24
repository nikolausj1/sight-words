import SwiftUI

// MARK: - MemoryCardView

/// One physical card (Games Spec §3.3): warm-textured face-down back with a
/// star, 3D-rotation flip to a face-up word (or, at T3, a speaker icon --
/// tap while face-up replays the word). A just-matched pair gets a small
/// local confetti burst and a green outline; an optionally-banked pair (the
/// 🎤 "Say it to bank it!" bonus) keeps a small star badge in its corner.
struct MemoryCardView: View {
    let card: MemoryCard
    let isFaceUp: Bool
    let isMatched: Bool
    let isBanked: Bool
    let showConfetti: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A tiny settle bounce the instant a pair matches (Games Spec's shared
    /// tile-feedback pass) -- separate from `showConfetti`'s own short-lived
    /// burst so the scale pop still plays even once confetti clears.
    @State private var matchBounce = false

    var body: some View {
        Button(action: action) {
            ZStack {
                flippingFaces
                if showConfetti && !reduceMotion {
                    GameConfettiBurst(particleCount: 14)
                        .allowsHitTesting(false)
                }
                if isBanked {
                    starBadge
                }
            }
        }
        .buttonStyle(PopButtonStyle())
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                .strokeBorder(isMatched ? Theme.Color.correct : Color.clear, lineWidth: 3)
        )
        .scaleEffect(matchBounce ? 1.08 : 1.0)
        .animation(Theme.Motion.tileLift, value: matchBounce)
        .onChange(of: isMatched) { _, matched in
            guard matched, !reduceMotion else { return }
            matchBounce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { matchBounce = false }
        }
        .accessibilityLabel(card.face == .speaker ? "Speaker" : card.displayText)
    }

    /// The flip itself: both faces sit in an inner container rotated
    /// 0<->180; the face-up content is pre-rotated another 180 so it reads
    /// right-way-round once the outer rotation lands on 180 (the two
    /// rotations cancel), while at 0 the face-down back reads correctly and
    /// the pre-rotated face-up content is simply hidden (opacity 0).
    /// Deliberately kept OUTSIDE the confetti/star overlay above -- those
    /// must never inherit this rotation, or they'd render mirrored/upside
    /// down whenever the card is face-up.
    private var flippingFaces: some View {
        ZStack {
            faceDown.opacity(isFaceUp ? 0 : 1)
            faceUp
                .opacity(isFaceUp ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(isFaceUp ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(reduceMotion ? nil : Theme.Motion.cardFlip, value: isFaceUp)
    }

    private var faceDown: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [Theme.Color.primary.shaded(by: 0.18), Theme.Color.primary],
                                      startPoint: .top, endPoint: .bottom))
            if Art.exists("board-texture") {
                Image("board-texture")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.5)
                    .clipShape(shape)
            } else {
                Textures.noise
                    .opacity(0.12)
                    .blendMode(.overlay)
                    .clipShape(shape)
            }
            Image(systemName: "star.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
    }

    /// Fills whatever space `MemoryBoardView`'s grid math already imposed
    /// via its own outer `.frame(width:height:)` -- unlike a fixed-size
    /// tray tile, a card's footprint is computed per device/tier, so this
    /// mirrors `GameTileStyle`'s exact visual recipe (Games Spec §1's
    /// shared tile chrome) inline rather than forcing that style's own
    /// fixed constant size (GameKit is frozen this pass, so this can't
    /// route through a shared non-`Button` variant of it either).
    private var faceUp: some View {
        Group {
            switch card.face {
            case .word:
                Text(card.displayText)
                    .font(Theme.Font.display(26))
                    .foregroundStyle(Theme.Color.ink)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(6)
            case .speaker:
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.Color.primary)
            }
        }
        // `.background` below sizes itself to its *foreground* content --
        // without this, the chrome would hug the Text/Image's own tight
        // intrinsic size instead of filling the whole card the way the old
        // bare `shape.fill(...)` ZStack layer used to (a ZStack gives every
        // child its own full proposed size).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperTileFace(fill: Theme.Color.surface, corner: Theme.Metric.cornerSmall)
    }

    private var starBadge: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "star.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                    .padding(6)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            Spacer()
        }
        .padding(6)
        .allowsHitTesting(false)
    }
}
