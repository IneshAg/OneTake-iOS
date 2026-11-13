import SwiftUI
import OneTakeUI

/// Step 3 of OCR Review: Due date, required deliverables (slate, headshots, full-body), casting asks, casting notes, actor notes, resume, notice image preview.
struct ReviewStepSpecsView: View {
    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date
    let asks: [String]
    @Binding var isSlateOptional: Bool
    @Binding var isFullBodyShotOptional: Bool
    @Binding var isHeadshotOptional: Bool
    @Binding var castingNotesText: String
    @Binding var actorNotesText: String
    @Binding var includeResume: Bool
    @Binding var resumeURL: URL?
    let sourcePreview: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Header
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Label("Specs & Requirements", systemImage: "list.bullet.clipboard")
                        .font(.otTitle)
                    Text("Deadlines, required shots, and character instructions.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }

                // Due date
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Label("Due date", systemImage: "calendar")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)

                    Toggle("Tape deadline found", isOn: $hasDueDate)
                        .font(.otFootnote)
                        .tint(OT.accent)

                    if hasDueDate {
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    } else {
                        Text("No deadline found — you can set one later.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelSecondary)
                    }
                }
                .otCard(.grouped)

                // Deliverables in flow (Slate & Headshots)
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    Label("What to prepare", systemImage: "list.bullet.rectangle")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: OTSpace.s) {
                        deliverableToggle(title: "Slate / intro", icon: "person.text.rectangle", isOptional: $isSlateOptional)
                        if asks.contains("Full-body shot") {
                            deliverableToggle(title: "Full-body shot", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                        } else if asks.contains("Full-body shot with slate") {
                            deliverableToggle(title: "Full-body view in slate", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                        }
                        deliverableToggle(title: "Headshots", icon: "person.crop.rectangle", isOptional: $isHeadshotOptional)
                    }
                }
                .otCard(.grouped)

                // Requested by casting
                if !asks.isEmpty {
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        Label("Requested by casting", systemImage: "checkmark.circle")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            ForEach(Array(asks.enumerated()), id: \.offset) { _, ask in
                                HStack(alignment: .top, spacing: OTSpace.s) {
                                    Image(systemName: symbol(for: ask))
                                        .font(.otIcon(.s))
                                        .foregroundStyle(OT.accent)
                                        .frame(width: 20) // ot-lint:allow
                                    Text(ask)
                                        .font(.otFootnote.weight(.medium))
                                        .foregroundStyle(OT.labelPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .otCard(.elevated)
                }

                // Notes from casting
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Label("Character details from the notice", systemImage: "person.text.rectangle")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                    Text("What casting says about the character. You can edit this.")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)
                    TextField("Character description", text: $castingNotesText, axis: .vertical)
                        .lineLimit(4...10)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(OTSpace.m)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                }

                // My notes & understanding
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    HStack(spacing: OTSpace.xs) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(OT.accent)
                            .frame(width: 18) // ot-lint:allow
                        Text("My notes & understanding")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                    }
                    TextField("My choices, subtext, questions", text: $actorNotesText)
                        .textInputAutocapitalization(.sentences)
                        .padding(OTSpace.m)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                }

                if asks.contains(where: { $0.localizedCaseInsensitiveContains("resume") || $0.localizedCaseInsensitiveContains("résumé") }) {
                    AuditionResumePicker(
                        isIncluded: $includeResume,
                        selectedURL: $resumeURL
                    )
                }

                if let sourcePreview {
                    DisclosureGroup {
                        Image(uiImage: sourcePreview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                            .accessibilityLabel("Full original casting notice image")
                    } label: {
                        Label("View full notice image", systemImage: "photo")
                            .font(.otSubhead.weight(.semibold))
                            .foregroundStyle(OT.labelPrimary)
                    }
                    .tint(OT.accent)
                    .otCard(.elevated)
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.m)
            .padding(.bottom, OTSpace.xl)
        }
    }

    private func symbol(for ask: String) -> String {
        let value = ask.lowercased()
        if value.contains("headshot") || value.contains("photo") { return "person.crop.rectangle" }
        if value.contains("resume") || value.contains("résumé") { return "doc.text" }
        if value.contains("video") || value.contains("self-tape") || value.contains("intro") { return "video" }
        if value.contains("email") || value.contains("link") || value.contains("whatsapp") { return "paperplane" }
        if value.contains("landscape") || value.contains("portrait") { return "rectangle.portrait.rotate" }
        if value.contains("slate") { return "person.text.rectangle" }
        return "checkmark"
    }

    private func deliverableToggle(title: String, icon: String, isOptional: Binding<Bool>) -> some View {
        Button {
            isOptional.wrappedValue.toggle()
            Haptics.tick()
        } label: {
            VStack(alignment: .leading, spacing: OTSpace.s) {
                Label(title, systemImage: icon)
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(isOptional.wrappedValue ? "Optional" : "Required")
                    .font(.otCaption.weight(.bold))
                    .foregroundStyle(isOptional.wrappedValue ? OT.labelSecondary : OT.accent)
                    .padding(.horizontal, OTSpace.s)
                    .padding(.vertical, OTSpace.xs)
                    .background(isOptional.wrappedValue ? OT.surfaceSunken : OT.accentSoft, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OTSpace.m)
            .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(isOptional.wrappedValue ? "optional" : "required"). Tap to change.")
    }
}
