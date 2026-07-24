import SwiftUI

/// The canonical GameKit letter/word tile look (Games Spec §1, folded into
/// the Design Direction §1 paper system): a rounded-14 "paper" tile -- flat
/// fill, glossy top highlight, a white 3pt inner stroke (matching
/// `PaperKeyButton`'s look so every tappable surface in a game reads as the
/// same material), and a soft drop shadow that lifts slightly under touch.
/// Parameterized by fill color and tile size so every game's tiles -- Word
/// Hunt's letters, Say & Match's word tiles, Missing Letter's tray tiles,
/// Spelling Builder's slots, Memory's cards -- share one visual recipe
/// without sharing layout.
///
/// THE one paper-tile implementation (Design Direction §4's tile-chrome
/// fold-in): this `ButtonStyle` covers real `Button` tiles, and
/// `paperTileFace()` below covers the non-button faces (Memory's card face,
/// Spelling Builder's slots, drag-gesture-driven tray tiles) that need the
/// exact same recipe applied as a plain modifier instead.
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
        let active = press == .lift ? pressed : false
        configuration.label
            .modifier(PaperTileChromeModifier(fill: fill, size: size, corner: corner,
                                              lifted: active,
                                              pressedDown: press == .pressDown && pressed))
    }
}

/// The non-`Button` variant of `GameTileStyle`'s exact recipe (Design
/// Direction §4): applies as a plain view modifier so it can dress a Memory
/// card face, a Spelling Builder slot, or a drag-gesture tray tile -- none of
/// which are real `Button`s, so `GameTileStyle` itself (a `ButtonStyle`)
/// can't apply to them. `lifted` mirrors `GameTileStyle(press: .lift)`'s
/// pressed state (driven by whatever "is this tile airborne/active" signal
/// the caller already has, e.g. a drag coordinator's `draggingTile`), since
/// these tiles use custom `DragGesture`s instead of a button's own
/// `isPressed`.
extension View {
    func paperTileFace(fill: Color, size: CGSize? = nil, corner: CGFloat = 14, lifted: Bool = false) -> some View {
        modifier(PaperTileChromeModifier(fill: fill, size: size, corner: corner, lifted: lifted, pressedDown: false))
    }
}

private struct PaperTileChromeModifier: ViewModifier {
    let fill: Color
    var size: CGSize?
    var corner: CGFloat = 14
    var lifted: Bool = false
    var pressedDown: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = lifted && !reduceMotion
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let shadowRadius: CGFloat = active ? 10 : 6
        let shadowY: CGFloat = active ? 6 : 3
        let shadowOpacity: Double = pressedDown ? 0.08 : 0.16

        return Group {
            if let size {
                content.frame(width: size.width, height: size.height)
            } else {
                content
            }
        }
        .background(
            ZStack {
                shape.fill(fill)
                // Glossy top highlight: a soft white gradient over the
                // upper half only, giving the flat fill a lit, glass-like
                // top edge without a full glassmorphism material.
                LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)],
                               startPoint: .top, endPoint: .center)
                    .clipShape(shape)
                shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 3)
            }
        )
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        .scaleEffect(active ? 1.06 : (pressedDown ? 0.96 : 1.0))
        .animation(Theme.Motion.tileLift, value: active)
        .animation(Theme.Motion.tileLift, value: pressedDown)
    }
}
