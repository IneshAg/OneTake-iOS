import SwiftUI

// MARK: - Headshot photo

struct HeadshotImage: View {
    /// Which of the actor's own headshots to show (`front`, `left`, `right`). Without one taken —
    /// or with no key — it's a neutral silhouette, never a stand-in photo of someone else.
    var realKey: String? = nil
    var auditionID: UUID? = nil
    var iconSize: CGFloat? = nil
    var onDark: Bool = false

    var body: some View {
        if let realKey, let real = HeadshotStore.load(key: realKey, auditionID: auditionID) {
            Color.clear
                .overlay {
                    Image(uiImage: real)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .contentShape(Rectangle())
        } else if onDark {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "person.fill").font(.system(size: iconSize ?? 40)).foregroundStyle(.white.opacity(0.35)))
        } else {
            ZStack {
                OT.accentSoft
                Image(systemName: "person.fill")
                    .font(.system(size: iconSize ?? 22, weight: .semibold))
                    .foregroundStyle(OT.accent)
            }
        }
    }
}
