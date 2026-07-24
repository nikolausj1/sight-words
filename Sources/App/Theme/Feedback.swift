import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Haptics + sound, routed through one place. Sounds play 1:1 with motion events.
/// Drop `sfx_*` files into Resources/Audio and they play automatically; until
/// then this is haptics-only (missing sound files silently no-op).
enum Feedback {
    static var soundEnabled = true

    enum Event {
        case keyTap
        case correct
        case almost
        case reteach
        case sessionComplete
        /// GameKit's shared wrong-answer treatment (Games Spec §1): soft
        /// "boing", no scolding. Plays `sfx_pop` when that clip exists;
        /// silently no-ops (haptic still fires) until it's added.
        case boing
    }

    static func fire(_ event: Event) {
        haptic(event)
        guard soundEnabled, let name = soundName(event) else { return }
        play(name)
    }

    private static func soundName(_ e: Event) -> String? {
        switch e {
        case .keyTap:         return "sfx_key"
        case .correct:        return "sfx_correct"
        case .almost:         return "sfx_almost"
        case .reteach:        return "sfx_reteach"
        case .sessionComplete: return "sfx_complete"
        case .boing:          return "sfx_pop"
        }
    }

    // MARK: Audio

    private static var players: [String: AVAudioPlayer] = [:]
    private static var sessionReady = false

    private static func play(_ name: String) {
        prepareSession()
        if let p = players[name] { p.currentTime = 0; p.play(); return }
        for ext in ["wav", "caf", "m4a", "mp3"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay(); players[name] = p; p.play(); return
            }
        }
        // No audio asset yet → silently skip (haptics already fired).
    }

    private static func prepareSession() {
        #if canImport(UIKit)
        guard !sessionReady else { return }
        // .ambient so the app never interrupts the child's music/podcast.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionReady = true
        #endif
    }

    // MARK: Haptics

    private static func haptic(_ event: Event) {
        #if canImport(UIKit)
        switch event {
        case .keyTap:          UISelectionFeedbackGenerator().selectionChanged()
        case .correct:         impact(.light)
        case .almost:          impact(.soft)
        case .reteach:         impact(.soft)
        case .sessionComplete: notify(.success)
        case .boing:           impact(.soft)
        }
        #endif
    }

    #if canImport(UIKit)
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style); g.impactOccurred()
    }
    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    #endif
}
