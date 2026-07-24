import SwiftUI

/// The canonical GameKit letter/word tile look (Games Spec §1): a rounded-14
/// card, a glossy top highlight over a flat fill, and a soft drop shadow
/// that lifts slightly under touch. Parameterized by fill color and tile
/// size so every game's tiles -- Word Hunt's letters, Say & Match's word
/// tiles, Missing Letter's tray tiles, Spelling Builder's slots, Memory's
/// cards -- can share one visual recipe without sharing layout.
///
/// NOT yet migrated into any individual game folder as part of this pass --
/// each game keeps its own inline tile chrome for now (e.g.
/// `SayMatchTile.tileBackground`, `MemoryCardView.faceUp`); a follow-up
/// worker swaps those call sites over to this style.
///
/// Two interaction feels, chosen per tile purpose via `press`:
/// - `.lift` (the default): the tile rises slightly (scale 1.06) under
///   touch, like it's being picked up off the table -- fits tiles a child
///   drags (tray tiles waiting to be placed).
/// - `.pressDown`: the tile sinks slightly (scale 0.96), like a key being
///   pushed in -- fits tiles that are tapped-to-lock/tapped-to-choose rather
///   than dragged.
struct GameTileStyle: ButtonStyle {
    /// How the tile responds to touch: rise (`.lift`, the default -- for
    /// draggable tiles) or sink (`.pressDown` -- for tap-to-choose tiles).
    enum Press {
        case lift
        case pressDown
    }

    var fill: Color = Theme.Color.surface
    var size: CGSize = CGSize(width: 120, height: 96)
    var corner: CGFloat = 14
    var press: Press = .lift

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let scale: CGFloat = pressed ? (press == .lift ? 1.06 : 0.96) : 1.0
        let shadowRadius: CGFloat = pressed && press == .lift ? 10 : 6
        let shadowY: CGFloat = pressed && press == .lift ? 6 : 3
        let shadowOpacity: Double = pressed && press == .pressDown ? 0.08 : 0.16

        configuration.label
            .frame(width: size.width, height: size.height)
            .background(
                ZStack {
                    shape.fill(fill)
                    // Glossy top highlight: a soft white gradient over the
                    // upper half only, giving the flat fill a lit, glass-like
                    // top edge without a full glassmorphism material.
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)],
                                   startPoint: .top, endPoint: .center)
                        .clipShape(shape)
                    shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            .scaleEffect(scale)
            .animation(Theme.Motion.tileLift, value: pressed)
    }
}
