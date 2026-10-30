import SwiftUI
import AVKit
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import UIKit

// MARK: - 24 Practice (tab)

struct PracticeView: View {
    @Environment(AppStore.self) private var store
    @State private var sidesAuditionID: Audition.ID?
    @AppStorage("practice.showSample") private var showSample = true

    var body: some View {
        Group {
            if store.practice.isEmpty {
                EmptyPracticeView(showSample: showSample) {
                    store.push(.practiceSample)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Time/duration tracking is cut for MVP — a real stats view (practice history, time
                        // invested) comes later, rather than a partial number shown ad hoc here.

                        if let piece = store.practice.first {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(text: "Pick up where you left off")
                                Text(piece.title).font(.otTitle)
                                Text("\(piece.detail) · \(piece.takesRecorded == 0 ? "no takes yet" : "\(piece.takesRecorded) take\(piece.takesRecorded == 1 ? "" : "s") so far")").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                ReadinessDashes(done: piece.linesLearned, total: piece.linesTotal)
                                HStack {
                                    Button { open(piece) } label: { Label("Practise", systemImage: "play.fill") }.buttonStyle(.otPrimary)
                                    Button("Record a take") { store.promotePracticePiece(piece.id); store.camera = .practiceTake }.buttonStyle(.otSecondary)
                                }
                            }
                            .padding(18).otCard()
                        }

                        if !store.auditions.isEmpty && !store.auditions.contains(where: { !$0.scenes.isEmpty }) { noScenesCard }

                        if store.auditions.contains(where: { !$0.scenes.isEmpty }) {
                            QuickDrillsGrid { mode in start(mode) }
                        }

                        SectionLabel(text: "Your pieces")
                        ForEach(store.practice) { p in
                            Button { open(p) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(p.title).font(.otBody).foregroundStyle(OT.labelPrimary)
                                        Text("\(p.detail) · \(p.linesLearned) of \(p.linesTotal) lines learned").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                                }
                                .frame(minHeight: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canOpen(p))
                            Divider()
                        }
                    }
                    .padding(.horizontal, OT.gutter)
                    .padding(.bottom, 120)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .safeAreaInset(edge: .top) { header }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: Binding(get: { sidesAuditionID != nil }, set: { if !$0 { sidesAuditionID = nil } })) {
            if let id = sidesAuditionID { RevisedSidesSheet(auditionID: id) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Practice")
                .font(.otLargeTitle)
                .foregroundStyle(OT.labelPrimary)
            Spacer()
            Button { store.push(.practiceSetup) } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OT.labelOnAccent)
                    .frame(width: 44, height: 44).background(OT.accent, in: Circle())
            }
            .accessibilityLabel("Practise a new scene")
            ProfileButton { store.showProfile = true }
        }
        .padding(.horizontal, OT.gutter)
        .padding(.bottom, 6)
        .background(OT.bgCanvas)
    }

    /// Practice works on scenes read from your auditions' sides. When auditions exist without sides, prompt to add them.
    private var noScenesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No audition scenes yet", systemImage: "theatermasks").font(.otHeadline)
            Text("Add audition sides, or create a personal scene with +.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            ForEach(store.auditions) { a in
                Button { sidesAuditionID = a.id } label: {
                    IconRow(symbol: "doc.badge.plus", title: "Add sides", detail: "\(a.project) · \(a.role)")
                }.buttonStyle(.plain)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).otCard()
    }

    /// A piece opens its scene in Prepare — as long as the audition it came from still has it.
    private func canOpen(_ p: PracticePiece) -> Bool {
        if let scene = p.scene { return !scene.lines.isEmpty }
        guard let id = p.auditionID, let scene = p.sceneIndex else { return false }
        return store.audition(id)?.scenes.indices.contains(scene) ?? false
    }

    private func open(_ p: PracticePiece) {
        guard canOpen(p) else { return }
        if let id = p.auditionID, let scene = p.sceneIndex {
            store.push(.prepare(id, sceneIndex: scene))
        } else {
            store.promotePracticePiece(p.id)
            store.push(.standalonePractice(p.id))
        }
    }

    /// Quick Drills need a scene to operate on: prefer the piece currently being picked up, else
    /// the first upcoming audition's first scene — creating a real `PracticePiece` for it if one
    /// doesn't exist yet, so progress has somewhere real to be tracked.
    private func start(_ mode: LineLearningMode) {
        let auditionID: Audition.ID
        let sceneIndex: Int
        if let piece = store.practice.first, let id = piece.auditionID, let scene = piece.sceneIndex {
            auditionID = id
            sceneIndex = scene
        } else if let a = store.auditions.first(where: { !$0.scenes.isEmpty }) {
            auditionID = a.id
            sceneIndex = 0
            store.practicePiece(for: auditionID, sceneIndex: sceneIndex)
        } else {
            // No scene to drill: send them to add sides (or an audition) rather than doing nothing.
            if let first = store.auditions.first { sidesAuditionID = first.id } else { store.showAddAudition = true }
            return
        }
        switch mode {
        case .firstLetter, .maskAndReveal: store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: mode))
        case .audioGap:                    store.push(.runLines(auditionID, sceneIndex: sceneIndex))
        case .handsFreeWalk:               store.push(.audioWalk(auditionID, sceneIndex: sceneIndex))
        }
    }
}

// MARK: - 24a Empty

struct EmptyPracticeView: View {
    var showSample = true
    var openSample: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("onetake-practice-illustration")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340, maxHeight: 300)
                .accessibilityLabel("No practice pieces yet illustration")

            Text("No practice pieces yet")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(OT.labelPrimary)

            if showSample {
                Button(action: openSample) {
                    Label("Try a sample scene", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.otPrimary)
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OT.gutter)
    }
}

// MARK: - 24b / 24c Practise a scene

struct PracticeSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("practice.showSample") private var showSample = true
    @State private var sceneTitle = ""
    @State private var character = ""
    @State private var sidesText = ""
    @State private var errorMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Practise a scene", backLabel: "Back", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            Form {
            Section("Practice your own scene") {
                TextField("Scene name", text: $sceneTitle)
                TextField("Your character", text: $character)
                HStack(spacing: 18) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photo", systemImage: "photo")
                    }
                    Button { openScanner() } label: { Label("Scan", systemImage: "doc.viewfinder") }
                    Button { showFileImporter = true } label: { Label("PDF / File", systemImage: "doc") }
                }
                .font(.otFootnote.weight(.medium))
                TextEditor(text: $sidesText)
                    .frame(minHeight: 150)
                    .overlay(alignment: .topLeading) {
                        if sidesText.isEmpty {
                            Text("Paste sides with character cues, e.g. MAYA: Hello\nREADER: Hi")
                                .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                if let errorMessage {
                    Text(errorMessage).font(.otFootnote).foregroundStyle(OT.danger)
                }
                Button("Create practice scene") { createStandaloneScene() }
                    .disabled(character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sidesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if showSample {
                Section("Sample scene") {
                    Button {
                        dismiss()
                        store.push(.practiceSample)
                    } label: {
                        IconRow(symbol: "play.rectangle", title: "A late goodbye", detail: "Try the sample scene")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Audition scenes") {
                let withScenes = store.auditions.filter { !$0.scenes.isEmpty }
                if withScenes.isEmpty {
                    Text("No audition scenes yet. Create your own above or add sides to an audition.")
                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                } else {
                    ForEach(withScenes) { a in
                        ForEach(Array(a.scenes.enumerated()), id: \.element.id) { i, scene in
                            Button { start(auditionID: a.id, sceneIndex: i) } label: {
                                IconRow(symbol: "theatermasks", title: scene.title, detail: "\(a.project) · \(a.role)")
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                Task {
                    let text = await NoticeOCR.recognizeText(in: pages)
                    await MainActor.run { importText(text) }
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                let text = NoticeOCR.extractText(fromFileAt: url) ?? ""
                if accessed { url.stopAccessingSecurityScopedResource() }
                importText(text)
            case .failure:
                errorMessage = "Couldn't open that file. Try another one or paste the sides."
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    await MainActor.run { errorMessage = "Couldn't open that photo." }
                    return
                }
                let text = await NoticeOCR.recognizeText(in: [image])
                await MainActor.run { importText(text) }
            }
        }
        .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs the camera. Use Photo or PDF / File instead.")
        }
    }

    private func start(auditionID: Audition.ID, sceneIndex: Int) {
        store.practicePiece(for: auditionID, sceneIndex: sceneIndex)
        dismiss()
        store.push(.runLines(auditionID, sceneIndex: sceneIndex))
    }

    private func createStandaloneScene() {
        let role = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scene = ScriptParser.parseScenes(from: sidesText, myRole: role).first else {
            errorMessage = "No dialogue found. Add character cues and lines."
            return
        }
        var savedScene = scene
        savedScene.title = sceneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Practice scene" : sceneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let piece = store.addStandalonePracticePiece(title: savedScene.title, character: role, scene: savedScene)
        dismiss()
        store.push(.standalonePractice(piece.id))
    }

    private func openScanner() {
        if VNDocumentCameraViewController.isSupported { showScanner = true }
        else { scannerUnavailable = true }
    }

    private func importText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "No text found. Try a clearer image or paste the sides."
            return
        }
        sidesText = text
        errorMessage = nil
    }
}

struct StandalonePracticeView: View {
    let pieceID: PracticePiece.ID?
    var isSample = false
    @Environment(AppStore.self) private var store
    @State private var displayMode = StandaloneDisplay.full
    @State private var revealed: Set<ScriptLine.ID> = []
    @State private var samplePiece = PracticeSample.make()
    @State private var savedSampleID: PracticePiece.ID?

    private var piece: PracticePiece? {
        if isSample { return samplePiece }
        guard let pieceID else { return nil }
        return store.practice.first { $0.id == pieceID }
    }
    private var scene: ScriptScene? { piece?.scene }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: isSample ? "Sample scene" : "Practice", backLabel: "Back", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            Group {
                if let piece, let scene {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(piece.title).font(.otTitle).foregroundStyle(OT.labelPrimary)
                        Text("Your role: \(piece.character)").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        Picker("Practice display", selection: $displayMode) {
                            Text("Full").tag(StandaloneDisplay.full)
                            Text("First letters").tag(StandaloneDisplay.firstLetters)
                            Text("Hide my lines").tag(StandaloneDisplay.hideMine)
                        }
                        .pickerStyle(.segmented)
                        ForEach(scene.lines) { line in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(line.isMine ? "\(line.character) · YOU" : line.character)
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(line.isMine ? OT.accent : OT.reader)
                                HStack(alignment: .top, spacing: 10) {
                                    if line.isMine { Capsule().fill(OT.accent).frame(width: 3) }
                                    Text(displayText(for: line))
                                        .font(line.isMine ? .system(size: 19, weight: .semibold) : .otBody)
                                        .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if displayMode == .hideMine && line.isMine {
                                    Button(revealed.contains(line.id) ? "Hide line" : "Reveal line") {
                                        if revealed.contains(line.id) { revealed.remove(line.id) } else { revealed.insert(line.id) }
                                    }
                                    .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).otCard(radius: 16)
                        }
                        if let pieceID, !isSample {
                            HStack {
                                Label("\(piece.linesLearned) of \(piece.linesTotal) learned", systemImage: "checkmark.circle")
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                Spacer()
                                Button("Mark lines learned") { store.recordStandaloneRun(pieceID: pieceID, linesOnYourOwn: piece.linesTotal) }
                                    .buttonStyle(.otSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, OT.gutter).padding(.bottom, 120)
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Record a take") {
                        if isSample {
                            if let savedSampleID {
                                store.promotePracticePiece(savedSampleID)
                            } else {
                                let saved = store.addStandalonePracticePiece(title: piece.title, character: piece.character,
                                                                            scene: scene, detail: "Sample scene")
                                savedSampleID = saved.id
                                store.promotePracticePiece(saved.id)
                            }
                        } else if let pieceID {
                            store.promotePracticePiece(pieceID)
                        }
                        store.camera = .practiceTake
                    }
                    .buttonStyle(.otPrimary).padding(OT.gutter)
                }
            } else {
                ContentUnavailableView("Scene unavailable", systemImage: "theatermasks")
            }
        }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func displayText(for line: ScriptLine) -> String {
        guard line.isMine else { return line.text }
        switch displayMode {
        case .full: return line.text
        case .firstLetters: return otLineDisplay(line, mode: .firstLetters, peeked: false)
        case .hideMine: return revealed.contains(line.id) ? line.text : otLineDisplay(line, mode: .hide, peeked: false)
        }
    }
}

private enum StandaloneDisplay: Hashable { case full, firstLetters, hideMine }

private enum PracticeSample {
    static func make() -> PracticePiece {
        let role = "Maya"
        let scene = ScriptScene(number: 1, title: "A late goodbye", heading: "INT. STATION — NIGHT", lines: [
            ScriptLine(character: "Maya", text: "I know the train leaves at six. I just didn't think you'd come.", isMine: true),
            ScriptLine(character: "Reader", text: "You asked me to.", isMine: false),
            ScriptLine(character: "Maya", text: "I asked you to say goodbye.", isMine: true),
            ScriptLine(character: "Reader", text: "Is that all you want?", isMine: false),
            ScriptLine(character: "Maya", text: "No. But it's all I know how to ask for.", isMine: true)
        ], estimatedSeconds: 30)
        return PracticePiece(title: scene.title, detail: "Sample · not saved", linesLearned: 0,
                             linesTotal: scene.lines.filter(\.isMine).count, character: role, scene: scene)
    }
}

// MARK: - 24e Practice take (no slate, never sent)

struct PracticeTakeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()

    private var piece: PracticePiece? { store.practice.first }

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle()) }
                    Spacer()
                    Text("Practice · TK \((piece?.takesRecorded ?? 0) + 1)").font(.otFootnote.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32).background(OT.cameraGlass, in: Capsule())
                    Spacer()
                    Color.clear.frame(width: 44)
                }
                Spacer()
                Label("Practice · no slate, never sent", systemImage: "lock.fill").font(.otFootnote).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 30).background(.black.opacity(0.55), in: Capsule())
                RecordButton(isRecording: camera.state == .recording) {
                    camera.state == .recording ? camera.stopRecording() : camera.startRecording()
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, OT.gutter)
        }
        .preferredColorScheme(.dark)
        .keepScreenAwake()
        .task { if await CameraController.requestAccess() { camera.configure() } }
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            if camera.state == .recording { camera.stopRecording() } else { camera.startRecording() }
        }
        .onChange(of: camera.state) { _, newState in
            guard newState == .ready, let url = camera.lastRecording, let piece else { return }
            let number = piece.takesRecorded + 1
            if MediaStore.persist(url, as: "take-\(number)-\(UUID().uuidString).mov", in: "practice-\(piece.id.uuidString)") != nil {
                store.incrementPracticeTakes(for: piece.id)
            }
        }
        .onDisappear { camera.stop() }
    }
}
