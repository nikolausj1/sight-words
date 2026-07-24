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
            .frame(width: 56, height: 56)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.Color.primary.shaded(by: 0.25), Theme.Color.primary,
                                                      Theme.Color.primary.shaded(by: -0.15)],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                }
            )
            .opacity(inert ? 0.6 : 1)
            .shadow(color: .black.opacity(lifted ? 0.35 : 0.16), radius: lifted ? 10 : 4, y: lifted ? 6 : 2)
            .scaleEffect(lifted ? 1.16 : 1.0)
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
