import SwiftUI

public struct OTScheduleRow: View {
    public let eyebrow: String
    public let value: String
    public let title: String
    public let detail: String
    public var trailing: AnyView?

    public init(
        eyebrow: String,
        value: String,
        title: String,
        detail: String,
        trailing: AnyView? = nil
    ) {
        self.eyebrow = eyebrow
        self.value = value
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: OTSpace.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrow)
                    .font(.otEyebrow)
                    .foregroundStyle(OT.labelTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
            }
            .frame(width: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text(title)
                    .font(.otBody)
                    .foregroundStyle(OT.labelPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: OTSpace.s)

            if let trailing {
                trailing
            }

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OT.labelTertiary)
        }
        .frame(minHeight: OT.rowHeight)
        .contentShape(Rectangle())
    }
}
