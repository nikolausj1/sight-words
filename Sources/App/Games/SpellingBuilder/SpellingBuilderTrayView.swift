import SwiftUI

// MARK: - SpellingTrayFrameKey

/// Every tray tile's own "home" frame, updated every layout pass regardless
/// of drag state (a tile stays laid out, just hidden, while airborne -- see
/// `SpellingBuilderTrayTileView`), so `SpellingBuilderCoordinator
/// .returnTileToTray` has somewhere real to animate a wrong/missed drop back
/// to. Mirrors `MissingLetter`'s `TrayFrameKey`.
struct SpellingTrayFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - SpellingBuilderTileFace

/// The shared chunky-key look for a scrambled letter tile (Games Spec §3.5:
/// "ChunkyKey tiles, lift/sparkle on touch") -- used at rest in the tray and,
/// scaled up with a deeper shadow, for the floating tile a drag is currently
/// carrying. Hand-rolled rather than `ChunkyKeyStyle` itself for the same
/// reason `MissingLetterTileFace` is: this tile needs its own custom
/// tap-vs-drag `DragGesture`, not a plain button tap, so `lifted` is driven
/// directly by "is this tile the one currently airborne" rather than a
/// `Button`'s `isPressed`.
struct SpellingBuilderTileFace: View {
    let letter: Character
    var lifted: Bool = false
    /// True only while the tray is still locked (voice opener / T3 look
    /// phase) -- dims the tile so its "not interactive yet" state reads
    /// clearly, without hiding the letters entirely (tap-to-hear still
    /// works the whole time, per Games Spec §1's "never gated").
    var inert: Bool = false

    var body: some View {
        Text(String(letter))
            .font(Theme.Font.display(28))
            .foregroundStyle(.white)
            .spellingBuilderTileChrome(fill: Theme.Color.primary, size: CGSize(width: 56, height: 56), lifted: lifted)
            .opacity(inert ? 0.6 : 1)
    }
}

// MARK: - SpellingBuilderTrayView

/// The scrambled tile tray (Games Spec §3.5): the word's own letters plus
/// (T2+) confusable-preferring decoys, in fixed shuffled order for the word.
/// Wraps via an adaptive grid so it behaves the same on iPad and
/// iPhone-compact, same approach as `MissingLetterTrayView`.
struct SpellingBuilderTrayView: View {
    @ObservedObject var coordinator: SpellingBuilderCoordinator

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Theme.Metric.gap)],
                  spacing: Theme.Metric.gap) {
            ForEach(coordinator.tray) { tile in
                SpellingBuilderTrayTileView(tile: tile, coordinator: coordinator)
            }
        }
    }
}

// MARK: - SpellingBuilderTrayTileView

/// One draggable tray tile. A single `DragGesture(minimumDistance: 0)`
/// disambiguates tap vs. drag itself (mirrors `MissingLetterTrayTileView`'s
/// exact approach) rather than layering a separate `onTapGesture` alongside
/// a `DragGesture` -- past `coordinator.dragChanged`'s own 6pt arm threshold
/// it's a drag; released before that, it's a tap (speaks the letter name,
/// always available per Games Spec §1, even before the tray unlocks).
private struct SpellingBuilderTrayTileView: View {
    let tile: SpellingBuilderTile
    @ObservedObject var coordinator: SpellingBuilderCoordinator

    var body: some View {
        SpellingBuilderTileFace(letter: tile.letter, inert: !coordinator.canInteractWithTray)
            // Hidden (not removed) while airborne: removing it would drop its
            // `SpellingTrayFrameKey` report, and `returnTileToTray` needs
            // that "home" frame to still be fresh for the return animation.
            .opacity(coordinator.draggingTile?.id == tile.id ? 0 : 1)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SpellingTrayFrameKey.self,
                                            value: [tile.id: geo.frame(in: .named(SpellingBuilderCoordinator.spaceName))])
                }
            )
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .accessibilityLabel("Letter \(tile.letter)")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(SpellingBuilderCoordinator.spaceName))
            .onChanged { value in
                guard coordinator.canInteractWithTray else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > 6 || coordinator.draggingTile?.id == tile.id else { return }
                coordinator.dragChanged(tile: tile, location: value.location)
            }
            .onEnded { value in
                if coordinator.draggingTile?.id == tile.id {
                    coordinator.dragEnded(tile: tile, location: value.location)
                } else {
                    GameAudio.shared.playLetter(tile.letter)
                }
            }
    }
}

/// `GameTileStyle`'s exact visual recipe (rounded-14 card, glossy top
/// highlight, soft shadow -- Games Spec §1's shared tile chrome), inlined
/// here rather than shared from `GameKit` (frozen this pass): both this
/// tray tile and `SpellingBuilderSlotView` (a non-`Button` drag target) need
/// it, so it's declared at this game's own internal (not `fileprivate`)
/// scope -- a local copy for this game folder only, not a new cross-game
/// shared entry point. `size: nil` skips the fixed frame for
/// `SpellingBuilderSlotView`'s own externally-imposed 42x50 slot size.
extension View {
    func spellingBuilderTileChrome(fill: Color, size: CGSize?, lifted: Bool = false) -> some View {
        modifier(SpellingBuilderTileChromeModifier(fill: fill, size: size, lifted: lifted))
    }
}

private struct SpellingBuilderTileChromeModifier: ViewModifier {
    let fill: Color
    let size: CGSize?
    let lifted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = lifted && !reduceMotion
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)],
                               startPoint: .top, endPoint: .center)
                    .clipShape(shape)
                shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(active ? 0.35 : 0.16), radius: active ? 10 : 6, y: active ? 6 : 3)
        .scaleEffect(active ? 1.06 : 1.0)
        .animation(Theme.Motion.tileLift, value: active)
    }
}
