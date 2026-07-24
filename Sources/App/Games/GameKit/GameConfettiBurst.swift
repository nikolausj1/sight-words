import SwiftUI

/// A one-shot confetti burst: rounded-rect particles in Theme colors,
/// falling with a slight rotation, then gone for good. Purely decorative
/// (`allowsHitTesting(false)`).
///
/// `SessionCompleteView.swift` has its own `private struct ConfettiBurst`
/// predating this one -- deliberately left untouched (rather than refactored
/// to share this type) so that file's already-verified behavior couldn't
/// regress from a change made outside this worker's own build task. Note
/// this type is named `GameConfettiBurst`, not `ConfettiBurst`, specifically
/// to avoid colliding with that one: Swift's top-level `private` does NOT
/// give a same-named declaration in another file of the same module
/// isolation from the "invalid redeclaration" check (confirmed against this
/// exact pair -- `private` only restricts *access* from other files, not the
/// top-level name itself), so an internal `struct ConfettiBurst` here would
/// fail to compile. This is GameKit's copy for `SuccessMoment` and
/// `RoundCelebration`; a future pass could consolidate both call sites onto
/// one shared implementation.
struct GameConfettiBurst: View {
    /// Number of particles. `SuccessMoment` uses the default (small burst);
    /// `RoundCelebration` passes a larger count for its full-screen moment.
    var particleCount: Int = 24
    @State private var startDate: Date?
    @State private var finished = false

    private struct Particle {
        var x: CGFloat
        var startY: CGFloat
        var endY: CGFloat
        var drift: CGFloat
        var size: CGSize
        var color: Color
        var delay: Double
        var fallDuration: Double
        var spin: Double
    }

    /// Computed once per `GameConfettiBurst` value (not per `body` evaluation) --
    /// a plain stored `let` initialized from `particleCount`, same pattern
    /// as the original `SessionCompleteView` version, so particles don't
    /// jump mid-fall if a parent view causes an unrelated re-render.
    private let particles: [Particle]

    init(particleCount: Int = 24) {
        self.particleCount = particleCount
        let colors = [Theme.Color.primary, Theme.Color.accent,
                      Theme.Color.correct, Theme.Color.accent.shaded(by: 0.3)]
        self.particles = (0..<particleCount).map { i in
            Particle(x: .random(in: 0.05...0.95),
                      startY: .random(in: -0.30 ... -0.05),
                      endY: .random(in: 0.85...1.05),
                      drift: .random(in: 8...28),
                      size: CGSize(width: .random(in: 6...11), height: .random(in: 9...16)),
                      color: colors[i % colors.count],
                      delay: .random(in: 0...0.3),
                      fallDuration: .random(in: 1.0...1.3),
                      spin: Double.random(in: 1...3) * (Bool.random() ? 1 : -1))
        }
    }

    var body: some View {
        Group {
            if finished {
                Color.clear
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { gc, size in
                        guard let startDate else { return }
                        let elapsed = timeline.date.timeIntervalSince(startDate)
                        for p in particles {
                            let raw = (elapsed - p.delay) / p.fallDuration
                            guard raw > 0, raw < 1.3 else { continue }
                            let opacity = raw < 0.8 ? 1 : max(0, 1 - (raw - 0.8) / 0.5)
                            guard opacity > 0.01 else { continue }
                            let y = (p.startY + (p.endY - p.startY) * raw) * size.height
                            let x = p.x * size.width + sin(raw * .pi * 2) * p.drift
                            gc.drawLayer { layer in
                                layer.opacity = opacity
                                layer.translateBy(x: x, y: y)
                                layer.rotate(by: .radians(p.spin * .pi * 2 * raw))
                                let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2,
                                                  width: p.size.width, height: p.size.height)
                                layer.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color))
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .onAppear {
                    startDate = Date()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { finished = true }
                }
            }
        }
    }
}
