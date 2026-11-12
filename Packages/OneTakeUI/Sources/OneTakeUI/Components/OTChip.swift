import SwiftUI

public struct OTChip: View {
    public let title: String
    public let systemImage: String?
    public let isSelected: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: {
            Haptics.tick()
            action()
        }) {
            HStack(spacing: OTSpace.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.otIcon(.s))
                }
                Text(title)
            }
        }
        .buttonStyle(OTButtonStyle(isSelected ? .primary : .secondary, size: .small, fullWidth: false))
    }
}
