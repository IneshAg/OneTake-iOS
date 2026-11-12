import SwiftUI

// MARK: - Sides Chip

struct SidesChip: View {
    let title: String
    let value: String
    var isAccent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title + ":")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAccent ? OT.accent : OT.labelSecondary)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isAccent ? OT.accent : OT.labelPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isAccent ? OT.accentSoft : OT.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAccent ? OT.accent.opacity(0.3) : OT.separator, lineWidth: 1)
        )
    }
}
