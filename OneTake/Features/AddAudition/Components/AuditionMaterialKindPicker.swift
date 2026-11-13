import SwiftUI
import OneTakeUI

// MARK: - Audition Material Kind Picker

struct AuditionMaterialKindPicker: View {
    @Binding var selected: AuditionMaterialKind

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            Picker("Audition Type", selection: $selected) {
                ForEach(AuditionMaterialKind.allCases) { kind in
                    Label(kind.shortLabel, systemImage: kind.icon).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selected) { _, _ in
                Haptics.tick()
            }

            Text(selected.description)
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
        }
    }
}
