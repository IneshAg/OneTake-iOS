import SwiftUI
import OneTakeUI

// MARK: - Sides Input Tiles (Native iOS quick action buttons)

struct SidesInputTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: OTSpace.m) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40) // ot-lint:allow
                Image(systemName: icon)
                    .font(.otIcon(.m))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text(title)
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
                Text(subtitle)
                    .font(.otCaption)
                    .foregroundStyle(OT.labelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OTSpace.m)
        .padding(.vertical, OTSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: OTRadius.control, style: .continuous)) // ot-lint:allow
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.control, style: .continuous)
                .stroke(OT.separator, lineWidth: 1)
        )
    }
}
