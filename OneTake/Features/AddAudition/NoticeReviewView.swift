import SwiftUI
import UserNotifications
import OneTakeUI

struct NoticeReviewView: View {
    @Environment(AppStore.self) private var store
    @State private var readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .recordNow
    @State private var showSidesSheet = false
    @State private var showValidationErrors = false
    @State private var createdAuditionID: Audition.ID? = nil

    private enum FocusField: Hashable {
        case project, role, castingOffice
    }
    @FocusState private var focusedField: FocusField?

    private var isProjectEmpty: Bool {
        store.auditionDraft.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var isRoleEmpty: Bool {
        store.auditionDraft.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canSave: Bool {
        !isProjectEmpty && !isRoleEmpty
    }

    private var availableRoles: [String] {
        var roles = store.auditionDraft.candidateRoles
        let scriptChars = ScriptParser.extractCharacters(from: store.auditionDraft.sourceText)
        for char in scriptChars where !roles.contains(char) && !ScriptParser.isBlacklistedNoticeWord(char) {
            roles.append(char)
        }
        // Filter out compound "Male and Female" when individual male and female roles are present
        if roles.contains(where: { $0.lowercased().hasPrefix("male") }) && roles.contains(where: { $0.lowercased().hasPrefix("female") }) {
            roles.removeAll(where: { $0.lowercased().contains("male and female") || $0.lowercased().contains("male & female") })
        }

        // Filter out any blacklisted notice words or location names
        return roles.filter { role in
            let base = role.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? role
            if base.lowercased() == "male" || base.lowercased() == "female" { return true }
            return !ScriptParser.isBlacklistedNoticeWord(base)
        }
    }

    private var hasReaderLines: Bool {
        guard !store.auditionDraft.role.isEmpty, store.auditionDraft.hasSides else { return false }
        let parsed = store.auditionDraft.customScenes?.isEmpty == false
            ? store.auditionDraft.customScenes!
            : ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
        return parsed.contains { $0.lines.contains { !$0.isMine } }
    }

    private var detectedReaderName: String {
        guard store.auditionDraft.hasSides else { return "Reader" }
        let parsedScenes = store.auditionDraft.customScenes?.isEmpty == false
            ? store.auditionDraft.customScenes!
            : ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
        let unownedLines = parsedScenes.flatMap(\.lines).filter { !$0.isMine }
        var seen = Set<String>()
        var list: [String] = []
        for line in unownedLines {
            let name = line.character.capitalized
            if !seen.contains(name.lowercased()) {
                seen.insert(name.lowercased())
                list.append(name)
            }
        }
        return list.first ?? "Reader"
    }

    private var readerCuesCount: Int {
        guard store.auditionDraft.hasSides else { return 0 }
        let parsedScenes = store.auditionDraft.customScenes?.isEmpty == false
            ? store.auditionDraft.customScenes!
            : ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
        return parsedScenes.flatMap(\.lines).filter { !$0.isMine }.count
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                let isNewManual = store.auditionDraft.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.auditionDraft.asks.isEmpty
                Text(isNewManual ? "New audition" : "Here's what they want").font(.otLargeTitle)
                Text(isNewManual ? "Enter your project and role details below, then attach sides or choose an audition type." : (store.auditionDraft.asks.isEmpty
                     ? "No recording requirements were detected. Review the details, then save."
                     : "\(store.auditionDraft.asks.count) requirement\(store.auditionDraft.asks.count == 1 ? "" : "s") found in the email. Tap any line to change it, then save."))
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)

                OTSectionLabel("Audition Type")
                AuditionMaterialKindPicker(selected: $store.auditionDraft.materialKind)

                OTSectionLabel("Due")
                if let due = store.auditionDraft.due {
                    HStack(alignment: .firstTextBaseline, spacing: OTSpace.s) {
                        Text(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.otTitle)
                        Text(due.formatted(date: .omitted, time: .shortened)).font(.otHeadline).foregroundStyle(OT.due)
                    }
                } else {
                    DatePicker("Due", selection: Binding(get: { store.auditionDraft.due ?? .now.addingTimeInterval(86400) }, set: { store.auditionDraft.due = $0 })).labelsHidden()
                }

                if !store.auditionDraft.importantDates.isEmpty {
                    OTSectionLabel("Milestone Dates")
                    MilestoneDatesListCard(dates: store.auditionDraft.importantDates)
                }

                OTSectionLabel("Sides & Scenes")
                let parsedScenes = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                if store.auditionDraft.materialKind == .slateOnly {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: "person.crop.rectangle.fill")
                            .font(.otIcon(.m))
                            .foregroundStyle(OT.accent)
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text("Slate & Intro Only")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text("No script dialogue required for this casting call")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }
                    .otCard(.grouped)
                } else if store.auditionDraft.materialKind == .monologue {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: "person.wave.2.fill")
                            .font(.otIcon(.m))
                            .foregroundStyle(OT.accent)
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text("Solo Monologue")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text("Continuous teleprompter flow without reader audio pauses")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                        Button("Edit text") {
                            showSidesSheet = true
                        }
                        .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                    }
                    .otCard(.grouped)
                } else if store.auditionDraft.materialKind == .song || store.auditionDraft.materialKind == .movement {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: store.auditionDraft.materialKind == .song ? "music.note" : "figure.dance")
                            .font(.otIcon(.m))
                            .foregroundStyle(OT.accent)
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text(store.auditionDraft.materialKind == .song ? "Vocal Audition Track" : "Physical / Dance Audition")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text("Recorded in full with framing guides and audio monitoring")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }
                    .otCard(.grouped)
                } else if parsedScenes.isEmpty {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: "doc.badge.plus")
                            .font(.otIcon(.m))
                            .foregroundStyle(OT.accent)
                            .frame(width: 34, height: 34) // ot-lint:allow
                            .background(OT.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text("No sides attached yet")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text("The notice has no script pages. Add them if casting sent sides separately.")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                        Button("Add sides") {
                            showSidesSheet = true
                        }
                        .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                    }
                    .otCard(.grouped)
                } else {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.otIcon(.m))
                            .foregroundStyle(OT.success)
                        let myCount = parsedScenes.flatMap(\.lines).filter(\.isMine).count
                        let readerCount = parsedScenes.flatMap(\.lines).filter { !$0.isMine }.count
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text("\(parsedScenes.count) scene\(parsedScenes.count == 1 ? "" : "s") · \(myCount) for you\(readerCount > 0 ? " · \(readerCount) for reader" : "")")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text(readerCount > 0 ? "Reader lines will play under your takes" : "Solo monologue ready for practice & shoot")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                        Button("Replace") {
                            showSidesSheet = true
                        }
                        .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                    }
                    .otCard(.grouped)
                }

                OTSectionLabel("Requested by casting")
                if !store.auditionDraft.aiGuidance.isEmpty {
                    Label(store.auditionDraft.aiGuidance, systemImage: "sparkles")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                        .padding(OTSpace.m)
                        .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous))
                }
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    HStack(alignment: .top, spacing: OTSpace.s) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(OT.accent).frame(width: 20) // ot-lint:allow
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text(store.auditionDraft.role.isEmpty ? "Character not selected" : "Your character: \(store.auditionDraft.role)")
                                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                            Text(store.auditionDraft.hasSides
                                 ? "\(store.auditionDraft.scenes) scene\(store.auditionDraft.scenes == 1 ? "" : "s") with lines found"
                                 : "No script sides are attached")
                                .font(.otCaption).foregroundStyle(OT.labelSecondary)
                        }
                    }
                    ForEach(Array(store.auditionDraft.asks.enumerated()), id: \.offset) { _, ask in
                        HStack(alignment: .top, spacing: OTSpace.s) {
                            Image(systemName: symbol(for: ask)).foregroundStyle(OT.accent).frame(width: 20) // ot-lint:allow
                            Text(ask).font(.otFootnote).foregroundStyle(OT.labelPrimary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .otCard(.elevated)

                if store.auditionDraft.asks.contains(where: { $0.localizedCaseInsensitiveContains("resume") || $0.localizedCaseInsensitiveContains("résumé") }) {
                    AuditionResumePicker(
                        isIncluded: $store.auditionDraft.includeResume,
                        selectedURL: $store.auditionDraft.resumeURL
                    )
                }

                VStack(alignment: .leading, spacing: OTSpace.m) {
                    VStack(alignment: .leading, spacing: OTSpace.xs) {
                        HStack {
                            Text("Audition name").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                            if showValidationErrors && isProjectEmpty {
                                Spacer()
                                Text("Required").font(.otCaption.weight(.semibold)).foregroundStyle(OT.danger)
                            }
                        }
                        Text("A label to help you find this casting call in your audition list.")
                            .font(.otCaption).foregroundStyle(OT.labelTertiary)
                        TextField("e.g. Alice audition", text: $store.auditionDraft.project)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .project)
                            .padding(OTSpace.m)
                            .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                    .stroke(showValidationErrors && isProjectEmpty ? OT.danger.opacity(0.8) : Color.clear, lineWidth: 1.5)
                            )

                        if showValidationErrors && isProjectEmpty {
                            Label("Please enter an audition name", systemImage: "exclamationmark.circle.fill")
                                .font(.otFootnote)
                                .foregroundStyle(OT.danger)
                        }
                    }

                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            Text("Which character are you auditioning for?").font(.otCaption.weight(.bold)).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            if showValidationErrors && isRoleEmpty {
                                Text("Required").font(.otCaption.weight(.semibold)).foregroundStyle(OT.danger)
                            }
                        }
                        Text("Choose the character named in the notice or script. This tells OneTake which dialogue is yours.")
                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                        if !store.auditionDraft.roleBreakdowns.isEmpty {
                            VStack(spacing: OTSpace.s) {
                                ForEach(store.auditionDraft.roleBreakdowns) { breakdown in
                                    let isCurrent = store.auditionDraft.role.caseInsensitiveCompare(breakdown.name) == .orderedSame
                                    RoleBreakdownCard(breakdown: breakdown, isSelected: isCurrent) {
                                        store.auditionDraft.role = breakdown.name
                                        let parsed = store.auditionDraft.hasSides
                                            ? ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: breakdown.name)
                                            : []
                                        if !parsed.isEmpty {
                                            store.auditionDraft.scenes = parsed.count
                                        }
                                        if let desc = breakdown.description {
                                            store.auditionDraft.castingNotes = desc
                                            store.auditionDraft.aiGuidance = desc
                                        }
                                        Haptics.tick()
                                    }
                                }
                            }
                        } else if !availableRoles.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OTSpace.s) {
                                    ForEach(availableRoles, id: \.self) { char in
                                        let isCurrent = store.auditionDraft.role.caseInsensitiveCompare(char) == .orderedSame
                                        Button {
                                            store.auditionDraft.role = char
                                            let parsed = store.auditionDraft.hasSides
                                                ? ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: char)
                                                : []
                                            if !parsed.isEmpty {
                                                store.auditionDraft.scenes = parsed.count
                                            }
                                            if let notes = NoticeParser.extractCharacterDescription(for: char, in: store.auditionDraft.sourceText) {
                                                store.auditionDraft.castingNotes = notes
                                                store.auditionDraft.aiGuidance = notes
                                            }
                                            Haptics.tick()
                                        } label: {
                                            HStack(spacing: OTSpace.xs) {
                                                Image(systemName: isCurrent ? "checkmark.circle.fill" : "person.fill")
                                                    .font(.otCaption.weight(.bold))
                                                Text(char)
                                                    .font(.otSubhead.weight(isCurrent ? .bold : .semibold))
                                            }
                                            .foregroundStyle(isCurrent ? Color.white : OT.accent) // ot-lint:allow
                                            .padding(.horizontal, OTSpace.m)
                                            .padding(.vertical, OTSpace.s)
                                            .background(isCurrent ? OT.accent : OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, OTSpace.xxs)
                            }
                        }

                        if store.auditionDraft.hasSides && !store.auditionDraft.role.isEmpty {
                            let parsed = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                            let myLinesCount = parsed.flatMap(\.lines).filter(\.isMine).count
                            let readerLines = parsed.flatMap(\.lines).filter { !$0.isMine }
                            let readerLinesCount = readerLines.count
                            let readerNames = Array(Set(readerLines.map { $0.character.capitalized })).sorted()

                            VStack(alignment: .leading, spacing: OTSpace.xs) {
                                HStack(spacing: OTSpace.s) {
                                    Image(systemName: "person.wave.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(OT.accent)
                                    Text("Spoken by you (\(store.auditionDraft.role)):")
                                        .font(.otFootnote.weight(.semibold))
                                        .foregroundStyle(OT.accent)
                                    Spacer()
                                    Text("\(myLinesCount) line\(myLinesCount == 1 ? "" : "s")")
                                        .font(.otCaption.weight(.bold))
                                        .foregroundStyle(OT.labelPrimary)
                                }

                                if readerLinesCount > 0 {
                                    HStack(spacing: OTSpace.s) {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.caption)
                                            .foregroundStyle(OT.reader)
                                        Text("Spoken by reader (\(readerNames.joined(separator: ", "))):")
                                            .font(.otFootnote.weight(.semibold))
                                            .foregroundStyle(OT.reader)
                                        Spacer()
                                        Text("\(readerLinesCount) line\(readerLinesCount == 1 ? "" : "s")")
                                            .font(.otCaption.weight(.bold))
                                            .foregroundStyle(OT.labelPrimary)
                                    }
                                } else if !parsed.isEmpty {
                                    HStack(spacing: OTSpace.s) {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                            .foregroundStyle(OT.labelTertiary)
                                        Text("Solo side · no reader lines needed")
                                            .font(.otFootnote)
                                            .foregroundStyle(OT.labelSecondary)
                                    }
                                }
                            }
                            .padding(OTSpace.s)
                            .otCard(.grouped)
                        }

                        if availableRoles.isEmpty && store.auditionDraft.roleBreakdowns.isEmpty {
                            TextField("Your character", text: $store.auditionDraft.role)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .role)
                                .padding(OTSpace.m)
                                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                        .stroke(showValidationErrors && isRoleEmpty ? OT.danger.opacity(0.8) : Color.clear, lineWidth: 1.5)
                                )
                        }

                        if showValidationErrors && isRoleEmpty {
                            Label("Please select or enter your character or role", systemImage: "exclamationmark.circle.fill")
                                .font(.otFootnote)
                                .foregroundStyle(OT.danger)
                        }
                    }

                    DisclosureGroup("Add a casting contact (optional)") {
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            Text("This is the office or person’s name. Enter the submission email below.")
                                .font(.otCaption).foregroundStyle(OT.labelTertiary)
                            TextField("Casting office or contact", text: $store.auditionDraft.castingOffice)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .castingOffice)
                                .padding(OTSpace.m)
                                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                        }
                        .padding(.top, OTSpace.s)
                    }
                    .tint(OT.accent)

                    if let selectedScenes = store.auditionDraft.customScenes, !selectedScenes.isEmpty {
                        Label("\(selectedScenes.count) scene\(selectedScenes.count == 1 ? "" : "s") chosen", systemImage: "checkmark.circle.fill")
                            .font(.otFootnote.weight(.medium))
                            .foregroundStyle(OT.success)
                    } else if store.auditionDraft.hasSides {
                        Stepper("Scenes to prepare: \(store.auditionDraft.scenes)", value: $store.auditionDraft.scenes, in: 0...6)
                            .padding(.top, OTSpace.xs)
                    } else {
                        Label("No scene sides were included in this notice", systemImage: "doc.text")
                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                    }
                }
                .otCard(.elevated)

                if let details = store.auditionDraft.projectDetails, details.hasReviewableContent {
                    ProjectDetailsCard(details: details)
                }

                OTSectionLabel("Delivery & Destination")
                NoticeDestinationCard(
                    destination: $store.auditionDraft.destination,
                    destinationDetail: $store.auditionDraft.destinationDetail
                )

                OTSectionLabel("Notes for this audition")
                NoticeNotesCard(
                    castingNotes: $store.auditionDraft.castingNotes,
                    actorNotes: $store.auditionDraft.actorNotes
                )

                OTSectionLabel("What to prepare")
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    auditionRequirementRow(
                        title: "Slate / introduction",
                        detail: "Self-tape or introduction video, as requested",
                        icon: "person.text.rectangle",
                        isOptional: $store.auditionDraft.isSlateOptional
                    )
                    Divider()
                    auditionRequirementRow(
                        title: "Headshot",
                        detail: "A recent headshot or clear photo",
                        icon: "person.crop.rectangle",
                        isOptional: $store.auditionDraft.isHeadshotOptional
                    )
                }
                .otCard(.elevated)

                if hasReaderLines {
                    OTSectionLabel("Practice cues")
                    VStack(alignment: .leading, spacing: OTSpace.m) {
                        HStack {
                            VStack(alignment: .leading, spacing: OTSpace.xs) {
                                HStack(spacing: OTSpace.xs) {
                                    Text("You:").font(.otCaption.weight(.bold)).foregroundStyle(OT.accent)
                                    Text(store.auditionDraft.role).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(OT.labelTertiary)
                                    Text("Other part:").font(.otCaption.weight(.bold)).foregroundStyle(OT.reader)
                                    Text(detectedReaderName).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.reader)
                                }
                                Text("Record the other character’s \(readerCuesCount) line\(readerCuesCount == 1 ? "" : "s") in your voice. They’ll play back as cues while you perform.")
                                    .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                        }

                        Picker("Reader audio", selection: $readerAudioPlan) {
                            Text("Record now").tag(AddAuditionFlow.ReaderAudioPlan.recordNow)
                            Text("Add later").tag(AddAuditionFlow.ReaderAudioPlan.later)
                        }
                        .pickerStyle(.segmented)
                    }
                    .otCard(.grouped)
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
        }
        .otCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .otBottomBar {
            VStack(spacing: OTSpace.s) {
                if showValidationErrors && !canSave {
                    HStack(spacing: OTSpace.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(OT.danger)
                        Text(isProjectEmpty && isRoleEmpty
                             ? "Audition name and character are required"
                             : (isProjectEmpty ? "Audition name is required" : "Your character is required"))
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.danger)
                    }
                    .padding(.horizontal, OTSpace.m)
                    .padding(.vertical, OTSpace.s)
                    .background(OT.danger.opacity(0.12), in: Capsule())
                    .transition(.opacity.combined(with: .scale))
                }

                Button(hasReaderLines && readerAudioPlan == .recordNow ? "Save & record practice cues" : "Save and start") {
                    saveAudition()
                }
                .buttonStyle(.ot(.primary))
            }
        }
        .sheet(isPresented: $showSidesSheet) {
            AddDraftSidesSheet(draft: $store.auditionDraft)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                let suggestions: [String] = {
                    switch focusedField {
                    case .project:
                        return store.projectSuggestions.filter {
                            store.auditionDraft.project.isEmpty || $0.localizedCaseInsensitiveContains(store.auditionDraft.project)
                        }
                    case .role:
                        return store.roleSuggestions.filter {
                            store.auditionDraft.role.isEmpty || $0.localizedCaseInsensitiveContains(store.auditionDraft.role)
                        }
                    case .castingOffice:
                        return store.castingOfficeSuggestions.filter {
                            store.auditionDraft.castingOffice.isEmpty || $0.localizedCaseInsensitiveContains(store.auditionDraft.castingOffice)
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
                                store.auditionDraft.project = selected
                            case .role:
                                store.auditionDraft.role = selected
                                let parsed = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: selected)
                                if !parsed.isEmpty {
                                    store.auditionDraft.scenes = parsed.count
                                }
                                if let notes = NoticeParser.extractCharacterDescription(for: selected, in: store.auditionDraft.sourceText) {
                                    store.auditionDraft.castingNotes = notes
                                }
                            case .castingOffice:
                                store.auditionDraft.castingOffice = selected
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
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openSidesSheet") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    showSidesSheet = true
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-focusProject") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    focusedField = .project
                }
            }
        }
        .onChange(of: store.auditionDraft.project) { _, _ in
            if canSave { withAnimation { showValidationErrors = false } }
        }
        .onChange(of: store.auditionDraft.role) { _, newRole in
            if canSave { withAnimation { showValidationErrors = false } }
            if !newRole.isEmpty, let note = NoticeParser.extractCharacterDescription(for: newRole, in: store.auditionDraft.sourceText) {
                store.auditionDraft.aiGuidance = note
                store.auditionDraft.castingNotes = note
            }
        }
        .task {
            if store.auditionDraft.aiGuidance.isEmpty && !store.auditionDraft.sourceText.isEmpty {
                let guidance = await OnDeviceIntelligence.noticeGuidance(store.auditionDraft.sourceText, parsed: store.auditionDraft)
                if let guidance {
                    store.auditionDraft.aiGuidance = guidance
                }
            }
        }
        .onDisappear {
            // If the user completely backed out of creating this audition (e.g. tapped < Auditions),
            // clean up any provisionally created audition so no ghost entry is left in the list.
            if !store.auditionsPath.contains(where: {
                switch $0 {
                case .noticeReview, .reader, .recordReader, .sceneAudioFlow, .auditionDetail: return true
                default: return false
                }
            }) {
                if let id = createdAuditionID {
                    store.deleteAudition(id)
                }
            }
        }
    }

    private func saveAudition() {
        guard canSave else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showValidationErrors = true
            }
            Haptics.warning()
            return
        }
        let auditionID: Audition.ID
        if let existingID = createdAuditionID, let idx = store.auditions.firstIndex(where: { $0.id == existingID }) {
            var updated = store.auditions[idx]
            updated.project = store.auditionDraft.project
            updated.role = store.auditionDraft.role
            updated.castingOffice = store.auditionDraft.castingOffice
            updated.due = store.auditionDraft.due ?? updated.due
            updated.destination = store.auditionDraft.destination
            updated.destinationWasChosen = true
            updated.destinationDetail = store.auditionDraft.destinationDetail
            updated.resumeURL = store.auditionDraft.includeResume
                ? (store.auditionDraft.resumeURL ?? store.slate.resumeURL)
                : nil
            if let notes = store.auditionDraft.castingNotes ?? NoticeParser.extractCharacterDescription(for: store.auditionDraft.role, in: store.auditionDraft.sourceText) {
                updated.castingNotes = notes
            }
            if let actorNotes = store.auditionDraft.actorNotes {
                updated.actorNotes = actorNotes
            }
            let parsedScenes = (store.auditionDraft.customScenes?.isEmpty == false ? store.auditionDraft.customScenes : nil) ?? ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
            if !parsedScenes.isEmpty { updated.scenes = parsedScenes }
            store.auditions[idx] = updated
            auditionID = existingID
        } else {
            let audition = store.auditionDraft.makeAudition()
            store.add(audition)
            createdAuditionID = audition.id
            auditionID = audition.id
        }
        store.tab = .auditions
        if readerAudioPlan == .recordNow,
           let a = store.audition(auditionID),
           let firstScene = a.scenes.indices.first(where: { !a.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
            // Place .auditionDetail underneath .reader so tapping Back or Continue goes to Project Overview!
            store.auditionsPath = [.auditionDetail(auditionID), .reader(auditionID, sceneIndex: firstScene)]
        } else {
            store.auditionsPath = [.auditionDetail(auditionID)]
            store.continueAfterAdd = auditionID
            store.auditionDraft = .blank
        }
        requestNotificationsIfFirstAudition()
    }

    private func requestNotificationsIfFirstAudition() {
        guard store.auditions.count == 1 else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    private func auditionRequirementRow(title: String, detail: String, icon: String, isOptional: Binding<Bool>) -> some View {
        HStack(spacing: OTSpace.m) {
            Image(systemName: icon)
                .font(.otIcon(.s))
                .foregroundStyle(OT.accent)
                .frame(width: 32, height: 32) // ot-lint:allow
                .background(OT.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text(title).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                Text(detail).font(.otCaption).foregroundStyle(OT.labelSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(isOptional.wrappedValue ? "Optional" : "Required") {
                isOptional.wrappedValue.toggle()
                Haptics.tick()
            }
            .font(.otCaption.weight(.bold))
            .fixedSize()
            .padding(.horizontal, OTSpace.s)
            .padding(.vertical, OTSpace.xs)
            .background(isOptional.wrappedValue ? OT.surfaceSunken : OT.accentSoft, in: Capsule())
            .foregroundStyle(isOptional.wrappedValue ? OT.labelSecondary : OT.accent)
            .accessibilityLabel("\(title), \(isOptional.wrappedValue ? "optional" : "required"). Tap to change.")
        }
        .frame(minHeight: 48) // ot-lint:allow
    }

    private func symbol(for ask: String) -> String {
        switch ask {
        case "Slate first": "person.text.rectangle"
        case "Landscape": "iphone.landscape"
        case "Full-body shot", "Full-body shot with slate", "Full length": "figure.stand"
        default: ask.hasPrefix("Under") ? "timer" : "paperplane"
        }
    }
}
