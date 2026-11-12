import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

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
            OTNavHeader(title: "Practise a scene", backLabel: "Back", onBack: { store.pop() })
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.xs)

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
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                                    .font(.system(size: 11, weight: .bold)) // ot-lint:allow
                                Text("Paste")
                                    .font(.otCaption.weight(.bold))
                            }
                            .padding(.horizontal, OTSpace.m)
                            .padding(.vertical, 6) // ot-lint:allow
                            .background(OT.accent, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Scene name", text: $sceneTitle)
                    TextField("Your character", text: $character)

                    HStack(spacing: OTSpace.l) {
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
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelTertiary)
                                .padding(.top, 10) // ot-lint:allow
                                .padding(.leading, 12) // ot-lint:allow
                                .allowsHitTesting(false)
                        }
                        ScriptTextEditor(text: $sidesText)
                            .frame(minHeight: 150) // ot-lint:allow
                            .onChange(of: sidesText) { _, newSides in
                                autoFillFromSides(newSides)
                            }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.otFootnote).foregroundStyle(OT.danger)
                    }

                    Button("Create practice scene") { createStandaloneScene() }
                        .buttonStyle(.otPrimary)
                        .disabled(character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sidesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showSample {
                    Section("Sample scene") {
                        Button {
                            store.pop()
                            store.push(.practiceSample)
                        } label: {
                            OTIconRow(symbol: "play.rectangle", title: "A late goodbye", detail: "Try the sample scene")
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
                                    OTIconRow(symbol: "theatermasks", title: scene.title, detail: "\(a.project) · \(a.role)")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
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
