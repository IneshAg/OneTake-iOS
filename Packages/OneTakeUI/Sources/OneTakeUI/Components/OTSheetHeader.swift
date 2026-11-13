import SwiftUI

public struct OTSheetHeader: View {
    public let title: String
    public var leading: String?
    public var trailing: String?
    public var onLeading: () -> Void
    public var onTrailing: () -> Void

    public init(
        title: String,
        leading: String? = "Cancel",
        trailing: String? = nil,
        onLeading: @escaping () -> Void = {},
        onTrailing: @escaping () -> Void = {}
    ) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
        self.onLeading = onLeading
        self.onTrailing = onTrailing
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(.otHeadline)
                .foregroundStyle(OT.labelPrimary)
                .lineLimit(1)
                .padding(.horizontal, 76)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                if let leading {
                    Button(leading, action: onLeading)
                        .font(.body)
                        .foregroundStyle(OT.accent)
                        .frame(minHeight: OTControlSize.large.height)
                }
                Spacer()
                if let trailing {
                    Button(trailing, action: onTrailing)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(OT.accent)
                        .frame(minHeight: OTControlSize.large.height)
                }
            }
        }
        .frame(minHeight: OTControlSize.large.height)
        .padding(.horizontal, OTSpace.gutter)
    }
}
