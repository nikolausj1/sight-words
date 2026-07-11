import SwiftUI

/// Calculator-style number pad (7-8-9 top), large kid-friendly keys, positioned low
/// for two-handed iPad reach. Keys are chunky 3D buttons that physically depress,
/// so they read as game pieces rather than flat UI (used for the parent gate).
struct NumberPadView: View {
    let enterEnabled: Bool
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    let onEnter: () -> Void
    /// Overrides the default tint on the digit keys.
    var keyTint: Color? = nil

    private let rows = [[7, 8, 9], [4, 5, 6], [1, 2, 3]]

    private var base: Color { keyTint ?? Theme.Color.primary }
    private var deep: Color { base.shaded(by: -0.35) }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 14) { ForEach(row, id: \.self) { digit(_: $0) } }
            }
            HStack(spacing: 14) {
                key(systemImage: "delete.left.fill",
                    base: Color(white: 0.42), deep: Color(white: 0.25), action: onDelete)
                    .accessibilityLabel("Delete")
                digit(0)
                key(systemImage: "checkmark",
                    base: Theme.Color.correct, deep: Theme.Color.correct.shaded(by: -0.35),
                    enabled: enterEnabled, action: onEnter)
                    .accessibilityLabel("Enter")
            }
        }
        .frame(maxWidth: 430)
    }

    private func digit(_ n: Int) -> some View {
        Button { onDigit(n) } label: {
            Text("\(n)").font(Theme.Font.number(32))
                .frame(maxWidth: .infinity, minHeight: 62)
        }
        .buttonStyle(ChunkyKeyStyle(base: base, deep: deep))
    }

    private func key(systemImage: String, base: Color, deep: Color,
                     enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 25, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 62)
        }
        .buttonStyle(ChunkyKeyStyle(base: base, deep: deep))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .saturation(enabled ? 1 : 0.4)
    }
}
