import SwiftUI

public struct OTCallout<Actions: View>: View {
    public let systemImage: String
    public let title: String
    public let message: String
    public let tint: Color
    private let actions: () -> Actions

    public init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = OT.accent,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            HStack(alignment: .top, spacing: OTSpace.m) {
                Image(systemName: systemImage)
                    .font(.otIcon(.xl))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                    }
                    if !message.isEmpty {
                        Text(message)
                            .font(.otCallout)
                            .foregroundStyle(OT.labelSecondary)
                    }
                }
            }

            let renderedActions = actions()
            if !(renderedActions is EmptyView) {
                renderedActions
            }
        }
        .otCard(.grouped)
    }
}
