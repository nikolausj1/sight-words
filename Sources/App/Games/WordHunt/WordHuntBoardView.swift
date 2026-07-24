import SwiftUI
import AVFoundation

/// Tiny local audio player for single-letter tap-to-hear (Games Spec §1:
/// "tapping any letter tile says the letter name"). Deliberately
/// self-contained here rather than adding a new method to the shared
/// `SpeechService` -- this game's scope is its own folder only, and the
/// `letter-<x>.m4a` clips (Games Spec §4) already exist in the bundle with
/// no player wired up yet.
@MainActor
final class WordHuntLetterPlayer {
    static let shared = WordHuntLetterPlayer()
    private var player: AVAudioPlayer?

    func play(_ letter: Character) {
        guard let url = Bundle.main.url(forResource: "letter-\(String(letter).lowercased())", withExtension: "m4a") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }
}

/// The grid card (Games Spec §3.1): swipe-select with a live highlight
/// ribbon, elastic neighbor-letter shift + lift under touch, persistent
/// pastel trails on found words, and idle/manual hint pulsing.
struct WordHuntBoardView: View {
    @ObservedObject var coordinator: WordHuntCoordinator
    @State private var dragLocation: CGPoint?
    @State private var startCell: WordHuntCellRef?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = coordinator.grid.size
            let cellSize = min(geo.size.width, geo.size.height) / CGFloat(size)
            let boardSide = cellSize * CGFloat(size)

            ZStack {
                ForEach(0..<size, id: \.self) { row in
                    ForEach(0..<size, id: \.self) { col in
                        cellView(row: row, col: col, cellSize: cellSize)
                            .position(x: cellSize * (CGFloat(col) + 0.5), y: cellSize * (CGFloat(row) + 0.5))
                    }
                }
            }
            .frame(width: boardSide, height: boardSide)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .contentShape(Rectangle())
            .gesture(dragGesture(cellSize: cellSize, size: size))
        }
    }

    /// `.local` coordinate space is relative to the gesture's own view (the
    /// board's `boardSide x boardSide` frame, `(0,0)` at its own top-left) --
    /// unaffected by the `.position()` placing that frame within the
    /// `GeometryReader`, so `value.location`/`.startLocation` need no extra
    /// offset math to line up with `cellView`'s own `cellSize`-based centers.
    private func dragGesture(cellSize: CGFloat, size: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                dragLocation = value.location
                let sCell = startCell ?? cellRef(at: value.startLocation, cellSize: cellSize, size: size)
                if startCell == nil { startCell = sCell }
                let curCell = cellRef(at: value.location, cellSize: cellSize, size: size)
                coordinator.selectionUpdated(start: sCell, current: curCell)
            }
            .onEnded { _ in
                coordinator.commitSelection()
                startCell = nil
                withAnimation(.easeOut(duration: 0.15)) { dragLocation = nil }
            }
    }

    private func cellRef(at point: CGPoint, cellSize: CGFloat, size: Int) -> WordHuntCellRef {
        let col = min(max(Int(point.x / cellSize), 0), size - 1)
        let row = min(max(Int(point.y / cellSize), 0), size - 1)
        return WordHuntCellRef(row: row, col: col)
    }

    /// Deliberately NOT `@ViewBuilder`: the body below computes plain local
    /// values (elastic offset, lift, background color) with ordinary
    /// imperative `if`/`let` before building exactly one `Text` view at the
    /// end -- `@ViewBuilder` would try to treat those imperative branches as
    /// view-producing components themselves and fail to compile.
    private func cellView(row: Int, col: Int, cellSize: CGFloat) -> some View {
        let ref = WordHuntCellRef(row: row, col: col)
        let letter = String(coordinator.grid.letters[row][col])
        let isSelected = coordinator.selection.contains(ref)
        let isFading = coordinator.fadingWrongSelection.contains(ref)
        let foundWord = coordinator.foundWord(containing: ref)
        let isHinting = coordinator.hintingCells.contains(ref)

        let center = CGPoint(x: cellSize * (CGFloat(col) + 0.5), y: cellSize * (CGFloat(row) + 0.5))
        var elasticOffset = CGSize.zero
        var lift: CGFloat = 1.0
        if let dragLocation, !reduceMotion {
            let dx = center.x - dragLocation.x, dy = center.y - dragLocation.y
            let dist = (dx * dx + dy * dy).squareRoot()
            let radius = cellSize * 1.5
            if dist > 0.5, dist < radius {
                let strength = (1 - dist / radius) * 6
                elasticOffset = CGSize(width: dx / dist * strength, height: dy / dist * strength)
            }
            if dist < cellSize * 0.6 { lift = 1.16 }
        }

        let background: Color = {
            if let foundWord, let color = coordinator.trailColor[foundWord] { return color }
            if isSelected { return Theme.Color.primary.opacity(0.35) }
            if isFading { return Theme.Color.gentle.opacity(0.3) }
            return Theme.Color.surface
        }()

        return Text(letter)
            .font(Theme.Font.display(cellSize * 0.42))
            .foregroundStyle(Theme.Color.ink)
            .minimumScaleFactor(0.5)
            .frame(width: cellSize - 4, height: cellSize - 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Theme.Color.primary : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(isHinting && coordinator.hintPulseOn && !reduceMotion ? 1.22 : lift)
            .offset(elasticOffset)
            .shadow(color: .black.opacity(lift > 1.01 ? 0.22 : 0), radius: lift > 1.01 ? 4 : 0, y: 2)
            .animation(Theme.Motion.snappy, value: isSelected)
            .animation(Theme.Motion.snappy, value: isHinting && coordinator.hintPulseOn)
            .animation(.easeOut(duration: 0.5), value: isFading)
            .animation(.easeOut(duration: 0.12), value: elasticOffset)
    }
}
