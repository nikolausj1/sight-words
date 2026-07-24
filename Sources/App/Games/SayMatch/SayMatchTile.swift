import SwiftUI
import AVFoundation

// MARK: - SayMatchTile

/// One floating word tile (Games Spec §3.2: "simple floating ChunkyKey-ish
/// tiles... no balloons"). Bobs gently in place forever; a caller drives
/// `isHighlighted` (the correct tile, on a correct tap) and `isDrifted`
/// (every other tile, drifting off-screen) -- this view owns only its own
/// idle motion and appearance, never scoring.
struct SayMatchTile: View {
    let text: String
    var fastBob = false
    var isHighlighted = false
    var isDrifted = false
    var action: () -> Void = {}

    @State private var bobUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Theme.Font.display(32))
                .foregroundStyle(Theme.Color.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(minWidth: 130, minHeight: 96)
                .padding(.horizontal, Theme.Metric.gap)
                .background(tileBackground)
        }
        .buttonStyle(PopButtonStyle())
        .scaleEffect(isHighlighted && !reduceMotion ? 1.15 : 1.0)
        .opacity(isDrifted ? 0 : 1)
        .offset(x: isDrifted && !reduceMotion ? 260 : 0,
                y: (bobUp && !reduceMotion ? -6 : 0) + (isDrifted ? 30 : 0))
        .allowsHitTesting(!isDrifted && !isHighlighted)
        .animation(Theme.Motion.snappy, value: isDrifted)
        .animation(Theme.Motion.snappy, value: isHighlighted)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: fastBob ? 0.55 : 1.1).repeatForever(autoreverses: true)) {
                bobUp = true
            }
        }
        .accessibilityLabel(text)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
            .fill(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                    .strokeBorder(Theme.Color.primary.opacity(0.35), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

// MARK: - SayMatchSFX

/// Tiny direct-playback helper for the one Say & Match-specific cue not
/// already routed through `Feedback` (Games Spec §4's `sfx_whoosh`, played
/// when the wrong tiles drift off on a correct tap). Kept local to this
/// folder rather than adding a case to the shared `Feedback.Event` enum
/// (Theme/Feedback.swift is outside this game's folder per the registration
/// contract). Silently no-ops if the clip isn't bundled, same fallback
/// behavior as `Feedback.play`.
enum SayMatchSFX {
    private static var players: [String: AVAudioPlayer] = [:]

    static func playWhoosh() { play("sfx_whoosh") }

    private static func play(_ name: String) {
        if let p = players[name] { p.currentTime = 0; p.play(); return }
        for ext in ["m4a", "wav", "caf", "mp3"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay(); players[name] = p; p.play(); return
            }
        }
    }
}
