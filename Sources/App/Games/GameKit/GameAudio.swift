import Foundation
import AVFoundation

/// One shared audio player pool for every GameKit game's local letter/SFX
/// clips (Games Spec §1/§4). Replaces six near-identical per-game helpers
/// that each kept their own `AVAudioPlayer` dictionary/instance and
/// duplicated the same "try each extension, cache by name" lookup:
/// `WordHuntLetterPlayer`, `MissingLetterLetterPlayer`,
/// `SpellingBuilderLetterPlayer`, `SpellingBuilderSFX`, `MemorySFX`, and
/// `SayMatchSFX`.
///
/// - `playLetter(_:)` -- a letter's NAME (`letter-<x>.m4a`). Games Spec §1:
///   "tapping any letter tile says the letter name... never gated" -- always
///   plays, independent of `Feedback.soundEnabled`, same as speech.
/// - `playLetterSound(_:)` -- a letter's SOUND (`sound-<x>.m4a`), falling
///   back to its name clip when no sound clip is bundled (or was excluded
///   for quality, Games Spec §4: "phonics accuracy > coverage"). Always
///   plays, same rule as `playLetter`. Callers that need Missing Letter's
///   "T1 plays the name, T2+ plays the sound" tier split call whichever of
///   the two methods applies at their own call site.
/// - `playSFX(_:)` -- a one-off cue by bundle resource name (e.g.
///   `"sfx_bloop"`). Respects `Feedback.soundEnabled`: muted when the parent
///   has turned sound off, matching every game's previous per-file SFX
///   helper. Letters/speech are never gated by this flag.
@MainActor
final class GameAudio {
    static let shared = GameAudio()
    private init() {}

    private var players: [String: AVAudioPlayer] = [:]

    func playLetter(_ letter: Character) {
        play(resource: "letter-\(String(letter).lowercased())")
    }

    func playLetterSound(_ letter: Character) {
        let lower = String(letter).lowercased()
        if play(resource: "sound-\(lower)") { return }
        play(resource: "letter-\(lower)")
    }

    func playSFX(_ name: String) {
        guard Feedback.soundEnabled else { return }
        play(resource: name)
    }

    /// Tries every known clip extension, caching the first hit by resource
    /// name (so repeat plays reuse the same `AVAudioPlayer`, restarted from
    /// the top). Returns whether anything actually played, so
    /// `playLetterSound` can fall back to the name clip when no sound clip
    /// is bundled.
    @discardableResult
    private func play(resource name: String) -> Bool {
        if let p = players[name] {
            p.currentTime = 0
            p.play()
            return true
        }
        for ext in ["m4a", "wav", "caf", "mp3"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                players[name] = p
                p.play()
                return true
            }
        }
        return false
    }
}
