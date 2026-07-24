import SwiftUI

/// The face-down cards grid (Games Spec §3.3): always 2 rows -- `columnCount`
/// (one per pair) on iPad, capped lower on iPhone compact so cards don't
/// shrink to illegibility (the grid then just wraps into more rows instead,
/// per this worker's "iPhone compact functional" brief).
struct MemoryBoardView: View {
    @ObservedObject var coordinator: MemoryCoordinator
    /// The board card's own interior size, read directly from
    /// `GameScaffold`'s `\.gameBoardAreaSize` environment value (see
    /// `GameBoardCard` in GameScaffold.swift). This used to be estimated
    /// from `UIScreen.main.bounds` because a real `GeometryReader` anywhere
    /// in this chain inherited a GameScaffold-level layout bug that inflated
    /// the whole board area to a wildly wrong (iPad-shaped) size on iPhone;
    /// that bug is now fixed at its source, so the environment value is a
    /// correct, bounded measurement on every device.
    ///
    /// Read here (inside the view `GameBoardCard.content()` actually
    /// constructs) rather than one level up in `MemoryGameContentView` --
    /// `@Environment` resolves to whatever is ambient at a view's own
    /// position in the tree, and `GameBoardCard` only sets this value on
    /// the subtree `content()` returns, not on `content()`'s caller. A
    /// parent reading it before calling `board()` always sees the
    /// unset `.zero` default, which is what previously starved every
    /// card's computed width/height to zero/negative and rendered a
    /// completely blank board no matter how many cards `coordinator.cards`
    /// actually held.
    @Environment(\.gameBoardAreaSize) private var availableSize
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    private var columnCount: Int {
        isCompact ? min(coordinator.pairCount, 3) : coordinator.pairCount
    }

    var body: some View {
        let count = max(coordinator.cards.count, 1)
        let rowCount = Int(ceil(Double(count) / Double(columnCount)))
        let spacing = Theme.Metric.gap
        let cardWidth = (availableSize.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        let maxHeightFromRows = (availableSize.height - spacing * CGFloat(max(rowCount - 1, 0))) / CGFloat(max(rowCount, 1))
        let cardHeight = min(cardWidth / 0.78, maxHeightFromRows)
        let boardWidth = cardWidth * CGFloat(columnCount) + spacing * CGFloat(columnCount - 1)
        let boardHeight = cardHeight * CGFloat(rowCount) + spacing * CGFloat(max(rowCount - 1, 0))

        ZStack {
            ForEach(Array(coordinator.cards.enumerated()), id: \.element.id) { index, card in
                let row = index / columnCount
                let col = index % columnCount
                let cx = cardWidth * (CGFloat(col) + 0.5) + spacing * CGFloat(col)
                let cy = cardHeight * (CGFloat(row) + 0.5) + spacing * CGFloat(row)
                cardView(for: card)
                    .frame(width: cardWidth, height: cardHeight)
                    .position(x: cx, y: cy)
            }
        }
        .frame(width: boardWidth, height: boardHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cardView(for card: MemoryCard) -> some View {
        MemoryCardView(
            card: card,
            isFaceUp: coordinator.faceUpIDs.contains(card.id) || coordinator.matchedPairIDs.contains(card.pairID),
            isMatched: coordinator.matchedPairIDs.contains(card.pairID),
            isBanked: coordinator.bankedPairIDs.contains(card.pairID),
            showConfetti: coordinator.justMatchedCardIDs.contains(card.id),
            action: { coordinator.flipCard(card.id) }
        )
        .wrongShake(Binding(
            get: { coordinator.wrongCardIDs.contains(card.id) },
            set: { firing in if !firing { coordinator.clearWrongFlag(card.id) } }
        ))
        .opacity(coordinator.clearingBoard ? 0 : 1)
        .scaleEffect(coordinator.clearingBoard ? 0.5 : 1)
        .animation(Theme.Motion.snappy, value: coordinator.clearingBoard)
    }
}

/// The 🎤 "Say it to bank it!" bonus beat (Games Spec §3.3): shown only
/// while `MemoryCoordinator` has an active bank target, and purely
/// presentational -- all listening/timeout logic lives in the coordinator.
/// Unlike Word Hunt/Say & Match's voice beats this one never blocks the
/// board (matching already happened; this is a bonus star only), so the
/// overlay stays a small bottom banner rather than a full-screen take-over.
struct MemoryBankBeatOverlay: View {
    @ObservedObject var coordinator: MemoryCoordinator

    var body: some View {
        if let word = coordinator.bankingDisplayText {
            VStack {
                Spacer()
                HStack(spacing: 14) {
                    PulsingMicIndicator(level: coordinator.bankMicLevel, flashCorrect: coordinator.bankFlashCorrect)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Say it to bank it!")
                            .font(Theme.Font.label(16))
                            .foregroundStyle(.white)
                        Text(word)
                            .font(Theme.Font.display(22))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .darkPlate(corner: 20)
                .padding(.horizontal, Theme.Metric.pad)
                .padding(.bottom, Theme.Metric.pad)
            }
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(Theme.Motion.snappy, value: coordinator.bankingPairID)
        }
    }
}
