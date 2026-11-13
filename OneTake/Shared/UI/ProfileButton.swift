import SwiftUI
import OneTakeUI

/// A profile button displaying the actor's front headshot if taken, or a fallback person icon.
struct ProfileButton: View {
    @Environment(AppStore.self) private var store
    let action: () -> Void

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
        .modifier(GlassButtonCompatibility(enabled: true))
        .id(store.headshotVersion)
        .accessibilityLabel("Profile")
    }
}
