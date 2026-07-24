import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Tiny local audio player for tray-tile/locked-slot tap-to-hear (Games Spec
/// §1: "tapping any letter tile says the letter name... Never gated" --
/// Spelling Builder's own §3.5 line never calls for a letter-SOUND tier the
/// way Missing Letter's does, so this only ever plays the letter's NAME, at
/// every tier). Self-contained here rather than a new `SpeechService`
/// method, same rationale as `MissingLetterLetterPlayer` and
/// `WordHuntLetterPlayer` -- this game's scope is its own folder only.
@MainActor
final class SpellingBuilderLetterPlayer {
    static let shared = SpellingBuilderLetterPlayer()
    private var player: AVAudioPlayer?

    func play(_ letter: Character) {
        let lower = String(letter).lowercased()
        guard let url = Bundle.main.url(forResource: "letter-\(lower)", withExtension: "m4a") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }
}

// MARK: - SpellingBuilderSFX

/// Tiny direct-playback helper for the two Spelling Builder-specific cues
/// (Games Spec §3.5/§4's `sfx_thunk` on a correct slot lock, `sfx_sparkle` on
/// a confident-voice-match tray unlock). Kept local to this folder rather
/// than adding cases to the shared `Feedback.Event` enum -- same pattern as
/// `SayMatchSFX`/`MemorySFX`. A light haptic rides along with the thunk
/// (mirrors `Feedback`'s own "haptic + sound, one call" shape) since this
/// bypasses `Feedback.fire` entirely to avoid layering its own `sfx_correct`
/// on top of the spec-named `sfx_thunk`. Silently no-ops if a clip isn't
/// bundled yet, same fallback behavior as `Feedback.play`.
enum SpellingBuilderSFX {
    private static var players: [String: AVAudioPlayer] = [:]

    static func playThunk() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        play("sfx_thunk")
    }

    static func playSparkle() { play("sfx_sparkle") }

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
