import SwiftUI

public struct OTIconRow: View {
    public let symbol: String
    public let title: String
    public let detail: String
    public let tint: Color

    public init(symbol: String, title: String, detail: String = "", tint: Color = OT.accent) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: OTSpace.l) {
            Image(systemName: symbol)
                .font(.otIcon(.l, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))

            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text(title)
                    .font(.otBody)
                    .foregroundStyle(OT.labelPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OT.labelTertiary)
        }
        .padding(.vertical, OTSpace.s)
    }
}
