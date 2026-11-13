import SwiftUI
import OneTakeUI

/// Shown after every scan, photo import, file import, and share-sheet import so the actor
/// can verify what OneTake read before it is committed to an audition draft.
/// Divided into focused steps (Project & Role, Scenes & Pages, Specs & Notes) to keep
/// each screen digestible and intuitive.
struct OCRReviewSheet: View {
    @Environment(AppStore.self) private var store
    /// The draft that the parser produced — presented as editable fields.
    @State var draft: NoticeParser.Draft
    let sourcePreview: UIImage?
    let onConfirm: (NoticeParser.Draft, AddAuditionFlow.ReaderAudioPlan) -> Void
    let onDiscard: () -> Void

    enum ReviewStep: Int, CaseIterable, Identifiable {
        case project = 0, scenes = 1, requirements = 2
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .project: return "Project & Role"
            case .scenes: return "Scenes & Pages"
            case .requirements: return "Specs & Notes"
            }
        }

        var shortTitle: String {
            switch self {
            case .project: return "Project"
            case .scenes: return "Scenes"
            case .requirements: return "Specs"
            }
        }

        var icon: String {
            switch self {
            case .project: return "person.text.rectangle"
            case .scenes: return "doc.text"
            case .requirements: return "list.bullet.clipboard"
            }
        }
    }

    private var availableSteps: [ReviewStep] {
        draft.availablePortions.count > 1 ? [.project, .scenes, .requirements] : [.project, .requirements]
    }

    @State private var currentStepIndex: Int = 0

    private var currentStep: ReviewStep {
        availableSteps[min(currentStepIndex, availableSteps.count - 1)]
    }

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

    init(
        draft: NoticeParser.Draft,
        sourcePreview: UIImage? = nil,
        initialStep: ReviewStep = .project,
        onConfirm: @escaping (NoticeParser.Draft, AddAuditionFlow.ReaderAudioPlan) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.draft = draft
        self.sourcePreview = sourcePreview
        self._currentStepIndex = State(initialValue: initialStep.rawValue)
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
            VStack(spacing: 0) {
                // Top step progress pills
                stepIndicator
                    .padding(.top, OTSpace.xs)
                    .padding(.bottom, OTSpace.s)

                // Current step content
                Group {
                    switch currentStep {
                    case .project:
                        step1ProjectAndRoleView
                    case .scenes:
                        step2ScenesAndPagesView
                    case .requirements:
                        step3SpecsAndNotesView
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
            }
            .otCanvas()
            .otBottomBar {
                bottomBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStepIndex == 0 {
                        Button("Discard") { onDiscard() }
                            .foregroundStyle(OT.labelSecondary)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { currentStepIndex = max(0, currentStepIndex - 1) }
                            Haptics.tick()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .foregroundStyle(OT.accent)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Step \(currentStepIndex + 1) of \(availableSteps.count)")
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(OT.labelSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this") {
                        commitConfirmedDraft()
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

                    if !suggestions.isEmpty {
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
                            }
                        )
                    }
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: OTSpace.s) {
            ForEach(Array(availableSteps.enumerated()), id: \.offset) { index, step in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStepIndex = index
                    }
                    Haptics.tick()
                } label: {
                    HStack(spacing: OTSpace.xxs) {
                        Image(systemName: index < currentStepIndex ? "checkmark.circle.fill" : step.icon)
                            .font(.otIcon(.xs, weight: .bold))
                        Text(step.shortTitle)
                            .font(.otCaption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OTSpace.xs)
                    .background(
                        index == currentStepIndex
                            ? OT.accent
                            : (index < currentStepIndex ? OT.accentSoft : OT.fillField),
                        in: Capsule()
                    )
                    .foregroundStyle(
                        index == currentStepIndex
                            ? Color.white
                            : (index < currentStepIndex ? OT.accent : OT.labelSecondary)
                    ) // ot-lint:allow
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, OTSpace.gutter)
    }

    // MARK: - Bottom Navigation Bar

    @ViewBuilder
    private var bottomBar: some View {
        let isLastStep = currentStepIndex >= availableSteps.count - 1
        if isLastStep {
            Button("Use this & Create Audition") {
                commitConfirmedDraft()
            }
            .buttonStyle(.otPrimary)
            .disabled(!canUseThis)
        } else {
            HStack(spacing: OTSpace.s) {
                if currentStepIndex > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStepIndex -= 1
                        }
                        Haptics.tick()
                    } label: {
                        Label("Back", systemImage: "arrow.left")
                    }
                    .buttonStyle(.ot(.secondary, size: .large, fullWidth: false))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStepIndex = min(currentStepIndex + 1, availableSteps.count - 1)
                    }
                    Haptics.tick()
                } label: {
                    HStack {
                        Text(nextButtonTitle)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.otPrimary)
            }
        }
    }

    private var nextButtonTitle: String {
        let nextIndex = currentStepIndex + 1
        guard nextIndex < availableSteps.count else { return "Next" }
        return "Continue to \(availableSteps[nextIndex].shortTitle)"
    }

    // MARK: - Step 1: Project & Role

    private var step1ProjectAndRoleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Header
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Label("Review what we read", systemImage: "doc.text.magnifyingglass")
                        .font(.otTitle)
                    Text("Check project and character details before continuing.")
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
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.m)
            .padding(.bottom, OTSpace.xl)
        }
    }

    // MARK: - Step 2: Scenes & Pages

    private var step2ScenesAndPagesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Header
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Label("Scenes & Pages to prepare", systemImage: "doc.text")
                        .font(.otTitle)
                    Text("Choose the relevant \(portionsArePages ? "pages" : "scenes") for \(roleText.isEmpty ? "your role" : roleText).")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }

                HStack {
                    Text("\(selectedPortionIDs.count) of \(draft.availablePortions.count) selected")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                    Spacer()
                    Button(selectedPortionIDs.count == draft.availablePortions.count ? "Deselect All" : "Select All") {
                        if selectedPortionIDs.count == draft.availablePortions.count {
                            selectedPortionIDs.removeAll()
                        } else {
                            selectedPortionIDs = Set(draft.availablePortions.map(\.id))
                        }
                        Haptics.tick()
                    }
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }

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
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.m)
            .padding(.bottom, OTSpace.xl)
        }
    }

    // MARK: - Step 3: Specs & Notes

    private var step3SpecsAndNotesView: some View {
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
                        if draft.asks.contains("Full-body shot") {
                            deliverableToggle(title: "Full-body shot", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                        } else if draft.asks.contains("Full-body shot with slate") {
                            deliverableToggle(title: "Full-body view in slate", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                        }
                        deliverableToggle(title: "Headshots", icon: "person.crop.rectangle", isOptional: $isHeadshotOptional)
                    }
                }
                .otCard(.grouped)

                // Requested by casting
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
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.m)
            .padding(.bottom, OTSpace.xl)
        }
    }

    // MARK: - Commit & Helpers

    private func commitConfirmedDraft() {
        Haptics.success()
        var confirmed = draft
        let clean: (String) -> String? = { s in
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        confirmed.project = clean(projectText) ?? ""
        confirmed.role = clean(roleText) ?? ""
        confirmed.castingOffice = clean(castingOfficeText) ?? ""
        confirmed.sidesLink = clean(sidesLinkText)
        confirmed.destinationDetail = clean(destinationDetailText)
        confirmed.due = hasDueDate ? dueDate : nil
        confirmed.castingNotes = clean(castingNotesText)
        confirmed.actorNotes = clean(actorNotesText)
        confirmed.isSlateOptional = isSlateOptional
        confirmed.isFullBodyShotOptional = isFullBodyShotOptional
        confirmed.isHeadshotOptional = isHeadshotOptional
        confirmed.includeSlate = includeSlate
        confirmed.includeHeadshots = includeHeadshots

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
