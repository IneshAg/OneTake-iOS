import SwiftUI
import OneTakeUI

/// Shown after every scan, photo import, file import, and share-sheet import so the actor
/// can verify what OneTake read before it is committed to an audition draft.
/// The actor can correct individual fields inline; tapping "Use this" proceeds.
struct OCRReviewSheet: View {
    @Environment(AppStore.self) private var store
    /// The draft that the parser produced — presented as editable fields.
    @State var draft: NoticeParser.Draft
    let sourcePreview: UIImage?
    let onConfirm: (NoticeParser.Draft, AddAuditionFlow.ReaderAudioPlan) -> Void
    let onDiscard: () -> Void

    private enum FocusField: Hashable {
        case project, role, castingOffice
    }
    @FocusState private var focusedField: FocusField?

    @State private var projectText: String
    @State private var roleText: String
    @State private var castingOfficeText: String
    @State private var sidesLinkText: String
    @State private var destinationDetailText: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var castingNotesText: String
    @State private var actorNotesText: String
    @State private var isSlateOptional: Bool
    @State private var isFullBodyShotOptional: Bool
    @State private var isHeadshotOptional: Bool
    @State private var includeSlate: Bool
    @State private var includeHeadshots: Bool
    @State private var selectedPortionIDs: Set<String>
    @State private var readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .recordNow

    private var hasReaderLines: Bool {
        let effective = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effective.isEmpty, draft.hasSides else { return false }
        let scenes = draft.hasSides
            ? ((draft.customScenes?.isEmpty == false ? draft.customScenes : nil) ?? ScriptParser.parseScenes(from: draft.sourceText, myRole: effective))
            : []
        return scenes.contains { $0.lines.contains { !$0.isMine } }
    }

    private var detectedReaderName: String {
        let effective = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let scenes = (draft.customScenes?.isEmpty == false ? draft.customScenes : nil) ?? ScriptParser.parseScenes(from: draft.sourceText, myRole: effective)
        let unowned = scenes.flatMap(\.lines).filter { !$0.isMine }
        return unowned.first?.character.capitalized ?? "Reader"
    }

    private var canUseThis: Bool {
        !roleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (draft.availablePortions.count <= 1 || !selectedPortionIDs.isEmpty)
    }

    var currentRoleText: String { roleText }
    var isUseThisEnabled: Bool { canUseThis }

    private var portionsArePages: Bool {
        !draft.availablePortions.isEmpty && draft.availablePortions.allSatisfy { $0.pageNumber != nil }
    }

    init(draft: NoticeParser.Draft, sourcePreview: UIImage? = nil, onConfirm: @escaping (NoticeParser.Draft, AddAuditionFlow.ReaderAudioPlan) -> Void, onDiscard: @escaping () -> Void) {
        self.draft = draft
        self.sourcePreview = sourcePreview
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard

        self._projectText = State(initialValue: draft.project)
        self._roleText = State(initialValue: draft.role)
        self._castingOfficeText = State(initialValue: draft.castingOffice)
        self._sidesLinkText = State(initialValue: draft.sidesLink ?? "")
        self._destinationDetailText = State(initialValue: draft.destinationDetail ?? "")
        self._dueDate = State(initialValue: draft.due ?? .now.addingTimeInterval(86400 * 3))
        self._hasDueDate = State(initialValue: draft.due != nil)
        let initialCastingNotes = draft.castingNotes ?? NoticeParser.extractCharacterDescription(for: draft.role, in: draft.sourceText) ?? ""
        self._castingNotesText = State(initialValue: initialCastingNotes)
        self._actorNotesText = State(initialValue: draft.actorNotes ?? "")
        self._isSlateOptional = State(initialValue: draft.isSlateOptional)
        self._isFullBodyShotOptional = State(initialValue: draft.isFullBodyShotOptional)
        self._isHeadshotOptional = State(initialValue: draft.isHeadshotOptional)
        self._includeSlate = State(initialValue: draft.includeSlate)
        self._includeHeadshots = State(initialValue: draft.includeHeadshots)
        self._selectedPortionIDs = State(initialValue: draft.selectedPortionIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.l) {
                    // Header
                    VStack(alignment: .leading, spacing: OTSpace.xs) {
                        Label("Review what we read", systemImage: "doc.text.magnifyingglass")
                            .font(.otTitle)
                        Text("Check each field — fix anything that looks wrong before continuing.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelSecondary)
                    }

                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        Label("Audition Type", systemImage: "theatermasks")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                        AuditionMaterialKindPicker(selected: $draft.materialKind)
                    }

                    if !draft.importantDates.isEmpty {
                        MilestoneDatesListCard(dates: draft.importantDates)
                    }

                    if let details = draft.projectDetails, details.hasReviewableContent {
                        ProjectDetailsCard(details: details)
                    }

                    reviewField(
                        icon: "film",
                        label: "Audition name",
                        placeholder: "A name to recognize this audition",
                        text: $projectText,
                        isRequired: false,
                        field: .project
                    )

                    reviewField(
                        icon: "person",
                        label: "Character you’re auditioning for",
                        placeholder: "e.g. Alice",
                        text: $roleText,
                        isRequired: true,
                        field: .role
                    )

                    // Candidate roles chip picker
                    if !draft.candidateRoles.isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            Text("Detected roles in notice:")
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

                    reviewField(
                        icon: "building.2",
                        label: "Casting office (optional)",
                        placeholder: "e.g. Anti-Casting, Telsey + Co",
                        text: $castingOfficeText,
                        isRequired: false,
                        field: .castingOffice
                    )

                    if draft.hasSides && draft.availablePortions.count > 1 {
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            HStack {
                                Label("Scenes & Pages to prepare", systemImage: "doc.text")
                                    .font(.otCaption.weight(.bold))
                                    .foregroundStyle(OT.labelPrimary)
                                Spacer()
                                Button(selectedPortionIDs.count == draft.availablePortions.count ? "Deselect All" : "Select All") {
                                    if selectedPortionIDs.count == draft.availablePortions.count {
                                        selectedPortionIDs.removeAll()
                                    } else {
                                        selectedPortionIDs = Set(draft.availablePortions.map(\.id))
                                    }
                                    Haptics.tick()
                                }
                                .font(.otCaption.weight(.medium))
                                .foregroundStyle(OT.accent)
                            }

                            Text("Choose the relevant \(portionsArePages ? "pages" : "scenes") for \(roleText.isEmpty ? "your role" : roleText).")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)

                            VStack(spacing: OTSpace.s) {
                                ForEach(draft.availablePortions) { portion in
                                    let isSelected = selectedPortionIDs.contains(portion.id)
                                    let isForMyRole = portion.characters.contains { $0.caseInsensitiveCompare(roleText) == .orderedSame }
                                    Button {
                                        if isSelected {
                                            selectedPortionIDs.remove(portion.id)
                                        } else {
                                            selectedPortionIDs.insert(portion.id)
                                        }
                                        Haptics.tick()
                                    } label: {
                                        HStack(alignment: .top, spacing: OTSpace.s) {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.otIcon(.m))
                                                .foregroundStyle(isSelected ? OT.accent : OT.labelTertiary)
                                                .padding(.top, OTSpace.xxs)

                                            VStack(alignment: .leading, spacing: OTSpace.xs) {
                                                HStack {
                                                    Text(portion.displayTitle)
                                                        .font(.otSubhead.weight(.semibold))
                                                        .foregroundStyle(OT.labelPrimary)
                                                    Spacer()
                                                    if isForMyRole {
                                                        Text("Matches role")
                                                            .font(.otCaption.weight(.bold))
                                                            .padding(.horizontal, OTSpace.xs)
                                                            .padding(.vertical, OTSpace.xxs)
                                                            .background(OT.accentSoft, in: Capsule())
                                                            .foregroundStyle(OT.accent)
                                                    }
                                                }

                                                if !portion.characters.isEmpty {
                                                    ScrollView(.horizontal, showsIndicators: false) {
                                                        HStack(spacing: OTSpace.xs) {
                                                            ForEach(portion.characters.prefix(4), id: \.self) { c in
                                                                Text(c)
                                                                    .font(.otCaption.weight(.medium))
                                                                    .padding(.horizontal, OTSpace.xs)
                                                                    .padding(.vertical, OTSpace.xxs)
                                                                    .background(c.caseInsensitiveCompare(roleText) == .orderedSame ? OT.accentSoft : OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.xs))
                                                                    .foregroundStyle(c.caseInsensitiveCompare(roleText) == .orderedSame ? OT.accent : OT.labelSecondary)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(OTSpace.m)
                                        .background(isSelected ? OT.accentSoft.opacity(0.3) : OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                                .stroke(isSelected ? OT.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .otCard(.grouped)
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
                    reviewField(
                        icon: "sparkles",
                        label: "My notes & understanding",
                        placeholder: "My choices, subtext, questions",
                        text: $actorNotesText,
                        isRequired: false
                    )

                    // Deliverables in flow (Slate & Headshots)
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        Label("What to prepare", systemImage: "list.bullet.rectangle")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: OTSpace.s) {
                            deliverableToggle(title: "Slate / intro", icon: "person.text.rectangle", isOptional: $isSlateOptional)
                            if draft.asks.contains("Full-body shot") {
                                deliverableToggle(title: "Full-body shot", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                            } else if draft.asks.contains("Full-body shot with slate") {
                                deliverableToggle(title: "Full-body view in slate", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                            }
                            deliverableToggle(title: "Headshots", icon: "person.crop.rectangle", isOptional: $isHeadshotOptional)
                        }
                    }
                    .otCard(.grouped)

                    // Reader audio option if lines for reader are present
                    if hasReaderLines {
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            HStack {
                                Label("Practice cue audio", systemImage: "waveform")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Spacer()
                                HStack(spacing: OTSpace.xs) {
                                    Text("Other character").font(.otCaption.weight(.bold)).foregroundStyle(OT.reader)
                                    Text(detectedReaderName).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.reader)
                                }
                            }
                            Text("Record the other character’s lines in your voice. They’ll play back as cues while you perform.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                            Picker("Reader audio", selection: $readerAudioPlan) {
                                Text("Record now").tag(AddAuditionFlow.ReaderAudioPlan.recordNow)
                                Text("Later").tag(AddAuditionFlow.ReaderAudioPlan.later)
                            }
                            .pickerStyle(.segmented)
                        }
                        .otCard(.grouped)
                    }

                    // Clear, wrapped requirement list. These are statements from the notice,
                    // not compact tags that truncate email addresses or long instructions.
                    if !draft.asks.isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            Label("Requested by casting", systemImage: "checkmark.circle")
                                .font(.otCaption.weight(.medium))
                                .foregroundStyle(OT.labelSecondary)
                            VStack(alignment: .leading, spacing: OTSpace.s) {
                                ForEach(Array(draft.asks.enumerated()), id: \.offset) { _, ask in
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

                    if draft.asks.contains(where: { $0.localizedCaseInsensitiveContains("resume") || $0.localizedCaseInsensitiveContains("résumé") }) {
                        AuditionResumePicker(
                            isIncluded: $draft.includeResume,
                            selectedURL: $draft.resumeURL
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
                .padding(OT.gutter)
            }
            .otCanvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { onDiscard() }
                        .foregroundStyle(OT.labelSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this") {
                        Haptics.success()
                        var confirmed = draft
                        confirmed.project = projectText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.role = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.castingOffice = castingOfficeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.sidesLink = sidesLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sidesLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.destinationDetail = destinationDetailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : destinationDetailText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.due = hasDueDate ? dueDate : nil
                        let trimmedCastingNotes = castingNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.castingNotes = trimmedCastingNotes.isEmpty ? nil : trimmedCastingNotes
                        let trimmedActorNotes = actorNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.actorNotes = trimmedActorNotes.isEmpty ? nil : trimmedActorNotes
                        confirmed.isSlateOptional = isSlateOptional
                        confirmed.isFullBodyShotOptional = isFullBodyShotOptional
                        confirmed.isHeadshotOptional = isHeadshotOptional
                        confirmed.includeSlate = includeSlate
                        confirmed.includeHeadshots = includeHeadshots

                        // Pass 2: Targeted Scene Chunker
                        if !draft.availablePortions.isEmpty {
                            let chosen = draft.availablePortions.filter { selectedPortionIDs.contains($0.id) }
                            if !chosen.isEmpty {
                                let selectedText = chosen.map(\.rawText).joined(separator: "\n\n")
                                let parsedScenes = portionsArePages
                                    ? ScriptParser.parseScenes(from: selectedText, myRole: confirmed.role)
                                    : ScriptParser.parseSelectedPortions(chosen, myRole: confirmed.role)
                                confirmed.customScenes = parsedScenes
                                confirmed.scenes = parsedScenes.count
                                confirmed.sourceText = selectedText
                            }
                        }
                        onConfirm(confirmed, readerAudioPlan)
                    }
                    .font(.otHeadline)
                    .foregroundStyle(canUseThis ? OT.accent : OT.labelTertiary)
                    .disabled(!canUseThis)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    let suggestions: [String] = {
                        switch focusedField {
                        case .project:
                            return store.projectSuggestions.filter {
                                projectText.isEmpty || $0.localizedCaseInsensitiveContains(projectText)
                            }
                        case .role:
                            return store.roleSuggestions.filter {
                                roleText.isEmpty || $0.localizedCaseInsensitiveContains(roleText)
                            }
                        case .castingOffice:
                            return store.castingOfficeSuggestions.filter {
                                castingOfficeText.isEmpty || $0.localizedCaseInsensitiveContains(castingOfficeText)
                            }
                        case nil:
                            return []
                        }
                    }()

                    KeyboardAutofillBar(
                        suggestions: suggestions,
                        onSelect: { selected in
                            switch focusedField {
                            case .project:
                                projectText = selected
                            case .role:
                                roleText = selected
                                if let auto = NoticeParser.extractCharacterDescription(for: selected, in: draft.sourceText) {
                                    castingNotesText = auto
                                }
                            case .castingOffice:
                                castingOfficeText = selected
                            case nil:
                                break
                            }
                        },
                        onDismiss: {
                            focusedField = nil
                        }
                    )
                }
            }
        }
    }

    private func reviewField(
        icon: String,
        label: String,
        placeholder: String,
        text: Binding<String>,
        isRequired: Bool,
        field: FocusField? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            HStack(spacing: OTSpace.xs) {
                Image(systemName: icon)
                    .foregroundStyle(OT.accent)
                    .frame(width: 18) // ot-lint:allow
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
                .focused($focusedField, equals: field)
                .padding(OTSpace.m)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
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
