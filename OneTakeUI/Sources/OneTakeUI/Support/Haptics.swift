import UIKit

public enum Haptics {
    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    public static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    public static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}
