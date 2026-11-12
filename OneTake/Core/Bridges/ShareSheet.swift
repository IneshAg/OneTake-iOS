import SwiftUI
import UIKit

// MARK: - Share sheet (UIActivityViewController)

/// "More ways to share" on the package screen — AirDrop, Mail, Messages, Files, or the casting
/// site's own app/upload if it's installed. `onComplete` reports whether the person actually
/// finished a share action (vs. dismissing), which is what "sent" should mean with no real backend.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var subject: String? = nil
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let subject, !subject.isEmpty {
            vc.setValue(subject, forKey: "subject")
        }
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete?(completed) }
        return vc
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
