import Foundation
import AVFoundation

/// Tiny local audio player for tray-tile tap-to-hear (Games Spec §3.4: "Tap
/// tile = letter name (T1) / letter SOUND (T2+)"). Self-contained here rather
/// than a new `SpeechService` method, same rationale as
/// `WordHuntLetterPlayer` (that type's own doc comment) — this game's scope
/// is its own folder only.
///
/// T2+'s `sound-<letter>.m4a` clips are a WP-G2 asset that may not exist yet,
/// or may have been excluded for quality (Games Spec §4: "any bad `sound-*`
/// clip is EXCLUDED and app falls back to letter name; phonics accuracy >
/// coverage") — that exclusion happens at asset-authoring time, not here;
/// this player only ever does the one thing it *can* check at runtime,
/// which is "does the file exist in the bundle right now". A missing
/// `sound-*` clip falls back to the `letter-*` name clip; a missing
/// `letter-*` clip (shouldn't happen — every letter has one) silently no-ops,
/// same as `WordHuntLetterPlayer`.
@MainActor
final class MissingLetterLetterPlayer {
    static let shared = MissingLetterLetterPlayer()
    private var player: AVAudioPlayer?

    /// `tier == .t1` plays the letter's NAME; `.t2`/`.t3` prefer its SOUND,
    /// falling back to the name when no sound clip is bundled.
    func play(_ letter: Character, tier: GameTier) {
        let lower = String(letter).lowercased()
        if tier != .t1, let soundURL = Bundle.main.url(forResource: "sound-\(lower)", withExtension: "m4a") {
            play(url: soundURL)
            return
        }
        guard let nameURL = Bundle.main.url(forResource: "letter-\(lower)", withExtension: "m4a") else { return }
        play(url: nameURL)
    }

    private func play(url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }
}
