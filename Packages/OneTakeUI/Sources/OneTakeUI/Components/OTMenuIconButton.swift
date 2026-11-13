import SwiftUI

/// Canonical circular glass menu button for navigation and header actions.
public struct OTMenuIconButton<Content: View>: View {
    public let systemName: String
    public let accessibilityLabel: String
    public let tintColor: Color?
    private let content: () -> Content

    @Environment(\.otSurface) private var otSurface: OTSurface

    public init(
        _ systemName: String,
        accessibilityLabel: String = "",
        tintColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel.isEmpty ? systemName : accessibilityLabel
        self.tintColor = tintColor
        self.content = content
    }

    public var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: systemName)
                .font(.otIcon(.m, weight: .semibold))
                .foregroundStyle(tintColor ?? (otSurface == .camera ? OT.cameraLabel : OT.labelPrimary))
                .frame(width: 44, height: 44) // ot-lint:allow
                .contentShape(Circle())
        }
        .modifier(GlassButtonCompatibility(enabled: true))
        .accessibilityLabel(accessibilityLabel)
    }
}
