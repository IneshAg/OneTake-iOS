import SwiftUI
import OneTakeUI

/// Step 3 of OCR Review: Due date, required deliverables (slate, headshots, full-body), casting asks, casting notes, actor notes, resume, notice image preview.
struct ReviewStepSpecsView: View {
    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date
    let asks: [String]
    let materialKind: AuditionMaterialKind
    @Binding var includeSlate: Bool
    @Binding var isSlateOptional: Bool
    @Binding var includeFullBodyShot: Bool
    @Binding var isFullBodyShotOptional: Bool
    @Binding var includeHeadshots: Bool
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
                    Text("Specs & Requirements")
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
                    Text("What to prepare")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                    VStack(spacing: 0) {
                        AuditionDeliverableRow(
                            title: "Slate / intro",
                            icon: "person.text.rectangle",
                            isIncluded: $includeSlate,
                            isOptional: $isSlateOptional,
                            isInclusionLocked: materialKind == .slateOnly,
                            lockedNote: "Required for Slate-only auditions"
                        )
                        Divider()
                        if asks.contains("Full-body shot") {
                            AuditionDeliverableRow(
                                title: "Full-body shot",
                                icon: "figure.stand",
                                isIncluded: $includeFullBodyShot,
                                isOptional: $isFullBodyShotOptional
                            )
                            Divider()
                        } else if asks.contains("Full-body shot with slate") {
                            AuditionDeliverableRow(
                                title: "Full-body view in slate",
                                icon: "figure.stand",
                                isIncluded: $includeFullBodyShot,
                                isOptional: $isFullBodyShotOptional
                            )
                            Divider()
                        }
                        AuditionDeliverableRow(
                            title: "Headshots",
                            icon: "person.crop.rectangle",
                            isIncluded: $includeHeadshots,
                            isOptional: $isHeadshotOptional
                        )
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
}

/// Shared deliverable row used across notice review screens to control both checklist
/// inclusion and required/optional status consistently.
struct AuditionDeliverableRow: View {
    let title: String
    var detail: String? = nil
    let icon: String
    @Binding var isIncluded: Bool
    @Binding var isOptional: Bool
    var isInclusionLocked: Bool = false
    var lockedNote: String? = nil

    private var effectiveIncluded: Bool {
        isInclusionLocked ? true : isIncluded
    }

    private var effectiveOptional: Bool {
        isInclusionLocked ? false : isOptional
    }

    private var statusText: String {
        if isInclusionLocked, let lockedNote {
            return lockedNote
        }
        guard effectiveIncluded else {
            return "Not included in checklist"
        }
        return effectiveOptional ? "Included · Optional" : "Included · Required"
    }

    var body: some View {
        HStack(spacing: OTSpace.s) {
            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Label(title, systemImage: icon)
                    .font(.otSubhead.weight(.medium))
                    .foregroundStyle(OT.labelPrimary)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.otCaption)
                        .foregroundStyle(OT.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(statusText)
                    .font(.otFootnote)
                    .foregroundStyle(effectiveIncluded && !effectiveOptional ? OT.accent : OT.labelSecondary)
            }

            Spacer(minLength: OTSpace.xs)

            if effectiveIncluded && !isInclusionLocked {
                Button(effectiveOptional ? "Optional" : "Required") {
                    isOptional.toggle()
                    Haptics.tick()
                }
                .font(.otCaption.weight(.bold))
                .fixedSize()
                .padding(.horizontal, OTSpace.s)
                .padding(.vertical, OTSpace.xs)
                .background(effectiveOptional ? OT.surfaceSunken : OT.accentSoft, in: Capsule())
                .foregroundStyle(effectiveOptional ? OT.labelSecondary : OT.accent)
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) status, \(effectiveOptional ? "optional" : "required"). Tap to switch.")
            }

            Toggle(title, isOn: Binding(
                get: { effectiveIncluded },
                set: { newValue in
                    guard !isInclusionLocked else { return }
                    isIncluded = newValue
                    Haptics.tick()
                }
            ))
            .labelsHidden()
            .tint(OT.accent)
            .disabled(isInclusionLocked)
        }
        .padding(.vertical, OTSpace.s)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusText)
    }
}
