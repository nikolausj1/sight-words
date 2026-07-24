import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A translucent panel that guarantees content stays readable over busy backgrounds.
struct ScrimCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}
extension View {
    func scrimCard() -> some View { modifier(ScrimCard()) }

    /// Dark glass plate: keeps white text/icons readable over any background without
    /// covering the environment in a big light card. Use per element, not per screen.
    func darkPlate(corner: CGFloat = Theme.Metric.corner) -> some View {
        self
            .background(.ultraThinMaterial.opacity(0.9))
            .environment(\.colorScheme, .dark)   // keep the material glass, not milk
            .background(Color.black.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}

/// Chunky 3D game key: lit face on a darker base that physically depresses on touch.
/// Subtle noise texture so flat colour reads as material.
struct ChunkyKeyStyle: ButtonStyle {
    var base: Color
    var deep: Color
    var corner: CGFloat = Theme.Metric.cornerSmall
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return configuration.label
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
            .background(
                ZStack {
                    shape.fill(LinearGradient(colors: [base.shaded(by: 0.28), base, base.shaded(by: -0.15)],
                                              startPoint: .top, endPoint: .bottom))
                    Textures.noise
                        .opacity(0.10)
                        .blendMode(.overlay)
                        .clipShape(shape)
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5)
                }
            )
            .offset(y: pressed ? 3 : 0)
            .background(
                shape.fill(deep.shaded(by: -0.3))
                    .offset(y: pressed ? 3.5 : 5)
            )
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Home Games-shelf tile press state (design review, g8-home-ipad.png): a
/// slightly deeper press than `PopButtonStyle`'s default (0.96 vs 0.95) paired
/// with a shadow that "tightens" (shrinks + lightens) on press, so the tile
/// reads as a lifted card settling down rather than just shrinking in place.
/// `.compositingGroup()` flattens the tile's icon+label+dots into one layer
/// first so the shadow wraps the whole tile instead of haloing each subview.
struct ShelfTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        return configuration.label
            .scaleEffect(pressed ? 0.96 : 1)
            .compositingGroup()
            .shadow(color: .black.opacity(pressed ? 0.06 : 0.12),
                    radius: pressed ? 3 : 8, y: pressed ? 1 : 4)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Tiny tiled monochrome noise so solid fills feel like a material, not a vector.
enum Textures {
    static let noise: Image = {
        #if canImport(UIKit)
        let side = 64
        var rng = NoiseRNG64(seed: 0xA11CE)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let ui = renderer.image { ctx in
            for y in 0..<side {
                for x in 0..<side {
                    let v = CGFloat(rng.next() % 256) / 255
                    ctx.cgContext.setFillColor(UIColor(white: v, alpha: 1).cgColor)
                    ctx.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return Image(uiImage: ui).resizable(resizingMode: .tile)
        #else
        return Image(systemName: "square")
        #endif
    }()
}

extension Color {
    /// Lighten (positive) or darken (negative) toward white/black in RGB space.
    func shaded(by amount: Double) -> Color {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let t = CGFloat(min(max(amount, -1), 1))
        func mix(_ c: CGFloat) -> CGFloat { t >= 0 ? c + (1 - c) * t : c * (1 + t) }
        return Color(red: mix(r), green: mix(g), blue: mix(b)).opacity(a)
        #else
        return self
        #endif
    }
}

/// Horizontal shake (e.g. locked-control nudges); integer phases land at zero
/// offset so the view always settles exactly in place.
struct Shake: GeometryEffect {
    var travel: CGFloat = 7
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * shakesPerUnit * 2), y: 0))
    }
}

/// The chunky orange close key used by all modal cards (upper-left corner).
struct ModalCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
        }
        .buttonStyle(ChunkyKeyStyle(base: Theme.Color.accent,
                                    deep: Theme.Color.accent.shaded(by: -0.4),
                                    corner: 20))
        .accessibilityLabel("Close")
    }
}

/// Minimal deterministic PRNG for the noise texture (avoids pulling in a dependency).
/// Named distinctly from the engine's RNG (Sources/Engine) to avoid a type collision
/// once that layer is ported — both compile into the same app module.
struct NoiseRNG64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
