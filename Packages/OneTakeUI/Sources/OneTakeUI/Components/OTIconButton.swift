import SwiftUI

public struct OTIconButton: View {
    public let systemName: String
    public let accessibilityLabel: String
    public let action: () -> Void

    @Environment(\.otSurface) private var otSurface: OTSurface

    public init(
        _ systemName: String,
        accessibilityLabel: String = "",
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel.isEmpty ? systemName : accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.otIcon(.m, weight: .semibold))
                .foregroundStyle(otSurface == .camera ? OT.cameraLabel : OT.labelPrimary)
                .frame(width: 44, height: 44) // ot-lint:allow
                .contentShape(Circle())
        }
        .modifier(GlassButtonCompatibility(enabled: true))
        .accessibilityLabel(accessibilityLabel)
    }
}
