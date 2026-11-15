import UIKit

public enum Haptics {
    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    public static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    public static func tick() { UISelectionFeedbackGenerator().selectionChanged() }

    /// Crisp tactile confirmation when finishing a single step (line learned, cue recorded, pose locked).
    public static func stepDone() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
    }

    /// Two-beat rewarding feedback for completing a milestone (all lines learned, rehearsal finished, 3/3 headshots).
    @MainActor
    public static func celebrate() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        }
    }
}
