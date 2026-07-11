import SwiftUI

/// The 8 avatar slots. Art arrives later as imagesets `avatar1`…`avatar8`;
/// until then each slot renders a themed SF symbol on its own gem circle.
/// Legacy profiles may still store a raw SF symbol name — tier 3 handles them.
enum AvatarCatalog {
    static let keys = (1...8).map { "avatar\($0)" }

    /// Carousel display order: the front-and-center slot flanked symmetrically.
    static let carouselOrder = ["avatar5", "avatar8", "avatar2", "avatar1",
                                "avatar3", "avatar4", "avatar6", "avatar7"]

    static let fallbacks: [String: (symbol: String, color: Color)] = [
        "avatar1": ("figure.hiking",   Color(red: 0.36, green: 0.68, blue: 0.35)),   // green
        "avatar2": ("map.fill",        Color(red: 0.95, green: 0.55, blue: 0.20)),   // orange
        "avatar3": ("sailboat.fill",   Color(red: 0.85, green: 0.30, blue: 0.25)),   // red
        "avatar4": ("wand.and.stars",  Color(red: 0.58, green: 0.42, blue: 0.88)),   // purple
        "avatar5": ("shield.fill",     Color(red: 0.30, green: 0.50, blue: 0.95)),   // blue
        "avatar6": ("airplane",        Color(red: 0.18, green: 0.65, blue: 0.62)),   // teal
        "avatar7": ("crown.fill",      Color(red: 0.95, green: 0.72, blue: 0.20)),   // gold
        "avatar8": ("moon.stars.fill", Color(red: 0.36, green: 0.38, blue: 0.75)),   // indigo
    ]
}

/// A circular avatar: real art when the imageset exists, themed symbol fallback
/// otherwise, and a raw-SF-symbol tier for legacy profile values.
struct AvatarBadge: View {
    let key: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if Art.exists(key) {
                Image(key).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                let fb = AvatarCatalog.fallbacks[key]
                let color = fb?.color ?? Theme.Color.primary
                Image(systemName: fb?.symbol ?? key)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(
                        Circle().fill(LinearGradient(colors: [color.shaded(by: 0.2),
                                                              color.shaded(by: -0.2)],
                                                     startPoint: .top, endPoint: .bottom)))
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: max(1.5, size * 0.02)))
    }
}

/// Horizontal snapping picker: the centered avatar is the selection. Reused by
/// onboarding and the kid profile screen.
struct AvatarCarousel: View {
    @Binding var selected: String
    var itemSize: CGFloat = 130

    @State private var position: String?

    var body: some View {
        GeometryReader { geo in
            let centerX = geo.frame(in: .global).midX
            ScrollView(.horizontal, showsIndicators: false) {
                // Negative spacing tucks the neighbors behind the front avatar;
                // zIndex keeps the one nearest center on top (dock effect).
                HStack(spacing: -itemSize * 0.22) {
                    ForEach(AvatarCatalog.carouselOrder, id: \.self) { key in
                        // Continuous magnification by distance from the carousel
                        // center, like the macOS Dock: big up front, small behind.
                        GeometryReader { cell in
                            let d = abs(cell.frame(in: .global).midX - centerX)
                            let t = min(d / (itemSize * 1.5), 1)
                            AvatarBadge(key: key, size: itemSize)
                                .overlay {
                                    if key == selected {
                                        Circle().strokeBorder(Theme.Color.accent, lineWidth: 4)
                                            .shadow(color: Theme.Color.accent.opacity(0.6), radius: 8)
                                    }
                                }
                                .scaleEffect(1.25 - 0.55 * t)
                                .opacity(1 - 0.4 * t)
                        }
                        .frame(width: itemSize, height: itemSize)
                        .zIndex(zRank(key))
                    }
                }
                .scrollTargetLayout()
                // Headroom for the 1.25x front scale (+ ring/glow): the scroll
                // view clips at its content height, so pad inside it.
                .padding(.vertical, itemSize * 0.16)
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - itemSize) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position)
            .onChange(of: position) { _, new in
                if let new, new != selected {
                    selected = new
                    Feedback.fire(.keyTap)
                }
            }
            .onAppear { position = selected }
        }
        .frame(height: itemSize * 1.32 + 16)
    }

    /// Cells closest to the current position draw on top of their neighbors.
    private func zRank(_ key: String) -> Double {
        let keys = AvatarCatalog.carouselOrder
        guard let sel = keys.firstIndex(of: position ?? selected),
              let idx = keys.firstIndex(of: key) else { return 0 }
        return -Double(abs(idx - sel))
    }
}
