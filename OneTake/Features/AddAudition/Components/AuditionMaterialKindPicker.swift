import SwiftUI
import OneTakeUI

// MARK: - Audition Material Kind Picker

struct AuditionMaterialKindPicker: View {
    @Binding var selected: AuditionMaterialKind

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
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
                HStack(spacing: OTSpace.m) {
                    Image(systemName: selected.icon)
                        .foregroundStyle(OT.accent)
                    Text(selected.shortLabel)
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.otIcon(.xs))
                        .foregroundStyle(OT.labelTertiary)
                }
                .padding(.horizontal, OTSpace.m)
                .padding(.vertical, OTSpace.s)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.control, style: .continuous)) // ot-lint:allow
            }

            Text(selected.description)
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
        }
    }
}
