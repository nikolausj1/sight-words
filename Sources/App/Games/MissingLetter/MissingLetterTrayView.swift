import SwiftUI

// MARK: - TrayFrameKey

/// Every tray tile's own "home" frame (its resting position, updated every
/// layout pass regardless of drag state -- the tile stays laid out even
/// while its face is hidden mid-drag, see `MissingLetterTrayTileView`), so
/// `MissingLetterCoordinator.returnTileToTray` has somewhere real to animate
/// a wrong/missed drop back to.
struct TrayFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - MissingLetterTileFace

/// The shared chunky-key look for a letter tile (Games Spec §3.4:
/// "ChunkyKey-ish, lift on touch") -- used at rest in the tray and, scaled
/// up with a deeper shadow, for the floating tile a drag is currently
/// carrying (`MissingLetterGameView`'s overlay). Hand-rolled rather than
/// `ChunkyKeyStyle` itself: that style's "lift" comes from a real `Button`'s
/// `configuration.isPressed`, but this tile needs its own custom
/// tap-vs-drag `DragGesture` (see `MissingLetterTrayTileView`) instead of a
/// plain button tap, so there's no `isPressed` to key off of here -- `lifted`
/// is driven directly by "is this tile the one currently airborne" instead.
/// Uses `GameTileStyle`'s exact visual recipe via `paperTileFace()` (Design
/// Direction §4's tile-chrome fold-in) -- `GameTileStyle` itself is a
/// `ButtonStyle` and can't apply to a non-`Button` drag tile, so this uses
/// the shared non-button modifier variant instead of its own local copy.
struct MissingLetterTileFace: View {
    let letter: Character
    var lifted: Bool = false

    var body: some View {
        Text(String(letter))
            .font(Theme.Font.display(28))
            .foregroundStyle(.white)
            .paperTileFace(fill: Theme.Color.primary, size: CGSize(width: 56, height: 56), lifted: lifted)
    }
}

// MARK: - MissingLetterTrayView

/// The tray of letter tiles below the worksheet (Games Spec §3.4): needed
/// letters + decoys, in fixed shuffled order for the round. Wraps via an
/// adaptive grid so it behaves the same on iPad and iPhone-compact ("tray
/// wraps" per this worker's brief) without any size-class branching of its
/// own.
struct MissingLetterTrayView: View {
    @ObservedObject var coordinator: MissingLetterCoordinator

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Theme.Metric.gap)],
                  spacing: Theme.Metric.gap) {
            ForEach(coordinator.tray) { tile in
                MissingLetterTrayTileView(tile: tile, coordinator: coordinator)
            }
        }
    }
}

// MARK: - MissingLetterTrayTileView

/// One draggable tray tile. A single `DragGesture(minimumDistance: 0)`
/// disambiguates tap vs. drag itself (mirroring `WordHuntBoardView`'s own
/// single-cell-vs-swipe pattern) rather than layering a separate
/// `onTapGesture` alongside a `DragGesture`, which is prone to stealing each
/// other's recognition: past `coordinator.dragChanged`'s own 6pt arm
/// threshold it's a drag; released before that, it's a tap (speaks the
/// letter). `coordinator.draggingTile`'s identity is the source of truth at
/// `onEnded`, not a re-measured distance, since a real drag can legitimately
/// end back near its start point (e.g. a drop that misses every blank).
private struct MissingLetterTrayTileView: View {
    let tile: MissingLetterTile
    @ObservedObject var coordinator: MissingLetterCoordinator

    var body: some View {
        MissingLetterTileFace(letter: tile.letter)
            // Hidden (not removed) while airborne: removing it would drop
            // its `TrayFrameKey` report, and `returnTileToTray` needs that
            // "home" frame to still be fresh for the return animation.
            .opacity(coordinator.draggingTile?.id == tile.id ? 0 : 1)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TrayFrameKey.self,
                                            value: [tile.id: geo.frame(in: .named(MissingLetterCoordinator.spaceName))])
                }
            )
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .accessibilityLabel("Letter \(tile.letter)")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(MissingLetterCoordinator.spaceName))
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > 6 || coordinator.draggingTile?.id == tile.id else { return }
                coordinator.dragChanged(tile: tile, location: value.location)
            }
            .onEnded { value in
                if coordinator.draggingTile?.id == tile.id {
                    coordinator.dragEnded(tile: tile, location: value.location)
                } else if coordinator.tier == .t1 {
                    GameAudio.shared.playLetter(tile.letter)
                } else {
                    GameAudio.shared.playLetterSound(tile.letter)
                }
            }
    }
}
