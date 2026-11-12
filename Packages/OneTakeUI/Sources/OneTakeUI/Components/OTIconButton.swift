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
                .font(.otIcon(.l))
                .foregroundStyle(otSurface == .camera ? OT.cameraLabel : OT.labelPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(otSurface == .camera ? OT.cameraGlass : Color.white.opacity(0.12))
                        .background(.ultraThinMaterial, in: Circle())
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(otSurface == .camera ? 0.18 : 0.5), lineWidth: 0.7)
                )
                .contentShape(Circle())
        }
        .buttonStyle(OTPressStyle(.icon))
        .accessibilityLabel(accessibilityLabel)
    }
}
