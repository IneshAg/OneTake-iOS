import SwiftUI

// MARK: - Audition Material Kind Picker

struct AuditionMaterialKindPicker: View {
    @Binding var selected: AuditionMaterialKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(AuditionMaterialKind.allCases) { kind in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selected = kind }
                        Haptics.tick()
                    } label: {
                        Label(kind.shortLabel, systemImage: kind.icon)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected.icon)
                        .foregroundStyle(OT.accent)
                    Text(selected.shortLabel)
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OT.labelTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            Text(selected.description)
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
        }
    }
}
