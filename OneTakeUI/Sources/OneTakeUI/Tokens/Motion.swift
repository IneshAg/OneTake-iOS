import SwiftUI

/// Standardized spring motion design tokens for OneTakeUI.
/// Prefer these tokens over ad-hoc `.easeInOut` / `.easeOut` timing curves so
/// interactions across camera, prompter, cards, and milestones share cohesive physics.
public enum OTMotion {
    /// Crisp response for toggles, button presses, chips, and line selection.
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// Fluid settling for cards, prompter scroll tracking, and sheet detents.
    public static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.88)

    /// Expressive pop for milestone badges, learned checkmarks, and celebrations.
    public static let bouncy = Animation.spring(response: 0.46, dampingFraction: 0.68)

    /// Direct manipulation curve for scrubbers, drag gestures, and interactive zoom.
    public static let interactive = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.86)

    /// Gentle continuous ambient pulse for active recording dots and listening badges.
    public static let breathe = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
}

public extension View {
    /// Applies `animation` only when Reduce Motion is disabled; falls back to an instant crossfade.
    func otAnimation<V: Equatable>(_ animation: Animation, value: V, reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? .default : animation, value: value)
    }
}
