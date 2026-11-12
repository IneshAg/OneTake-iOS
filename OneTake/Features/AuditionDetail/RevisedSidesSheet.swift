import SwiftUI
import PhotosUI
import VisionKit

// MARK: - Revised sides

/// Add sides to an audition without sides, or swap in revised sides from casting:
/// paste them, import a PDF/text file, or scan pages on device.
struct RevisedSidesSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var editableScenes: [ScriptScene] = []
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var reading = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importError = false
    @State private var emptyClipboardAlert = false

    private var audition: Audition? {
        store.audition(auditionID)
    }

    private var isNewSides: Bool {
        audition?.scenes.isEmpty ?? true
    }

    private var parsed: [ScriptScene] {
        let role = audition?.role ?? ""
        return ScriptParser.parseScenes(from: text, myRole: role)
    }

    private var activeScenes: [ScriptScene] {
        editableScenes.isEmpty ? parsed : editableScenes
    }

    @State private var readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .recordNow

    private var readerLines: [ScriptLine] {
        activeScenes.flatMap(\.lines).filter { !$0.isMine }
    }

    private var detectedReaderName: String {
        readerLines.first?.character.capitalized ?? "Reader"
    }

    var body: some View {
        let role = audition?.role ?? ""
        VStack(spacing: 0) {
            OTSheetHeader(
                title: isNewSides ? "Add sides" : "Edit sides",
                leading: "Cancel",
                trailing: isNewSides ? "Add" : "Save changes",
                onLeading: { dismiss() },
                onTrailing: {
                    store.replaceSides(of: auditionID, with: activeScenes, sourceText: text)
                    dismiss()
                    if readerAudioPlan == .recordNow,
                       let firstScene = activeScenes.indices.first(where: { !activeScenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
                        store.push(.reader(auditionID, sceneIndex: firstScene))
                    }
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
                            pasteFromClipboard(role: role)
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
                            Text(isNewSides ? "SCRIPT TEXT" : "REVISED SIDES TEXT")
                                .font(.otEyebrow)
                                .foregroundStyle(OT.labelSecondary)
                            Spacer()
                            if !text.isEmpty {
                                Button("Clear") {
                                    withAnimation {
                                        text = ""
                                        editableScenes = []
                                    }
                                }
                                .font(.otCaption.weight(.semibold))
                                .foregroundStyle(OT.danger)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(isNewSides ? "Or paste or type sides here...\nCues in CAPS (e.g. MAYA) or “Maya: dialogue”." : "Paste the new sides here...")
                                    .font(.otCallout)
                                    .foregroundStyle(OT.labelTertiary)
                                    .padding(.horizontal, OTSpace.m)
                                    .padding(.vertical, OTSpace.s)
                                    .allowsHitTesting(false)
                            }

                            ScriptTextEditor(text: $text)
                                .frame(minHeight: 140, maxHeight: 220) // ot-lint:allow
                                .onChange(of: text) { _, newText in
                                    editableScenes = ScriptParser.parseScenes(from: newText, myRole: role)
                                }
                        }
                        .otCard(.inset)
                    }

                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            HStack {
                                Text("DETECTED SIDES")
                                    .font(.otEyebrow)
                                    .foregroundStyle(OT.labelSecondary)
                                Spacer()
                                Text("Tap speaker or text to edit")
                                    .font(.system(size: 11)) // ot-lint:allow
                                    .foregroundStyle(OT.labelTertiary)
                            }

                            if !activeScenes.isEmpty {
                                HStack(spacing: OTSpace.s) {
                                    SidesChip(title: "Scenes", value: "\(activeScenes.count)", isAccent: false)
                                    SidesChip(title: role.isEmpty ? "Your role" : role, value: "\(activeScenes.flatMap(\.lines).filter(\.isMine).count)", isAccent: true)
                                    if !readerLines.isEmpty {
                                        SidesChip(title: "Reader (\(detectedReaderName))", value: "\(readerLines.count)", isAccent: false)
                                    }
                                    SidesChip(title: "Total lines", value: "\(activeScenes.flatMap(\.lines).count)", isAccent: false)
                                }

                                if !readerLines.isEmpty {
                                    VStack(alignment: .leading, spacing: OTSpace.s) {
                                        HStack {
                                            Label("Reader audio", systemImage: "person.wave.2.fill")
                                                .font(.otHeadline)
                                                .foregroundStyle(OT.labelPrimary)
                                            Spacer()
                                            HStack(spacing: 4) { // ot-lint:allow
                                                Text("Reader:").font(.otCaption.weight(.bold)).foregroundStyle(OT.reader)
                                                Text(detectedReaderName).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.reader)
                                            }
                                        }
                                        Text("Record \(detectedReaderName)’s \(readerLines.count) cue\(readerLines.count == 1 ? "" : "s") in your voice so it plays under your takes.")
                                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                                        Picker("Reader audio", selection: $readerAudioPlan) {
                                            Text("Record cues now").tag(AddAuditionFlow.ReaderAudioPlan.recordNow)
                                            Text("Add later").tag(AddAuditionFlow.ReaderAudioPlan.later)
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                    .padding(OTSpace.m)
                                    .otCard(.inset)
                                }

                                ScriptReviewAndEditView(scenes: $editableScenes)
                            } else {
                                HStack(spacing: OTSpace.s) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(OT.labelTertiary)
                                    Text("No character lines recognised yet. Cues should be in CAPS (e.g. “MAYA”) or “Maya: dialogue”.")
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
                Button(isNewSides ? "Add sides" : "Save changes") {
                    store.replaceSides(of: auditionID, with: activeScenes, sourceText: text)
                    dismiss()
                }
                .buttonStyle(.otPrimary)
                .disabled(activeScenes.isEmpty)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !isNewSides, let existing = audition?.scriptText, !existing.isEmpty {
                text = existing
                editableScenes = audition?.scenes ?? ScriptParser.parseScenes(from: existing, myRole: role)
            }
        }
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
                            let cleaned = ScriptParser.cleanPastedText(extracted)
                            text = cleaned
                            editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
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
                        let cleaned = ScriptParser.cleanPastedText(recognized)
                        text = cleaned
                        editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
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
                       let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                guard !images.isEmpty else {
                    await MainActor.run { reading = false }
                    return
                }
                let recognized = await NoticeOCR.recognizeText(in: images)
                await MainActor.run {
                    let cleaned = ScriptParser.cleanPastedText(recognized)
                    text = cleaned
                    editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
                    reading = false
                    photoItems = []
                    Haptics.success()
                }
            }
        }
        .interactiveDismissDisabled(!text.isEmpty)
    }

    private func pasteFromClipboard(role: String) {
        let pasted = UIPasteboard.general.string ?? ""
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = ScriptParser.cleanPastedText(trimmed)
        if !cleaned.isEmpty {
            text = cleaned
            editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
            Haptics.success()
        } else {
            emptyClipboardAlert = true
            Haptics.warning()
        }
    }
}
