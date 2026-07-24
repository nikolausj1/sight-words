import SwiftUI

// MARK: - PaperBlobShape

/// The core paper-cut primitive (Design Direction §1): an organic rounded
/// blob -- a smooth CLOSED spline over jittered control points around an
/// ellipse inscribed in the shape's rect, so every layer reads as a hand-cut
/// piece of paper rather than a perfect oval or rounded rect.
///
/// Built as a Catmull-Rom spline converted to cubic Bezier segments (the
/// standard closed-curve conversion: for points `p0,p1,p2,p3` the segment
/// from `p1` to `p2` uses control points `p1 + (p2-p0)/6` and
/// `p2 - (p3-p1)/6`), which is what makes the edge "smooth closed" rather
/// than a jagged polygon -- every vertex it passes through blends into the
/// next with no sharp corners, matching the reference art's wavy-but-soft
/// cut edges.
///
/// `variant` (0-3) plus `seed` together pick a distinct jitter pattern, so
/// `PaperWindow`'s stacked rings -- built from the same base shape at
/// different insets -- don't all trace an identical outline (Design
/// Direction §1: "2-4 seeded variants so edges aren't identical everywhere").
struct PaperBlobShape: Shape {
    var seed: UInt64
    var variant: Int = 0
    /// Fraction of the half-dimension each control point's radius can jitter
    /// by. Small values (~0.03-0.05) read as a gentle wave suitable for
    /// content-bearing innermost layers; larger values (~0.08-0.12) suit
    /// purely decorative outer rings.
    var jitter: CGFloat = 0.06
    /// Number of control points around the blob. More points = gentler,
    /// more numerous waves; fewer = bigger, lazier bulges.
    var pointCount: Int = 10

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        var rng = NoiseRNG64(seed: seed &+ UInt64(variant) &* 0x9E3779B1 &+ UInt64(pointCount))

        var points: [CGPoint] = []
        points.reserveCapacity(pointCount)
        for i in 0..<pointCount {
            let angle = (CGFloat(i) / CGFloat(pointCount)) * 2 * .pi
            // [-1, 1] pseudo-random, scaled by `jitter`.
            let unit = CGFloat(rng.next() % 10_000) / 10_000 * 2 - 1
            let radiusScale = 1 + unit * jitter
            let x = center.x + cos(angle) * rx * radiusScale
            let y = center.y + sin(angle) * ry * radiusScale
            points.append(CGPoint(x: x, y: y))
        }
        return Self.closedCatmullRom(through: points)
    }

    /// Smooth closed spline through `points`, as cubic Bezier segments.
    private static func closedCatmullRom(through points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count >= 3 else {
            if let first = points.first { path.addRect(CGRect(origin: first, size: .zero)) }
            return path
        }
        let n = points.count
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - PaperLayer

/// One flat-colored, organically-edged sheet of "paper" (Design Direction
/// §1): a `PaperBlobShape` filled flat, the shared low-opacity noise grain
/// clipped to it, and -- for layers that sit above others -- the paper drop
/// shadow (`black 0.14, radius 6, y 4`). Inner rings pass `castsShadow: false`
/// since a shadow from a layer that's fully covered by the one above it just
/// wastes a compositing pass without ever being visible.
struct PaperLayer: View {
    var fill: Color
    var seed: UInt64
    var variant: Int = 0
    var jitter: CGFloat = 0.06
    var pointCount: Int = 10
    var castsShadow: Bool = true

    private var shape: PaperBlobShape {
        PaperBlobShape(seed: seed, variant: variant, jitter: jitter, pointCount: pointCount)
    }

    var body: some View {
        shape
            .fill(fill)
            .overlay(
                Textures.noise
                    .opacity(0.05)
                    .blendMode(.overlay)
                    .clipShape(shape)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(castsShadow ? 0.14 : 0), radius: 6, y: 4)
    }
}

// MARK: - PaperTheme

/// Per-game accent color families (Design Direction §3) plus the shared
/// cream/sage/sky families used on home and other cross-game surfaces. Every
/// family derives its ring/surface/accent tones from one base hue via
/// `Color.shaded(by:)` (already shared with `ChunkyKeyStyle`'s gradients),
/// so the whole paper system and the pre-existing chunky-key look stay
/// tonally related rather than introducing a second unrelated palette.
enum PaperTheme {
    /// One accent family: the two ring tones a `PaperWindow` stacks behind
    /// its content, the innermost near-content paper tone, and the
    /// saturated `accent` used for that game's buttons/highlights/confetti.
    /// `seed` gives every family's blob layers their own distinct wobble
    /// pattern so two different games' windows never trace identical edges.
    struct Family {
        let ring2: Color
        let ring1: Color
        let surface: Color
        let accent: Color
        let seed: UInt64

        init(base: Color, seed: UInt64) {
            self.ring2 = base.shaded(by: -0.12)
            self.ring1 = base
            self.surface = base.shaded(by: 0.62)
            self.accent = base.shaded(by: -0.06)
            self.seed = seed
        }
    }

    // MARK: Per-game families (§3)

    static let leafGreen = Family(base: Color(red: 0.24, green: 0.62, blue: 0.36), seed: 0x1001)       // wordHunt
    static let skyBlue = Family(base: Color(red: 0.30, green: 0.62, blue: 0.88), seed: 0x1002)          // sayMatch
    static let violet = Family(base: Color(red: 0.56, green: 0.42, blue: 0.82), seed: 0x1003)           // memory
    static let coral = Family(base: Color(red: 0.95, green: 0.48, blue: 0.34), seed: 0x1004)            // missingLetter
    static let sunshineGold = Family(base: Color(red: 0.98, green: 0.74, blue: 0.22), seed: 0x1005)     // spellingBuilder
    static let warmRedOrange = Family(base: Color(red: 0.86, green: 0.34, blue: 0.24), seed: 0x1006)    // trickyWords (Phase B; no GameID yet)

    // MARK: Shared surfaces (home + cross-game chrome)

    static let cream = Family(base: Color(red: 0.96, green: 0.90, blue: 0.78), seed: 0x2001)
    static let sage = Family(base: Color(red: 0.58, green: 0.68, blue: 0.52), seed: 0x2002)
    static let sky = Family(base: Color(red: 0.62, green: 0.82, blue: 0.90), seed: 0x2003)

    /// The accent family for a given game (§3's fixed game→color mapping).
    static func family(for id: GameID) -> Family {
        switch id {
        case .wordHunt: return leafGreen
        case .sayMatch: return skyBlue
        case .memory: return violet
        case .missingLetter: return coral
        case .spellingBuilder: return sunshineGold
        }
    }
}

// MARK: - PaperWindow

/// THE container for every game board, card area, and modal (Design
/// Direction §1): 2-3 concentric `PaperLayer`s -- each inset further and one
/// tint step in from the last -- with `content` innermost. Replaces bare
/// white cards floating on a plain background: the space around content is
/// always layered colored paper.
///
/// Content is padded well inside the innermost blob's bounding box rather
/// than clipped to its wavy path -- a judgment call: clipping interactive
/// content (game tiles, buttons) to an organic edge risks cutting off a tap
/// target whenever the blob's jitter happens to pinch in near a corner,
/// which would violate the kid-scale-touch-target rules this whole system
/// exists to serve. The generous inset keeps content safely clear of the
/// wave at every angle while still reading as "sitting inside cut paper."
///
/// A plain rectangular `clipShape` (not the organic path, for the same
/// tap-target reason above) still guards the case where content needs MORE
/// room than this window was given -- e.g. a compact-width game board
/// stacking a grid above a scrollable word list -- so an oversized child
/// scrolls/clips cleanly at a predictable rectangular edge instead of
/// visibly spilling out over the surrounding paper rings.
struct PaperWindow<Content: View>: View {
    var family: PaperTheme.Family
    /// Extra seed offset so sibling windows using the same family (e.g. a
    /// game's board window and its own word-list window) don't trace
    /// identical outlines.
    var seedOffset: UInt64 = 0
    @ViewBuilder var content: () -> Content

    private var seed: UInt64 { family.seed &+ seedOffset }
    private let ringInset: CGFloat = 16

    var body: some View {
        ZStack {
            PaperLayer(fill: family.ring2, seed: seed, variant: 0, jitter: 0.09)
            PaperLayer(fill: family.ring1, seed: seed, variant: 1, jitter: 0.07, castsShadow: false)
                .padding(ringInset)
            PaperLayer(fill: family.surface, seed: seed, variant: 2, jitter: 0.045, castsShadow: false)
                .padding(ringInset * 2)
            content()
                .padding(ringInset * 2 + 20)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
        }
    }
}
