import SwiftUI
import OneTakeUI

/// Step 1 of OCR Review: Material kind, milestone dates, audition name, character, candidate roles, casting office.
struct ReviewStepProjectView: View {
    @Binding var draft: NoticeParser.Draft
    @Binding var projectText: String
    @Binding var roleText: String
    @Binding var castingOfficeText: String
    @Binding var castingNotesText: String
    var focusedField: FocusState<OCRReviewSheet.FocusField?>.Binding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Header
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Text("Review what we read")
                        .font(.otTitle)
                    Text("Check project and character details before continuing.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }

                AuditionMaterialKindPicker(selected: $draft.materialKind, compact: true)

                if !draft.importantDates.isEmpty {
                    MilestoneDatesListCard(dates: draft.importantDates)
                }

                if let details = draft.projectDetails, details.hasReviewableContent {
                    ProjectDetailsCard(details: details)
                }

                reviewField(
                    label: "Audition name",
                    placeholder: "A name to recognize this audition",
                    text: $projectText,
                    isRequired: false,
                    field: .project
                )

                VStack(alignment: .leading, spacing: OTSpace.s) {
                    reviewField(
                        label: "Your role",
                        placeholder: "e.g. Alice",
                        text: $roleText,
                        isRequired: true,
                        field: .role
                    )

                    if !draft.candidateRoles.isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            Text("Detected roles")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OTSpace.s) {
                                    ForEach(draft.candidateRoles, id: \.self) { roleOption in
                                        Button {
                                            roleText = roleOption
                                            if let auto = NoticeParser.extractCharacterDescription(for: roleOption, in: draft.sourceText) {
                                                castingNotesText = auto
                                            }
                                            Haptics.tick()
                                        } label: {
                                            HStack(spacing: OTSpace.xs) {
                                                if roleText == roleOption {
                                                    Image(systemName: "checkmark")
                                                        .font(.otIcon(.xs))
                                                }
                                                Text(roleOption)
                                                    .font(.otCaption.weight(.semibold))
                                            }
                                            .padding(.horizontal, OTSpace.s)
                                            .padding(.vertical, OTSpace.xs)
                                            .background(roleText == roleOption ? OT.accent : OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                                            .foregroundStyle(roleText == roleOption ? Color.white : OT.labelPrimary) // ot-lint:allow
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                reviewField(
                    label: "Casting office (optional)",
                    placeholder: "e.g. Anti-Casting, Telsey + Co",
                    text: $castingOfficeText,
                    isRequired: false,
                    field: .castingOffice
                )
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.m)
            .padding(.bottom, OTSpace.xl)
        }
    }

    private func reviewField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isRequired: Bool,
        field: OCRReviewSheet.FocusField
    ) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            HStack(spacing: OTSpace.xs) {
                Text(label)
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelSecondary)
                if isRequired && text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Spacer()
                    Label("Not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.warning)
                }
            }
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .focused(focusedField, equals: field)
                .padding(OTSpace.m)
                .background(OT.fillField.opacity(0.5), in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                .overlay(
                    RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                        .stroke(
                            isRequired && text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? OT.warning.opacity(0.7) : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
    }
}
