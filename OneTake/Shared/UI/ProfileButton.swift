import SwiftUI

// MARK: - Top bar Profile button

struct ProfileButton: View {
    var action: () -> Void
    @Environment(AppStore.self) private var store

    private var strokeColor: Color {
        Color(UIColor(light: 0x1E1A22, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.85))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let front = HeadshotStore.load(key: "front") {
                    Image(uiImage: front)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(strokeColor, lineWidth: 1.5))
                } else {
                    Circle()
                        .fill(OT.accentSoft)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(OT.accent.opacity(0.25), lineWidth: 1))
                    Image(systemName: "person.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(OT.accent)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .id(store.headshotVersion)
        .accessibilityLabel("Profile")
    }
}
