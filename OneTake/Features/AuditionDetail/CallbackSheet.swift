import SwiftUI
import PhotosUI
import VisionKit

struct CallbackSheet: View {
    let audition: Audition
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var due = Date.now.addingTimeInterval(5 * 86400)
    @State private var castingNotes = ""
    @State private var actorNotes = ""
    @State private var bringReader = true
    @State private var callbackScenes: [ScriptScene] = []
    @State private var initialSceneCount: Int = 0
    @State private var extraScriptText: String = ""
    @State private var showPDFPicker = false
    @State private var isProcessingPDF = false
    @State private var showPDFError = false
    @State private var showExtraSidesSheet = false
    @State private var recordCallbackReaderNow = false

    private var readerName: String {
        callbackScenes.first?.lines.first(where: { !$0.isMine })?.character
            ?? audition.scenes.first?.lines.first(where: { !$0.isMine })?.character
            ?? "your reader"
    }

    var body: some View {
        VStack(spacing: 0) {
            OTSheetHeader(
                title: "Start a callback",
                leading: "Cancel",
                trailing: "Create",
                onLeading: { dismiss() },
                onTrailing: {
                    if let id = store.startCallback(
                        from: audition.id,
                        due: due,
                        notes: castingNotes,
                        actorNotes: actorNotes,
                        scenes: callbackScenes,
                        extraScriptText: extraScriptText.isEmpty ? nil : extraScriptText,
                        bringReader: bringReader
                    ) {
                        dismiss()
                        if recordCallbackReaderNow,
                           let cbAudition = store.audition(id),
                           let firstScene = cbAudition.scenes.indices.first(where: { !cbAudition.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
                            store.push(.reader(id, sceneIndex: firstScene))
                        } else {
                            store.push(.auditionDetail(id))
                        }
                    }
                }
            )
            .padding(.top, OTSpace.m)

            Form {
                Section { LabeledContent(audition.project, value: "Round \((audition.round ?? 1) + 1)") }

                Section("When is it due?") {
                    DatePicker("Due", selection: $due, in: Date.now...)
                    HStack(spacing: OTSpace.s) {
                        Text("Presets:")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelSecondary)
                        presetTimeChip("5:00 PM") { setDueTime(hour: 17, minute: 0) }
                        presetTimeChip("10:00 AM") { setDueTime(hour: 10, minute: 0) }
                        presetTimeChip("Noon") { setDueTime(hour: 12, minute: 0) }
                        presetTimeChip("11:59 PM") { setDueTime(hour: 23, minute: 59) }
                    }
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scenes to tape")
                                .font(.otHeadline)
                            let extraCount = max(0, callbackScenes.count - initialSceneCount)
                            Text("\(callbackScenes.count) \(callbackScenes.count == 1 ? "scene" : "scenes")\(extraCount > 0 ? " (\(extraCount) added for callback)" : "")")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                        Stepper("", value: Binding(
                            get: { callbackScenes.count },
                            set: { newCount in
                                if newCount > callbackScenes.count && newCount <= 12 {
                                    for num in (callbackScenes.count + 1)...newCount {
                                        callbackScenes.append(ScriptScene(number: num, title: "Scene \(num)", heading: "SCENE \(num)", lines: []))
                                    }
                                } else if newCount < callbackScenes.count && newCount >= max(1, initialSceneCount) {
                                    callbackScenes.removeLast(callbackScenes.count - newCount)
                                }
                            }
                        ), in: max(1, initialSceneCount)...12)
                        .labelsHidden()
                    }

                    ForEach(Array(callbackScenes.enumerated()), id: \.element.id) { index, scene in
                        HStack {
                            Image(systemName: "film")
                                .foregroundStyle(OT.accent)
                                .font(.system(size: 14)) // ot-lint:allow
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scene.title.isEmpty ? "Scene \(scene.number)" : scene.title)
                                    .font(.otSubhead.weight(.medium))
                                if scene.lines.isEmpty {
                                    Text("No sides attached")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelTertiary)
                                } else {
                                    let mine = scene.lines.filter(\.isMine).count
                                    Text("\(mine) actor \(mine == 1 ? "line" : "lines")")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                            }
                            Spacer()
                            if index < initialSceneCount {
                                OTChip("Round 1")
                            } else {
                                OTChip("Callback", tint: OT.accent)

                                Button {
                                    callbackScenes.remove(at: index)
                                    renumberScenes()
                                    Haptics.tick()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13)) // ot-lint:allow
                                        .foregroundStyle(OT.labelTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        if callbackScenes.count < 12 {
                            let nextNum = callbackScenes.count + 1
                            callbackScenes.append(ScriptScene(number: nextNum, title: "Scene \(nextNum)", heading: "SCENE \(nextNum)", lines: []))
                            Haptics.tick()
                        }
                    } label: {
                        Label("Add another scene", systemImage: "plus.circle.fill")
                            .font(.otSubhead.weight(.semibold))
                            .foregroundStyle(OT.accent)
                    }
                    .disabled(callbackScenes.count >= 12)
                } header: {
                    Text("Scenes to tape")
                } footer: {
                    Text("Keep your Round 1 scenes and add any new scenes casting requested for this callback.")
                }

                Section {
                    if !extraScriptText.isEmpty {
                        let extraScenesCount = max(0, callbackScenes.count - initialSceneCount)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Extra sides attached")
                                    .font(.otHeadline)
                                Text("\(extraScenesCount) callback \(extraScenesCount == 1 ? "scene" : "scenes") merged with Round 1 sides")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OT.accent)
                                .font(.system(size: 20)) // ot-lint:allow
                        }
                    }

                    Button {
                        showPDFPicker = true
                    } label: {
                        HStack {
                            Label(extraScriptText.isEmpty ? "Import extra sides (PDF / Document)…" : "Import more sides (PDF / Document)…", systemImage: "doc.badge.plus")
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
                        showExtraSidesSheet = true
                    } label: {
                        Label(extraScriptText.isEmpty ? "Paste or scan extra sides…" : "Add more sides by pasting or scanning…", systemImage: "pencil.and.list.clipboard")
                            .font(.otSubhead.weight(.medium))
                            .foregroundStyle(OT.accent)
                    }
                } header: {
                    Text("Extra Sides & Script")
                } footer: {
                    Text("Extra sides are kept alongside your original sides so you have all scenes ready in the teleprompter & line runner.")
                }

                Section {
                    TextField("e.g. “Less angry, more hurt.”", text: $castingNotes, axis: .vertical)
                } header: {
                    Text("Notes from casting")
                } footer: {
                    Text("Character breakdown and casting adjustments. Shown on Prepare before every take.")
                }

                Section {
                    TextField("My subtext, scene objective, choices, questions…", text: $actorNotes, axis: .vertical)
                } header: {
                    Text("My notes & understanding")
                } footer: {
                    Text("Private rehearsal notes, intentions, and character choices for this callback.")
                }

                Section {
                    Toggle("Bring over reader track · \(readerName)", isOn: $bringReader)
                    if !bringReader || !extraScriptText.isEmpty {
                        Toggle("Record cues for callback scenes after creating", isOn: $recordCallbackReaderNow)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
        .navigationBarBackButtonHidden(true)
        .onAppear {
            setupInitialState()
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
                        await MainActor.run {
                            appendExtraSides(text: text)
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
        .sheet(isPresented: $showExtraSidesSheet) {
            CallbackExtraSidesSheet(role: audition.role) { extraText in
                appendExtraSides(text: extraText)
            }
        }
        .alert("We couldn't read this file", isPresented: $showPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No readable text was found in the document. You can scan the pages or paste text directly.")
        }
    }

    private func setupInitialState() {
        if callbackScenes.isEmpty {
            if !audition.scenes.isEmpty {
                callbackScenes = audition.scenes
                initialSceneCount = audition.scenes.count
            } else {
                let scenePieces = audition.pieces.filter { $0.kind == .scene }
                let count = max(1, scenePieces.count)
                callbackScenes = (1...count).map { num in
                    ScriptScene(number: num, title: "Scene \(num)", heading: "SCENE \(num)", lines: [])
                }
                initialSceneCount = callbackScenes.count
            }
        }
        if castingNotes.isEmpty, let c = audition.castingNotes {
            castingNotes = c
        }
        if actorNotes.isEmpty, let a = audition.actorNotes {
            actorNotes = a
        }
    }

    private func appendExtraSides(text: String) {
        let cleaned = ScriptParser.cleanPastedText(text)
        guard !cleaned.isEmpty else { return }

        let parsed = ScriptParser.parseScenes(from: cleaned, myRole: audition.role)
        let startNum = callbackScenes.count + 1

        if !parsed.isEmpty {
            let renumbered = parsed.enumerated().map { idx, scene in
                ScriptScene(
                    number: startNum + idx,
                    title: (scene.title.isEmpty || scene.title.hasPrefix("Scene")) ? "Scene \(startNum + idx)" : scene.title,
                    heading: scene.heading.isEmpty ? "SCENE \(startNum + idx)" : scene.heading,
                    lines: scene.lines,
                    estimatedSeconds: scene.estimatedSeconds
                )
            }
            callbackScenes.append(contentsOf: renumbered)
        } else {
            let roleName = audition.role.isEmpty ? "Me" : audition.role
            let line = ScriptLine(character: roleName, text: cleaned, isMine: true)
            let newScene = ScriptScene(
                number: startNum,
                title: "Scene \(startNum)",
                heading: "SCENE \(startNum)",
                lines: [line]
            )
            callbackScenes.append(newScene)
        }

        if extraScriptText.isEmpty {
            extraScriptText = cleaned
        } else {
            extraScriptText += "\n\n" + cleaned
        }

        if let newNotes = NoticeParser.extractCharacterDescription(for: audition.role, in: cleaned) {
            if castingNotes.isEmpty {
                castingNotes = newNotes
            } else if !castingNotes.contains(newNotes) {
                castingNotes += "\n\n" + newNotes
            }
        }

        Haptics.success()
    }

    private func renumberScenes() {
        for i in callbackScenes.indices {
            let num = i + 1
            callbackScenes[i].number = num
            if callbackScenes[i].title.hasPrefix("Scene ") {
                callbackScenes[i].title = "Scene \(num)"
            }
        }
    }

    private func presetTimeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            Haptics.tick()
        }) {
            Text(title)
                .font(.otCaption.weight(.semibold))
                .padding(.horizontal, OTSpace.s)
                .padding(.vertical, 6) // ot-lint:allow
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)) // ot-lint:allow
                .foregroundStyle(OT.accent)
        }
        .buttonStyle(.plain)
    }

    private func setDueTime(hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = calendar.dateComponents([.year, .month, .day], from: due)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let newDate = calendar.date(from: comps) {
            due = newDate
        }
    }
}

// MARK: - Callback Extra Sides Sheet

struct CallbackExtraSidesSheet: View {
    let role: String
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var reading = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importError = false
    @State private var emptyClipboardAlert = false

    private var parsedScenes: [ScriptScene] {
        ScriptParser.parseScenes(from: text, myRole: role)
    }

    var body: some View {
        VStack(spacing: 0) {
            OTSheetHeader(
                title: "Add extra sides",
                leading: "Cancel",
                trailing: "Add sides",
                onLeading: { dismiss() },
                onTrailing: {
                    onAdd(text)
                    dismiss()
                }
            )
            .padding(.top, OTSpace.m)

            ScrollView {
                VStack(spacing: OTSpace.m) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: OTSpace.m), GridItem(.flexible(), spacing: OTSpace.m)], spacing: OTSpace.m) {
                        Button {
                            showImporter = true
                        } label: {
                            SidesInputTile(
                                icon: "doc.badge.plus",
                                title: "Import PDF",
                                subtitle: "PDF or script file",
                                color: OT.accent
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            pasteFromClipboard()
                        } label: {
                            SidesInputTile(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "Paste Text",
                                subtitle: "From clipboard",
                                color: Color(uiColor: .systemIndigo) // ot-lint:allow
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            if VNDocumentCameraViewController.isSupported {
                                showScanner = true
                            } else {
                                scannerUnavailable = true
                            }
                        } label: {
                            SidesInputTile(
                                icon: "doc.viewfinder",
                                title: "Scan Pages",
                                subtitle: "Camera scanner",
                                color: Color(uiColor: .systemPurple) // ot-lint:allow
                            )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(selection: $photoItems, matching: .images) {
                            SidesInputTile(
                                icon: "photo.on.rectangle",
                                title: "Photos",
                                subtitle: "Camera roll",
                                color: Color(uiColor: .systemTeal) // ot-lint:allow
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if reading {
                        HStack(spacing: OTSpace.m) {
                            ProgressView()
                            Text("Reading pages and parsing sides…")
                                .font(.otSubhead)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OTSpace.m)
                        .otCard(.inset)
                    }

                    // Script Text Area Card
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            Text("CALLBACK SIDES TEXT")
                                .font(.otEyebrow)
                                .foregroundStyle(OT.labelSecondary)
                            Spacer()
                            if !text.isEmpty {
                                Button("Clear") {
                                    withAnimation { text = "" }
                                }
                                .font(.otCaption.weight(.semibold))
                                .foregroundStyle(OT.danger)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste or type callback sides here...\nThese extra sides will be appended to your Round 1 script.")
                                    .font(.otCallout)
                                    .foregroundStyle(OT.labelTertiary)
                                    .padding(.horizontal, OTSpace.m)
                                    .padding(.vertical, OTSpace.s)
                                    .allowsHitTesting(false)
                            }

                            ScriptTextEditor(text: $text)
                                .frame(minHeight: 140, maxHeight: 220) // ot-lint:allow
                        }
                        .otCard(.inset)
                    }

                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            Text("DETECTED IN EXTRA SIDES")
                                .font(.otEyebrow)
                                .foregroundStyle(OT.labelSecondary)

                            if !parsedScenes.isEmpty {
                                HStack(spacing: OTSpace.s) {
                                    SidesChip(title: "Scenes", value: "\(parsedScenes.count)", isAccent: false)
                                    SidesChip(title: role.isEmpty ? "Your role" : role, value: "\(parsedScenes.flatMap(\.lines).filter(\.isMine).count)", isAccent: true)
                                    SidesChip(title: "Total lines", value: "\(parsedScenes.flatMap(\.lines).count)", isAccent: false)
                                }
                            } else {
                                HStack(spacing: OTSpace.s) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(OT.labelTertiary)
                                    Text("No structured scenes detected yet. We'll still attach this text as a new scene for your teleprompter.")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelTertiary)
                                }
                                .padding(OTSpace.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .otCard(.inset)
                            }
                        }
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .padding(.bottom, 90) // ot-lint:allow
            }
        }
        .otBottomBar {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add sides to callback") {
                    onAdd(text)
                    dismiss()
                }
                .buttonStyle(.otPrimary)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
        .navigationBarBackButtonHidden(true)
        .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs the iPhone camera. Use Photo or File instead.")
        }
        .alert("Couldn't read this file", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn't extract readable text from this file. If it's a scanned document or photocopy, try taking a photo or pasting the script directly.")
        }
        .alert("Clipboard is empty", isPresented: $emptyClipboardAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No text was found on your clipboard. Copy sides from an email, script, or PDF viewer, then tap Paste.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf, .text]) { result in
            switch result {
            case .success(let url):
                reading = true
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer {
                        resolved.cleanup()
                        Task { @MainActor in reading = false }
                    }
                    let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)
                    await MainActor.run {
                        if let extracted, !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            text = ScriptParser.cleanPastedText(extracted)
                            Haptics.success()
                        } else {
                            importError = true
                            Haptics.warning()
                        }
                    }
                }
            case .failure:
                importError = true
                Haptics.warning()
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                reading = true
                Task {
                    let recognized = await NoticeOCR.recognizeText(in: pages)
                    await MainActor.run {
                        text = ScriptParser.cleanPastedText(recognized)
                        reading = false
                        Haptics.success()
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            reading = true
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        images.append(img)
                    }
                }
                guard !images.isEmpty else {
                    await MainActor.run { reading = false }
                    return
                }
                let recognized = await NoticeOCR.recognizeText(in: images)
                await MainActor.run {
                    text = ScriptParser.cleanPastedText(recognized)
                    photoItems = []
                    reading = false
                    Haptics.success()
                }
            }
        }
        .interactiveDismissDisabled(!text.isEmpty)
    }

    private func pasteFromClipboard() {
        let pasted = UIPasteboard.general.string ?? ""
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = ScriptParser.cleanPastedText(trimmed)
        if !cleaned.isEmpty {
            text = cleaned
            Haptics.success()
        } else {
            emptyClipboardAlert = true
            Haptics.warning()
        }
    }
}
