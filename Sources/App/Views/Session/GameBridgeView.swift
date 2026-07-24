import SwiftUI

/// Guided seam "Bonus round!" bridge (Games Spec §2, WP-G8 CX pass): the
/// beat `SessionView` shows for `SessionCoordinator`'s `.gameBridge` phase,
/// between the cards portion ending and the embedded game round's cover
/// presenting. Replaces what used to be a hard cut straight into the game's
/// `fullScreenCover`.
///
/// Purely a visual+sfx moment: the day's game icon and "Bonus round!" text
/// zoom-spring in (fade only under Reduce Motion) over `WarmBackdrop`, which
/// is already the background underneath in `SessionView`'s `ZStack` — no
/// separate overlay container needed here. `Feedback.fire(.bonusRoundBridge)`
/// (the sfx_whoosh cue) and the fixed ~1.6s timing both live on
/// `SessionCoordinator.presentGameBridge(_:)`, firing the instant `phase`
/// flips to `.gameBridge` — mirrors how `Feedback.fire(.sessionComplete)`
/// already fires from the coordinator rather than from `SessionCompleteView`
/// — so neither is repeated here.
struct GameBridgeView: View {
    let gameID: GameID
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var artKey: String { "gameicon-\(gameID.rawValue)" }

    var body: some View {
        VStack(spacing: Theme.Metric.gap) {
            Group {
                if Art.exists(artKey) {
                    Image(artKey)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 90, weight: .bold))
                        .foregroundStyle(Theme.Color.primary)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

            Text("Bonus round!")
                .font(Theme.Font.display(40))
                .foregroundStyle(Theme.Color.ink)
        }
        .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.5))
        .opacity(appeared ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            } else {
                withAnimation(Theme.Motion.celebrate) { appeared = true }
            }
        }
    }
}
