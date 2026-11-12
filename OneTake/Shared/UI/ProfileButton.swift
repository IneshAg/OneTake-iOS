import SwiftUI

// MARK: - Top bar Profile button

struct ProfileButton: View {
    var action: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        Button(action: action) {
            ZStack {
                if let front = HeadshotStore.load(key: "front") {
                    Image(uiImage: front)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44) // ot-lint:allow 44pt touch target
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5)) // ot-lint:allow
                } else {
                    Circle()
                        .fill(OT.accentSoft)
                        .frame(width: 44, height: 44) // ot-lint:allow 44pt touch target
                        .overlay(Circle().stroke(OT.accent.opacity(0.25), lineWidth: 1))
                    Image(systemName: "person.fill")
                        .font(.otIcon(.m, weight: .semibold))
                        .foregroundStyle(OT.accent)
                }
            }
            .frame(width: 44, height: 44) // ot-lint:allow 44pt touch target
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .id(store.headshotVersion)
        .accessibilityLabel("Profile")
    }
}
