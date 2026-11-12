import SwiftUI

public struct OTChip: View {
    public let title: String
    public let systemImage: String?
    public let isSelected: Bool
    public let tint: Color?
    public let action: (() -> Void)?

    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        tint: Color? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    private var content: some View {
        HStack(spacing: OTSpace.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.otIcon(.s))
            }
            Text(title)
                .font(.otCaption)
        }
    }

    public var body: some View {
        if let action {
            Button(action: {
                Haptics.tick()
                action()
            }) {
                content
            }
            .buttonStyle(OTButtonStyle(isSelected ? .primary : .secondary, size: .small, fullWidth: false))
        } else {
            content
                .foregroundStyle(tint ?? OT.labelSecondary)
                .padding(.horizontal, OTSpace.s)
                .padding(.vertical, OTSpace.xxs)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint?.opacity(0.14) ?? OT.fillQuiet)
                )
        }
    }
}
