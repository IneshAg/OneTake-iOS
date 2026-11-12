import SwiftUI
import PhotosUI
import OneTakeUI

struct AddDraftSidesSheet: View {
    @Binding var draft: NoticeParser.Draft
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var editableScenes: [ScriptScene] = []
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var reading = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var sidesParseTask: Task<Void, Never>?
    @State private var importError = false
    @State private var emptyClipboardAlert = false

    private var activeScenes: [ScriptScene] {
        editableScenes
    }

    var body: some View {
        OTScreen(
            title: draft.hasSides ? "Replace sides" : "Add sides",
            backLabel: "Cancel",
            onBack: { dismiss() },
            trailing: {
                Button(draft.hasSides ? "Replace" : "Add") {
                    commitSides()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        ) {
            VStack(spacing: OTSpace.l) {
                if let sidesLink = draft.sidesLink, !sidesLink.isEmpty {
                    sidesLinkCard(sidesLink)
                }

                // 4 Action Buttons Grid (replaces long text rows)
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
                        openScanner()
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
                    .otCard(.grouped)
                }

                // Script Text Area Card (Clean, centered, beautifully bordered)
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    HStack {
                        Text("SCRIPT TEXT")
                            .font(.otCaption.weight(.semibold))
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
                            Text("Or type/paste sides directly here...\nCues should be in CAPS (e.g. MAYA) or “Maya: dialogue”.")
                                .font(.otCallout)
                                .foregroundStyle(OT.labelTertiary)
                                .padding(.horizontal, OTSpace.m)
                                .padding(.vertical, OTSpace.m)
                                .allowsHitTesting(false)
                        }

                        ScriptTextEditor(text: $text)
                            .frame(minHeight: 140, maxHeight: 220) // ot-lint:allow
                            .onChange(of: text) { _, newText in
                                sidesParseTask?.cancel()
                                let role = draft.role
                                sidesParseTask = Task {
                                    try? await Task.sleep(for: .milliseconds(220))
                                    guard !Task.isCancelled else { return }
                                    let scenes = await Task.detached(priority: .userInitiated) {
                                        ScriptParser.parseScenes(from: newText, myRole: role)
                                    }.value
                                    guard !Task.isCancelled else { return }
                                    editableScenes = scenes
                                }
                            }
                    }
                    .otCard(.grouped)
                }

                // Detected from sides section
                if !text.isEmpty {
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            Text("DETECTED SIDES")
                                .font(.otCaption.weight(.semibold))
                                .foregroundStyle(OT.labelSecondary)
                            Spacer()
                            Text("Tap speaker or text to edit")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelTertiary)
                        }

                        if !activeScenes.isEmpty {
                            HStack(spacing: OTSpace.s) {
                                SidesChip(title: "Scenes", value: "\(activeScenes.count)", isAccent: false)
                                SidesChip(title: draft.role.isEmpty ? "Your role" : draft.role, value: "\(activeScenes.flatMap(\.lines).filter(\.isMine).count)", isAccent: true)
                                let readerLines = activeScenes.flatMap(\.lines).filter { !$0.isMine }
                                if !readerLines.isEmpty {
                                    let readerName = readerLines.first?.character.capitalized ?? "Reader"
                                    SidesChip(title: "Reader (\(readerName))", value: "\(readerLines.count)", isAccent: false)
                                }
                                SidesChip(title: "Total lines", value: "\(activeScenes.flatMap(\.lines).count)", isAccent: false)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .otCard(.grouped)
                        }
                    }
                }
            }
        }
        .otBottomBar {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(draft.hasSides ? "Replace sides" : "Add sides") {
                    commitSides()
                }
                .buttonStyle(.ot(.primary))
            }
        }
        .onAppear {
            if draft.hasSides {
                text = draft.sourceText
                if let custom = draft.customScenes, !custom.isEmpty {
                    editableScenes = custom
                } else {
                    editableScenes = ScriptParser.parseScenes(from: draft.sourceText, myRole: draft.role)
                }
            } else {
                text = ""
                editableScenes = []
            }
        }
        .onDisappear { sidesParseTask?.cancel() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf, .text]) { result in
            switch result {
            case .success(let url):
                reading = true
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer {
                        resolved.cleanup()
                        reading = false
                    }
                    if let doc = await NoticeOCR.extractDocument(fromFileAt: resolved.url) {
                        await MainActor.run {
                            text = doc.fullText
                            editableScenes = ScriptParser.parseScenes(from: doc.fullText, myRole: draft.role)
                            Haptics.success()
                        }
                    } else if let parsedText = await NoticeOCR.extractText(fromFileAt: resolved.url) {
                        await MainActor.run {
                            text = parsedText
                            editableScenes = ScriptParser.parseScenes(from: parsedText, myRole: draft.role)
                            Haptics.success()
                        }
                    } else {
                        await MainActor.run { importError = true }
                    }
                }
            case .failure:
                importError = true
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                reading = true
                Task {
                    let pageTexts = await NoticeOCR.recognizePages(in: pages)
                    let combined = pageTexts.joined(separator: "\n\n")
                    await MainActor.run {
                        reading = false
                        text = combined
                        editableScenes = ScriptParser.parseScenes(from: combined, myRole: draft.role)
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
                var pages: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        pages.append(img)
                    }
                }
                let pageTexts = await NoticeOCR.recognizePages(in: pages)
                let combined = pageTexts.joined(separator: "\n\n")
                await MainActor.run {
                    reading = false
                    photoItems = []
                    text = combined
                    editableScenes = ScriptParser.parseScenes(from: combined, myRole: draft.role)
                    Haptics.success()
                }
            }
        }
        .alert("Scanning isn't available", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs the iPhone camera. Use Import PDF or Photos instead.")
        }
        .alert("Couldn't read this file", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try choosing another PDF or text file, or paste the script text.")
        }
        .alert("Nothing to paste", isPresented: $emptyClipboardAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy script text in Mail, Safari, or another app first.")
        }
    }

    private func pasteFromClipboard() {
        if let s = UIPasteboard.general.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = s
            editableScenes = ScriptParser.parseScenes(from: s, myRole: draft.role)
            Haptics.success()
        } else {
            emptyClipboardAlert = true
            Haptics.warning()
        }
    }

    private func commitSides() {
        let cleaned = ScriptParser.cleanPastedText(text)
        draft.sourceText = cleaned
        draft.customScenes = editableScenes.isEmpty ? ScriptParser.parseScenes(from: cleaned, myRole: draft.role) : editableScenes
        draft.scenes = draft.customScenes?.count ?? 0
        Haptics.success()
        dismiss()
    }

    private func openScanner() {
        #if targetEnvironment(simulator)
        scannerUnavailable = true
        #else
        showScanner = true
        #endif
    }

    private func sidesLinkCard(_ sidesLink: String) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            HStack(spacing: OTSpace.s) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(OT.accent)
                Text("Script sides link detected")
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
            }
            Text("Open the link to download the PDF or copy script text, then import or paste it below.")
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
            if let url = URL(string: sidesLink.hasPrefix("http") ? sidesLink : "https://\(sidesLink)") {
                Link(destination: url) {
                    HStack(spacing: OTSpace.xs) {
                        Image(systemName: "safari")
                        Text("Open sides in browser")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }
                .padding(.top, OTSpace.xxs)
            }
        }
        .otCard(.grouped)
    }
}
