import SwiftUI

public struct OTEmptyState: View {
    public let illustration: Image?
    public let title: String
    public let message: String
    public let action: (title: String, run: () -> Void)?

    public init(
        illustration: Image? = nil,
        title: String,
        message: String,
        action: (title: String, run: () -> Void)? = nil
    ) {
        self.illustration = illustration
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(spacing: OTSpace.l) {
            if let illustration {
                illustration
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 160, maxHeight: 160)
            }

            VStack(spacing: OTSpace.s) {
                Text(title)
                    .font(.otTitle)
                    .foregroundStyle(OT.labelPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.otBody)
                    .foregroundStyle(OT.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.ot(.primary, size: .large, fullWidth: false))
                    .padding(.top, OTSpace.s)
            }
        }
        .padding(.horizontal, OTSpace.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
