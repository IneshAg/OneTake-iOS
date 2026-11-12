import SwiftUI

// MARK: - Rich Role Breakdown Card

struct RoleBreakdownCard: View {
    let breakdown: AuditionRoleBreakdown
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text(breakdown.name)
                        .font(.otSubhead.weight(.semibold))
                    Spacer(minLength: 4)
                    let tags = [breakdown.gender, breakdown.ageRange].compactMap { $0 }
                    if !tags.isEmpty {
                        Text(tags.joined(separator: " · "))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : OT.labelTertiary)
                    }
                }
                .foregroundStyle(isSelected ? Color.white : OT.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let desc = breakdown.description, !desc.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(desc)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } label: {
                    Text(isExpanded ? "Hide full description" : "View full role description")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : OT.labelSecondary)
                }
                .tint(isSelected ? .white : OT.accent)
            }
        }
        .padding(12)
        .background(isSelected ? OT.accent : OT.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? Color.clear : OT.separator, lineWidth: 1))
    }
}
