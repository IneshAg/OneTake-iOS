import SwiftUI

// MARK: - Edit details

struct EditAuditionSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showValidationErrors = false
    @State private var sceneCount: Int = 1
    @State private var showPDFPicker = false
    @State private var showRevisedSides = false
    @State private var isProcessingPDF = false
    @State private var showPDFError = false
    @State private var recordReaderAfterSave = false

    var body: some View {
        NavigationStack {
            Group {
                if let audition = store.binding(for: auditionID) {
                    Form {
                    Section("Audition Type") {
                        Picker("Type", selection: Binding(
                            get: { audition.wrappedValue.resolvedMaterialKind },
                            set: { audition.wrappedValue.materialKind = $0 }
                        )) {
                            ForEach(AuditionMaterialKind.allCases) { kind in
                                Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                            }
                        }
                    }

                    Section("Project") {
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            TextField("Project", text: audition.project)
                            if showValidationErrors && audition.wrappedValue.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label("Project name is required", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red) // ot-lint:allow
                            }
                        }
                        TextField("Type (film, series, commercial…)", text: audition.projectType)
                        TextField("Casting office", text: audition.castingOffice)
                    }
                    Section("Role") {
                        let chars = scriptCharacters(for: audition.wrappedValue)
                        if !chars.isEmpty {
                            Picker("Character in script", selection: Binding(
                                get: {
                                    chars.first { $0.caseInsensitiveCompare(audition.wrappedValue.role) == .orderedSame } ?? Self.customRoleTag
                                },
                                set: { newValue in
                                    if newValue != Self.customRoleTag {
                                        audition.wrappedValue.role = newValue
                                        Haptics.tick()
                                    }
                                }
                            )) {
                                Text("Enter a different role manually").tag(Self.customRoleTag)
                                ForEach(chars, id: \.self) { char in
                                    Text(char).tag(char)
                                }
                            }
                            .pickerStyle(.menu)

                            Text("Choose a character detected in the sides, or enter a different role below.")
                                .font(.otCaption).foregroundStyle(OT.labelTertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OTSpace.s) {
                                    ForEach(chars, id: \.self) { char in
                                        let isCurrent = char.caseInsensitiveCompare(audition.wrappedValue.role) == .orderedSame
                                        Button {
                                            audition.wrappedValue.role = char
                                            Haptics.tick()
                                        } label: {
                                            HStack(spacing: OTSpace.xs) {
                                                if isCurrent {
                                                    Image(systemName: "checkmark")
                                                        .font(.otCaption.weight(.bold))
                                                }
                                                Text(char)
                                                    .lineLimit(1)
                                            }
                                            .fixedSize(horizontal: true, vertical: false)
                                            .font(.otCaption.weight(isCurrent ? .bold : .medium))
                                            .foregroundStyle(isCurrent ? OT.bgCanvas : OT.accent)
                                            .padding(.horizontal, OTSpace.m)
                                            .padding(.vertical, OTSpace.xs)
                                            .background(isCurrent ? AnyShapeStyle(OT.accent) : AnyShapeStyle(OT.accentSoft), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, OTSpace.xxs)
                            }

                            let otherChars = chars.filter { $0.caseInsensitiveCompare(audition.wrappedValue.role) != .orderedSame }
                            if let reader = otherChars.first {
                                Toggle("Record cues for \(reader) after saving", isOn: $recordReaderAfterSave)
                                    .font(.otCaption.weight(.medium))
                                    .foregroundStyle(OT.reader)
                            }
                        } else {
                            Label("No character names were found in the script. Enter your role below.", systemImage: "text.magnifyingglass")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            TextField("Your role / character", text: audition.role)
                                .textInputAutocapitalization(.words)
                            if showValidationErrors && audition.wrappedValue.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label("Character or role name is required", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red) // ot-lint:allow
                            }
                        }
                        TextField("Size (lead, supporting…)", text: audition.roleSize)
                    }
                    Section("Scenes") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scenes to tape")
                                    .font(.otHeadline)
                                Text("\(sceneCount) \(sceneCount == 1 ? "scene" : "scenes") in package")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Stepper("", value: $sceneCount, in: 1...12)
                                .labelsHidden()
                        }

                        ForEach(1...sceneCount, id: \.self) { num in
                            HStack {
                                Image(systemName: "film")
                                    .foregroundStyle(OT.accent)
                                    .font(.system(size: 14)) // ot-lint:allow
                                Text("Scene \(num)")
                                    .font(.otSubhead)
                                Spacer()
                                if num <= audition.wrappedValue.scenes.count {
                                    let s = audition.wrappedValue.scenes[num - 1]
                                    if s.lines.isEmpty {
                                        Text("No sides yet")
                                            .font(.otCaption)
                                            .foregroundStyle(OT.labelTertiary)
                                    } else {
                                        let mine = s.lines.filter(\.isMine).count
                                        Text("\(mine) line\(mine == 1 ? "" : "s")")
                                            .font(.otCaption)
                                            .foregroundStyle(OT.labelSecondary)
                                    }
                                } else {
                                    Text("New scene")
                                        .font(.otCaption.weight(.medium))
                                        .foregroundStyle(OT.accent)
                                }
                            }
                        }

                        Button {
                            if sceneCount < 12 {
                                sceneCount += 1
                                Haptics.tick()
                            }
                        } label: {
                            Label("Add another scene", systemImage: "plus.circle.fill")
                                .font(.otSubhead.weight(.semibold))
                                .foregroundStyle(OT.accent)
                        }
                        .disabled(sceneCount >= 12)
                    }
                    Section {
                        VStack(alignment: .leading, spacing: OTSpace.m) {
                            // Slate
                            HStack {
                                Label("Slate", systemImage: "person.text.rectangle")
                                    .font(.otSubhead.weight(.medium))
                                Spacer()
                                Toggle("Include slate", isOn: Binding(
                                    get: { audition.wrappedValue.pieces.contains { $0.kind == .slate } },
                                    set: { included in
                                        if included {
                                            if !audition.wrappedValue.pieces.contains(where: { $0.kind == .slate }) {
                                                let isDone = audition.wrappedValue.slateVideoURL != nil
                                                let p = Piece(kind: .slate, title: "Slate", detail: "Name, height, city", isDone: isDone, isOptional: false)
                                                let insertAt = audition.wrappedValue.pieces.firstIndex(where: { $0.kind == .headshot }).map { $0 + 1 } ?? 0
                                                audition.wrappedValue.pieces.insert(p, at: insertAt)
                                            }
                                        } else {
                                            audition.wrappedValue.pieces.removeAll { $0.kind == .slate }
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }

                            if let slateIndex = audition.wrappedValue.pieces.firstIndex(where: { $0.kind == .slate }) {
                                Picker("Slate requirement", selection: Binding(
                                    get: { audition.wrappedValue.pieces[slateIndex].isOptional ? "Optional" : "Required" },
                                    set: {
                                        let opt = ($0 == "Optional")
                                        audition.wrappedValue.pieces[slateIndex].isOptional = opt
                                        audition.wrappedValue.pieces[slateIndex].title = opt ? "Slate (Optional)" : "Slate"
                                    }
                                )) {
                                    Text("Required in flow").tag("Required")
                                    Text("Optional").tag("Optional")
                                }
                                .pickerStyle(.segmented)
                            }

                            // Headshots
                            HStack {
                                Label("Headshots", systemImage: "person.crop.square")
                                    .font(.otSubhead.weight(.medium))
                                Spacer()
                                Toggle("Include headshots", isOn: Binding(
                                    get: { audition.wrappedValue.pieces.contains { $0.kind == .headshot } },
                                    set: { included in
                                        if included {
                                            if !audition.wrappedValue.pieces.contains(where: { $0.kind == .headshot }) {
                                                let isDone = HeadshotStore.exists(key: "front", auditionID: auditionID)
                                                let p = Piece(kind: .headshot, title: "Headshot", detail: "Photos", isDone: isDone, isOptional: false)
                                                let insertAt = audition.wrappedValue.pieces.firstIndex(where: { $0.kind != .headshot }) ?? audition.wrappedValue.pieces.endIndex
                                                audition.wrappedValue.pieces.insert(p, at: insertAt)
                                            }
                                        } else {
                                            audition.wrappedValue.pieces.removeAll { $0.kind == .headshot }
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }

                            if let headshotIndex = audition.wrappedValue.pieces.firstIndex(where: { $0.kind == .headshot }) {
                                Picker("Headshot requirement", selection: Binding(
                                    get: { audition.wrappedValue.pieces[headshotIndex].isOptional ? "Optional" : "Required" },
                                    set: {
                                        let opt = ($0 == "Optional")
                                        audition.wrappedValue.pieces[headshotIndex].isOptional = opt
                                        audition.wrappedValue.pieces[headshotIndex].title = opt ? "Headshot (Optional)" : "Headshot"
                                    }
                                )) {
                                    Text("Required in flow").tag("Required")
                                    Text("Optional").tag("Optional")
                                }
                                .pickerStyle(.segmented)
                            }

                            // Scenes requirement
                            let sceneIndices = audition.wrappedValue.pieces.indices.filter { audition.wrappedValue.pieces[$0].kind == .scene }
                            if !sceneIndices.isEmpty {
                                Text("Scenes")
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(OT.labelSecondary)
                                    .padding(.top, OTSpace.xxs)
                                ForEach(sceneIndices, id: \.self) { scenePieceIndex in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label(audition.wrappedValue.pieces[scenePieceIndex].title, systemImage: "theatermasks.fill")
                                                .font(.otSubhead.weight(.medium))
                                            Spacer()
                                            Text(audition.wrappedValue.pieces[scenePieceIndex].isOptional ? "Optional" : "Required")
                                                .font(.otCaption.weight(.semibold))
                                                .foregroundStyle(audition.wrappedValue.pieces[scenePieceIndex].isOptional ? OT.labelSecondary : OT.accent)
                                        }
                                        Picker("Scene requirement", selection: Binding(
                                            get: { audition.wrappedValue.pieces[scenePieceIndex].isOptional ? "Optional" : "Required" },
                                            set: { opt in
                                                audition.wrappedValue.pieces[scenePieceIndex].isOptional = (opt == "Optional")
                                            }
                                        )) {
                                            Text("Required in flow").tag("Required")
                                            Text("Optional").tag("Optional")
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                    .padding(.vertical, OTSpace.xxs)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, OTSpace.xxs)
                        .listRowSeparator(.hidden)
                    } header: {
                        Text("Audition Flow & Requirements")
                    } footer: {
                        Text("Scenes, Slate, and Headshots can each be set to Required or Optional depending on casting instructions.")
                    }
                    Section {
                        ForEach(audition.wrappedValue.pieces) { piece in
                            HStack(spacing: OTSpace.s) {
                                Image(systemName: piece.kind.symbol)
                                    .foregroundStyle(OT.accent)
                                    .frame(width: 24) // ot-lint:allow
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(piece.title).font(.otBody.weight(.medium))
                                    Text(piece.isOptional ? "Optional" : "Required")
                                        .font(.otCaption).foregroundStyle(piece.isOptional ? OT.labelSecondary : OT.accent)
                                }
                            }
                        }
                        .onMove { source, destination in
                            audition.wrappedValue.pieces.move(fromOffsets: source, toOffset: destination)
                            Haptics.tick()
                        }
                    } header: {
                        HStack {
                            Text("Flow order")
                            Spacer()
                            EditButton()
                        }
                    } footer: {
                        Text("Tap Edit, then drag items to choose the order you prepare them.")
                    }
                    Section("Due") {
                        DatePicker("Due", selection: audition.due)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quick time")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OTSpace.s) {
                                    presetTimeChip("5:00 PM") { setAuditionDueTime(audition: audition, hour: 17, minute: 0) }
                                    presetTimeChip("10:00 AM") { setAuditionDueTime(audition: audition, hour: 10, minute: 0) }
                                    presetTimeChip("12:00 PM") { setAuditionDueTime(audition: audition, hour: 12, minute: 0) }
                                    presetTimeChip("11:59 PM") { setAuditionDueTime(audition: audition, hour: 23, minute: 59) }
                                }
                            }
                        }
                    }
                    Section("Sending to") {
                        Picker("Destination", selection: audition.destination) {
                            ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
                        }
                        TextField(
                            audition.wrappedValue.destination == .emailOrLink
                                ? "Email address or submission link"
                                : "\(audition.wrappedValue.destination.rawValue) account or submission notes",
                            text: Binding(
                                get: {
                                    if let detail = audition.wrappedValue.destinationDetail, !detail.isEmpty {
                                        return detail
                                    }
                                    if let emailAsk = audition.wrappedValue.asks.first(where: { $0.hasPrefix("Email: ") }) {
                                        return emailAsk.replacingOccurrences(of: "Email: ", with: "")
                                    }
                                    return ""
                                },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    audition.wrappedValue.destinationDetail = trimmed.isEmpty ? nil : trimmed
                                    audition.wrappedValue.asks.removeAll { $0.hasPrefix("Email: ") }
                                    if !trimmed.isEmpty {
                                        if trimmed.contains("@") {
                                            audition.wrappedValue.asks.append("Email: \(trimmed)")
                                        } else {
                                            audition.wrappedValue.asks.append(trimmed)
                                        }
                                    }
                                }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(audition.wrappedValue.destination == .emailOrLink ? .emailAddress : .default)
                    }
                    Section("Sides & Script") {
                        let hasSides = !audition.wrappedValue.scenes.isEmpty
                        if hasSides {
                            let totalLines = audition.wrappedValue.scenes.flatMap(\.lines).filter(\.isMine).count
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(audition.wrappedValue.scenes.count) \(audition.wrappedValue.scenes.count == 1 ? "scene" : "scenes") attached")
                                        .font(.otHeadline)
                                    Text("\(totalLines) actor \(totalLines == 1 ? "line" : "lines") detected")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(OT.accent)
                                    .font(.system(size: 20)) // ot-lint:allow
                            }

                            Button {
                                showPDFPicker = true
                            } label: {
                                HStack {
                                    Label("Replace with PDF / Document…", systemImage: "doc.badge.arrow.up")
                                        .font(.otSubhead.weight(.medium))
                                    Spacer()
                                    if isProcessingPDF {
                                        ProgressView().scaleEffect(0.8) // ot-lint:allow
                                    }
                                }
                                .foregroundStyle(OT.accent)
                            }
                            .disabled(isProcessingPDF)

                            Button {
                                showRevisedSides = true
                            } label: {
                                Label("Edit Text / Scan with Camera…", systemImage: "pencil.and.list.clipboard")
                                    .font(.otSubhead.weight(.medium))
                                    .foregroundStyle(OT.accent)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No script sides attached")
                                    .font(.otHeadline)
                                Text("Import a PDF, scan pages, or paste text to enable the teleprompter & line runner.")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            .padding(.vertical, OTSpace.xxs)

                            Button {
                                showPDFPicker = true
                            } label: {
                                HStack {
                                    Label("Import Sides PDF / Document", systemImage: "doc.badge.plus")
                                        .font(.otSubhead.weight(.semibold))
                                    Spacer()
                                    if isProcessingPDF {
                                        ProgressView().scaleEffect(0.8) // ot-lint:allow
                                    }
                                }
                                .foregroundStyle(OT.accent)
                            }
                            .disabled(isProcessingPDF)

                            Button {
                                showRevisedSides = true
                            } label: {
                                Label("Scan with Camera or Paste Text…", systemImage: "doc.viewfinder")
                                    .font(.otSubhead.weight(.medium))
                                    .foregroundStyle(OT.accent)
                            }
                        }

                        // Cloud Link (Drive, Dropbox, iCloud)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cloud link (optional)")
                                .font(.otCaption.weight(.medium))
                                .foregroundStyle(OT.labelSecondary)

                            TextField("Google Drive, Dropbox, or cloud link", text: Binding(
                                get: { audition.wrappedValue.sidesLink ?? "" },
                                set: { audition.wrappedValue.sidesLink = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                            if let sidesLink = audition.wrappedValue.sidesLink,
                                let url = URL(string: sidesLink.hasPrefix("http") ? sidesLink : "https://\(sidesLink)") {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text("Open link in browser")
                                    }
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                                }
                                .padding(.top, OTSpace.xxs)
                            }
                        }
                        .padding(.top, OTSpace.xxs)
                    }
                    Section {
                        TextField("Character breakdown, director notes, adjustments", text: Binding(
                            get: { audition.wrappedValue.castingNotes ?? "" },
                            set: { audition.wrappedValue.castingNotes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                    } header: {
                        Text("Notes from casting")
                    } footer: {
                        Text("Character breakdown and casting adjustments. Shown on Prepare before every take.")
                    }

                    Section {
                        TextField("My subtext, scene objective, choices, questions", text: Binding(
                            get: { audition.wrappedValue.actorNotes ?? "" },
                            set: { audition.wrappedValue.actorNotes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                    } header: {
                        Text("My notes & understanding")
                    } footer: {
                        Text("Private rehearsal notes, intentions, and character choices. Kept handy while preparing.")
                    }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .otCanvas()
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let audition = store.audition(auditionID) {
                            let isProjectEmpty = audition.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            let isRoleEmpty = audition.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            if isProjectEmpty || isRoleEmpty {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showValidationErrors = true
                                }
                                Haptics.warning()
                                return
                            }
                        }
                        store.updateSceneCount(for: auditionID, count: sceneCount)
                        store.reclassifyRole(for: auditionID)
                        dismiss()
                        if recordReaderAfterSave,
                           let updated = store.audition(auditionID),
                           let firstScene = updated.scenes.indices.first(where: { !updated.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
                            store.push(.reader(auditionID, sceneIndex: firstScene))
                        }
                    }
                }
            }
        }
        .onAppear {
            if let a = store.audition(auditionID) {
                let count = max(a.scenes.count, a.pieces.filter { $0.kind == .scene }.count)
                sceneCount = max(1, count)
            }
        }
        .fileImporter(isPresented: $showPDFPicker, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            switch result {
            case .success(let url):
                isProcessingPDF = true
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer {
                        resolved.cleanup()
                        Task { @MainActor in isProcessingPDF = false }
                    }
                    if let text = await NoticeOCR.extractText(fromFileAt: resolved.url), NoticeOCR.looksReadable(text) {
                        let role = store.audition(auditionID)?.role ?? ""
                        let parsedScenes = ScriptParser.parseScenes(from: text, myRole: role)
                        await MainActor.run {
                            store.replaceSides(of: auditionID, with: parsedScenes, sourceText: text)
                            sceneCount = max(sceneCount, parsedScenes.count)
                            Haptics.success()
                        }
                    } else {
                        await MainActor.run {
                            showPDFError = true
                            Haptics.warning()
                        }
                    }
                }
            case .failure:
                showPDFError = true
            }
        }
        .sheet(isPresented: $showRevisedSides) {
            RevisedSidesSheet(auditionID: auditionID)
        }
        .alert("We couldn't read this file", isPresented: $showPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No readable text was found in the document. You can scan the pages or paste text directly.")
        }
    }

    private static let customRoleTag = "__onetake_custom_role__"

    private func scriptCharacters(for audition: Audition) -> [String] {
        var candidates = (audition.roleBreakdowns ?? []).map(\.name)
        if let script = audition.scriptText, !script.isEmpty {
            candidates += ScriptParser.extractCharacters(from: script)
        }
        for scene in audition.scenes {
            candidates += scene.lines.map(\.character)
        }
        var found: [String] = []
        for candidate in candidates {
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !ScriptParser.isBlacklistedNoticeWord(name),
                  !found.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            found.append(name)
        }
        return found
    }

    private func presetTimeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            Haptics.tick()
        }) {
            Text(title)
                .font(.otCaption.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, OTSpace.s)
                .frame(minHeight: 34) // ot-lint:allow
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)) // ot-lint:allow
                .foregroundStyle(OT.accent)
        }
        .buttonStyle(.plain)
    }

    private func setAuditionDueTime(audition: Binding<Audition>, hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = calendar.dateComponents([.year, .month, .day], from: audition.wrappedValue.due)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let newDate = calendar.date(from: comps) {
            audition.wrappedValue.due = newDate
        }
    }
}
