import SwiftUI
import OneTakeUI

struct NoticeDestinationCard: View {
    @Binding var destination: Destination
    @Binding var destinationDetail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            Picker("Destination", selection: $destination) {
                ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            TextField(
                destination == .emailOrLink
                    ? "Email address or submission link"
                    : "\(destination.rawValue) account or submission notes",
                text: Binding(
                    get: { destinationDetail ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        destinationDetail = trimmed.isEmpty ? nil : trimmed
                    }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(destination == .emailOrLink ? .emailAddress : .default)
            .padding(OTSpace.m)
            .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
        }
        .otCard(.grouped)
    }
}

struct NoticeNotesCard: View {
    @Binding var castingNotes: String?
    @Binding var actorNotes: String?

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            VStack(alignment: .leading, spacing: OTSpace.xs) {
                Text("Character details from casting").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                Text("The character description or direction copied from the notice.")
                    .font(.otCaption).foregroundStyle(OT.labelTertiary)
                TextField("Character breakdown, director notes", text: Binding(
                    get: { castingNotes ?? "" },
                    set: { castingNotes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(4...10)
                .fixedSize(horizontal: false, vertical: true)
                .padding(OTSpace.m)
                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
            }

            VStack(alignment: .leading, spacing: OTSpace.xs) {
                Text("My notes & understanding").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                TextField("Scene objective, choices, subtext", text: Binding(
                    get: { actorNotes ?? "" },
                    set: { actorNotes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ), axis: .vertical)
                .padding(OTSpace.m)
                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
            }
        }
        .otCard(.grouped)
    }
}
