import SwiftUI
import OneTakeUI

// MARK: - Sides Chip

struct SidesChip: View {
    let title: String
    let value: String
    var isAccent: Bool = false

    var body: some View {
        HStack(spacing: OTSpace.xs) {
            Text(title + ":")
                .font(.otCaption)
                .foregroundStyle(isAccent ? OT.accent : OT.labelSecondary)
            Text(value)
                .font(.otCaption.weight(.bold))
                .foregroundStyle(isAccent ? OT.accent : OT.labelPrimary)
        }
        .padding(.horizontal, OTSpace.s)
        .padding(.vertical, OTSpace.xs)
        .background(isAccent ? OT.accentSoft : OT.surfaceCard, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                .stroke(isAccent ? OT.accent.opacity(0.3) : OT.separator, lineWidth: 1)
        )
    }
}
