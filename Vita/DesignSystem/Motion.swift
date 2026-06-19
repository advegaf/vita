import SwiftUI

// Springs only for tactile moments; all <= 320ms so it reads as weight, not animation.
enum VMotion {
    static let segmentExpand = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// The dose-log "settle": smooth, near-critically-damped (no second bounce).
    /// The ring blooms and the checkmark draws on in this single motion.
    static let pinCommit     = Animation.spring(response: 0.4, dampingFraction: 0.86)
    static let cardEntrance  = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let cardStaggerStep: Double = 0.06 // 60ms per card
    /// The 1–10 slider's release: a small, classy overshoot (damping < 0.8).
    static let sliderSettle  = Animation.spring(response: 0.30, dampingFraction: 0.62)

    /// Reduce-Motion fallback: a single 0.2s opacity fade.
    static let reduced = Animation.easeOut(duration: 0.2)

    static func enter(reduceMotion: Bool) -> Animation { reduceMotion ? reduced : cardEntrance }
}
