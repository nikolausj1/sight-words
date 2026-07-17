import SwiftUI

/// Screen F — Session complete (§6.10). Word-count summary in the child's
/// voice, an optional "practice again" list, one warm celebrate-spring — no
/// stars, no scores.
struct SessionCompleteView: View {
    @ObservedObject var coordinator: SessionCoordinator
    let onDone: () -> Void

    @State private var appeared = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isCompact: Bool { hSizeClass == .compact }
    private var avatarSize: CGFloat { isCompact ? 108 : 148 }

    var body: some View {
        VStack(spacing: Theme.Metric.gap * 1.5) {
            ZStack {
                if !reduceMotion {
                    ConfettiBurst()
                        .frame(width: isCompact ? 260 : 340, height: isCompact ? 220 : 280)
                }
                AvatarBadge(key: coordinator.avatarSymbol, size: avatarSize)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .rotationEffect(.degrees(appeared ? 0 : -25))
            }

            Text("You read \(coordinator.totalWords) words!")
                .font(Theme.Font.display(44))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.center)

            if !coordinator.missedWords.isEmpty {
                Text("We'll practice these again: \(coordinator.missedWords.joined(separator: ", "))")
                    .font(Theme.Font.body(18))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isCompact ? 24 : 60)
            }

            Button(action: onDone) {
                Text("Done")
                    .font(Theme.Font.label(20))
                    .frame(width: 200, height: 64)
            }
            .buttonStyle(ChunkyKeyStyle(base: Theme.Color.primary,
                                       deep: Theme.Color.primary.shaded(by: -0.35)))
            .padding(.top, Theme.Metric.gap)
        }
        .padding(Theme.Metric.pad)
        .onAppear {
            // `Feedback.fire(.sessionComplete)` already fires from
            // `SessionCoordinator.finish()` the moment `phase` flips to
            // `.complete` — before this view even appears — so it isn't
            // repeated here.
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(Theme.Motion.celebrate) { appeared = true }
            }
        }
    }
}

/// One-shot confetti burst behind the session-complete avatar: ~24 rounded-rect
/// particles in Theme colors, falling with a slight rotation over ~1.8s, then
/// gone for good. Purely decorative (`allowsHitTesting(false)`); callers are
/// responsible for not constructing this at all under Reduce Motion.
private struct ConfettiBurst: View {
    @State private var startDate: Date?
    @State private var finished = false

    private struct Particle {
        var x: CGFloat          // horizontal start, as a fraction of width
        var startY: CGFloat     // fraction of height, above the top edge
        var endY: CGFloat       // fraction of height, roughly at/past the bottom
        var drift: CGFloat      // horizontal sway amplitude in points
        var size: CGSize
        var color: Color
        var delay: Double
        var fallDuration: Double
        var spin: Double        // signed full turns over the fall
    }

    private static func makeParticles() -> [Particle] {
        let colors = [Theme.Color.primary, Theme.Color.accent,
                      Theme.Color.correct, Theme.Color.accent.shaded(by: 0.3)]
        return (0..<24).map { i in
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

    private let particles = ConfettiBurst.makeParticles()

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
                    // Longest possible particle life is ~0.3s delay + 1.3s fall
                    // * 1.3 cutoff ≈ 2.0s; give it a hair more before tearing
                    // the TimelineView down so nothing gets cut off mid-fade.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { finished = true }
                }
            }
        }
    }
}
