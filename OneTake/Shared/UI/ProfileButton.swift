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
                } else {
                    Image(systemName: "person.fill")
                        .font(.otIcon(.m, weight: .semibold))
                        .foregroundStyle(OT.labelPrimary)
                        .frame(width: 44, height: 44) // ot-lint:allow 44pt touch target
                        .contentShape(Circle())
                }
            }
            .frame(width: 44, height: 44) // ot-lint:allow 44pt touch target
            .contentShape(Circle())
        }
        .modifier(GlassButtonCompatibility(enabled: true))
        .id(store.headshotVersion)
        .accessibilityLabel("Profile")
    }
}
