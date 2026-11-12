import SwiftUI
import OneTakeUI

struct MissingDetailsView: View {
    @Environment(AppStore.self) private var store
    @State private var picked: Date = .now.addingTimeInterval(86400)
    @State private var requestedFields: [String] = []
    @State private var showSidesSheet = false
    @State private var showValidationErrors = false

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
    private var canContinue: Bool {
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

    private var missing: [String] {
        requestedFields
    }

    private var missingSubtitle: String {
        if missing.isEmpty { return "Ready to review what casting is asking for." }
        if missing.count == 1 {
            return "I couldn't find the \(missing[0]) in this notice. Add it below to continue."
        }
        let allButLast = missing.dropLast().joined(separator: ", ")
        return "I couldn't find the \(allButLast), and \(missing.last!) in the notice. Add what you know to continue."
    }

    var body: some View {
        @Bindable var store = store
        OTScreen(
            title: "",
            backLabel: "Back",
            onBack: {
                store.popToRoot()
                store.pendingRouteAfterAdd = nil
                store.continueAfterAdd = nil
                store.showAddAudition = true
            }
        ) {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                Text(missing.isEmpty ? "All set" : missing.count == 1 ? "One thing missing" : "A few details missing")
                    .font(.otLargeTitle)
                Text(missingSubtitle)
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)

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
                            .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                            .overlay(
                                RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                    .stroke(showValidationErrors && isProjectEmpty ? OT.danger.opacity(0.8) : Color.clear, lineWidth: 1.5)
                            )

                        if showValidationErrors && isProjectEmpty {
                            Label("Please enter an audition name to continue", systemImage: "exclamationmark.circle.fill")
                                .font(.otFootnote)
                                .foregroundStyle(OT.danger)
                        }
                    }

                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            Text("Which role are you auditioning for?").font(.otCaption.weight(.bold)).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            if showValidationErrors && isRoleEmpty {
                                Text("Required").font(.otCaption.weight(.semibold)).foregroundStyle(OT.danger)
                            }
                        }
                        Text("Select your character so OneTake knows which lines are yours to speak and which belong to your reader.")
                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                        if !availableRoles.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OTSpace.s) {
                                    ForEach(availableRoles, id: \.self) { char in
                                        let isCurrent = store.auditionDraft.role.caseInsensitiveCompare(char) == .orderedSame
                                        Button {
                                            store.auditionDraft.role = char
                                            let parsed = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: char)
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
                        } else {
                            Label("No character names were found in the notice or script. Enter your role below.", systemImage: "text.magnifyingglass")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                            TextField("e.g. Maya", text: $store.auditionDraft.role)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .role)
                                .padding(OTSpace.m)
                                .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                                .overlay(
                                    RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                        .stroke(showValidationErrors && isRoleEmpty ? OT.danger.opacity(0.8) : Color.clear, lineWidth: 1.5)
                                )
                        }

                        if showValidationErrors && isRoleEmpty {
                            Label("Please select or enter the character or role you are reading for", systemImage: "exclamationmark.circle.fill")
                                .font(.otFootnote)
                                .foregroundStyle(OT.danger)
                        }
                    }

                    VStack(alignment: .leading, spacing: OTSpace.xs) {
                        Text("Casting office (optional)").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                        TextField("e.g. Anti-Casting, Telsey + Co", text: $store.auditionDraft.castingOffice)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .castingOffice)
                            .padding(OTSpace.m)
                            .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                    }

                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            Text("When is it due?").font(.otHeadline)
                            Spacer()
                            DatePicker("Due date", selection: $picked, in: Date.now...)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            Text("Quick time")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OTSpace.s) {
                                    presetTimeChip("5:00 PM") { setPickedTime(hour: 17, minute: 0) }
                                    presetTimeChip("10:00 AM") { setPickedTime(hour: 10, minute: 0) }
                                    presetTimeChip("12:00 PM") { setPickedTime(hour: 12, minute: 0) }
                                    presetTimeChip("11:59 PM") { setPickedTime(hour: 23, minute: 59) }
                                }
                            }
                        }
                    }
                }
                .otCard(.grouped)

                OTSectionLabel("Script Sides")
                let parsedScenes = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                if parsedScenes.isEmpty {
                    if let sidesLink = store.auditionDraft.sidesLink, !sidesLink.isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            HStack(spacing: OTSpace.m) {
                                Image(systemName: sidesLink.contains("drive.google") ? "externaldrive.fill.badge.icloud" : "link.circle.fill")
                                    .font(.otIcon(.m))
                                    .foregroundStyle(OT.accent)
                                    .frame(width: 34, height: 34) // ot-lint:allow
                                    .background(OT.accentSoft, in: Circle())
                                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                    Text(sidesLink.contains("drive.google") ? "Google Drive sides attached" : "Sides link attached")
                                        .font(.otHeadline)
                                        .foregroundStyle(OT.labelPrimary)
                                    Text("Open link to view/download sides, then import or paste here")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                                Button("Add sides") {
                                    showSidesSheet = true
                                }
                                .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                            }

                            if let url = URL(string: sidesLink.hasPrefix("http") ? sidesLink : "https://\(sidesLink)") {
                                Link(destination: url) {
                                    HStack(spacing: OTSpace.xs) {
                                        Image(systemName: "safari")
                                        Text("Open \(sidesLink.contains("drive.google") ? "Google Drive link" : "Sides link")")
                                        Image(systemName: "arrow.up.right")
                                    }
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                                    .padding(.horizontal, OTSpace.m)
                                    .padding(.vertical, OTSpace.xs)
                                    .background(OT.accentSoft.opacity(0.8), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                                }
                            }
                        }
                        .otCard(.grouped)
                    } else {
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
                    }
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

                Button("Choose a different notice") {
                    store.pop()
                    store.showAddAudition = true
                }
                .font(.otFootnote)
                .foregroundStyle(OT.labelTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, OTSpace.s)
            }
        }
        .otBottomBar {
            VStack(spacing: OTSpace.s) {
                if showValidationErrors && !canContinue {
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

                Button(store.auditionDraft.hasSides ? "Continue" : "Continue without sides") {
                    if !canContinue {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showValidationErrors = true
                        }
                        Haptics.warning()
                        return
                    }
                    if store.auditionDraft.due == nil { store.auditionDraft.due = picked }
                    store.push(.noticeReview)
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
                    },
                    onDismiss: {
                        focusedField = nil
                    }
                )
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
        .onAppear {
            if let due = store.auditionDraft.due {
                picked = due
            } else {
                store.auditionDraft.due = picked
            }
            let req = store.auditionDraft.missingRequiredDetails
            requestedFields = req.isEmpty ? ["project", "role", "due date"] : req
        }
        .onChange(of: picked) { _, newDate in
            store.auditionDraft.due = newDate
        }
        .onChange(of: store.auditionDraft.project) { _, _ in
            if canContinue { withAnimation { showValidationErrors = false } }
        }
        .onChange(of: store.auditionDraft.role) { _, _ in
            if canContinue { withAnimation { showValidationErrors = false } }
        }
    }

    private func presetTimeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            Haptics.tick()
        }) {
            Text(title)
                .font(.otCaption.weight(.medium))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, OTSpace.s)
                .frame(minHeight: 34) // ot-lint:allow
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)) // ot-lint:allow
                .foregroundStyle(OT.accent)
        }
        .buttonStyle(.plain)
    }

    private func setPickedTime(hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = calendar.dateComponents([.year, .month, .day], from: picked)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let newDate = calendar.date(from: comps) {
            picked = newDate
        }
    }
}
