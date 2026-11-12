import SwiftUI
import AVKit
import PhotosUI
import VisionKit
@preconcurrency import Speech
import UniformTypeIdentifiers
import UIKit

// MARK: - 24 Practice (tab)

struct PracticeView: View {
    @Environment(AppStore.self) private var store
    @State private var sidesAuditionID: Audition.ID?
    @AppStorage("practice.showSample") private var showSample = true

    /// Practice pieces with sample data filtered out when "Show sample scene" is off.
    private var displayedPractice: [PracticePiece] {
        showSample ? store.practice : store.practice.filter { !store.isSamplePiece($0) }
    }

    var body: some View {
        Group {
            if displayedPractice.isEmpty {
                EmptyPracticeView(showSample: showSample) {
                    store.push(.practiceSample)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Time/duration tracking is cut for MVP — a real stats view (practice history, time
                        // invested) comes later, rather than a partial number shown ad hoc here.

                        if let piece = displayedPractice.first {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(text: "Pick up where you left off")
                                Text(piece.title).font(.otTitle)
                                Text("\(piece.detail) · \(piece.takesRecorded == 0 ? "no takes yet" : "\(piece.takesRecorded) take\(piece.takesRecorded == 1 ? "" : "s") so far")").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                ReadinessDashes(done: piece.linesLearned, total: piece.linesTotal)
                                HStack {
                                    Button { open(piece) } label: { Label("Practise", systemImage: "play.fill") }.buttonStyle(.otPrimary)
                                    Button("Record a take") { store.promotePracticePiece(piece.id); store.camera = .practiceTake(pieceID: piece.id) }.buttonStyle(.otSecondary)
                                }
                            }
                            .padding(18).otCard()
                            .contextMenu {
                                if piece.linesLearned >= piece.linesTotal && piece.linesTotal > 0 {
                                    Button {
                                        store.recordStandaloneRun(pieceID: piece.id, linesOnYourOwn: 0)
                                        Haptics.tick()
                                    } label: {
                                        Label("Mark unlearned", systemImage: "arrow.counterclockwise")
                                    }
                                } else {
                                    Button {
                                        store.recordStandaloneRun(pieceID: piece.id, linesOnYourOwn: piece.linesTotal)
                                        Haptics.success()
                                    } label: {
                                        Label("Mark lines learned", systemImage: "checkmark.circle")
                                    }
                                }
                            }
                        }

                        if !store.auditions.isEmpty && !store.auditions.contains(where: { !$0.scenes.isEmpty }) { noScenesCard }

                        SectionLabel(text: "Your pieces")
                        ForEach(displayedPractice) { p in
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
                            .contextMenu {
                                if p.linesLearned >= p.linesTotal && p.linesTotal > 0 {
                                    Button {
                                        store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: 0)
                                        Haptics.tick()
                                    } label: {
                                        Label("Mark unlearned", systemImage: "arrow.counterclockwise")
                                    }
                                } else {
                                    Button {
                                        store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: p.linesTotal)
                                        Haptics.success()
                                    } label: {
                                        Label("Mark lines learned", systemImage: "checkmark.circle")
                                    }
                                }
                                if p.linesLearned > 0 && p.linesLearned < p.linesTotal {
                                    Button(role: .destructive) {
                                        store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: 0)
                                        Haptics.tick()
                                    } label: {
                                        Label("Reset progress", systemImage: "arrow.counterclockwise")
                                    }
                                }
                            }
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
        .showSystemTabBar()
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
            GlassIconButton(systemName: "plus", accessibilityLabel: "Practise a new scene") {
                store.push(.practiceSetup)
            }
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

    /// A piece opens its shared Practice options — as long as the audition it came from still has it.
    private func canOpen(_ p: PracticePiece) -> Bool {
        if let scene = p.scene { return !scene.lines.isEmpty }
        guard let id = p.auditionID, let scene = p.sceneIndex else { return false }
        return store.audition(id)?.scenes.indices.contains(scene) ?? false
    }

    private func open(_ p: PracticePiece) {
        guard canOpen(p) else { return }
        if let id = p.auditionID, let scene = p.sceneIndex {
            store.push(.practiceOptions(id, sceneIndex: scene))
        } else {
            store.promotePracticePiece(p.id)
            store.push(.standalonePractice(p.id))
        }
    }

}

struct PracticeOptionsView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store

    var body: some View {
        if let audition = store.audition(auditionID),
           audition.scenes.indices.contains(sceneIndex) {
            let scene = audition.scenes[sceneIndex]
            VStack(alignment: .leading, spacing: 18) {
                InContentNavHeader(
                    title: "Practice",
                    backLabel: "Back",
                    onBack: { store.pop() }
                )
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.title).font(.otLargeTitle)
                    Text("\(audition.project) · \(audition.role)")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                }

                Text("Choose how you want to rehearse")
                    .font(.otHeadline)

                VStack(spacing: 10) {
                    practiceButton(
                        title: "Practice the scene",
                        detail: "Follow the scene and speak your lines",
                        symbol: "play.fill"
                    ) {
                        store.push(.runLines(auditionID, sceneIndex: sceneIndex))
                    }
                    practiceButton(
                        title: "First-letter prompts",
                        detail: "Use the first letter of each word",
                        symbol: "textformat"
                    ) {
                        store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: .firstLetter))
                    }
                    practiceButton(
                        title: "Meaningful word gaps",
                        detail: "Hide key words · tap a gap for a clue",
                        symbol: "text.word.spacing"
                    ) {
                        store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: .gapRecall))
                    }
                    practiceButton(
                        title: "Cold read",
                        detail: "Hide your lines and reveal them when needed",
                        symbol: "eye.slash"
                    ) {
                        store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: .maskAndReveal))
                    }
                    practiceButton(
                        title: "Audio gap",
                        detail: "Hear the reader and answer in the pauses",
                        symbol: "waveform"
                    ) {
                        store.push(.runLines(auditionID, sceneIndex: sceneIndex))
                    }
                    practiceButton(
                        title: "Audio walk",
                        detail: "Rehearse hands-free with your reader recordings",
                        symbol: "headphones"
                    ) {
                        store.push(.audioWalk(auditionID, sceneIndex: sceneIndex))
                    }
                    practiceButton(
                        title: "Record a practice take",
                        detail: "Record yourself without submitting a tape",
                        symbol: "record.circle"
                    ) {
                        let piece = store.practicePiece(for: auditionID, sceneIndex: sceneIndex)
                        store.camera = .practiceTake(pieceID: piece.id)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, OT.gutter)
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
        }
    }

    private func practiceButton(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 42, height: 42)
                    .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                    Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OT.labelTertiary)
            }
            .padding(12)
            .otCard(radius: 16)
        }
        .buttonStyle(.plain)
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
                HStack {
                    Text("Paste sides from clipboard")
                        .font(.otHeadline)
                    Spacer()
                    Button {
                        let pasted = UIPasteboard.general.string ?? ""
                        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleaned = ScriptParser.cleanPastedText(trimmed)
                        if !cleaned.isEmpty {
                            sidesText = cleaned
                            autoFillFromSides(cleaned)
                            Haptics.success()
                        } else {
                            Haptics.tick()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.doc.on.clipboard")
                                .font(.system(size: 11, weight: .bold))
                            Text("Paste")
                                .font(.otCaption.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(OT.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

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
                ZStack(alignment: .topLeading) {
                    if sidesText.isEmpty {
                        Text("Paste sides with character cues, e.g. MAYA: Hello\nREADER: Hi")
                            .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            .padding(.top, 10).padding(.leading, 12).allowsHitTesting(false)
                    }
                    ScriptTextEditor(text: $sidesText)
                        .frame(minHeight: 150)
                        .onChange(of: sidesText) { _, newSides in
                            autoFillFromSides(newSides)
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
                        store.pop()
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
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer { resolved.cleanup() }
                    let text = await NoticeOCR.extractText(fromFileAt: resolved.url) ?? ""
                    await MainActor.run {
                        importText(text)
                    }
                }
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
        store.pop()
        store.push(.practiceOptions(auditionID, sceneIndex: sceneIndex))
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
        store.pop()
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
        let cleaned = ScriptParser.cleanPastedText(text)
        sidesText = cleaned
        autoFillFromSides(cleaned)
        errorMessage = nil
    }

    private func autoFillFromSides(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let chars = ScriptParser.extractCharacters(from: text)
        if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let firstChar = chars.first {
            character = firstChar
        }
        if sceneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let firstScene = ScriptParser.parseScenes(from: text, myRole: character).first, firstScene.heading != "SIDES" {
                sceneTitle = firstScene.heading.capitalized
            } else if let firstChar = chars.first {
                sceneTitle = "\(firstChar)'s scene"
            } else {
                sceneTitle = "Practice scene"
            }
        }
    }
}

struct StandalonePracticeView: View {
    let pieceID: PracticePiece.ID?
    var isSample = false
    @Environment(AppStore.self) private var store
    @State private var displayMode = StandaloneDisplay.full
    @State private var revealed: Set<ScriptLine.ID> = []
    @State private var revealedWords: [ScriptLine.ID: Set<Int>] = [:]
    @State private var hiddenGapWords: [ScriptLine.ID: Set<Int>] = [:]
    @State private var samplePiece = PracticeSample.make()
    @State private var savedSampleID: PracticePiece.ID?

    private var piece: PracticePiece? {
        if let id = savedSampleID ?? pieceID {
            return store.practice.first { $0.id == id }
        }
        if isSample { return samplePiece }
        return nil
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
                            Text("Gaps").tag(StandaloneDisplay.gaps)
                            Text("Hide my lines").tag(StandaloneDisplay.hideMine)
                        }
                        .pickerStyle(.segmented)
                        ForEach(scene.lines) { line in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(line.isMine ? "\(line.character) · YOU" : line.character)
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(line.isMine ? OT.accent : OT.reader)
                                if line.isSilentReactionCue {
                                    SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: false)
                                } else {
                                    HStack(alignment: .top, spacing: 10) {
                                        if line.isMine { Capsule().fill(OT.accent).frame(width: 3) }
                                        if line.isMine && displayMode == .firstLetters && !revealed.contains(line.id) {
                                            RecallWordHintText(
                                                text: line.text,
                                                revealedWords: revealedWords[line.id, default: []],
                                                font: .system(size: 19, weight: .semibold),
                                                color: OT.labelPrimary
                                            ) { wordIndex in
                                                var words = revealedWords[line.id, default: []]
                                                if words.contains(wordIndex) { words.remove(wordIndex) }
                                                else { words.insert(wordIndex) }
                                                revealedWords[line.id] = words
                                                Haptics.tick()
                                            }
                                        } else if line.isMine && displayMode == .gaps && !revealed.contains(line.id) {
                                            RecallGapHintText(text: line.text,
                                                              hiddenWords: hiddenGapWords[line.id, default: []],
                                                              revealedWords: revealedWords[line.id, default: []],
                                                              font: .system(size: 19, weight: .semibold), color: OT.labelPrimary) { wordIndex in
                                                var words = revealedWords[line.id, default: []]
                                                if words.contains(wordIndex) { words.remove(wordIndex) } else { words.insert(wordIndex) }
                                                revealedWords[line.id] = words
                                                Haptics.tick()
                                            }
                                        } else {
                                            Text(displayText(for: line))
                                                .font(line.isMine ? .system(size: 19, weight: .semibold) : .otBody)
                                                .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    guard line.isMine, displayMode == .hideMine else { return }
                                                    if revealed.contains(line.id) { revealed.remove(line.id) }
                                                    else { revealed.insert(line.id) }
                                                    Haptics.tick()
                                                }
                                        }
                                    }
                                }
                                if displayMode == .hideMine && line.isMine && !line.isSilentReactionCue {
                                    Button(revealed.contains(line.id) ? "Hide line" : "Reveal line") {
                                        if revealed.contains(line.id) { revealed.remove(line.id) } else { revealed.insert(line.id) }
                                    }
                                    .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent)
                                } else if displayMode == .firstLetters && line.isMine && !line.isSilentReactionCue {
                                    Text("Tap any word to reveal it")
                                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                } else if displayMode == .gaps && line.isMine && !line.isSilentReactionCue {
                                    Text("Tap a gap to reveal its word")
                                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).otCard(radius: 16)
                        }
                        let targetPieceID: PracticePiece.ID? = isSample ? (savedSampleID ?? pieceID) : pieceID
                        if let targetID = targetPieceID {
                            let activePiece = piece
                            HStack {
                                Label("\(activePiece.linesLearned) of \(activePiece.linesTotal) learned",
                                      systemImage: activePiece.linesLearned >= activePiece.linesTotal && activePiece.linesTotal > 0 ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.otFootnote)
                                    .foregroundStyle(activePiece.linesLearned >= activePiece.linesTotal && activePiece.linesTotal > 0 ? OT.accent : OT.labelTertiary)
                                Spacer()
                                if activePiece.linesLearned >= activePiece.linesTotal && activePiece.linesTotal > 0 {
                                    Button("Mark unlearned") {
                                        store.recordStandaloneRun(pieceID: targetID, linesOnYourOwn: 0)
                                        samplePiece.linesLearned = 0
                                        Haptics.tick()
                                    }
                                    .buttonStyle(.otCompact)
                                } else {
                                    HStack(spacing: 8) {
                                        if activePiece.linesLearned > 0 {
                                            Button("Reset") {
                                                store.recordStandaloneRun(pieceID: targetID, linesOnYourOwn: 0)
                                                samplePiece.linesLearned = 0
                                                Haptics.tick()
                                            }
                                            .buttonStyle(.otCompact)
                                        }
                                        Button("Mark lines learned") {
                                            store.recordStandaloneRun(pieceID: targetID, linesOnYourOwn: activePiece.linesTotal)
                                            samplePiece.linesLearned = activePiece.linesTotal
                                            Haptics.success()
                                        }
                                        .buttonStyle(.otCompact)
                                    }
                                }
                            }
                        } else if isSample && !scene.lines.isEmpty {
                            HStack {
                                Label("\(samplePiece.linesLearned) of \(scene.lines.filter(\.isMine).count) learned",
                                      systemImage: samplePiece.linesLearned >= scene.lines.filter(\.isMine).count && !scene.lines.isEmpty ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.otFootnote)
                                    .foregroundStyle(samplePiece.linesLearned >= scene.lines.filter(\.isMine).count ? OT.accent : OT.labelTertiary)
                                Spacer()
                                Button("Mark lines learned") {
                                    let saved = store.addStandalonePracticePiece(title: piece.title,
                                                                                character: piece.character,
                                                                                scene: scene, detail: "Sample scene")
                                    savedSampleID = saved.id
                                    samplePiece.linesLearned = scene.lines.filter(\.isMine).count
                                    store.recordStandaloneRun(pieceID: saved.id, linesOnYourOwn: scene.lines.filter(\.isMine).count)
                                    Haptics.success()
                                }
                                .buttonStyle(.otCompact)
                            }
                        }
                    }
                    .padding(.horizontal, OT.gutter).padding(.bottom, 120)
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 12) {
                        Button {
                            launchPractice(mode: .voiceOnly)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "mic.fill")
                                Text("Run voice")
                            }
                        }
                        .buttonStyle(.ot(.glass, size: .large))

                        Button {
                            launchPractice(mode: .camera)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "video.fill")
                                Text("Record take")
                            }
                        }
                        .buttonStyle(.ot(.primary, size: .large))
                    }
                    .padding(.horizontal, OT.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .background(.ultraThinMaterial)
                }
            } else {
                ContentUnavailableView("Scene unavailable", systemImage: "theatermasks")
            }
        }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task(id: displayMode) {
            guard displayMode == .gaps, let lines = scene?.lines else { return }
            var selections: [ScriptLine.ID: Set<Int>] = [:]
            for line in lines where line.isMine && !line.isSilentReactionCue {
                selections[line.id] = await RecallGapSelectionStore.hiddenWordIndices(for: line.text)
            }
            hiddenGapWords = selections
        }
        .onChange(of: displayMode) { _, _ in
            revealed.removeAll()
            revealedWords.removeAll()
        }
    }

    private func launchPractice(mode: PracticeRecordMode) {
        guard let piece, let scene else { return }
        let targetID: PracticePiece.ID
        if isSample {
            if let savedSampleID {
                store.promotePracticePiece(savedSampleID)
                targetID = savedSampleID
            } else {
                let saved = store.addStandalonePracticePiece(title: piece.title, character: piece.character,
                                                            scene: scene, detail: "Sample scene")
                savedSampleID = saved.id
                store.promotePracticePiece(saved.id)
                targetID = saved.id
            }
        } else if let pieceID {
            store.promotePracticePiece(pieceID)
            targetID = pieceID
        } else {
            targetID = piece.id
        }
        store.camera = .practiceTake(pieceID: targetID, initialDisplayMode: displayMode, initialRecordMode: mode)
    }

    private func displayText(for line: ScriptLine) -> String {
        guard line.isMine else { return line.text }
        switch displayMode {
        case .full: return line.text
        case .firstLetters: return otLineDisplay(line, mode: .firstLetters, peeked: revealed.contains(line.id))
        case .gaps: return line.text
        case .hideMine:
            return revealed.contains(line.id) ? line.text : String(repeating: "• ", count: min(line.text.split(separator: " ").count, 8))
        }
    }

}

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

// MARK: - 24e Practice take

struct PracticeTakeView: View {
    var pieceID: PracticePiece.ID? = nil
    var initialDisplayMode: StandaloneDisplay = .full
    var initialRecordMode: PracticeRecordMode = .camera

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var recordedTakeURL: URL?
    @State private var recordedTakeDuration: Int = 0
    @State private var showPlayer = false
    @State private var activePieceID: PracticePiece.ID?
    @State private var lineIndex = 0
    @State private var follower = SpeechFollower()
    @State private var displayMode: StandaloneDisplay = .full
    @State private var recordMode: PracticeRecordMode = .camera
    @State private var revealedLines: Set<ScriptLine.ID> = []
    @State private var onYourOwnLines: Set<ScriptLine.ID> = []
    @State private var hiddenGapWords: [ScriptLine.ID: Set<Int>] = [:]
    @State private var voiceReview: [VoiceLineReview] = []
    @State private var isAnalyzingVoice = false
    @State private var voiceReviewError: String?
    @State private var showVoiceReview = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @AppStorage("prompter.size") private var prompterSize = 1
    @AppStorage("prompter.mirror") private var mirrorPrompter = false

    init(pieceID: PracticePiece.ID? = nil, initialDisplayMode: StandaloneDisplay = .full, initialRecordMode: PracticeRecordMode = .camera) {
        self.pieceID = pieceID
        self.initialDisplayMode = initialDisplayMode
        self.initialRecordMode = initialRecordMode
        _displayMode = State(initialValue: initialDisplayMode)
        _recordMode = State(initialValue: initialRecordMode)
    }

    private var piece: PracticePiece? {
        if let id = activePieceID ?? pieceID {
            return store.practice.first { $0.id == id }
        }
        return store.practice.first
    }

    private var sceneTitle: String {
        piece?.scene?.title ?? piece?.title ?? "Practice"
    }

    private var takeNumber: Int {
        (piece?.takesRecorded ?? 0) + 1
    }

    /// Checks if a next scene is available (either from the parent audition or next practice piece)
    private var nextSceneAvailable: Bool {
        guard let p = piece else { return false }
        if let audID = p.auditionID, let sIdx = p.sceneIndex, let audition = store.audition(audID) {
            return sIdx + 1 < audition.scenes.count
        }
        if let idx = store.practice.firstIndex(where: { $0.id == p.id }) {
            return idx + 1 < store.practice.count
        }
        return false
    }

    private func advanceToNextScene() {
        guard let p = piece else { return }
        recordedTakeURL = nil
        lineIndex = 0
        onYourOwnLines.removeAll()
        revealedLines.removeAll()
        if let audID = p.auditionID, let sIdx = p.sceneIndex, let audition = store.audition(audID) {
            if sIdx + 1 < audition.scenes.count {
                let nextPiece = store.practicePiece(for: audID, sceneIndex: sIdx + 1)
                activePieceID = nextPiece.id
                store.promotePracticePiece(nextPiece.id)
                Haptics.tick()
                return
            }
        }
        if let idx = store.practice.firstIndex(where: { $0.id == p.id }), idx + 1 < store.practice.count {
            let nextPiece = store.practice[idx + 1]
            activePieceID = nextPiece.id
            store.promotePracticePiece(nextPiece.id)
            Haptics.tick()
        }
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        ZStack {
            if recordMode == .camera {
                CameraBackground(controller: camera)
                    .ignoresSafeArea()
            } else {
                // Studio Voice Rehearsal Stage (Figma 11.4)
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.06, blue: 0.12), Color(red: 0.04, green: 0.03, blue: 0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay {
                    ZStack {
                        Circle()
                            .stroke(OT.reader.opacity(camera.state == .recording ? 0.25 : 0.08), lineWidth: 1)
                            .frame(width: 320, height: 320)
                        Circle()
                            .stroke(OT.accent.opacity(camera.state == .recording ? 0.18 : 0.05), lineWidth: 1)
                            .frame(width: 480, height: 480)
                    }
                    .allowsHitTesting(false)
                }
                .clipped()
                .ignoresSafeArea()
            }

            VStack {
                // Top header bar:
                // When recording: HIDE close button and title pill completely; show subtle red recording indicator.
                // When idle: Show close button, Camera vs Voice pill, Display mode menu, and text size menu.
                if camera.state == .recording {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text(formatElapsed(camera.elapsed))
                            .font(.otFootnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                        if recordMode == .voiceOnly {
                            Text("· VOICE ONLY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(OT.prompterGold)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.top, 8)
                } else {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")

                        Spacer()

                        // Record Mode Switcher: Camera vs Voice only
                        HStack(spacing: 2) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { recordMode = .camera }
                                Haptics.tick()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill").font(.system(size: 11))
                                    Text("Camera").font(.otCaption.weight(.semibold))
                                }
                                .foregroundStyle(recordMode == .camera ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(recordMode == .camera ? Color.white.opacity(0.25) : Color.clear, in: Capsule())
                            }

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { recordMode = .voiceOnly }
                                Haptics.tick()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "mic.fill").font(.system(size: 11))
                                    Text("Voice").font(.otCaption.weight(.semibold))
                                }
                                .foregroundStyle(recordMode == .voiceOnly ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(recordMode == .voiceOnly ? OT.reader : Color.clear, in: Capsule())
                            }
                        }
                        .padding(3)
                        .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        // Practice Display Mode Menu (Full / First letters / Hide my lines)
                        Menu {
                            Button { displayMode = .full; Haptics.tick() } label: {
                                Label("Full lines", systemImage: displayMode == .full ? "checkmark" : "")
                            }
                            Button { displayMode = .firstLetters; Haptics.tick() } label: {
                                Label("First letters", systemImage: displayMode == .firstLetters ? "checkmark" : "")
                            }
                            Button { displayMode = .hideMine; Haptics.tick() } label: {
                                Label("Hide my lines", systemImage: displayMode == .hideMine ? "checkmark" : "")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: displayMode == .firstLetters ? "character.textbox" : (displayMode == .hideMine ? "eye.slash" : "text.alignleft"))
                                    .font(.system(size: 13, weight: .semibold))
                                Text(displayMode.title)
                                    .font(.otCaption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        // Text Size Menu
                        Menu {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    prompterSize = 0
                                }
                                Haptics.tick()
                            } label: {
                                Label("Regular text (18pt)", systemImage: prompterSize == 0 ? "checkmark" : "")
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    prompterSize = 1
                                }
                                Haptics.tick()
                            } label: {
                                Label("Big text (26pt)", systemImage: prompterSize == 1 ? "checkmark" : "")
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    prompterSize = 2
                                }
                                Haptics.tick()
                            } label: {
                                Label("Huge text (38pt)", systemImage: prompterSize == 2 ? "checkmark" : "")
                            }
                        } label: {
                            Image(systemName: "textformat.size")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.top, 4)
                }

                if camera.state == .recording && recordMode == .camera {
                    HStack(spacing: 5) {
                        Capsule().fill(OT.prompterGold).frame(width: 3, height: 14)
                        Text("LOOK AT LENS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(OT.prompterGold)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Color.black.opacity(0.65), in: Capsule())
                }

                if recordMode == .voiceOnly {
                    VStack(spacing: 6) {
                        VoiceWaveformBars(isRecording: camera.state == .recording, level: camera.audioLevel)
                            .frame(height: 28)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(camera.state == .recording ? Color.red : OT.reader)
                                .frame(width: 7, height: 7)
                            Text(camera.state == .recording ? "RECORDING VOICE · LISTENING" : "VOICE REHEARSAL · NO CAMERA")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(camera.state == .recording ? OT.prompterGold : Color.white.opacity(0.75))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45), in: Capsule())
                    }
                    .padding(.top, 4)
                }

                if let lines = piece?.scene?.lines, !lines.isEmpty {
                    if camera.state == .recording || recordedTakeURL == nil {
                        SidesPrompterView(
                            lines: lines,
                            currentIndex: lineIndex,
                            spokenTranscript: follower.transcript,
                            prompterSize: prompterSize,
                            mirror: mirrorPrompter,
                            readerIsPlaying: false,
                            readerAudioMissing: false,
                            displayMode: displayMode,
                            hiddenGapWords: hiddenGapWords,
                            revealedLines: revealedLines,
                            onAdvance: {
                                advanceRehearsalLine()
                            },
                            onPrevious: {
                                autoAdvanceTask?.cancel()
                                autoAdvanceTask = nil
                                lineIndex = max(0, lineIndex - 1)
                                follower.reset()
                                Haptics.tick()
                                scheduleRehearsalAutoAdvance()
                            },
                            onToggleReveal: { id in
                                if revealedLines.contains(id) {
                                    revealedLines.remove(id)
                                } else {
                                    revealedLines.insert(id)
                                }
                                Haptics.tick()
                            },
                            onCycleSize: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    prompterSize = (prompterSize + 1) % 3
                                }
                                Haptics.tick()
                            }
                        )
                        .padding(.top, 6)
                    } else {
                        HStack(spacing: 8) {
                            Text(lines.indices.contains(lineIndex) ? lines[lineIndex].text : sceneTitle)
                                .font(.otFootnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            Text("\(lineIndex + 1) of \(lines.count) lines")
                                .font(.otCaption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(OT.prompterGold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                }

                Spacer()

                // Post-take review & next scene options
                if camera.state != .recording, let _ = recordedTakeURL {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: recordMode == .voiceOnly ? "waveform.circle.fill" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(recordMode == .voiceOnly ? OT.reader : OT.success)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(recordMode == .voiceOnly ? "Voice take" : "Take") \(takeNumber - 1) saved")
                                    .font(.otHeadline)
                                    .foregroundStyle(.white)
                                Text("\(formatElapsed(Double(recordedTakeDuration))) · \(sceneTitle)")
                                    .font(.otFootnote)
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            Spacer()

                            Button {
                                showPlayer = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: recordMode == .voiceOnly ? "waveform" : "play.fill")
                                        .font(.caption)
                                    Text(recordMode == .voiceOnly ? "Play voice" : "Watch take")
                                }
                                .font(.otFootnote.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 10))
                            .tint(.white)
                            .foregroundStyle(.black)
                        }

                        if recordMode == .voiceOnly {
                            Button { showVoiceReview = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isAnalyzingVoice ? "hourglass" : "text.alignleft")
                                    Text(isAnalyzingVoice ? "Checking your lines…" : "Review speech against script")
                                    Spacer()
                                    if !isAnalyzingVoice, !voiceReview.isEmpty {
                                        Text("\(voiceReview.filter { $0.mark != .matched && !$0.dismissed }.count) notes")
                                            .font(.otCaption.weight(.semibold))
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                }
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isAnalyzingVoice)
                        }

                        // Memory & lines learned evaluation
                        let myLines = piece?.scene?.lines.filter(\.isMine).count ?? piece?.linesTotal ?? 0
                        let rememberedCount = max(onYourOwnLines.count, displayMode == .full ? myLines : 0)
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .font(.subheadline)
                                .foregroundStyle(OT.prompterGold)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(displayMode == .full ? "Full prompt used (\(myLines) lines)" : "\(rememberedCount) of \(myLines) lines from memory")
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(displayMode == .full ? "Try 'First letters' or 'Hide mine' to test recall" : (rememberedCount == myLines ? "Perfect memory on this run!" : "Good practice! Re-run to lock lines in"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            Spacer()

                            if displayMode != .full && myLines > 0 {
                                let pct = Int((Double(rememberedCount) / Double(myLines)) * 100)
                                Text("\(pct)%")
                                    .font(.otFootnote.monospacedDigit().weight(.bold))
                                    .foregroundStyle(pct >= 80 ? OT.accent : OT.prompterGold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                        // Explicit lines learned toggle
                        let isAllLearned = (piece?.linesLearned ?? 0) >= myLines && myLines > 0
                        HStack {
                            Button {
                                if let p = piece {
                                    let nextLearned = isAllLearned ? 0 : myLines
                                    store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: nextLearned)
                                    Haptics.success()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isAllLearned ? "checkmark.circle.fill" : "circle")
                                        .font(.subheadline.weight(.semibold))
                                    Text(isAllLearned ? "Lines learned (\(myLines)/\(myLines))" : "Mark lines learned (\(myLines) lines)")
                                        .font(.otFootnote.weight(.semibold))
                                }
                                .foregroundStyle(isAllLearned ? OT.accent : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isAllLearned ? AnyShapeStyle(OT.accentSoft) : AnyShapeStyle(Color.white.opacity(0.12)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }

                        HStack(spacing: 10) {
                            if nextSceneAvailable {
                                Button {
                                    advanceToNextScene()
                                } label: {
                                    HStack(spacing: 5) {
                                        Text("Next scene")
                                        Image(systemName: "chevron.right")
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.roundedRectangle(radius: 12))
                                .tint(OT.accent)
                                .foregroundStyle(.white)
                            }

                            Button("Done") {
                                dismiss()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                            .tint(.white)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.bottom, 6)
                }

                if let lines = piece?.scene?.lines, lines.indices.contains(lineIndex), camera.state == .recording {
                    let cur = lines[lineIndex]
                    VoiceFollowingPill(
                        isListening: follower.isListening,
                        isActorLine: cur.isMine,
                        characterName: cur.character,
                        isFollowingVoice: true,
                        isReaderPlaying: false
                    )
                    .padding(.bottom, 2)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                if let lines = piece?.scene?.lines, !lines.isEmpty, camera.state == .recording {
                    HStack(spacing: 8) {
                        Button {
                            if lineIndex + 1 < lines.count { lineIndex += 1; Haptics.tick() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                                Text("Next line").font(.otFootnote.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                prompterSize = (prompterSize + 1) % 3
                            }
                            Haptics.tick()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "textformat.size").font(.caption)
                                Text(["Regular", "Big", "Huge"][prompterSize]).font(.otCaption.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        if recordMode == .camera {
                            Button {
                                camera.toggleExposureLock()
                                Haptics.tick()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: camera.isExposureLocked ? "lock.fill" : "lock.open")
                                        .font(.caption2)
                                    Text(camera.isExposureLocked ? "Locked" : "AE")
                                        .font(.otCaption.weight(.bold))
                                }
                                .foregroundStyle(camera.isExposureLocked ? OT.prompterGold : .white)
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }

                if recordMode == .voiceOnly {
                    HStack {
                        Spacer()
                        Button {
                            if camera.state == .recording {
                                Haptics.impact(.medium)
                                camera.stopRecording()
                            } else {
                                Haptics.impact(.heavy)
                                recordedTakeURL = nil
                                onYourOwnLines.removeAll()
                                camera.startRecording()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(camera.state == .recording ? Color.red.opacity(0.25) : Color.white.opacity(0.12))
                                    .frame(width: 78, height: 78)
                                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 2))

                                if camera.state == .recording {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(Color.red)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.bottom, 6)

                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                        Text("Voice rehearsal · records voice only, no camera")
                            .font(.otCaption.weight(.medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 8)
                } else {
                    RecordButton(isRecording: camera.state == .recording) {
                        if camera.state == .recording {
                            Haptics.impact(.medium)
                            camera.stopRecording()
                        } else {
                            Haptics.impact(.heavy)
                            recordedTakeURL = nil
                            onYourOwnLines.removeAll()
                            camera.startRecording()
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, OT.gutter)
        }
        .preferredColorScheme(.dark)
        .keepScreenAwake()
        .task {
            if await CameraController.requestAccess() {
                camera.configure()
            }
            if await SpeechFollower.requestAccess() {
                follower.start()
            }
            scheduleRehearsalAutoAdvance()
        }
        .task(id: displayMode) {
            guard displayMode == .gaps, let lines = piece?.scene?.lines else { return }
            var selections: [ScriptLine.ID: Set<Int>] = [:]
            for line in lines where line.isMine && !line.isSilentReactionCue {
                selections[line.id] = await RecallGapSelectionStore.hiddenWordIndices(for: line.text)
            }
            hiddenGapWords = selections
        }
        .onChange(of: follower.transcript) { _, transcript in
            guard let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
            let line = lines[lineIndex]
            let required = SpokenLineMatcher.requiredMatches(for: line.text)
            if required > 0 && SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: transcript).count >= required {
                let curID = line.id
                if line.isMine && !revealedLines.contains(curID) {
                    onYourOwnLines.insert(curID)
                }
                advanceRehearsalLine()
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if (cmd?.word == "action" || cmd?.word == "now"), camera.state == .ready {
                Haptics.impact(.heavy)
                recordedTakeURL = nil
                onYourOwnLines.removeAll()
                camera.startRecording()
                scheduleRehearsalAutoAdvance()
            }
            if cmd?.word == "cut", camera.state == .recording {
                Haptics.impact(.medium)
                camera.stopRecording()
            }
        }
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            if camera.state == .recording {
                Haptics.impact(.medium)
                camera.stopRecording()
            } else {
                Haptics.impact(.heavy)
                recordedTakeURL = nil
                onYourOwnLines.removeAll()
                camera.startRecording()
                scheduleRehearsalAutoAdvance()
            }
        }
        .onChange(of: camera.state) { _, newState in
            guard newState == .ready, let url = camera.lastRecording, let p = piece else { return }
            let number = p.takesRecorded + 1
            recordedTakeDuration = Int(camera.elapsed)
            if let saved = MediaStore.persist(url, as: "take-\(number)-\(UUID().uuidString).mov", in: "practice-\(p.id.uuidString)") {
                store.incrementPracticeTakes(for: p.id)
                let linesCount = p.scene?.lines.filter(\.isMine).count ?? p.linesTotal
                let learned = max(onYourOwnLines.count, (lineIndex + 1 >= (p.scene?.lines.count ?? 0) && displayMode == .full) ? linesCount : 0)
                if learned > 0 {
                    store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: learned)
                }
                recordedTakeURL = saved
                if recordMode == .voiceOnly, let lines = p.scene?.lines {
                    isAnalyzingVoice = true
                    voiceReviewError = nil
                    voiceReview = []
                    Task { @MainActor in
                        defer { isAnalyzingVoice = false }
                        do {
                            voiceReview = try await VoicePracticeReviewAnalyzer.analyze(url: saved, lines: lines)
                        } catch {
                            voiceReviewError = "On-device speech recognition wasn't available or couldn't detect enough speech. Your recording stays on this iPhone; play it and review the lines yourself."
                        }
                    }
                }
                Haptics.success()
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = recordedTakeURL {
                PracticeVideoPlayerSheet(url: url, isVoiceTake: recordMode == .voiceOnly, sceneTitle: sceneTitle)
            }
        }
        .sheet(isPresented: $showVoiceReview) {
            VoicePracticeReviewView(recordingURL: recordedTakeURL, reviews: $voiceReview,
                                    isAnalyzing: isAnalyzingVoice, errorMessage: voiceReviewError)
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
            autoAdvanceTask = nil
            camera.stop()
            follower.stop()
        }
    }

    private func advanceRehearsalLine() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        follower.reset()
        guard let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
        if lineIndex + 1 < lines.count {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                lineIndex += 1
            }
            Haptics.tick()
            scheduleRehearsalAutoAdvance()
        }
    }

    private func scheduleRehearsalAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        guard let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        let hasSpokenWords = !line.text.split(separator: " ").map({ SpokenLineMatcher.cleanWord($0) }).filter({ !$0.isEmpty }).isEmpty

        // Auto-advance reader lines or non-dialogue cues (silence/punctuation)
        guard !line.isMine || !hasSpokenWords || line.isSilentReactionCue else { return }

        let wordCount = max(1, line.text.split(separator: " ").count)
        let delay: Double = (!hasSpokenWords || line.isSilentReactionCue) ? 1.6 : max(2.0, Double(wordCount) * 0.38 + 0.8)

        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            advanceRehearsalLine()
        }
    }
}

struct VoiceWaveformBars: View {
    let isRecording: Bool
    let level: Float

    // 10 bar heights from Figma node 1109:10274: 6, 14, 22, 10, 26, 18, 8, 20, 12, 4
    private let baseHeights: [CGFloat] = [6, 14, 22, 10, 26, 18, 8, 20, 12, 4]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<baseHeights.count, id: \.self) { i in
                let factor: CGFloat = isRecording ? max(0.4, CGFloat(sin(Double(i) * 0.9 + Double(level) * 8) + 1.2)) : 0.85
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isRecording ? OT.reader : Color.white.opacity(0.45))
                    .frame(width: 3, height: max(4, min(32, baseHeights[i] * factor)))
                    .animation(.easeInOut(duration: 0.12), value: level)
            }
        }
    }
}

private struct PracticeVideoPlayerSheet: View {
    let url: URL
    var isVoiceTake: Bool = false
    var sceneTitle: String = "Take"
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: isVoiceTake ? "Voice rehearsal take" : "Preview take", backLabel: "Close", onDark: true, onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(Color.black)

            if isVoiceTake {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.06, blue: 0.12), Color(red: 0.04, green: 0.03, blue: 0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 96))
                            .foregroundStyle(OT.reader)

                        VStack(spacing: 6) {
                            Text(sceneTitle)
                                .font(.otTitle)
                                .foregroundStyle(.white)
                            Text("Voice rehearsal take")
                                .font(.otFootnote)
                                .foregroundStyle(.white.opacity(0.65))
                        }

                        VideoPlayer(player: player ?? AVPlayer(url: url))
                            .frame(height: 60)
                            .padding(.horizontal, OT.gutter)

                        Spacer()
                    }
                }
            } else {
                VideoPlayer(player: player ?? AVPlayer(url: url))
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
