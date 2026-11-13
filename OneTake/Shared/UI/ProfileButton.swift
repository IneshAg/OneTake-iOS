import SwiftUI

// MARK: - Top bar Profile button

struct ProfileButton: View {
    var action: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        Button(action: action) {
            if let front = HeadshotStore.load(key: "front") {
                Image(uiImage: front)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30) // ot-lint:allow nav-bar avatar size
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1)) // ot-lint:allow
            } else {
                Label("Profile", systemImage: "person")
            }
        }
        .id(store.headshotVersion)
        .accessibilityLabel("Profile")
    }
}
