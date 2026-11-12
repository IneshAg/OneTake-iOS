import SwiftUI
import OneTakeUI

// MARK: - Rich Role Breakdown Card

struct RoleBreakdownCard: View {
    let breakdown: AuditionRoleBreakdown
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            Button(action: onSelect) {
                HStack(spacing: OTSpace.s) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.otIcon(.s))
                    Text(breakdown.name)
                        .font(.otSubhead.weight(.semibold))
                    Spacer(minLength: 4)
                    let tags = [breakdown.gender, breakdown.ageRange].compactMap { $0 }
                    if !tags.isEmpty {
                        Text(tags.joined(separator: " · "))
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : OT.labelTertiary) // ot-lint:allow
                    }
                }
                .foregroundStyle(isSelected ? Color.white : OT.accent) // ot-lint:allow
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let desc = breakdown.description, !desc.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(desc)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, OTSpace.xs)
                } label: {
                    Text(isExpanded ? "Hide full description" : "View full role description")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : OT.labelSecondary) // ot-lint:allow
                }
                .tint(isSelected ? .white : OT.accent) // ot-lint:allow
            }
        }
        .padding(OTSpace.m)
        .background(isSelected ? OT.accent : OT.surfaceCard, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous).stroke(isSelected ? Color.clear : OT.separator, lineWidth: 1))
    }
}
