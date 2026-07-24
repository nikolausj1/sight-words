import SwiftUI

/// The shared wrong-answer treatment (Games Spec §1): "target shakes once,
/// soft 'boing' SFX, element returns/resets. NO scolding voice, no red X, no
/// lost progress." Every game drives this off its own local `@State` bool --
/// nothing here touches persistence; a wrong tap is simply never reported to
/// `GameSessionRecorder`.
extension View {
    /// Shakes this view once whenever `trigger` flips to `true` (playing
    /// `Feedback.fire(.boing)` at the same moment), then flips `trigger` back
    /// to `false` once the shake settles so it's armed for the next miss.
    /// Callers own resetting whatever the shake was attached to (a selection
    /// ribbon, a dragged tile snapping back, a flipped card) -- this modifier
    /// only owns the shake + SFX beat.
    func wrongShake(_ trigger: Binding<Bool>) -> some View {
        modifier(WrongShakeModifier(trigger: trigger))
    }
}

private struct WrongShakeModifier: ViewModifier {
    @Binding var trigger: Bool
    @State private var shakes: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Matches `Shake`'s own settle time closely enough that `trigger` clears
    /// right as the motion finishes, not mid-shake.
    private let settleDelay: TimeInterval = 0.4

    func body(content: Content) -> some View {
        content
            .modifier(Shake(animatableData: shakes))
            .onChange(of: trigger) { _, isShaking in
                guard isShaking else { return }
                Feedback.fire(.boing)
                guard !reduceMotion else {
                    trigger = false
                    return
                }
                withAnimation(.easeInOut(duration: settleDelay)) { shakes += 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
                    trigger = false
                }
            }
    }
}
