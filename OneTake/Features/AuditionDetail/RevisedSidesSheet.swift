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
    @State private var showScriptEditor = false
    @State private var selectedRole = ""

    private var audition: Audition? {
        store.audition(auditionID)
    }

    private var effectiveRole: String {
        let trimmed = selectedRole.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return audition?.role ?? ""
    }

    private var detectedCharacters: [String] {
        ScriptParser.extractCharacters(from: text)
    }

    private var roleNeedsSelection: Bool {
        guard !detectedCharacters.isEmpty else { return false }
        let role = effectiveRole.trimmingCharacters(in: .whitespacesAndNewlines)
        if role.isEmpty || role.caseInsensitiveCompare("Role") == .orderedSame { return true }
        return !detectedCharacters.contains { $0.caseInsensitiveCompare(role) == .orderedSame }
    }

    private var isNewSides: Bool {
        audition?.scenes.isEmpty ?? true
    }

    private var parsed: [ScriptScene] {
        ScriptParser.parseScenes(from: text, myRole: effectiveRole)
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
        let role = effectiveRole
        NavigationStack {
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

                    // Script Text Area Card + Dedicated Full-Screen Editor
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            Text(isNewSides ? "SCRIPT TEXT" : "REVISED SIDES TEXT")
                                .font(.otEyebrow)
                                .foregroundStyle(OT.labelSecondary)
                            Spacer()
                            Button {
                                showScriptEditor = true
                            } label: {
                                Label(text.isEmpty ? "Type script" : "Edit script", systemImage: "square.and.pencil")
                                    .font(.otCaption.weight(.semibold))
                            }
                            .buttonStyle(.otCompact)
                            if !text.isEmpty {
                                Button("Clear") {
                                    withAnimation(OTMotion.snappy) {
                                        text = ""
                                        editableScenes = []
                                    }
                                }
                                .font(.otCaption.weight(.semibold))
                                .foregroundStyle(OT.danger)
                            }
                        }

                        Button {
                            showScriptEditor = true
                        } label: {
                            HStack(alignment: .top, spacing: OTSpace.m) {
                                Image(systemName: text.isEmpty ? "text.badge.plus" : "doc.text")
                                    .font(.otIcon(.m))
                                    .foregroundStyle(OT.accent)
                                    .padding(.top, OTSpace.xxs)

                                VStack(alignment: .leading, spacing: OTSpace.xs) {
                                    Text(text.isEmpty ? "Open script editor" : "Tap to edit script in full screen")
                                        .font(.otSubhead.weight(.semibold))
                                        .foregroundStyle(OT.labelPrimary)
                                    Text(text.isEmpty
                                         ? "Write or paste sides in a clean, distraction-free editor."
                                         : text.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelSecondary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(OT.labelTertiary)
                            }
                            .padding(OTSpace.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .otCard(.grouped, padding: nil)
                        }
                        .buttonStyle(OTPressStyle(.card))
                    }

                    if !text.isEmpty {
                        if !detectedCharacters.isEmpty {
                            roleSelectionCard
                        }
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
            .otBottomBar {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(isNewSides ? "Add sides" : "Save changes") {
                        commitSides()
                    }
                    .buttonStyle(.otPrimary)
                    .disabled(activeScenes.isEmpty)
                }
            }
            .otCanvas()
            .navigationTitle(isNewSides ? "Add sides" : "Edit sides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if selectedRole.isEmpty, let initialRole = audition?.role, initialRole != "Role" {
                selectedRole = initialRole
            }
            if !isNewSides, let existing = audition?.scriptText, !existing.isEmpty {
                text = existing
                editableScenes = audition?.scenes ?? ScriptParser.parseScenes(from: existing, myRole: effectiveRole)
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
            photoItems = []
            reading = true
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let raw = UIImage(data: data) {
                        images.append(NoticeOCR.normalizedScanImage(raw, maxDimension: 2048))
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
                    editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: effectiveRole)
                    reading = false
                    Haptics.success()
                }
            }
        }
        .interactiveDismissDisabled(!text.isEmpty)
        .sheet(isPresented: $showScriptEditor) {
            ScriptTextEditSheet(
                title: isNewSides ? "Edit script text" : "Edit revised sides",
                roleName: role,
                initialText: text
            ) { updated in
                let cleaned = ScriptParser.cleanPastedText(updated)
                text = cleaned
                editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: effectiveRole)
            }
        }
    }

    @ViewBuilder
    private var roleSelectionCard: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            HStack {
                Label("Your role in these sides", systemImage: "person.fill")
                    .font(.otHeadline)
                    .foregroundStyle(OT.labelPrimary)
                Spacer()
                if roleNeedsSelection {
                    Text("Select role")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.due)
                }
            }
            Text(roleNeedsSelection
                 ? "Tap the character you’re reading for so your lines and reader cues split properly."
                 : "Reading as \(effectiveRole). Tap another character to switch.")
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OTSpace.s) {
                    ForEach(detectedCharacters, id: \.self) { character in
                        let isSelected = character.caseInsensitiveCompare(effectiveRole) == .orderedSame
                        Button {
                            selectedRole = character
                            editableScenes = ScriptParser.parseScenes(from: text, myRole: character)
                            Haptics.tick()
                        } label: {
                            HStack(spacing: OTSpace.xs) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.otCaption.weight(.bold))
                                }
                                Text(character)
                                    .lineLimit(1)
                            }
                            .font(.otCaption.weight(isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? OT.labelOnAccent : OT.accent)
                            .padding(.horizontal, OTSpace.m)
                            .padding(.vertical, OTSpace.xs)
                            .background(
                                isSelected ? AnyShapeStyle(OT.accent) : AnyShapeStyle(OT.accentSoft),
                                in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(OTSpace.m)
        .otCard(.grouped, padding: nil)
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                .strokeBorder(roleNeedsSelection ? OT.due.opacity(0.6) : Color.clear, lineWidth: 1) // ot-lint:allow
        )
    }

    private func commitSides() {
        let scenesToSave = activeScenes
        let roleToSave = effectiveRole
        store.replaceSides(of: auditionID, with: scenesToSave, sourceText: text, role: roleToSave)
        let shouldRecordReader = readerAudioPlan == .recordNow
        let firstReaderScene = scenesToSave.indices.first(where: { !scenesToSave[$0].lines.filter({ !$0.isMine }).isEmpty })
        dismiss()
        if shouldRecordReader, let firstScene = firstReaderScene {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                store.push(.reader(auditionID, sceneIndex: firstScene))
            }
        }
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
