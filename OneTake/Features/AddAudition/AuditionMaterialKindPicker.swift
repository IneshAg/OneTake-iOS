import SwiftUI
import OneTakeUI

// MARK: - Audition Material Kind Picker

struct AuditionMaterialKindPicker: View {
    @Binding var selected: AuditionMaterialKind

    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            if compact {
                HStack {
                    Text("Audition type")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                    Spacer()
                    picker.labelsHidden()
                }
            } else {
                picker
            }

            Text(selected.description)
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
        }
    }

    private var picker: some View {
        Picker("Audition Type", selection: $selected) {
            ForEach(AuditionMaterialKind.allCases) { kind in
                if compact {
                    Text(kind.shortLabel).tag(kind)
                } else {
                    Label(kind.shortLabel, systemImage: kind.icon).tag(kind)
                }
            }
        }
        .pickerStyle(.menu)
        .onChange(of: selected) { _, _ in
            Haptics.tick()
        }
    }
}
