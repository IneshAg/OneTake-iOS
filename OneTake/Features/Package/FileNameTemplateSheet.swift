import SwiftUI

/// A bottom sheet that lets the actor override the deliverable filename pattern for a specific
/// audition. Supports {firstName}, {lastName}, {name}, {role}, {project}, {side}, {scene}, {take}.
/// Leaving the field blank reverts to the app default (`LAST_FIRST_ROLE_PROJECT.mp4`).
struct FileNameTemplateSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""

    private let tokens = ["{firstName}", "{lastName}", "{name}", "{role}", "{project}", "{side}", "{scene}", "{take}"]

    private var audition: Audition? { store.audition(auditionID) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Description
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Text("Match Casting's Instructions")
                        .font(.otHeadline)
                    Text("Enter the exact filename pattern casting asked for. Use tokens for the parts that vary. Leave blank to use the OneTake default.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }

                // Template text field
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Text("Pattern")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.labelTertiary)
                    TextField(
                        "{lastName}_{firstName}_{role}_{project}",
                        text: $draft,
                        axis: .vertical
                    )
                    .font(.system(size: 14, weight: .medium, design: .monospaced)) // ot-lint:allow
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(OTSpace.m)
                    .background(OT.surfaceSunken) // ot-lint:allow
                    .clipShape(RoundedRectangle(cornerRadius: OTRadius.m))

                    if !draft.isEmpty {
                        Text("Preview: \(previewName)")
                            .font(.system(size: 11, design: .monospaced)) // ot-lint:allow
                            .foregroundStyle(OT.accent)
                            .lineLimit(2)
                    }
                }

                // Token chips
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    Text("Available tokens — tap to insert")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: OTSpace.s)], spacing: OTSpace.s) {
                        ForEach(tokens, id: \.self) { token in
                            Button {
                                draft += (draft.isEmpty ? "" : "_") + token
                            } label: {
                                Text(token)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced)) // ot-lint:allow
                                    .padding(.horizontal, OTSpace.s)
                                    .padding(.vertical, OTSpace.xs)
                                    .frame(maxWidth: .infinity)
                                    .background(OT.accentSoft)
                                    .foregroundStyle(OT.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: OTRadius.s))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Reset button
                if audition?.submissionInstructions?.fileNameTemplate?.isEmpty == false {
                    Button(role: .destructive) {
                        store.setFileNameTemplate(nil, for: auditionID)
                        dismiss()
                    } label: {
                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.ot(.destructive, size: .medium))
                }

                Spacer()
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.l)
            .navigationTitle("Filename Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setFileNameTemplate(draft.isEmpty ? nil : draft, for: auditionID)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                draft = audition?.submissionInstructions?.fileNameTemplate ?? ""
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var previewName: String {
        guard let a = audition else { return draft }
        let slate = store.slate
        var mockInstructions = AuditionSubmissionInstructions()
        mockInstructions.fileNameTemplate = draft
        var mockAudition = a
        mockAudition.submissionInstructions = mockInstructions
        return mockAudition.deliverableFileName(slate: slate)
    }
}
