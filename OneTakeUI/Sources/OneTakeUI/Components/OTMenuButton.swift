import SwiftUI

public struct OTMenuButton<Content: View>: View {
    public let title: String
    public let systemImage: String?
    public let variant: OTButtonVariant
    public let size: OTControlSize
    public let fullWidth: Bool
    private let content: () -> Content

    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: OTButtonVariant = .secondary,
        size: OTControlSize = .large,
        fullWidth: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
        self.content = content
    }

    public var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: OTSpace.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.otIcon(.s, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .buttonStyle(OTButtonStyle(variant, size: size, fullWidth: fullWidth))
    }
}
