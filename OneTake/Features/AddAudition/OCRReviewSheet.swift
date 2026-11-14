import SwiftUI
import OneTakeUI

/// Shown after every scan, photo import, file import, and share-sheet import so the actor
/// can verify what OneTake read before it is committed to an audition draft.
/// Coordinates the 3-step structured review flow:
/// 1. Project & Role (`ReviewStepProjectView`)
/// 2. Scenes & Pages (`ReviewStepScenesView`)
/// 3. Specs & Notes (`ReviewStepSpecsView`)
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
    }

    private var availableSteps: [ReviewStep] {
        draft.availablePortions.count > 1 ? [.project, .scenes, .requirements] : [.project, .requirements]
    }

    @State private var currentStepIndex: Int = 0

    private var currentStep: ReviewStep {
        availableSteps[min(currentStepIndex, availableSteps.count - 1)]
    }

    enum FocusField: Hashable {
        case project, role, castingOffice
    }
    @FocusState var focusedField: FocusField?

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
                        ReviewStepProjectView(
                            draft: $draft,
                            projectText: $projectText,
                            roleText: $roleText,
                            castingOfficeText: $castingOfficeText,
                            castingNotesText: $castingNotesText,
                            focusedField: $focusedField
                        )
                    case .scenes:
                        ReviewStepScenesView(
                            portions: draft.availablePortions,
                            roleText: roleText,
                            portionsArePages: portionsArePages,
                            selectedPortionIDs: $selectedPortionIDs,
                            hasReaderLines: hasReaderLines,
                            detectedReaderName: detectedReaderName,
                            readerAudioPlan: $readerAudioPlan
                        )
                    case .requirements:
                        ReviewStepSpecsView(
                            hasDueDate: $hasDueDate,
                            dueDate: $dueDate,
                            asks: draft.asks,
                            isSlateOptional: $isSlateOptional,
                            isFullBodyShotOptional: $isFullBodyShotOptional,
                            isHeadshotOptional: $isHeadshotOptional,
                            castingNotesText: $castingNotesText,
                            actorNotesText: $actorNotesText,
                            includeResume: $draft.includeResume,
                            resumeURL: $draft.resumeURL,
                            sourcePreview: sourcePreview
                        )
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
                        onDone: { focusedField = nil }
                    )
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
                    Text(step.shortTitle)
                        .font(.otCaption.weight(.semibold))
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

    // MARK: - Commit

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
}
