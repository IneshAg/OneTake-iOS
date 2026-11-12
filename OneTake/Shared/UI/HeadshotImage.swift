import SwiftUI
import OneTakeUI

// MARK: - Headshot photo

struct HeadshotImage: View {
    /// Which of the actor's own headshots to show (`front`, `left`, `right`). Without one taken —
    /// or with no key — it's a neutral silhouette, never a stand-in photo of someone else.
    var realKey: String? = nil
    var auditionID: UUID? = nil
    var iconSize: CGFloat? = nil
    @Environment(\.otSurface) private var otSurface

    var body: some View {
        let isDark = otSurface == .camera
        if let realKey, let real = HeadshotStore.load(key: realKey, auditionID: auditionID) {
            Color.clear
                .overlay {
                    Image(uiImage: real)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .contentShape(Rectangle())
        } else if isDark {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom) // ot-lint:allow
                .overlay(Image(systemName: "person.fill").font(.system(size: iconSize ?? 40)).foregroundStyle(.white.opacity(0.35))) // ot-lint:allow
        } else {
            ZStack {
                OT.accentSoft
                Image(systemName: "person.fill")
                    .font(.system(size: iconSize ?? 22, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.accent)
            }
        }
    }
}
