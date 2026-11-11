import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import UserNotifications
import PDFKit

/// 06 Add an audition capture sheet
struct AddAuditionFlow: View {
    enum ReaderAudioPlan: Hashable { case recordNow, later }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingReviewImage: UIImage?
    @State private var showFileImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var unreadableNoticeError = false
    @State private var emptyClipboardAlert = false
    /// Parsed draft pending the actor's review — shown in OCRReviewSheet before being committed.
    @State private var pendingReviewDraft: NoticeParser.Draft? = nil

    var body: some View {
        capture
            .presentationDetents([.height(315)])
            .presentationDragIndicator(.visible)
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { pages in
                    showScanner = false
                    guard !pages.isEmpty else { return }
                    Task {
                        let pageTexts = await NoticeOCR.recognizePages(in: pages)
                        let text = pageTexts.joined(separator: "\n\n")
                        if !NoticeOCR.looksReadable(text) {
                            await MainActor.run { unreadableNoticeError = true }
                        } else {
                            let draft = await NoticeParser.parseAsync(text, pages: pageTexts, sourceDocuments: [AuditionSource(name: "Scanned notice", kind: .castingNotice, pageCount: pageTexts.count)])
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await MainActor.run {
                                pendingReviewImage = pages.first
                                pendingReviewDraft = draft
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }
            // OCR Review sheet — shown after every scan/photo/file import so the actor can
            // verify parsed fields before they are committed to the audition draft.
            .sheet(item: $pendingReviewDraft) { draft in
                OCRReviewSheet(draft: draft, sourcePreview: pendingReviewImage) { confirmedDraft, readerPlan in
                    pendingReviewDraft = nil
                    pendingReviewImage = nil
                    if confirmedDraft.missingRequiredDetails.isEmpty {
                        store.commitAuditionDraft(confirmedDraft, readerAudioPlan: readerPlan)
                    } else {
                        store.startAuditionDraft(confirmedDraft)
                    }
                } onDiscard: {
                    pendingReviewDraft = nil
                    pendingReviewImage = nil
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
                switch result {
                case .success(let url):
                    pendingReviewImage = nil
                    let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                    let pdfPreview = resolved.url.pathExtension.lowercased() == "pdf"
                        ? PDFDocument(url: resolved.url)?.page(at: 0)?.thumbnail(of: CGSize(width: 1200, height: 1600), for: .mediaBox)
                        : nil
                    Task {
                        defer { resolved.cleanup() }
                        if let doc = await NoticeOCR.extractDocument(fromFileAt: resolved.url) {
                            let draft = await NoticeParser.parseAsync(doc.fullText, pages: doc.pages, sourceDocuments: [AuditionSource(name: resolved.url.lastPathComponent, kind: .castingNotice, url: resolved.url, pageCount: doc.pageCount)])
                            await MainActor.run {
                                pendingReviewImage = pdfPreview
                                pendingReviewDraft = draft
                            }
                        } else if let text = await NoticeOCR.extractText(fromFileAt: resolved.url), NoticeOCR.looksReadable(text) {
                            let draft = await NoticeParser.parseAsync(text, sourceDocuments: [AuditionSource(name: resolved.url.lastPathComponent, kind: .castingNotice, url: resolved.url, pageCount: 1)])
                            await MainActor.run {
                                pendingReviewImage = pdfPreview
                                pendingReviewDraft = draft
                            }
                        } else {
                            await MainActor.run { unreadableNoticeError = true }
                        }
                    }
                case .failure:
                    unreadableNoticeError = true
                }
            }
            .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Document scanning needs the iPhone camera. Use Photo or File instead.")
            }
            .alert("We couldn't read this notice", isPresented: $unreadableNoticeError) {
                Button("Type details") { store.startAuditionDraft(NoticeParser.Draft.blank) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("No readable text was found — it may be blurry or very small print. You can type the details instead.")
            }
            .alert("Clipboard is empty", isPresented: $emptyClipboardAlert) {
                Button("Type details manually") { store.startAuditionDraft(NoticeParser.Draft.blank) }
                Button("OK", role: .cancel) {}
            } message: {
                Text("No text was found on your clipboard. Copy text from your email, message, or sides first, then tap Paste.")
            }
            .task { await readSharedNotice() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                pendingReviewImage = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        await MainActor.run { unreadableNoticeError = true }
                        return
                    }
                    let text = await NoticeOCR.recognizeText(in: [image])
                    if !NoticeOCR.looksReadable(text) {
                        await MainActor.run { unreadableNoticeError = true }
                    } else {
                        let draft = await NoticeParser.parseAsync(text, pages: [text])
                        await MainActor.run {
                            pendingReviewImage = image
                            pendingReviewDraft = draft
                        }
                    }
                }
            }
    }

    private func openScanner() {
        if VNDocumentCameraViewController.isSupported { showScanner = true } else { scannerUnavailable = true }
    }

    private func readSharedNotice() async {
        guard let item = store.incomingShare else { return }
        store.incomingShare = nil
        var parts: [String] = []
        var pageTexts: [String] = []
        var sourceDocuments: [AuditionSource] = []
        if let text = item.text, !text.isEmpty {
            parts.append(text)
            pageTexts.append(text)
            sourceDocuments.append(AuditionSource(name: "Shared text", kind: .castingNotice, pageNumber: pageTexts.count, pageCount: 1))
        }
        for pdfURL in item.pdfs {
            if let document = await NoticeOCR.extractDocument(fromFileAt: pdfURL) {
                parts.append(document.fullText)
                let firstPage = pageTexts.count + 1
                pageTexts.append(contentsOf: document.pages)
                sourceDocuments.append(AuditionSource(name: pdfURL.lastPathComponent, kind: .castingNotice, url: pdfURL, pageNumber: firstPage, pageCount: document.pageCount))
            } else if let extracted = await NoticeOCR.extractText(fromFileAt: pdfURL) {
                parts.append(extracted)
                pageTexts.append(extracted)
                sourceDocuments.append(AuditionSource(name: pdfURL.lastPathComponent, kind: .castingNotice, url: pdfURL, pageNumber: pageTexts.count, pageCount: 1))
            }
        }
        let images = item.images.compactMap { UIImage(contentsOfFile: $0.path) }
        if !images.isEmpty {
            let pages = await NoticeOCR.recognizePages(in: images)
            let firstPage = pageTexts.count + 1
            pageTexts.append(contentsOf: pages)
            parts.append(pages.joined(separator: "\n\n"))
            sourceDocuments.append(AuditionSource(name: "Shared images", kind: .castingNotice, pageNumber: firstPage, pageCount: pages.count))
        }
        ShareInbox.remove(item)
        let text = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !NoticeOCR.looksReadable(text) {
            await MainActor.run { unreadableNoticeError = true }
        } else {
            // Route through OCR Review sheet so the actor can verify what was read
            // from the shared notice before it is committed to the audition draft.
            let draft = await NoticeParser.parseAsync(text, pages: pageTexts, sourceDocuments: sourceDocuments)
            await MainActor.run {
                pendingReviewImage = images.first
                pendingReviewDraft = draft
            }
        }
    }

    private func handlePasteNotice(providedText: String? = nil) {
        let raw = providedText ?? UIPasteboard.general.string ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emptyClipboardAlert = true
            Haptics.tick()
            return
        }
        Haptics.success()
        let cleaned = ScriptParser.cleanPastedText(trimmed)
        Task {
            let draft = await NoticeParser.parseAsync(cleaned)
            await MainActor.run {
                pendingReviewDraft = draft
            }
        }
    }

    private var capture: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Add an audition").font(.otTitle)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }

                Button {
                    handlePasteNotice()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(OT.accent)
                            .frame(width: 40, height: 40)
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Copied notice or sides?")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text("Tap to paste breakdown, email, or sides")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.doc.on.clipboard")
                                .font(.system(size: 11, weight: .bold))
                            Text("Paste")
                                .font(.otCaption.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(OT.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OT.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                SectionLabel(text: "Or bring in notice or sides")
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) { way("photo", "Photo") }
                    Button { openScanner() } label: { way("doc.viewfinder", "Scan") }
                    Button { showFileImporter = true } label: { way("folder", "File") }
                    Button { store.startAuditionDraft(NoticeParser.Draft.blank) } label: { way("keyboard", "Type it") }
                }
                .buttonStyle(.plain)

                Label("Faster: in Mail or WhatsApp, Share → OneTake", systemImage: "square.and.arrow.up")
                    .font(.otFootnote).foregroundStyle(OT.accent)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func way(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(OT.labelPrimary)
                .frame(width: 52, height: 52).background(OT.fillField, in: Circle())
            Text(title).font(.otFootnote).foregroundStyle(OT.labelSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - OCR Review Sheet

/// Shown after every scan, photo import, file import, and share-sheet import so the actor
/// can verify what OneTake read before it is committed to an audition draft.
/// The actor can correct individual fields inline; tapping "Use this" proceeds.
/// Interactive autofill keyboard toolbar bar that renders suggestions dynamically
/// above the software keyboard when the user is editing an audition field.
struct KeyboardAutofillBar: View {
    let suggestions: [String]
    let onSelect: (String) -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions.prefix(6), id: \.self) { item in
                            Button {
                                Haptics.tick()
                                onSelect(item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(OT.accent)
                                    Text(item)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(OT.labelPrimary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                                .overlay(
                                    Capsule().stroke(OT.separator, lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Spacer()
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OT.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Kept for backward compatibility
struct SuggestionChipBar: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        EmptyView()
    }
}

private struct OCRReviewSheet: View {
    @Environment(AppStore.self) private var store
    /// The draft that the parser produced — presented as editable fields.
    @State var draft: NoticeParser.Draft
    let sourcePreview: UIImage?
    let onConfirm: (NoticeParser.Draft, AddAuditionFlow.ReaderAudioPlan) -> Void
    let onDiscard: () -> Void

    private enum FocusField: Hashable {
        case project, role, castingOffice
    }
    @FocusState private var focusedField: FocusField?

    @State private var projectText: String
    @State private var roleText: String
    @State private var castingOfficeText: String
    @State private var sidesLinkText: String
    @State private var destinationDetailText: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var castingNotesText: String
    @State private var actorNotesText: String
    @State private var isSlateOptional: Bool
    @State private var isFullBodyShotOptional: Bool
    @State private var isHeadshotOptional: Bool
    @State private var includeSlate: Bool
    @State private var includeHeadshots: Bool
    @State private var selectedPortionIDs: Set<String>
    @State private var readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .recordNow

    private var hasReaderLines: Bool {
        let effective = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effective.isEmpty, draft.hasSides else { return false }
        let scenes = draft.hasSides
            ? ((draft.customScenes?.isEmpty == false ? draft.customScenes : nil) ?? ScriptParser.parseScenes(from: draft.sourceText, myRole: effective))
            : []
        return scenes.contains { $0.lines.contains { !$0.isMine } }
    }

    private var detectedReaderName: String {
        let effective = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let scenes = (draft.customScenes?.isEmpty == false ? draft.customScenes : nil) ?? ScriptParser.parseScenes(from: draft.sourceText, myRole: effective)
        let unowned = scenes.flatMap(\.lines).filter { !$0.isMine }
        return unowned.first?.character.capitalized ?? "Reader"
    }

    private var canUseThis: Bool {
        !roleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (draft.availablePortions.count <= 1 || !selectedPortionIDs.isEmpty)
    }

    private var portionsArePages: Bool {
        !draft.availablePortions.isEmpty && draft.availablePortions.allSatisfy { $0.pageNumber != nil }
    }

    init(draft: NoticeParser.Draft, sourcePreview: UIImage? = nil, onConfirm: @escaping (NoticeParser.Draft, AddAuditionFlow.ReaderAudioPlan) -> Void, onDiscard: @escaping () -> Void) {
        self._draft = State(initialValue: draft)
        self.sourcePreview = sourcePreview
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        self._projectText = State(initialValue: draft.project)
        let effectiveRole = draft.role.isEmpty ? (draft.candidateRoles.first ?? "") : draft.role
        self._roleText = State(initialValue: effectiveRole)
        self._castingOfficeText = State(initialValue: draft.castingOffice)
        self._sidesLinkText = State(initialValue: draft.sidesLink ?? "")
        self._destinationDetailText = State(initialValue: draft.destinationDetail ?? "")
        self._hasDueDate = State(initialValue: draft.due != nil)
        self._dueDate = State(initialValue: draft.due ?? .now.addingTimeInterval(3 * 86400))
        let initialCastingNotes = draft.castingNotes ?? NoticeParser.extractCharacterDescription(for: effectiveRole, in: draft.sourceText) ?? ""
        self._castingNotesText = State(initialValue: initialCastingNotes)
        self._actorNotesText = State(initialValue: draft.actorNotes ?? "")
        self._isSlateOptional = State(initialValue: draft.isSlateOptional)
        self._isFullBodyShotOptional = State(initialValue: draft.isFullBodyShotOptional)
        self._isHeadshotOptional = State(initialValue: draft.isHeadshotOptional)
        self._includeSlate = State(initialValue: draft.includeSlate)
        self._includeHeadshots = State(initialValue: draft.includeHeadshots)
        self._selectedPortionIDs = State(initialValue: draft.selectedPortionIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Review what we read", systemImage: "doc.text.magnifyingglass")
                            .font(.otTitle)
                        Text("Check each field — fix anything that looks wrong before continuing.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Audition Type", systemImage: "theatermasks")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                        AuditionMaterialKindPicker(selected: $draft.materialKind)
                    }

                    if !draft.importantDates.isEmpty {
                        MilestoneDatesListCard(dates: draft.importantDates)
                    }

                    if let details = draft.projectDetails, details.hasReviewableContent {
                        ProjectDetailsCard(details: details)
                    }

                    reviewField(
                        icon: "film",
                        label: "Audition name",
                        placeholder: "A name to recognize this audition",
                        text: $projectText,
                        isRequired: false,
                        field: .project
                    )

                    reviewField(
                        icon: "person",
                        label: "Character you’re auditioning for",
                        placeholder: "e.g. Alice",
                        text: $roleText,
                        isRequired: true,
                        field: .role
                    )

                    // Quick-select candidate roles extracted from the notice
                    if !draft.roleBreakdowns.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Role details found in the notice")
                                .font(.otCaption.weight(.bold))
                                .foregroundStyle(OT.labelSecondary)
                            VStack(spacing: 8) {
                                ForEach(draft.roleBreakdowns) { breakdown in
                                    let isCurrent = roleText.caseInsensitiveCompare(breakdown.name) == .orderedSame
                                    RoleBreakdownCard(breakdown: breakdown, isSelected: isCurrent) {
                                        roleText = breakdown.name
                                        if let desc = breakdown.description {
                                            castingNotesText = desc
                                            draft.aiGuidance = desc
                                        }
                                        let matching = draft.availablePortions.filter { $0.characters.contains { $0.caseInsensitiveCompare(breakdown.name) == .orderedSame } }.map(\.id)
                                        if !matching.isEmpty { selectedPortionIDs = Set(matching) }
                                        Haptics.tick()
                                    }
                                }
                            }
                        }
                    } else if !draft.candidateRoles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(draft.candidateRoles, id: \.self) { roleOption in
                                    Button {
                                        roleText = roleOption
                                        if let auto = NoticeParser.extractCharacterDescription(for: roleOption, in: draft.sourceText) {
                                            castingNotesText = auto
                                            draft.aiGuidance = auto
                                        }
                                        let matching = draft.availablePortions.filter { $0.characters.contains { $0.caseInsensitiveCompare(roleOption) == .orderedSame } }.map(\.id)
                                        if !matching.isEmpty { selectedPortionIDs = Set(matching) }
                                        Haptics.tick()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: roleText == roleOption ? "checkmark" : "plus.circle.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text(roleOption)
                                                .font(.otCaption.weight(.medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(roleText == roleOption ? OT.accent : OT.fillField, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .foregroundStyle(roleText == roleOption ? .white : OT.labelPrimary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    DisclosureGroup {
                        reviewField(
                            icon: "building.2",
                            label: "Casting contact or office",
                            placeholder: "Name of the casting office",
                            text: $castingOfficeText,
                            isRequired: false,
                            field: .castingOffice
                        )
                    } label: {
                        Label("Add casting contact (optional)", systemImage: "person.crop.rectangle")
                            .font(.otFootnote.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                    }
                    .tint(OT.accent)

                    // Sides link (Google Drive / Dropbox / Cloud link for script sides)
                    if !sidesLinkText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            reviewField(
                                icon: "folder.badge.person.crop",
                                label: "Sides / Script link (Google Drive / Cloud)",
                                placeholder: "Optional",
                                text: $sidesLinkText,
                                isRequired: false
                            )
                            if let url = URL(string: sidesLinkText.hasPrefix("http") ? sidesLinkText : "https://\(sidesLinkText)") {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text("Open sides in browser")
                                    }
                                    .font(.otCaption.weight(.medium))
                                    .foregroundStyle(OT.accent)
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }

                    // Submission destination detail (email, upload link, or WhatsApp)
                    if !destinationDetailText.isEmpty || draft.destination == .emailOrLink {
                        reviewField(
                            icon: destinationDetailText.contains("@") ? "envelope" : "paperplane",
                            label: destinationDetailText.contains("@") ? "Submission email" : "Submission link / WhatsApp",
                            placeholder: "Optional",
                            text: $destinationDetailText,
                            isRequired: false
                        )
                    }


                    // Choose script scenes, or pages when OCR could only identify page boundaries.
                    if !draft.availablePortions.isEmpty && draft.availablePortions.count > 1 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(portionsArePages ? "Which pages contain your sides?" : "Which scene(s) are you taping?", systemImage: "film.stack")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Spacer()
                                Button(selectedPortionIDs.count == draft.availablePortions.count ? "Deselect all" : "Select all") {
                                    if selectedPortionIDs.count == draft.availablePortions.count {
                                        selectedPortionIDs.removeAll()
                                    } else {
                                        selectedPortionIDs = Set(draft.availablePortions.map(\.id))
                                    }
                                    Haptics.tick()
                                }
                                .font(.otCaption.weight(.medium))
                                .foregroundStyle(OT.accent)
                            }

                            Text("Choose the relevant \(portionsArePages ? "pages" : "scenes") for \(roleText.isEmpty ? "your role" : roleText).")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)

                            VStack(spacing: 8) {
                                ForEach(draft.availablePortions) { portion in
                                    let isSelected = selectedPortionIDs.contains(portion.id)
                                    let isForMyRole = portion.characters.contains { $0.caseInsensitiveCompare(roleText) == .orderedSame }
                                    Button {
                                        if isSelected {
                                            selectedPortionIDs.remove(portion.id)
                                        } else {
                                            selectedPortionIDs.insert(portion.id)
                                        }
                                        Haptics.tick()
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(isSelected ? OT.accent : OT.labelTertiary)
                                                .padding(.top, 2)

                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(portion.displayTitle)
                                                        .font(.otSubhead.weight(.semibold))
                                                        .foregroundStyle(OT.labelPrimary)
                                                    Spacer()
                                                    if isForMyRole {
                                                        Text("Matches role")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(OT.accentSoft, in: Capsule())
                                                            .foregroundStyle(OT.accent)
                                                    }
                                                }

                                                if !portion.characters.isEmpty {
                                                    ScrollView(.horizontal, showsIndicators: false) {
                                                        HStack(spacing: 4) {
                                                            ForEach(portion.characters.prefix(4), id: \.self) { c in
                                                                Text(c)
                                                                    .font(.system(size: 11, weight: .medium))
                                                                    .padding(.horizontal, 6)
                                                                    .padding(.vertical, 2)
                                                                    .background(c.caseInsensitiveCompare(roleText) == .orderedSame ? OT.accent.opacity(0.15) : OT.fillField, in: RoundedRectangle(cornerRadius: 6))
                                                                    .foregroundStyle(c.caseInsensitiveCompare(roleText) == .orderedSame ? OT.accent : OT.labelSecondary)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(12)
                                        .background(isSelected ? OT.accentSoft.opacity(0.3) : OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(isSelected ? OT.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(14)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // Due date
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Due date", systemImage: "calendar")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)

                        Toggle("Tape deadline found", isOn: $hasDueDate)
                            .font(.otFootnote)
                            .tint(OT.accent)

                        if hasDueDate {
                            DatePicker("", selection: $dueDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        } else {
                            Text("No deadline found — you can set one later.")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                    }
                    .padding(14)
                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Notes from casting
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Character details from the notice", systemImage: "person.text.rectangle")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                        Text("What casting says about the character. You can edit this.")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelTertiary)
                        TextField("Character description", text: $castingNotesText, axis: .vertical)
                            .lineLimit(4...10)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // My notes & understanding
                    reviewField(
                        icon: "sparkles",
                        label: "My notes & understanding",
                        placeholder: "My choices, subtext, questions",
                        text: $actorNotesText,
                        isRequired: false
                    )

                    // Deliverables in flow (Slate & Headshots)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("What to prepare", systemImage: "list.bullet.rectangle")
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                            deliverableToggle(title: "Slate / intro", icon: "person.text.rectangle", isOptional: $isSlateOptional)
                            if draft.asks.contains("Full-body shot") {
                                deliverableToggle(title: "Full-body shot", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                            } else if draft.asks.contains("Full-body shot with slate") {
                                deliverableToggle(title: "Full-body view in slate", icon: "figure.stand", isOptional: $isFullBodyShotOptional)
                            }
                            deliverableToggle(title: "Headshots", icon: "person.crop.rectangle", isOptional: $isHeadshotOptional)
                        }
                    }
                    .padding(14)
                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Reader audio option if lines for reader are present
                    if hasReaderLines {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Practice cue audio", systemImage: "waveform")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text("Other character").font(.otCaption.weight(.bold)).foregroundStyle(OT.reader)
                                    Text(detectedReaderName).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.reader)
                                }
                            }
                            Text("Record the other character’s lines in your voice. They’ll play back as cues while you perform.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                            Picker("Reader audio", selection: $readerAudioPlan) {
                            Text("Record now").tag(AddAuditionFlow.ReaderAudioPlan.recordNow)
                            Text("Later").tag(AddAuditionFlow.ReaderAudioPlan.later)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(14)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Clear, wrapped requirement list. These are statements from the notice,
                    // not compact tags that truncate email addresses or long instructions.
                    if !draft.asks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Requested by casting", systemImage: "checkmark.circle")
                                .font(.otCaption.weight(.medium))
                                .foregroundStyle(OT.labelSecondary)
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(draft.asks.enumerated()), id: \.offset) { _, ask in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: symbol(for: ask))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(OT.accent)
                                            .frame(width: 20)
                                        Text(ask)
                                            .font(.otFootnote.weight(.medium))
                                            .foregroundStyle(OT.labelPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if draft.asks.contains(where: { $0.localizedCaseInsensitiveContains("resume") || $0.localizedCaseInsensitiveContains("résumé") }) {
                        AuditionResumePicker(
                            isIncluded: $draft.includeResume,
                            selectedURL: $draft.resumeURL
                        )
                    }

                    if let sourcePreview {
                        DisclosureGroup {
                            Image(uiImage: sourcePreview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityLabel("Full original casting notice image")
                        } label: {
                            Label("View full notice image", systemImage: "photo")
                                .font(.otSubhead.weight(.semibold))
                                .foregroundStyle(OT.labelPrimary)
                        }
                        .tint(OT.accent)
                        .padding(14)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(OT.gutter)
            }
            .otCanvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { onDiscard() }
                        .foregroundStyle(OT.labelSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this") {
                        Haptics.success()
                        var confirmed = draft
                        confirmed.project = projectText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.role = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.castingOffice = castingOfficeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.sidesLink = sidesLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sidesLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.destinationDetail = destinationDetailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : destinationDetailText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.due = hasDueDate ? dueDate : nil
                        let trimmedCastingNotes = castingNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.castingNotes = trimmedCastingNotes.isEmpty ? nil : trimmedCastingNotes
                        let trimmedActorNotes = actorNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirmed.actorNotes = trimmedActorNotes.isEmpty ? nil : trimmedActorNotes
                        confirmed.isSlateOptional = isSlateOptional
                        confirmed.isFullBodyShotOptional = isFullBodyShotOptional
                        confirmed.isHeadshotOptional = isHeadshotOptional
                        confirmed.includeSlate = includeSlate
                        confirmed.includeHeadshots = includeHeadshots

                        // Pass 2: Targeted Scene Chunker
                        if !draft.availablePortions.isEmpty {
                            let chosen = draft.availablePortions.filter { selectedPortionIDs.contains($0.id) }
                            if !chosen.isEmpty {
                                let selectedText = chosen.map(\.rawText).joined(separator: "\n\n")
                                let parsedScenes = portionsArePages
                                    ? ScriptParser.parseScenes(from: selectedText, myRole: confirmed.role)
                                    : ScriptParser.parseSelectedPortions(chosen, myRole: confirmed.role)
                                confirmed.customScenes = parsedScenes
                                confirmed.scenes = parsedScenes.count
                                confirmed.sourceText = selectedText
                            }
                        }
                        onConfirm(confirmed, readerAudioPlan)
                    }
                    .font(.otHeadline)
                    .foregroundStyle(canUseThis ? OT.accent : OT.labelTertiary)
                    .disabled(!canUseThis)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    let suggestions: [String] = {
                        switch focusedField {
                        case .project:
                            return store.projectSuggestions.filter {
                                projectText.isEmpty || $0.localizedCaseInsensitiveContains(projectText)
                            }
                        case .role:
                            return store.roleSuggestions.filter {
                                roleText.isEmpty || $0.localizedCaseInsensitiveContains(roleText)
                            }
                        case .castingOffice:
                            return store.castingOfficeSuggestions.filter {
                                castingOfficeText.isEmpty || $0.localizedCaseInsensitiveContains(castingOfficeText)
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
                                projectText = selected
                            case .role:
                                roleText = selected
                                if let auto = NoticeParser.extractCharacterDescription(for: selected, in: draft.sourceText) {
                                    castingNotesText = auto
                                }
                            case .castingOffice:
                                castingOfficeText = selected
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
        }
        .onChange(of: roleText) { _, newRole in
            let matching = draft.availablePortions
                .filter { portion in portion.characters.contains { $0.caseInsensitiveCompare(newRole) == .orderedSame } }
                .map(\.id)
            if !matching.isEmpty {
                selectedPortionIDs = Set(matching)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func reviewField(
        icon: String,
        label: String,
        placeholder: String,
        text: Binding<String>,
        isRequired: Bool,
        field: FocusField? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(OT.accent)
                    .frame(width: 18)
                Text(label)
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelSecondary)
                if isRequired && text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Spacer()
                    Label("Not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: field)
                .padding(12)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isRequired && text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.orange.opacity(0.7) : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
    }

    private func symbol(for ask: String) -> String {
        let value = ask.lowercased()
        if value.contains("headshot") || value.contains("photo") { return "person.crop.rectangle" }
        if value.contains("resume") || value.contains("résumé") { return "doc.text" }
        if value.contains("video") || value.contains("self-tape") || value.contains("intro") { return "video" }
        if value.contains("email") || value.contains("link") || value.contains("whatsapp") { return "paperplane" }
        if value.contains("landscape") || value.contains("portrait") { return "rectangle.portrait.rotate" }
        if value.contains("slate") { return "person.text.rectangle" }
        return "checkmark"
    }

    private func deliverableToggle(title: String, icon: String, isOptional: Binding<Bool>) -> some View {
        Button {
            isOptional.wrappedValue.toggle()
            Haptics.tick()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(isOptional.wrappedValue ? "Optional" : "Required")
                    .font(.otCaption.weight(.bold))
                    .foregroundStyle(isOptional.wrappedValue ? OT.labelSecondary : OT.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isOptional.wrappedValue ? OT.surfaceSunken : OT.accentSoft, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(isOptional.wrappedValue ? "optional" : "required"). Tap to change.")
    }
}

private struct AuditionResumePicker: View {
    @Environment(AppStore.self) private var store
    @Binding var isIncluded: Bool
    @Binding var selectedURL: URL?
    @State private var showingImporter = false
    @State private var errorMessage: String?

    private var resumeURL: URL? { selectedURL ?? store.slate.resumeURL }
    private var includeBinding: Binding<Bool> {
        Binding(
            get: { isIncluded },
            set: { newValue in
                isIncluded = newValue
                if newValue, selectedURL == nil { selectedURL = store.slate.resumeURL }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Résumé", systemImage: "doc.text")
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(OT.labelPrimary)

            if let resumeURL {
                Toggle(isIncluded ? "Include with this audition" : "Don't include with this audition", isOn: includeBinding)
                    .font(.otFootnote)
                    .tint(OT.accent)
                Text(resumeURL.lastPathComponent)
                    .font(.otCaption).foregroundStyle(OT.labelSecondary)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                Text("No résumé saved to your profile yet.")
                    .font(.otFootnote).foregroundStyle(OT.labelSecondary)
            }

            Button(resumeURL == nil ? "Add résumé to Profile" : "Replace profile résumé") {
                showingImporter = true
            }
            .font(.otFootnote.weight(.semibold))
            .foregroundStyle(OT.accent)

            Text("Your profile résumé is reusable. Choose whether to include it for this audition.")
                .font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
        .padding(14)
        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [
            .pdf, .rtf, .plainText,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data
        ]) { result in
            switch result {
            case .success(let url):
                do {
                    let savedURL = try ResumeStore.importFile(from: url)
                    store.slate.resumeURL = savedURL
                    selectedURL = savedURL
                    isIncluded = true
                    Haptics.success()
                } catch {
                    errorMessage = "Choose a PDF, Word, RTF, or plain text résumé."
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't add résumé", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Try choosing a résumé file again.")
        }
    }
}

// MARK: - Notice parsing (on-device, rule-based — runs on whatever real text OCR/the file importer found)

enum NoticeParser {
    /// A casting notice can contain uppercase headings and bullet lists that resemble character cues.
    /// Only treat a notice-plus-sides document as script material when a scene heading is present;
    /// otherwise do not turn the notice's own headings into dialogue or a required scene.
    static func isNoticeOnly(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasNoticeMarkers = ["what to submit", "currently casting", "actors should email", "audition notice"]
            .contains(where: lower.contains)
        guard hasNoticeMarkers else { return false }
        let hasSceneMarker = text.range(of: #"(?im)^\s*(?:INT\.|EXT\.|INT/EXT\b|SCENE\s+[0-9A-Z]+\b|ACT\s+(?:ONE|TWO|THREE|[0-9IVX]+)\b|[A-Z]{2,20}\s*[·•|—-]\s*(?:He|She|They)/|[A-Z]{2,20}\s*[-—–]\s*(?:Page|Pg\.?)\s*\d+)"#, options: .regularExpression) != nil
        return !hasSceneMarker
    }

    struct Draft: Hashable, Identifiable {
        /// Stable identity so `.sheet(item:)` can distinguish different parsed drafts.
        var id: String { "\(project)|\(role)|\(castingOffice)|\(due?.timeIntervalSince1970 ?? 0)|\(sidesLink ?? "")" }
        var project = ""
        var role = ""
        var candidateRoles: [String] = []
        var castingOffice = ""
        var projectType = "Feature film"
        var due: Date?
        var scenes = 0
        var asks: [String] = []
        var aiGuidance = ""
        var roleSize = "Lead"
        /// True when the notice explicitly says sides will be provided at the audition, so
        /// `missingRequiredDetails` does not ask the actor to add them in advance.
        var sidesOnArrival = false
        /// A cloud drive link (Google Drive, Dropbox, WeTransfer, OneDrive) where script sides or materials are hosted.
        var sidesLink: String? = nil
        var destination: Destination = .actorsAccess
        var destinationDetail: String? = nil
        var destinationWasDetected = false
        /// The real recognised text this draft came from — kept so `makeAudition()` can parse real
        /// sides out of it instead of substituting a canned scene.
        var sourceText = ""
        var customScenes: [ScriptScene]? = nil
        var castingNotes: String? = nil
        var actorNotes: String? = nil
        var materialKind: AuditionMaterialKind = .sides
        var isSlateOptional: Bool = false
        var isFullBodyShotOptional: Bool = false
        var isHeadshotOptional: Bool = false
        var includeSlate: Bool = true
        var includeHeadshots: Bool = true
        var includeResume: Bool = false
        var resumeURL: URL? = nil
        var availablePortions: [ScriptParser.ScenePortion] = []
        var selectedPortionIDs: Set<String> = []
        var projectDetails: AuditionProjectDetails? = nil
        var importantDates: [AuditionDate] = []
        var roleBreakdowns: [AuditionRoleBreakdown] = []
        var sideMaterials: [AuditionSideMaterial] = []
        var noticeSources: [AuditionSource] = []
        var fieldEvidence: [AuditionFieldEvidence] = []
        var submissionInstructions: AuditionSubmissionInstructions? = nil
        var sourceDocuments: [AuditionSource] = []

        static let blank = Draft()

        var hasSides: Bool {
            if !materialKind.requiresSides { return true }
            if let customScenes, !customScenes.isEmpty { return true }
            return !NoticeParser.isNoticeOnly(sourceText) && !ScriptParser.parseScenes(from: sourceText, myRole: role).isEmpty
        }

        var missingRequiredDetails: [String] {
            var missing: [String] = []
            if role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && materialKind != .slateOnly { missing.append("role") }
            if materialKind.requiresSides && !hasSides && !NoticeParser.isNoticeOnly(sourceText) && !sidesOnArrival && (sidesLink == nil || sidesLink?.isEmpty == true) { missing.append("script sides") }
            let resumeRequired = asks.contains { ask in
                let value = ask.lowercased()
                return (value == "resume" || value == "résumé") && !value.contains("optional")
            }
            if resumeRequired && (!includeResume || resumeURL == nil) { missing.append("resume") }
            return missing
        }

        func makeAudition() -> Audition {
            var parsedScenes = hasSides
                ? ((customScenes?.isEmpty == false ? customScenes : nil) ?? ScriptParser.parseScenes(from: sourceText, myRole: role))
                : []

            // Non-dialogue audition types: adapt scenes and pieces accordingly
            switch materialKind {
            case .monologue:
                if parsedScenes.isEmpty {
                    let cleaned = ScriptParser.cleanPastedText(sourceText)
                    let monologueLines = cleaned.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { ScriptLine(character: role.isEmpty ? "Actor" : role, text: $0, isMine: true) }
                    if !monologueLines.isEmpty {
                        parsedScenes = [ScriptScene(number: 1, title: "Monologue", heading: "SOLO MONOLOGUE", lines: monologueLines, estimatedSeconds: max(30, monologueLines.count * 3))]
                    }
                }
            case .song:
                if parsedScenes.isEmpty {
                    parsedScenes = [ScriptScene(number: 1, title: "Song Cut", heading: "VOCAL AUDITION", lines: [], estimatedSeconds: 90)]
                }
            case .movement:
                if parsedScenes.isEmpty {
                    parsedScenes = [ScriptScene(number: 1, title: "Movement / Dance", heading: "PHYSICAL AUDITION", lines: [], estimatedSeconds: 90)]
                }
            case .slateOnly:
                parsedScenes = []
            case .sides:
                break
            }

            var pieces: [Piece] = []
            if includeSlate || materialKind == .slateOnly {
                var slateDetail = materialKind == .slateOnly
                    ? "Direct-to-camera slate & intro"
                    : (asks.contains(where: { $0.localizedCaseInsensitiveContains("self-tape") || $0.localizedCaseInsensitiveContains("introduction video") })
                       ? "Self-tape or introduction video, as requested"
                       : "Name, height, city")
                if asks.contains("Full-body shot with slate") {
                    slateDetail += isFullBodyShotOptional ? " · optional head-to-toe view" : " · include a head-to-toe view"
                }
                pieces.append(.init(kind: .slate, title: isSlateOptional ? "Slate (Optional)" : "Slate", detail: slateDetail, isDone: false, isOptional: isSlateOptional && materialKind != .slateOnly))
            }

            if asks.contains("Full-body shot")
                || (asks.contains("Full-body shot with slate") && !includeSlate) {
                pieces.append(.init(kind: .fullLength, title: "Full-body shot",
                                    detail: "Head-to-toe video, as requested",
                                    isDone: false, isOptional: isFullBodyShotOptional))
            }

            if materialKind != .slateOnly {
                if parsedScenes.isEmpty {
                    // No sides could be read from what was captured — be honest about that rather than
                    // filling in a stand-in scene. Pieces still exist so the checklist has something to
                    // point at; "Add sides" is left for the actor to do once they have the real pages.
                    for i in 0..<max(scenes, 0) {
                        pieces.append(.init(kind: .scene, title: "Scene \(i + 1)", detail: "No sides yet — add them", isDone: false))
                    }
                } else {
                    for scene in parsedScenes {
                        let isOpt = NoticeParser.isSceneOptional(scene: scene, in: sourceText)
                        pieces.append(.init(kind: .scene, title: scene.title, detail: isOpt ? "Optional scene" : "", isDone: false, isOptional: isOpt))
                    }
                }
            }

            if includeHeadshots {
                pieces.append(.init(kind: .headshot, title: isHeadshotOptional ? "Headshot (Optional)" : "Headshot", detail: "Photos", isDone: false, isOptional: isHeadshotOptional))
            }
            pieces = Piece.defaultFlowOrder(pieces)
            let autoNotes = NoticeParser.extractCharacterDescription(for: role, in: sourceText)
            // Project-level guidance is not a character breakdown. Keep it out of the casting
            // notes column unless we have notes explicitly attached to the selected role.
            let resolvedCastingNotes = castingNotes ?? autoNotes
            let auditionName = project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled audition" : "\(role) audition")
                : project
            var audition = Audition(project: auditionName, projectType: projectType,
                            role: role.isEmpty ? (materialKind == .slateOnly ? "Self" : "Role") : role, roleSize: roleSize, castingOffice: castingOffice,
                            due: due ?? .now.addingTimeInterval(3 * 86400),
                            asks: asks, pieces: pieces, scenes: parsedScenes,
                            scriptText: sourceText.isEmpty ? nil : sourceText,
                            destination: destination, status: .due)
            audition.materialKind = materialKind
            audition.destinationWasChosen = destinationWasDetected
            audition.destinationDetail = destinationDetail
            audition.sidesLink = sidesLink
            audition.castingNotes = resolvedCastingNotes
            audition.actorNotes = actorNotes
            audition.projectDetails = projectDetails
            audition.importantDates = importantDates.isEmpty ? nil : importantDates
            audition.roleBreakdowns = roleBreakdowns.isEmpty ? nil : roleBreakdowns
            audition.sideMaterials = sideMaterials.isEmpty ? nil : sideMaterials
            audition.sourceDocuments = sourceDocuments.isEmpty ? nil : sourceDocuments
            audition.noticeSources = noticeSources.isEmpty ? nil : noticeSources
            audition.fieldEvidence = fieldEvidence.isEmpty ? nil : fieldEvidence
            audition.submissionInstructions = submissionInstructions
            audition.resumeURL = includeResume ? resumeURL : nil
            return audition
        }
    }

    /// Asynchronous parsing pipeline: runs deterministic regex/anchor extraction first,
    /// then enriches with the on-device Foundation Model when supported on this iPhone.
    static func parseAsync(_ rawText: String, pages: [String] = [], sourceDocuments: [AuditionSource] = []) async -> Draft {
        let base = parse(rawText, pages: pages, sourceDocuments: sourceDocuments)
        var refined = await OnDeviceIntelligence.refineDraftWithFoundationModel(base, sourceText: rawText)
        populateStructuredNoticeData(&refined, text: refined.sourceText, pages: pages)
        return refined
    }

    static func parse(_ rawText: String, pages: [String] = [], sourceDocuments: [AuditionSource] = []) -> Draft {
        var d = Draft()
        let cleaned = ScriptParser.cleanPastedText(rawText)
        d.sourceText = cleaned
        d.sourceDocuments = sourceDocuments

        // Pass 1 (Notice Extractor): If multi-page packet, focus notice field extraction on Pages 1–2
        let isLongPacket = pages.count >= 2 || rawText.count > 3500
        let noticeSource = isLongPacket && !pages.isEmpty
            ? pages.prefix(2).joined(separator: "\n\n")
            : (rawText.count > 3500 ? String(rawText.prefix(2500)) : cleaned)

        let text = tidy(noticeSource)
        let lower = text.lowercased()
        let noticeOnly = isNoticeOnly(cleaned)

        d.due = detectDate(in: text)
        var candidates = detectCandidateRoles(in: text)
        // If notice labels didn't have explicit roles, check if screenplay cues contain characters
        if candidates.isEmpty && !noticeOnly {
            candidates = ScriptParser.extractCharacters(from: cleaned)
        }
        d.candidateRoles = candidates
        if candidates.count == 1 && !containsOpenRoleChoice(in: text) {
            d.role = candidates[0]
            d.castingNotes = extractCharacterDescription(for: d.role, in: cleaned)
        } else {
            // When multiple roles are present, do not arbitrarily choose one:
            // leave it empty so the app explicitly asks the actor which role they are auditioning for.
            d.role = ""
        }
        if let project = detectProject(in: text) {
            d.project = project
        }
        // Detect explicit role size/tier from notice text
        let roleSizeLower = lower
        if roleSizeLower.contains("series regular") || roleSizeLower.contains("series lead") {
            d.roleSize = "Series Regular"
        } else if roleSizeLower.range(of: #"\bco[-\s]?star\b"#, options: .regularExpression) != nil {
            d.roleSize = "Co-Star"
        } else if roleSizeLower.contains("day player") {
            d.roleSize = "Day Player"
        } else if roleSizeLower.range(of: #"\bsupporting\b"#, options: .regularExpression) != nil {
            d.roleSize = "Supporting"
        } else if roleSizeLower.range(of: #"\b(?:lead|lead role|main role|principal role|feature role)\b"#, options: .regularExpression) != nil {
            d.roleSize = "Lead"
        } else if roleSizeLower.contains("principal") {
            d.roleSize = "Principal"
        }
        if let office = detectCastingOffice(in: text) {
            d.castingOffice = office
        }
        // Hierarchical Scene Portions (Pass 2 identification)
        let portions = noticeOnly ? [] : ScriptParser.identifyScenePortions(from: cleaned, pages: pages)
        d.availablePortions = portions

        let targetRole = d.role.isEmpty ? (d.candidateRoles.first ?? "") : d.role
        let matchingIDs = portions.filter { $0.characters.contains { $0.caseInsensitiveCompare(targetRole) == .orderedSame } }.map(\.id)
        d.selectedPortionIDs = Set(matchingIDs.isEmpty ? portions.prefix(3).map(\.id) : matchingIDs)

        let parsedScenes = noticeOnly ? [] : ScriptParser.parseScenes(from: cleaned, myRole: d.role)
        if !parsedScenes.isEmpty {
            d.scenes = parsedScenes.count
        } else if !portions.isEmpty {
            d.scenes = d.selectedPortionIDs.isEmpty ? portions.count : d.selectedPortionIDs.count
        } else if noticeOnly {
            d.scenes = 0
        } else if let explicit = detectSceneCount(in: text) {
            d.scenes = max(explicit, 0)
        } else {
            d.scenes = 0
        }

        func ask(_ s: String) { if !d.asks.contains(s) { d.asks.append(s) } }
        // Contextual requirements: match actual instruction contexts rather than isolated screenplay dialogue words
        if firstMatch(#"(?i)\b(?:please\s+)?slate\s*(?:first|video|instructions?|clip|required)?\b|\binclude\s+(?:a\s+)?slate\b"#, in: text) != nil {
            ask("Slate first")
        }
        if firstMatch(#"(?i)\b(?:horizontal|landscape)\s+(?:mode|framing|orientation|video|format|shot)\b|\b(?:frame|shoot|record|film)\s+in\s+landscape\b|\bslate\s+first\s*,\s*landscape\b|\blandscape\s*,\s*full\s+length\b|\bhorizontal\s*\(landscape\)|\borientation\s*[:\-]\s*(?:horizontal|landscape)\b|\blandscape\s+only\b|\bhorizontal\s*/\s*landscape\b"#, in: text) != nil {
            ask("Landscape")
        }
        if firstMatch(#"(?i)\b(?:full[-\s]?body|head[-\s]?to[-\s]?toe)\s+(?:photo|picture|headshot)\b"#, in: text) != nil {
            ask("Headshots")
        }
        let fullBodyPattern = #"(?i)\b(?:full[-\s]?body|head[-\s]?to[-\s]?toe|full[-\s]?length)\s*(?:shot|slate|framing|video|view)\b"#
        let instructionLines = text.components(separatedBy: .newlines)
        if let bodyLineIndex = instructionLines.firstIndex(where: { firstMatch(fullBodyPattern, in: $0) != nil }) {
            let context = instructionLines.enumerated()
                .filter { abs($0.offset - bodyLineIndex) <= 1 }
                .map(\.element)
                .joined(separator: " ").lowercased()
            let explicitlySeparate = context.range(of: #"\bseparat(?:e|ely)\b[^.\n]{0,80}\b(?:video|clip|file)\b|\b(?:video|clip|file)\b[^.\n]{0,80}\bseparat(?:e|ely)\b"#, options: .regularExpression) != nil
            let includesSlate = !explicitlySeparate && (
                context.range(of: #"\b(?:slate|intro(?:duction)?)\b"#, options: .regularExpression) != nil
                    || context.range(of: #"\bname\b[^.\n]{0,80}\bheight\b|\bheight\b[^.\n]{0,80}\bname\b"#, options: .regularExpression) != nil
            )
            ask(includesSlate ? "Full-body shot with slate" : "Full-body shot")
            d.isFullBodyShotOptional = context.range(of: #"\b(?:optional|if available|not required)\b"#, options: .regularExpression) != nil
        }
        if firstMatch(#"(?i)\b(?:intro|introduction)\s+video\b|\bintroductory\s+video\b|\bintro\s+clip\b"#, in: text) != nil {
            ask("Intro video")
        }
        if firstMatch(#"(?i)\bvideo\b[\s\S]{0,80}\b(?:self[\s-]?tape|introduction|intro)\b|\b(?:self[\s-]?tape|introduction|intro)\b[\s\S]{0,80}\bvideo\b"#, in: text) != nil {
            ask("Self-tape or introduction video")
        }
        if firstMatch(#"(?i)\b(?:headshots?|recent\s+photos?|recent\s+photographs?)\b|(?is)\b(?:send|attach|include|submit|mail|with|along\s+with)\b[\s\S]{0,60}?\b(?:pictures?|photos?)\b"#, in: text) != nil {
            ask("Headshots")
        }
        if firstMatch(#"(?i)\b(?:resume|résumé)\b[\s\S]{0,50}\b(?:optional|not\s+required|if\s+available)\b|\b(?:optional|not\s+required|if\s+available)\b[\s\S]{0,50}\b(?:resume|résumé)\b"#, in: text) != nil {
            ask("Resume (optional)")
        } else if firstMatch(#"(?i)\b(?:resume|résumé)\b"#, in: text) != nil {
            ask("Resume")
        }
        d.includeSlate = d.asks.contains { $0.localizedCaseInsensitiveContains("video") || $0.localizedCaseInsensitiveContains("slate") || $0.localizedCaseInsensitiveContains("intro") }
        d.includeHeadshots = d.asks.contains { $0.localizedCaseInsensitiveContains("headshot") || $0.localizedCaseInsensitiveContains("photo") }
        d.isSlateOptional = firstMatch(#"(?i)\b(?:slate|intro(?:duction)?\s+video|self-?tape)\b[^.\n]{0,50}\b(?:optional|if\s+available|not\s+required)\b|\b(?:optional|if\s+available|not\s+required)\b[^.\n]{0,50}\b(?:slate|intro(?:duction)?\s+video|self-?tape)\b"#, in: text) != nil
        d.isHeadshotOptional = firstMatch(#"(?i)\b(?:headshot|photo|photograph)\b[^.\n]{0,50}\b(?:optional|if\s+available|not\s+required)\b|\b(?:optional|if\s+available|not\s+required)\b[^.\n]{0,50}\b(?:headshot|photo|photograph)\b"#, in: text) != nil
        if let location = detectLocation(in: text) {
            ask("Location: \(location)")
        }
        if let email = firstMatch(#"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})"#, in: text) {
            d.destinationDetail = email
            d.destination = .email
            d.destinationWasDetected = true
        }

        // Context-aware link classification: inspects the text and labels immediately before each URL
        // to distinguish whether a link is for uploading/submitting tapes vs downloading/reading script sides.
        let classified = detectClassifiedLinks(in: text)
        if let sidesLink = classified.sidesLink {
            d.sidesLink = sidesLink
            if sidesLink.contains("drive.google.com") {
                ask("Sides: Google Drive link")
            } else if sidesLink.contains("dropbox.com") {
                ask("Sides: Dropbox link")
            } else if sidesLink.contains("wetransfer.com") {
                ask("Sides: WeTransfer link")
            } else {
                ask("Sides link attached")
            }
        }
        if let subLink = classified.submissionLink {
            if d.destinationDetail == nil || d.destinationDetail?.contains("@") == false {
                d.destinationDetail = subLink
                d.destination = .emailOrLink
                d.destinationWasDetected = true
            }
        }
        if let minutes = detectLengthLimit(in: text) { ask("Under \(minutes) min") }

        // Detect WhatsApp submission (very common in Indian casting notices)
        if let waNumber = firstMatch(#"(?i)(?:whatsapp|wa\.me|send\s+on\s+whatsapp|submit\s+(?:on|via|to|through)\s+whatsapp)\s*(?:to\s*)?[:\-]?\s*(\+?[\d\s\-]{7,15})"#, in: text, options: .caseInsensitive) {
            let number = waNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if number.count >= 7 {
                d.destinationDetail = "+\(number)"
                d.destination = .emailOrLink
                d.destinationWasDetected = true
                ask("WhatsApp: +\(number)")
            }
        }
        // Detect WeTransfer submission
        if firstMatch(#"(?i)\bwetransfer\b"#, in: text) != nil {
            ask("WeTransfer upload")
        }
        // Detect Google Form
        if firstMatch(#"(?i)\bgoogle\s*form\b|forms\.gle\b|docs\.google\.com/forms\b"#, in: text) != nil {
            ask("Google Form")
        }
        // Detect pay/compensation mentions
        if let pay = firstMatch(#"(?i)\b(?:paid|stipend|honorarium|compensation|fee|per\s+day|day\s+rate|rate\s*[:\-]\s*[\$₹£€]?\d+)"#, in: text) {
            let _ = pay // just note it exists — set a flag to indicate paid project
            ask("Paid role")
        }
        // If no submission destination found yet, check for a plain phone number
        if d.destinationDetail == nil {
            if let phone = firstMatch(#"(?:call|contact|reach|send|submit|whatsapp|call\s+us|contact\s+us)\s*(?:at|on|to)?\s*[:\-]?\s*(\+?[\d\s\(\)\-]{7,18})"#, in: text, options: .caseInsensitive) {
                let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if digits.count >= 7 {
                    d.destinationDetail = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                    ask("Call/WhatsApp: \(phone.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        // If notice says sides will be given at the audition, do not flag sides as missing
        if firstMatch(#"(?i)\b(?:sides\s+(?:will\s+be\s+provided|on\s+arrival|given\s+at|provided\s+at|to\s+be\s+provided|at\s+the\s+audition|sent\s+later|will\s+be\s+sent)|audition\s+sides\s+to\s+follow|scripts?\s+(?:will\s+be|to\s+be)\s+(?:provided|sent|given|shared))\b"#, in: text) != nil {
            d.sidesOnArrival = true
        }

        // Contextual project type
        if firstMatch(#"(?i)\b(?:short\s+film|short\s+format|short\s+movie)\b"#, in: text) != nil {
            d.projectType = "Short film"
        } else if firstMatch(#"(?i)\b(?:music\s+video|lyric\s+video|album\s+video)\b"#, in: text) != nil {
            d.projectType = "Music video"
        } else if firstMatch(#"(?i)\b(?:documentary|docuseries|docu-?series|doc\s+series)\b"#, in: text) != nil {
            d.projectType = "Documentary"
        } else if firstMatch(#"(?i)\b(?:web\s+series|ott\s+series|streaming\s+series|digital\s+series)\b"#, in: text) != nil {
            d.projectType = "Web series"
        } else if firstMatch(#"(?i)\b(?:reality\s+(?:show|series|tv)|reality\s+program)\b"#, in: text) != nil {
            d.projectType = "Reality show"
        } else if firstMatch(#"(?i)\b(?:ott\s+film|ott\s+original|streaming\s+film|direct-to-ott|direct\s+to\s+ott)\b"#, in: text) != nil {
            d.projectType = "OTT film"
        } else if firstMatch(#"(?i)\b(?:tv\s+ad|television\s+advertisement|brand\s+film|brand\s+video|product\s+video|social\s+media\s+ad|digital\s+ad|influencer)\b"#, in: text) != nil {
            d.projectType = "Brand content"
        } else if firstMatch(#"(?i)\b(?:feature\s+film|feature\s+length|theatrical\s+film|film\s+project|indie\s+film|cinema)\b"#, in: text) != nil {
            d.projectType = "Feature film"
        } else if firstMatch(#"(?i)\b(?:tv\s+series|television\s+series|web\s+series|limited\s+series|mini-?series|episodic|drama\s+series|comedy\s+series|pilot)\b"#, in: text) != nil {
            d.projectType = "Series"
        } else if firstMatch(#"(?i)\b(?:commercial|brand\s+campaign|tv\s+spot|ad\s+campaign|ad\s+film|promo)\b"#, in: text) != nil {
            d.projectType = "Commercial"
        } else if firstMatch(#"(?i)\b(?:stage\s+play|theatrical\s+production|theatre\s+play|broadway|musical\s+theatre|stage\s+production)\b"#, in: text) != nil {
            d.projectType = "Theatre"
        }

        // Industry platform destinations
        for dest in [Destination.actorsAccess, .backstage, .castingNetworks, .spotlight] {
            if lower.contains(dest.rawValue.lowercased()) {
                d.destination = dest
                d.destinationWasDetected = true
                ask(dest.rawValue)
                break
            }
        }
        // Extract director/character notes for guidance (prioritizing actionable notes over generic announcements)
        let guidanceRole = d.role.isEmpty ? (d.candidateRoles.first ?? "") : d.role
        if !guidanceRole.isEmpty, let roleNote = extractCharacterDescription(for: guidanceRole, in: cleaned), isValidGuidance(roleNote) {
            d.aiGuidance = roleNote
        }

        if d.aiGuidance.isEmpty {
            let guidancePatterns = [
                // Director note / what I'm looking for / acting notes
                #"(?i)(?:director(?:['’]s)?\s*notes?|what\s+i(?:['’]m)?\s+looking\s+for|what\s+i\s+need\s+to\s+see|acting\s+notes?|tone\s+notes?)[:\-]?\s*([^\n]+(?:\n(?!\s*(?:SLATE|THE\s+SIDE|SIDE\s+[A-Z0-9]|SCENE|INT\.|EXT\.|AUDITION|\z))[^\n]+)*)"#,
                // How to use these sides / sides instructions / dialogue sides notes
                #"(?i)(?:how\s+to\s+use\s+these\s+sides|sides?\s+instructions?|dialogue\s+sides?\s*\([^)]*\))[:\-]?\s*([^\n]+(?:\n(?!\s*(?:THE\s+CHARACTERS|SLATE|SIDE|\z))[^\n]+)*)"#,
                // Notes on casting
                #"(?i)(?:notes?\s+on\s+casting|casting\s+notes?)[:\-]?\s*([^\n]+(?:\n(?!\s*(?:Audition\s+Dates|Submissions?|\z))[^\n]+)*)"#,
                // Character brief / role description (NOT generic project description)
                #"(?i)(?:character\s+(?:note|brief|description|background|overview)|about\s+the\s+(?:role|character)|role\s+(?:description|brief|overview))[:\-]?\s*\n?([^\n]+(?:\n(?!\s*(?:AUDITION|SUBMISSION|DATE|\z))[^\n]+)*)"#
            ]
            for pattern in guidancePatterns {
                if let note = firstMatch(pattern, in: text, options: .caseInsensitive) {
                    let trimmed = clean(note).trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 20 && isValidGuidance(trimmed) {
                        d.aiGuidance = trimmed
                        break
                    }
                }
            }
        }
        populateStructuredNoticeData(&d, text: cleaned, pages: pages)
        return d
    }

    /// Adds a structured, source-aware layer over the rule-based notice and sides extraction.
    /// The raw text remains available for review; this layer records only fields grounded in it.
    private static func populateStructuredNoticeData(_ draft: inout Draft, text: String, pages: [String]) {
        draft.fieldEvidence = []
        let sourcePages = pages.isEmpty ? [text] : pages
        if draft.sourceDocuments.isEmpty {
            draft.sourceDocuments = [AuditionSource(name: "Pasted or imported notice", kind: .castingNotice, pageCount: sourcePages.count)]
        }
        draft.noticeSources = sourcePages.enumerated().map { index, page in
            let lower = page.lowercased()
            let looksLikeSides = !ScriptParser.extractCharacters(from: page).isEmpty ||
                lower.contains("audition sides") || lower.contains("script sides")
            let kind: AuditionSourceKind = looksLikeSides ? .scriptSides : .castingNotice
            let parent = draft.sourceDocuments.first(where: { doc in
                let start = (doc.pageNumber ?? 1)
                let end = start + max((doc.pageCount ?? 1) - 1, 0)
                return (start...end).contains(index + 1)
            })
            return AuditionSource(name: "\(parent?.name ?? "Imported document") · page \(index + 1)", kind: kind, url: parent?.url, pageNumber: index + 1, pageCount: 1, parentSourceID: parent?.id)
        }

        let synopsis = firstMatch(
            #"(?is)(?:about\s+the\s+project|project\s+synopsis|synopsis)(?:\s*:\s*|\s+)(.+?)(?=\n\s*(?:character\s+breakdowns?|note\s+on\s+casting|production\s+schedule|production\s+information|audition\s+dates|audition\s+requirements|submission|casting\s+team)\b|\z)"#,
            in: text
        ).map { clean($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let payLine = lines.first { $0.range(of: #"(?i)\b(?:pay|paid|stipend|salary|rate|compensation|honorarium|per\s+diem)\b"#, options: .regularExpression) != nil }
        let unionLine = lines.first { $0.range(of: #"(?i)\b(?:SAG[- ]?AFTRA|AEA|Equity|non[- ]union|nonunion|union contract|no union contract)\b"#, options: .regularExpression) != nil }
        let ndaLine = lines.first { $0.range(of: #"(?i)\bNDA\b|non[- ]disclosure agreement"#, options: .regularExpression) != nil }
        let travelLine = lines.first { $0.range(of: #"(?i)\b(?:travel|travel expenses|accommodation|lodging|per diem|relocation)\b"#, options: .regularExpression) != nil }
        let existingDetails = draft.projectDetails
        draft.projectDetails = AuditionProjectDetails(
            synopsis: (synopsis?.isEmpty == false ? synopsis : nil) ?? existingDetails?.synopsis,
            productionCompany: labeled(["production company", "produced by"], in: text) ?? existingDetails?.productionCompany,
            producer: labeled(["producer"], in: text) ?? existingDetails?.producer,
            director: labeled(["director"], in: text) ?? existingDetails?.director,
            payTerms: payLine ?? existingDetails?.payTerms,
            unionStatus: unionLine ?? existingDetails?.unionStatus,
            ndaNotes: ndaLine ?? existingDetails?.ndaNotes,
            castingArea: detectLocation(in: text) ?? existingDetails?.castingArea,
            productionLocation: labeled(["production location", "filming location", "location"], in: text) ?? existingDetails?.productionLocation,
            travelNotes: travelLine ?? existingDetails?.travelNotes
        )

        var extractedDates = extractImportantDates(in: draft.sourceText, pages: sourcePages, sources: draft.noticeSources)
        for date in draft.importantDates {
            if !extractedDates.contains(where: { $0.kind == date.kind }) {
                extractedDates.append(date)
            }
        }
        draft.importantDates = extractedDates
        draft.roleBreakdowns = draft.candidateRoles.map { role in
            let description = extractCharacterDescription(for: role, in: draft.sourceText)
            let age = description.flatMap { firstMatch(#"(?i)\b(?:early\s+|mid[- ]|late\s+)?\d{1,2}\s*(?:-|–|to)\s*\d{1,2}\b|\b(?:early|mid|late)\s+\d{1,2}s?\b|\b\d{1,2}s\b"#, in: $0) }
            let gender = description.flatMap { firstMatch(#"(?i)\b(?:female|male|woman|man|girl|boy|non[- ]binary|femme|F|M|NB)\b"#, in: $0) }
            return AuditionRoleBreakdown(
                name: role,
                description: description,
                ageRange: age,
                gender: gender,
                ethnicity: nil,
                skills: [],
                eligibilityNotes: description
            )
        }

        var materials: [AuditionSideMaterial] = []
        for portion in draft.availablePortions {
            let sideNumber = firstMatch(#"(?i)\bside\s*#?\s*([A-Z0-9]+)\b"#, in: portion.heading)
                ?? firstMatch(#"(?i)\bside\s*#?\s*([A-Z0-9]+)\b"#, in: portion.rawText)
            let material = AuditionSideMaterial(
                title: portion.displayTitle,
                roleName: portion.characters.count == 1 ? portion.characters.first : nil,
                sideNumber: sideNumber,
                pageStart: portion.pageNumber,
                sourceID: portion.pageNumber.flatMap { page in draft.noticeSources.first(where: { $0.pageNumber == page })?.id },
                text: portion.rawText
            )
            materials.append(material)
            for character in portion.characters {
                if let roleIndex = draft.roleBreakdowns.firstIndex(where: { $0.name.caseInsensitiveCompare(character) == .orderedSame }) {
                    draft.roleBreakdowns[roleIndex].sideMaterialIDs.append(material.id)
                }
            }
        }
        draft.sideMaterials = materials

        var instructions = draft.submissionInstructions ?? AuditionSubmissionInstructions()
        if instructions.slateRequirements.isEmpty {
            instructions.slateRequirements = lines.filter { $0.localizedCaseInsensitiveContains("slate") }
        }
        if instructions.videoOrientation == nil {
            if text.range(of: #"(?i)\b(?:horizontal|landscape)\b"#, options: .regularExpression) != nil { instructions.videoOrientation = "Landscape" }
            else if text.range(of: #"(?i)\b(?:vertical|portrait)\b"#, options: .regularExpression) != nil { instructions.videoOrientation = "Portrait" }
        }
        if instructions.acceptedFormats.isEmpty {
            instructions.acceptedFormats = ["mp4", "mov", "m4v"].filter { format in
                text.range(of: #"(?i)\.\s*"# + format + #"\b|\b"# + format + #"\s+(?:format|file)"#, options: .regularExpression) != nil
            }
        }
        if instructions.requiredVideoCount == nil {
            instructions.requiredVideoCount = firstMatch(#"(?i)\b(?:record|submit|send|upload)\s+(?:exactly\s+)?(\d{1,2}|one|two|three|four)\s+(?:separate\s+)?videos?\b"#, in: text).flatMap(parseSmallNumber)
        }
        if instructions.maxTakes == nil {
            instructions.maxTakes = firstMatch(#"(?i)\b(?:maximum|max|up to|no more than)\s+(\d{1,2})\s+takes?\b"#, in: text).flatMap(Int.init)
        }
        let filename = detectFileNamingInstruction(in: text)
        if instructions.fileNamingRule == nil {
            instructions.fileNamingRule = filename.rule
        }
        if instructions.fileNameTemplate == nil {
            instructions.fileNameTemplate = filename.template
        }
        if instructions.submissionRouteNotes == nil {
            instructions.submissionRouteNotes = lines.first { $0.range(of: #"(?i)\b(?:submit|upload|email|send|share)\b"#, options: .regularExpression) != nil }
        }
        instructions.otherRequirements = draft.asks
        draft.submissionInstructions = instructions

        func addEvidence(field: String, value: String) {
            guard !value.isEmpty,
                  let pageIndex = sourcePages.firstIndex(where: { $0.range(of: value, options: .caseInsensitive) != nil }),
                  draft.noticeSources.indices.contains(pageIndex) else { return }
            let nsText = sourcePages[pageIndex] as NSString
            let match = nsText.range(of: value, options: .caseInsensitive)
            guard match.location != NSNotFound else { return }
            let excerptRange = NSRange(location: max(0, match.location - 80), length: min(nsText.length - max(0, match.location - 80), match.length + 180))
            draft.fieldEvidence.append(AuditionFieldEvidence(
                field: field,
                sourceID: draft.noticeSources[pageIndex].id,
                pageNumber: pageIndex + 1,
                excerpt: nsText.substring(with: excerptRange).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        if !draft.project.isEmpty { addEvidence(field: "project", value: draft.project) }
        if !draft.castingOffice.isEmpty { addEvidence(field: "castingOffice", value: draft.castingOffice) }
        if !draft.role.isEmpty { addEvidence(field: "role", value: draft.role) }
        for date in draft.importantDates {
            if let sourceText = date.sourceText { addEvidence(field: "date.\(date.kind.rawValue)", value: sourceText) }
        }
    }

    private static func parseSmallNumber(_ value: String) -> Int? {
        if let number = Int(value) { return number }
        return ["one": 1, "two": 2, "three": 3, "four": 4][value.lowercased()]
    }

    static func detectFileNamingInstruction(in text: String) -> (rule: String?, template: String?) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in lines where line.range(of: #"(?i)\b(?:file\s*name|filename|name\s+(?:each\s+|all\s+)?files?|label\s+(?:each\s+|all\s+)?files?)\b"#, options: .regularExpression) != nil {
            let templatePattern = #"(?i)(?:format|as|like|e\.g\.|e\.g|:|with)\s*[\"']?([A-Za-z][A-Za-z0-9{}#._-]*(?:[._-][A-Za-z0-9{}#._-]+){1,})"#
            let template = firstMatch(templatePattern, in: line).map(normalizeFileNameTemplate)
            if template != nil { return (line, template) }
            if line.localizedCaseInsensitiveContains("side #") || line.localizedCaseInsensitiveContains("side number") {
                return (line, "{name}_SIDE_{side}")
            }
            if line.localizedCaseInsensitiveContains("full name") {
                return (line, "{name}")
            }
            return (line, nil)
        }
        return (nil, nil)
    }

    private static func normalizeFileNameTemplate(_ raw: String) -> String {
        var template = raw
        let replacements: [(String, String)] = [
            (#"(?i)first[ _-]?name"#, "{firstName}"),
            (#"(?i)last[ _-]?name"#, "{lastName}"),
            (#"(?i)(?:actor|performer|full)[ _-]?name|\bname\b"#, "{name}"),
            (#"(?i)role|character"#, "{role}"),
            (#"(?i)project|production|job"#, "{project}"),
            (#"(?i)side\s*#?"#, "{side}"),
            (#"(?i)scene"#, "{scene}"),
            (#"(?i)take"#, "{take}"),
            (#"(?i)song\s*title"#, "{song}")
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            template = regex.stringByReplacingMatches(in: template, range: NSRange(template.startIndex..., in: template), withTemplate: replacement)
        }
        return template
    }

    private static func extractImportantDates(in text: String, pages: [String], sources: [AuditionSource]) -> [AuditionDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var dates: [AuditionDate] = []
        for match in matches {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let lineRange = text.lineRange(for: range)
            let context = String(text[lineRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = context.lowercased()
            let hasDateContext = ["deadline", "due", "submit", "submission", "callback", "recall", "rehearsal", "audition", "dance call", "vocal call", "performance", "opening", "closing", "show date", "production", "filming", "shoot", "schedule", "dates"].contains(where: lower.contains)
            guard hasDateContext else { continue }
            let kind: AuditionDateKind
            if ["deadline", "due", "submit by", "submission", "accepted until", "tape due"].contains(where: lower.contains) {
                kind = .submissionDeadline
            } else if lower.contains("callback") || lower.contains("recall") {
                kind = .callback
            } else if lower.contains("rehearsal") {
                let priorSameLine = dates.filter { $0.label == context && $0.kind == .rehearsalStart }.count
                kind = priorSameLine == 0 ? .rehearsalStart : .rehearsalEnd
            } else if lower.contains("audition") || lower.contains("dance call") || lower.contains("vocal call") {
                kind = .audition
            } else if lower.contains("performance") || lower.contains("opening") || lower.contains("show date") {
                kind = lower.contains("closing") || lower.contains("last performance") ? .performanceEnd : .performanceStart
            } else if lower.contains("production") || lower.contains("filming") || lower.contains("shoot") {
                let priorSameLine = dates.filter { $0.label == context && $0.kind == .productionStart }.count
                kind = lower.contains("wrap") || lower.contains("end") || priorSameLine > 0 ? .productionEnd : .productionStart
            } else if lower.contains("rehearsal") {
                kind = .rehearsalEnd
            } else {
                kind = .other
            }
            let dateText = String(text[range])
            let pageIndex = pages.firstIndex { $0.range(of: dateText, options: .caseInsensitive) != nil }
            let source = pageIndex.flatMap { sources.indices.contains($0) ? sources[$0] : nil }
            dates.append(AuditionDate(kind: kind, date: date, label: context, sourceID: source?.id, pageNumber: source?.pageNumber, sourceText: String(text[range])))
        }
        return dates
    }

    /// A casting notice that says the actor may choose a character must not be converted into an
    /// arbitrary role selection, even if OCR happened to find only one role on the notice page.
    static func containsOpenRoleChoice(in text: String) -> Bool {
        firstMatch(#"(?i)\b(?:your choice|role of your choice|character of your choice|any character|choose (?:a|any) character|character you(?:'|’)d like to read|role you(?:'|’)d like to read)\b"#, in: text) != nil
    }

    /// Verifies that an extracted guidance block contains genuine director/actor instructions,
    /// rejecting company PR, boilerplate audition announcements, and generic synopses.
    private static func isValidGuidance(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("holding audition") || lower.contains("holds audition") || lower.contains("holding a casting call") {
            return false
        }
        if lower.contains("submissions will be accepted") || lower.contains("in-person auditions will be held") {
            return false
        }
        if lower.contains("for the world premiere production") {
            return false
        }
        if lower.contains("the shattered glass project") {
            return false
        }
        return true
    }

    /// Detects browser tab headers, repo paths, or window status chrome captured when scanning screen displays
    private static func isNoiseLine(_ line: String) -> Bool {
        let trimmed = clean(line)
        if trimmed.isEmpty { return false }
        // Browser tab / window chrome: e.g. "• - 100 Days Of Sv X Ineshag/Onetal X * History."
        if trimmed.contains(" X ") || trimmed.contains(" x ") || trimmed.contains(" • ") || trimmed.hasPrefix("• -") || trimmed.hasPrefix("- •") {
            if trimmed.contains("History") || trimmed.contains("/") || trimmed.contains("*") || trimmed.contains("Days Of") || trimmed.contains("localhost") {
                return true
            }
        }
        if trimmed.range(of: #"(?i)\b(?:github\.com|localhost|chrome|safari|firefox)\b"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[•\-\*\s]+[0-9]+\s+Days\s+Of\b"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"[A-Za-z0-9_\-]+/[A-Za-z0-9_\-]+\s+X\s+\*"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Normalises OCR output: unified quotes/dashes/newlines, no zero-width characters, strips display chrome noise.
    private static func tidy(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "\u{200B}", with: "")
        let filteredLines = normalized.components(separatedBy: .newlines).filter { !isNoiseLine($0) }
        return filteredLines.joined(separator: "\n")
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let g = (group < match.numberOfRanges) ? group : (match.numberOfRanges > 0 ? 0 : -1)
        guard g >= 0, match.range(at: g).location != NSNotFound,
              let r = Range(match.range(at: g), in: text) else { return nil }
        return String(text[r])
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'*_.,;:-#“"))
    }

    /// "Role: Maya", "Project - The Last Summer" — a label at the start of a line, then its value.
    private static func labeled(_ labels: [String], in text: String) -> String? {
        for label in labels {
            let pattern = #"^[\s>*•\-]*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*[:\-]\s*(.+)$"#
            if let value = firstMatch(pattern, in: text, options: [.caseInsensitive, .anchorsMatchLines]) {
                let cleaned = clean(value)
                if !cleaned.isEmpty, cleaned.count <= 150 { return cleaned }
            }
        }
        return nil
    }

    /// Prefers a date near "due / deadline / submit / by" over non-submission dates.
    /// Never falls back to arbitrary dates (such as shoot dates, publication dates, or birthdays).
    private static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))

        // OCR often drops the punctuation around times in lines such as
        // “Video submissions will be accepted until 11:59 pm on December 6, 2026”.
        // Anchor on that explicit submission wording before scanning other event dates.
        let acceptedUntil = #"(?i)\b(?:video|self[- ]?tape|tape)\s+submissions?\s+(?:will\s+be\s+)?accepted\s+(?:until|through)\s+(?:(?:by|at)\s+)?(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\s+)?(?:on\s+)?([A-Z][a-z]+\s+\d{1,2},?\s+\d{4})"#
        if let value = firstMatch(acceptedUntil, in: text) {
            let normalized = value.replacingOccurrences(of: ",", with: "")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "MMMM d yyyy"
            if let date = formatter.date(from: normalized) { return date }
        }
        let submissionKeywords = [
            "due", "deadline", "submit by", "submit before", "submission deadline", "tape due",
            "self-tape due", "send tape by", "send submissions by", "no later than", "submissions due",
            "due date", "submit no later", "turn in by",
            "accepted until", "submissions will be accepted", "video submissions", "accepted through",
            "submissions accepted", "submit your tape by", "submit by", "last day to submit",
            "last day to apply", "accept submissions until", "close on", "closes on"
        ]
        let nonDueKeywords = [
            "shoot", "shooting", "filming", "production", "principal photography", "rehearsal",
            "callback", "callbacks", "born", "birthday", "posted", "published", "notice date"
        ]

        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let line = text.lineRange(for: r)
            let context = text[line].lowercased()
            // Skip dates in lines explicitly about filming/shooting/callbacks unless explicitly about tape deadline
            if nonDueKeywords.contains(where: { context.contains($0) }) && !context.contains("tape") && !context.contains("audition") && !context.contains("due") {
                continue
            }
            if submissionKeywords.contains(where: { context.contains($0) }) {
                // NSDataDetector has a quirk where "due by November 5" can offset the parsed date.
                // Strip the preposition and evaluate the date substring directly when available.
                let matchedSub = String(text[r])
                if let stripped = firstMatch(#"(?i)(?:due\s+by|due|by|before|on|until)\s+([A-Za-z0-9,\s]+)"#, in: matchedSub) {
                    if let refinedMatch = detector.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)).first, let refinedDate = refinedMatch.date {
                        return refinedDate
                    }
                }
                if let d = match.date { return d }
            }
        }

        // Secondary pass: pick the earliest date mentioned in lines about auditions/submissions
        // when no explicit "due"/"deadline" keyword is present (e.g. "Auditions: December 7, 2026").
        var auditionDates: [Date] = []
        for match in matches {
            guard let r = Range(match.range, in: text), let d = match.date else { continue }
            let line = text.lineRange(for: r)
            let context = text[line].lowercased()
            // Skip scheduling/non-submission lines (rehearsals, callbacks, opening/closing)
            let scheduleOnly = ["rehearsal", "callback", "opening", "closing", "tech", "strike", "load-in", "meet & greet"]
            if scheduleOnly.contains(where: { context.contains($0) }) { continue }
            if context.contains("audition") || context.contains("submission") || context.contains("video") || context.contains("accepted") {
                auditionDates.append(d)
            }
        }
        if let earliest = auditionDates.min() { return earliest }

        // Support day-first formats like "5 November 2026" or "5th Nov 2026"
        let dayFirstPattern = #"(?i)\b(?:deadline|due date|submission deadline|last date to apply|submit(?:ting)? by|tape due|self-tape due(?: by)?|due by|due)\s*[:\-]?\s*(\d{1,2}(?:st|nd|rd|th)?\s+[A-Za-z]+\s+\d{4})\b"#
        if let value = firstMatch(dayFirstPattern, in: text) {
            let normalized = value.replacingOccurrences(
                of: #"(?i)(\d)(st|nd|rd|th)\b"#,
                with: "$1",
                options: .regularExpression
            ).replacingOccurrences(of: ",", with: "")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMMM yyyy"
            if let d = formatter.date(from: normalized) { return d }
            formatter.dateFormat = "d MMM yyyy"
            if let d = formatter.date(from: normalized) { return d }
        }

        // NSDataDetector can miss dates copied from HTML where the label and date are
        // separated by non-breaking spaces or punctuation.
        let labeledDatePattern = #"(?i)\b(?:deadline|due date|submission deadline|submit(?:ting)? by|tape due|self-tape due(?: by)?|due by|due)\s*[:\-]?\s*([A-Z][a-z]+ \d{1,2}(?:st|nd|rd|th)?,? \d{4})\b"#
        guard let value = firstMatch(labeledDatePattern, in: text) else { return nil }
        let normalized = value.replacingOccurrences(
            of: #"(?i)(\d)(st|nd|rd|th)\b"#,
            with: "$1",
            options: .regularExpression
        ).replacingOccurrences(of: ",", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d yyyy"
        return formatter.date(from: normalized)
    }

    /// Detects if a scene is marked optional or secondary in casting instructions or script headers.
    /// E.g. "Scene 2 (optional)", "Scene 2: prepare if time permits", "Callback scene (optional)"
    static func isSceneOptional(scene: ScriptScene, in text: String) -> Bool {
        let t = scene.title.lowercased()
        let h = scene.heading.lowercased()
        if t.contains("optional") || h.contains("optional") { return true }
        if t.contains("if time permits") || h.contains("if time permits") { return true }

        let escapedTitle = NSRegularExpression.escapedPattern(for: scene.title)
        let patterns = [
            #"(?i)\b(?:scene\s*"# + "\(scene.number)" + #"\b|"# + escapedTitle + #")[^.\n\r]*\b(optional|if time permits|callback only|not required)\b"#,
            #"(?i)\b(optional|if time permits|callback only|not required)\b[^.\n\r]*\b(?:scene\s*"# + "\(scene.number)" + #"\b|"# + escapedTitle + #")"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    /// Extracts character breakdown demographics and director notes for a specific role from sides or notice text.
    /// E.g.: "NOOR · She/her · Early 60s · Afghan American" + "Director note: What I'm looking for..."
    static func extractCharacterDescription(for role: String, in text: String) -> String? {
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let escapedRole = NSRegularExpression.escapedPattern(for: trimmedRole)
        let lines = text.components(separatedBy: .newlines)

        // Narrative character profiles may have no label or line break after the
        // name. Keep the complete profile, stopping at the next notice section.
        let prosePattern = #"(?is)\b"# + escapedRole + #"\s+is\s+(a|an)\s+(.+?)(?=\s+(?:what\s+to\s+submit|actors?\s+should\s+email|submission\s+(?:details|instructions?)|audition\s+dates?|deadline)\b|\z)"#
        if let regex = try? NSRegularExpression(pattern: prosePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let articleRange = Range(match.range(at: 1), in: text),
           let descriptionRange = Range(match.range(at: 2), in: text) {
            let article = String(text[articleRange])
            let details = String(text[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let description = clean("\(trimmedRole) is \(article) \(details)")
            if description.count > trimmedRole.count + 10 {
                return description.trimmingCharacters(in: CharacterSet(charactersIn: " .\n\r\t"))
            }
        }

        var headerLine: String?
        var headerIndex: Int?

        // 1. Look for a role header line with breakdown/demographics:
        for (idx, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard let regex = try? NSRegularExpression(pattern: #"^\s*"# + escapedRole + #"\b\s*[·—\-:]\s*(.+)$"#, options: .caseInsensitive),
                  let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
                  match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: trimmedLine) else { continue }

            let rest = String(trimmedLine[r]).trimmingCharacters(in: .whitespaces)
            if (try? NSRegularExpression(pattern: #"^(?:page|p\.)\s*\d+$"#, options: .caseInsensitive))?.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) != nil {
                continue
            }
            headerLine = trimmedLine
            headerIndex = idx
            break
        }

        // Fallback: check if role name appears on its own line followed immediately by demographics
        if headerLine == nil {
            for (idx, line) in lines.enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.caseInsensitiveCompare(trimmedRole) == .orderedSame, idx + 1 < lines.count {
                    let nextLine = lines[idx + 1].trimmingCharacters(in: .whitespaces)
                    if (try? NSRegularExpression(pattern: #"^(?:she/her|he/him|they/them|\d{1,2}s?|age|female|male|non-binary)\b"#, options: .caseInsensitive))?.firstMatch(in: nextLine, range: NSRange(nextLine.startIndex..., in: nextLine)) != nil {
                        headerLine = "\(trimmedLine) · \(nextLine)"
                        headerIndex = idx + 1
                        break
                    }
                }
            }
        }

        // 2. Look for director's note or character description following the header line
        var directorNote: String?
        if let hIdx = headerIndex {
            let maxIdx = min(lines.count, hIdx + 30)
            let subsequent = lines[(hIdx + 1)..<maxIdx].joined(separator: "\n")
            let notePattern = #"(?i)\b(?:director(?:['’]s)?\s*note|character\s*note|note)\s*[:\-]\s*([^\n]+(?:\n(?!\s*(?:SLATE|THE\s+SIDE|SIDE\s+[A-Z]|SCENE|INT\.|EXT\.|[A-Z]{3,}\s*[·—\-:]))[^\n]+)*)"#
            if let regex = try? NSRegularExpression(pattern: notePattern, options: []),
               let match = regex.firstMatch(in: subsequent, range: NSRange(subsequent.startIndex..., in: subsequent)),
               let r = Range(match.range, in: subsequent) {
                directorNote = String(subsequent[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 3. Fallback for general casting notice format:
        if headerLine == nil && directorNote == nil {
            let generalPattern = #"(?im)^\s*"# + escapedRole + #"\s*[:\-]\s*([^\n]+(?:\n(?!\s*(?:[A-Z]{3,}\b|SCENE|DEADLINE|AUDITION))[^\n]+){0,4})"#
            if let regex = try? NSRegularExpression(pattern: generalPattern, options: []),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(match.range, in: text) {
                let candidate = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.lowercased().contains("page ") {
                    return candidate
                }
            }
        }

        var parts: [String] = []
        if let h = headerLine, !h.isEmpty { parts.append(h) }
        if let note = directorNote, !note.isEmpty { parts.append(note) }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Detects all candidate roles mentioned in a casting notice, prioritizing explicit roles, industry tiers, and demographic breakdowns.
    static func detectCandidateRoles(in text: String) -> [String] {
        var roles: [String] = []

        let invalidRoleNames: Set<String> = [
            "multiple roles", "multiple role", "each character", "separate video", "a separate video",
            "all roles", "any role", "both roles", "various roles", "other characters", "the role",
            "your role", "this role", "character", "cast", "setting", "settings", "director note", "slate instruction",
            "what to submit", "submission requirements", "audition requirements", "requirements", "role details", "character details",
            "how to use these sides", "casting sides", "audition sides", "dialogue sides", "sides",
            "female identifying", "male identifying", "for female identifying", "for male identifying", "for any gender", "any gender",
            "your choice", "character of your choice", "the character of your choice", "a character of your choice"
        ]

        func addRole(_ r: String) {
            let cleaned = clean(r)
            guard !cleaned.isEmpty, !roles.contains(cleaned) else { return }
            let lower = cleaned.lowercased()
            guard !invalidRoleNames.contains(lower) else { return }
            let base = cleaned.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? cleaned
            if base.lowercased() != "male" && base.lowercased() != "female" {
                guard !ScriptParser.isBlacklistedNoticeWord(base) else { return }
            }
            roles.append(cleaned)
        }

        // Prose character profiles often have no "Role:" label or breakdown heading.
        // Example: "Alice is a 12–13-year-old girl who is introverted ...".
        let proseCharacterPattern = #"(?i)\b([A-Z][A-Za-z'’\-]{1,24})\s+is\s+(?:a|an)\s+(?:\d{1,2}\s*[-–]\s*\d{1,2}[- ]year[- ]old\s+)?(?:girl|boy|woman|man|child|teenager|teen|person)\b"#
        if let regex = try? NSRegularExpression(pattern: proseCharacterPattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    addRole(String(text[range]))
                }
            }
        }

        // 0. Audition sides page breakdown table (e.g. Grease style breakdown)
        let bdPattern = #"(?is)(?:Audition\s+Sides\s+Page\s+Breakdown|Sides\s+Page\s+Breakdown|Sides\s+Breakdown)\s*[:\n](.*?)(?=\n\s*\d+\s*\n|\n==|\z)"#
        if let regex = try? NSRegularExpression(pattern: bdPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let block = text[range]
            for line in block.components(separatedBy: .newlines) {
                let trimmed = clean(line)
                if trimmed.isEmpty || trimmed.lowercased().contains("please familiarise") { continue }
                let charSection: String
                if let actRange = trimmed.range(of: #"\bACT\b"#, options: [.caseInsensitive, .regularExpression]) {
                    charSection = String(trimmed[..<actRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else if let pageRange = trimmed.range(of: #"\bPAGE\b"#, options: [.caseInsensitive, .regularExpression]) {
                    charSection = String(trimmed[..<pageRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else {
                    charSection = trimmed
                }
                for piece in charSection.components(separatedBy: CharacterSet(charactersIn: ",&/")) {
                    let name = clean(piece)
                    if name.count >= 2 && !invalidRoleNames.contains(name.lowercased()) {
                        addRole(name.capitalized)
                    }
                }
            }
        }

        // 1. Character index list in sides packet: "THE CHARACTERS IN THIS DOCUMENT\nNOOR — Page 2\n..."
        let pageListPattern = #"(?m)^([A-Z][A-Za-z0-9'\-]{1,20})\s*[-–—]\s*(?:Page|Pg\.?)\s*\d+"#
        if let pageRegex = try? NSRegularExpression(pattern: pageListPattern) {
            let matches = pageRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range(at: 1), in: text) {
                    let name = clean(String(text[r]))
                    if !invalidRoleNames.contains(name.lowercased()) {
                        addRole(name.capitalized)
                    }
                }
            }
        }

        // Monologue / character sides cues: e.g. "Roxie:\n", "Velma:\n", "Mama Morton:\n"
        let cueLinesPattern = #"(?m)^([A-Z][A-Za-z\s'\-]{1,24}):\s*$"#
        if let r = try? NSRegularExpression(pattern: cueLinesPattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            let nonCueTitles: Set<String> = [
                "audition sides", "for female identifying", "for male identifying", "for any gender",
                "setting", "settings", "director note", "note", "slate", "instructions",
                "stage reading event", "reading event", "event", "dates", "date", "shoot dates", "shoot date",
                "production dates", "rehearsal dates", "submission specs", "specs", "location", "deadline"
            ]
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    let candidate = clean(String(text[range]))
                    let lower = candidate.lowercased()
                    if !nonCueTitles.contains(lower) && !invalidRoleNames.contains(lower) && !lower.contains("event") && !lower.contains("dates") && !lower.contains("specs") {
                        addRole(candidate.capitalized)
                    }
                }
            }
        }

        // 2. Character headers on sides pages: "NOOR · She/her · Early 60s"
        let headerPattern = #"(?m)^([A-Z]{2,20})\s*[·•|\-—]\s*(?:(?:He|She|They)/|[0-9]{1,2}s?\b|Early|Mid|Late)"#
        if let r = try? NSRegularExpression(pattern: headerPattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    addRole(String(text[range]).capitalized)
                }
            }
        }

        // 2b. Theatre/stage character breakdown format (Title Case names):
        //     "Maggie - F, 40s. a prostitute; ..."
        //     "Francis - F, 40s. a rancher; ..."
        //     Matches: Name - [M|F|NB|Male|Female|Non-binary], [age] [description]
        //     Also matches "Character Breakdowns" section lists like "Maggie\nF, 40s. ..."
        let theatreBreakdownPattern = #"(?m)^([A-Z][a-z]{1,22}(?:\s+[A-Z][a-z]{1,22})?)\s*[-–—]\s*(?:[FfMmNn][A-Za-z]*(?:on-binary)?)[,.]?\s*(?:\d{1,2}s?\b|Early|Mid|Late|teens?|\d{1,2})"#
        if let r = try? NSRegularExpression(pattern: theatreBreakdownPattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    let name = clean(String(text[range]))
                    if name.count >= 2 && !invalidRoleNames.contains(name.lowercased()) {
                        addRole(name.capitalized)
                    }
                }
            }
        }

        // 2c. "Character Breakdowns" section: standalone role name lines followed by demographics on the next line
        //     e.g. "Character Breakdowns\nMaggie\nF, 40s. ..."
        let breakdownSectionPattern = #"(?is)(?:character\s+breakdowns?|breakdowns?|characters?)\s*\n(.*?)(?=\n\s*(?:note|production|audition|submission|when|how|deadline|\z))"#
        if let r = try? NSRegularExpression(pattern: breakdownSectionPattern),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range(at: 1), in: text) {
            let block = String(text[range])
            // Within the section pick lines that look like character names (Title Case, 2-20 chars)
            for line in block.components(separatedBy: .newlines) {
                let candidate = clean(line)
                guard candidate.count >= 2, candidate.count <= 25 else { continue }
                // Must be a simple Title Case word or two words
                if candidate.range(of: #"^[A-Z][a-z]{1,20}(?:\s+[A-Z][a-z]{1,20})?$"#, options: .regularExpression) != nil {
                    if !invalidRoleNames.contains(candidate.lowercased()) {
                        addRole(candidate)
                    }
                }
            }
        }

        // 3. Slate instruction character: "the role you are reading for (NOOR)"
        let slatePattern = #"(?i)reading\s+for\s*\(([A-Za-z]{2,20})\)"#
        if let r = try? NSRegularExpression(pattern: slatePattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    addRole(String(text[range]).capitalized)
                }
            }
        }

        // Casting webpages often list role names as standalone lines under a
        // "The Characters" heading, without screenplay-style age or pronoun metadata.
        let characterSectionPattern = #"(?is)\bthe\s+characters\b\s*(.*?)(?=\bcasting\s+sides\b|\bvideo\s+submission\b|\z)"#
        if let r = try? NSRegularExpression(pattern: characterSectionPattern),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range(at: 1), in: text) {
            for line in text[range].components(separatedBy: .newlines) {
                let candidate = clean(line)
                if candidate.range(of: #"^[A-Z][A-Za-z'\-]{1,20}$"#, options: .regularExpression) != nil {
                    addRole(candidate.capitalized)
                }
            }
        }

        // 4. Explicit labeled roles: "Role: Maya", "Character: Arjun".
        // Scan every labeled line (not just the first value) and strip parenthetical
        // casting metadata such as "(Lead, 30s)" from the display name.
        let explicitRolePattern = #"(?im)^\s*(?:role|character|part|playing)\s*:\s*([^\n]+)"#
        if let regex = try? NSRegularExpression(pattern: explicitRolePattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                var roleVal = clean(String(text[valueRange]))
                if let paren = roleVal.firstIndex(of: "(") {
                    roleVal = String(roleVal[..<paren]).trimmingCharacters(in: .whitespaces)
                }
                if let delim = roleVal.range(of: #"\s*(?:[,;–—]|\s*-\s*|\s+(?:who|aged|is|described\s+as)\b).*"#, options: .regularExpression) {
                    roleVal = String(roleVal[..<delim.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                addRole(roleVal.capitalized)
            }
        }

        // Fallback for inline or non-colon labels: "Role Maya", "Character — Arjun".
        if let v = labeled(["role", "character", "part", "playing"], in: text) {
            var roleVal = clean(v)
            if let delim = roleVal.range(of: #"\s*(?:[,;–—]|\s*-\s*|\s+(?:who|aged|is|described\s+as)\b).*"#, options: .regularExpression) {
                let prefix = String(roleVal[..<delim.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty { roleVal = prefix }
            }
            addRole(roleVal.capitalized)
        }

        // 5. Specific character phrasing: "reading for Maya", "role of Kat"
        let name = #"([A-Za-z][A-Za-z.'\-]*(?:\s+[A-Za-z][A-Za-z.'\-]*){0,2}?)"#
        let stop = #"(?=\s+(?:in|on|by|for|from|at|to)\b|\s*[,.;:\n(]|\s*$)"#
        let lead = #"\b(?:role\s+of|part\s+of|character\s+of|playing|audition(?:ing)?\s+for|reading\s+for|self-?tape\s+for|submitting\s+for)\s+(?:the\s+)?(?:role\s+of\s+)?"#
        if let v = firstMatch(lead + name + stop, in: text, options: [.caseInsensitive, .anchorsMatchLines]) {
            let cleaned = clean(v)
            let lower = cleaned.lowercased()
            // Skip generic/vague phrases like "your choice", "a character of your choice"
            let isVague = lower.contains("your choice") || lower.contains("any character") || lower.contains("the character")
            if !cleaned.isEmpty, !lower.hasPrefix("age"), !lower.hasPrefix("a "), !isVague {
                addRole(cleaned.capitalized)
            }
        }
        if let v = firstMatch(#"\bfor\s+(?:the\s+role\s+of\s+)?([A-Z][A-Z\-]{1,22})\b"#, in: text) {
            let lowerV = v.lowercased()
            if !invalidRoleNames.contains(lowerV) && lowerV != "female" && lowerV != "male" && lowerV != "any" {
                addRole(v.capitalized)
            }
        }

        // 6. Standard industry role tiers (Lead, Supporting, Series Regular)
        let tierPattern = #"\b(female\s+lead|male\s+lead|lead\s+female|lead\s+male|lead\s+actress|lead\s+actor|supporting\s+actor|supporting\s+actress|supporting\s+lead|series\s+regular)\b"#
        if let regex = try? NSRegularExpression(pattern: tierPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range, in: text) {
                    var tier = clean(String(text[r])).capitalized
                    if let age = firstMatch(#"(?:age(?:\s+group)?|aged?)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs))?)"#, in: text, options: .caseInsensitive) {
                        let cleanedAge = clean(age)
                        if !tier.contains(cleanedAge) { tier += " (\(cleanedAge))" }
                    }
                    addRole(tier)
                }
            }
        }

        // 7. Demographic breakdowns in casting notices:
        // "Male Age: 20-40 years", "Female Age: 22-60 years", "Male: 20-40", "Female: 20-40", "Boy Age: 8-12", "Girl Age: 8-12"
        let demoPattern = #"(?i)\b(male|female|boy|girl|man|woman)\s*(?:actor|actress|age)?\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs|year old))?)"#
        if let regex = try? NSRegularExpression(pattern: demoPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                guard let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { continue }
                let gender = String(text[r1]).capitalized
                let age = clean(String(text[r2]))
                let roleTitle = "\(gender) Actor (\(age))"
                addRole(roleTitle)
            }
        }

        // 7b. Tabular / Columnar demographic breakdowns (e.g. Casting Bay flyer style):
        // AGE \n 18 - 23 years \n AGE \n 45 - 55 years \n GENDER \n Female \n GENDER \n Male
        var detectedAges: [String] = []
        if let ageRegex = try? NSRegularExpression(pattern: #"(?i)(?:^|\b|\n)(?:age|age\s*group)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs|year old))?)"#) {
            let matches = ageRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range(at: 1), in: text) {
                    let a = clean(String(text[r]))
                    if !detectedAges.contains(a) { detectedAges.append(a) }
                }
            }
        }
        var detectedGenders: [String] = []
        if let genRegex = try? NSRegularExpression(pattern: #"(?i)(?:^|\b|\n)(?:gender|sex)\s*[:\-]?\s*(male|female|boy|girl|man|woman)\b"#) {
            let matches = genRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range(at: 1), in: text) {
                    let g = clean(String(text[r])).capitalized
                    if !detectedGenders.contains(g) { detectedGenders.append(g) }
                }
            }
        }
        if !detectedAges.isEmpty && !detectedGenders.isEmpty {
            let count = min(detectedAges.count, detectedGenders.count)
            for i in 0..<count {
                let rTitle = "\(detectedGenders[i]) (\(detectedAges[i]))"
                addRole(rTitle)
            }
        }

        // 8. Seeking/looking for — strict validation so acting directions/adjectives never become roles
        let nonRoleWords: Set<String> = [
            "passionate", "grounded", "authentic", "talented", "experienced", "fresh", "creative",
            "charismatic", "diverse", "local", "real", "natural", "subtle", "dynamic", "versatile",
            "submissions", "actors", "actresses", "performers", "artists", "talent", "people",
            "individuals", "faces", "new faces", "all ethnicities", "any ethnicity", "upcoming project"
        ]
        let seekLead = #"\b(?:looking\s+for|seeking|cast(?:ing)?\s+for|in\s+search\s+of)\s+(?:a\s+|an\s+)?([A-Za-z0-9\s\-/]{2,30}?)(?=\s+(?:for|in|as|who|aged?)\b|\s*[,.;:\n])"#
        if let v = firstMatch(seekLead, in: text, options: .caseInsensitive) {
            let cleaned = clean(v)
            let lower = cleaned.lowercased()
            let firstWord = lower.components(separatedBy: .whitespaces).first ?? ""
            let isNonRole = nonRoleWords.contains(lower) || nonRoleWords.contains(firstWord)
            let isDemographicOnly = lower.hasPrefix("age") || lower.contains("year old") || lower.contains("yrs old") || lower.range(of: #"^\d{1,2}\s*[-–]"#, options: .regularExpression) != nil
            if !cleaned.isEmpty && !isNonRole && !isDemographicOnly && !roles.contains(where: { $0.lowercased().contains(cleaned.lowercased()) }) {
                var res = cleaned.capitalized
                if let age = firstMatch(#"(?:age(?:\s+group)?|aged?)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs))?)"#, in: text, options: .caseInsensitive) {
                    let cleanedAge = clean(age)
                    if !res.contains(cleanedAge) { res += " (\(cleanedAge))" }
                }
                addRole(res)
            }
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

    private static func detectRole(in text: String) -> String? {
        detectCandidateRoles(in: text).first
    }

    private static func detectLocation(in text: String) -> String? {
        if let v = labeled(["location", "city", "venue", "place", "based in", "shoot location"], in: text) {
            return clean(v).capitalized
        }
        for city in ["Bengaluru", "Bangalore", "Mumbai", "Delhi", "New Delhi", "Hyderabad", "Chennai", "Kolkata", "Pune", "Goa", "Jaipur", "Kochi", "New York", "Los Angeles", "London", "Toronto", "Vancouver"] {
            let pattern = #"(?i)\b(?:location|in|at)\s*[:\-]?\s*"# + city + #"\b"#
            if firstMatch(pattern, in: text) != nil {
                return city
            }
        }
        return nil
    }

    private static func isGenericHeadline(_ s: String) -> Bool {
        let lower = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—*\"' \t\r\n"))
        let words = [
            "casting", "audition", "sides", "notice", "call", "how to use", "page", "scene", "script",
            "breakdown", "character", "characters", "urgent", "open call", "casting call", "casting notice",
            "urgent casting", "commercial", "feature film", "theatre", "confidential", "for audition use only",
            "do not distribute", "not for distribution", "all rights reserved", "property of", "untitled"
        ]
        return words.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ":") })
    }

    private static func isSluglineOrScene(_ s: String) -> Bool {
        let upper = s.uppercased().trimmingCharacters(in: .whitespaces)
        let prefixes = ["INT.", "EXT.", "INT/EXT", "EXT/INT", "I/E", "INT ", "EXT ", "SCENE ", "SC.", "ACT "]
        return prefixes.contains(where: { upper.hasPrefix($0) })
    }

    /// Labeled "Project:" / "Title:", explicit project folder, prominent header, then "in THE LAST SUMMER (feature)".
    /// Never returns scene headings, character names, casting office names, dates, or watermarks.
    private static func detectProject(in text: String) -> String? {
        func cleanTitle(_ s: String) -> String? {
            var title = clean(s)
            guard !title.isEmpty, title.count >= 2, title.count <= 50 else { return nil }
            if isNoiseLine(title) || isSluglineOrScene(title) { return nil }
            // Strip leading prefixes like "Casting Call:", "Casting Notice:", "Project:", "Audition Call:"
            let prefixes = [
                #"(?i)^casting\s+call\s*[:\-]\s*"#,
                #"(?i)^casting\s+notice\s*[:\-]\s*"#,
                #"(?i)^now\s+casting\s*[:\-]\s*"#,
                #"(?i)^urgent\s+casting\s*[:\-]\s*"#,
                #"(?i)^project\s*[:\-]\s*"#,
                #"(?i)^audition\s*(?:call|notice)?\s*[:\-]\s*"#
            ]
            for p in prefixes {
                if let r = title.range(of: p, options: .regularExpression) {
                    title = String(title[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
            if isGenericHeadline(title) { return nil }
            let lower = title.lowercased()
            if lower.hasPrefix("role:") || lower.hasPrefix("character:") || lower.hasPrefix("part:") || lower.hasPrefix("sides:") || lower.hasPrefix("download:") || lower.hasPrefix("due:") { return nil }
            if lower.hasSuffix("casting") || lower.contains("casting director") || lower.contains("page ") { return nil }
            // Clean trailing role information e.g. "The Last Summer - Role of Maya" -> "The Last Summer"
            if let idx = title.range(of: #"\s*[-–—]\s*(?:Role|Part|Character)\b.*"#, options: .regularExpression) {
                title = String(title[..<idx.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return title.isEmpty ? nil : title.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }

        // Resolve the play title before a generic “in …” match can mistake its synopsis
        // (“in a small western town…”) for the project name.
        if let title = firstMatch(#"(?i)\bworld\s+premiere\s+production\s+of\s+([^,\n.]{2,50})"#, in: text),
           let valid = cleanTitle(title) {
            return valid
        }

        // Premier/world-premiere phrasing: e.g. "world premiere production of Eve's Ale"
        // Also handles: "premiere of X", "production of X", "staging of X"
        let premierePhrases = [
            #"(?i)\b(?:world\s+premiere|world\s+premiere\s+production|premiere\s+production|premiere)\s+of\s+([A-Za-z0-9'&,\s\-]{2,45}?)(?=\s*[,.\n(]|\s+by\b|\s*$)"#,
            #"(?i)\b(?:production\s+of|staging\s+of|adaptation\s+of|revival\s+of)\s+([A-Za-z0-9'&,\s\-]{2,45}?)(?=\s*[,.\n(]|\s+by\b|\s+a\b|\s*$)"#,
        ]
        for pattern in premierePhrases {
            if let v = firstMatch(pattern, in: text), let valid = cleanTitle(v.trimmingCharacters(in: .whitespaces)) {
                return valid
            }
        }

        // Show / musical / production phrasing: e.g. "GREASE is such a fun production"
        let showPattern = #"(?i)\b([A-Z][A-Za-z0-9 '\-]{2,25})\s+is\s+(?:a|an|such\s+a)\s+(?:fun\s+)?(?:production|musical|play|film|movie|show|series|theatrical)\b"#
        if let showMatch = firstMatch(showPattern, in: text), let valid = cleanTitle(showMatch) {
            return valid
        }

        // Catchy banner phrasing: e.g. "ROXIE ROCKS CHICAGO."
        let bannerPattern = #"(?i)\b[A-Za-z]+\s+ROCKS\s+([A-Za-z0-9'\-]{2,30})\b"#
        if let bannerMatch = firstMatch(bannerPattern, in: text), let valid = cleanTitle(bannerMatch) {
            return valid
        }

        // 1. Explicit high-confidence call line: "Casting Call: Ad Film", "Now Casting: <Title>"
        if let callMatch = firstMatch(#"(?im)^(?:casting\s+call|now\s+casting|urgent\s+casting)\s*[:\-]\s*([A-Za-z0-9\s'&,\-]{2,40})$"#, in: text),
           let valid = cleanTitle(callMatch) {
            return valid
        }

        // 2. Explicitly labeled: "Project: ...", "Title: ...", "Project folder \"...\""
        if let v = firstMatch(#"(?:project\s+folder|project(?:\s+name|\s+title)?|title|film\s+title|series\s+title|show\s+title)\s*[:\-]?\s*["“]([^"”\n]+)["”]"#, in: text, options: .caseInsensitive),
           let valid = cleanTitle(v) {
            return valid
        }
        if let v = labeled(["project name", "project title", "film title", "series title", "show title", "project folder", "title", "project"], in: text),
           let valid = cleanTitle(v) {
            return valid
        }

        // 3. Quoted title when the notice explicitly calls it a subject, folder, or title
        if let v = firstMatch(#"\bmention\s+["“]([^"”\n]{2,45})["”]\s+in\s+(?:the\s+)?(?:email\s+)?subject\b"#, in: text, options: .caseInsensitive),
           let valid = cleanTitle(v) {
            return valid
        }
        if let v = firstMatch(#"(?:subject|folder|titled|called|project)\s*[:\-]?\s*["“]([^"”\n]{2,45})["”]"#, in: text, options: .caseInsensitive),
           let valid = cleanTitle(v) {
            return valid
        }

        // 4. Prominent project title immediately preceding "CASTING SIDES", "AUDITION SIDES", "CASTING NOTICE", "CASTING CALL"
        let lines = text.components(separatedBy: .newlines).map { clean($0) }.filter { !$0.isEmpty }
        let sideKeywords = ["CASTING SIDES", "AUDITION SIDES", "CASTING NOTICE", "CASTING CALL", "AUDITION NOTICE", "SIDES"]

        // Web casting pages commonly put the title between the call label and the venue,
        // rather than on a standalone line before "CASTING SIDES".
        if let first = lines.first,
           let match = first.range(of: #"(?i)^casting\s+call\s*[-–—:]\s*([^|]+?)(?:\s*\|.*)?$"#, options: .regularExpression) {
            let candidate = String(first[match]).replacingOccurrences(
                of: #"(?i)^casting\s+call\s*[-–—:]\s*|\s*\|.*$"#,
                with: "",
                options: .regularExpression
            )
            if let valid = cleanTitle(candidate) { return valid }
        }
        if lines.count > 2, lines[1].lowercased().contains("for the new play"),
           let valid = cleanTitle(lines[2]) {
            return valid
        }

        for i in 0..<min(lines.count - 1, 8) {
            let line = lines[i]
            let nextLine = lines[i + 1].uppercased()
            if sideKeywords.contains(where: { nextLine == $0 || nextLine.hasPrefix($0 + " ") || nextLine.hasPrefix($0 + "-") }) {
                if !line.lowercased().hasPrefix("role:") && !line.lowercased().hasPrefix("character:") {
                    if let valid = cleanTitle(line) {
                        return valid
                    }
                }
            }
        }

        // 5. First line if standalone title followed by author or casting metadata
        if let firstLine = lines.first, !isNoiseLine(firstLine), let valid = cleanTitle(firstLine) {
            let lower = text.lowercased()
            if lower.contains("casting") || lower.contains("sides") || lower.contains("audition") {
                if lines.count > 1 {
                    let secondLine = lines[1].uppercased()
                    if secondLine.contains("CASTING") || secondLine.contains("SIDES") || secondLine.contains("BY ") || secondLine.contains("&") || secondLine.contains("DIRECTOR") {
                        return valid
                    }
                }
            }
        }

        // 6. Specific project phrasing: "Self-tape for MAYA in THE LAST SUMMER (feature)"
        let inPattern = #"(?i)\b(?:audition(?:ing)?\s+for|self-?tape\s+for|reading\s+for)\s+[A-Za-z0-9'\-]+\s+in\s+([A-Z][A-Za-z0-9'&, \-]{2,40}?)(?=\s*[\(.,]|\s+by\b|\s*$)"#
        if let v = firstMatch(inPattern, in: text), let valid = cleanTitle(v) {
            return valid
        }
        // This fallback intentionally requires an all-caps title. A case-insensitive
        // `[A-Z]` also matches lowercase text and used to turn synopsis phrases such as
        // “in a small western town...” into the project name.
        if let v = firstMatch(#"\bin\s+([A-Z][A-Z0-9'&, \-]{2,40}?)(?=\s*[\(.,]|\s+by\b|\s*$)"#, in: text),
           let valid = cleanTitle(v), detectLocation(in: valid) == nil {
            return valid
        }

        // 7. Standalone project mention e.g. "AD FILM" at bottom or header
        if let adFilm = firstMatch(#"(?im)^[\s>*•\-\[\]]*AD\s+FILM[\s>*•\-\[\]]*$"#, in: text) {
            let _ = adFilm
            return "Ad Film"
        }

        return nil
    }

    private static func detectCastingOffice(in text: String) -> String? {
        let genericCastingWords: Set<String> = [
            "casting", "casting call", "casting notice", "urgent casting", "open casting", "open call",
            "commercial casting", "theatrical casting", "film casting", "feature film casting", "series casting",
            "tv casting", "television casting", "child casting", "voice casting", "worldwide casting", "online casting",
            "self-tape casting", "sides casting", "audition casting", "actors casting", "acting", "audition",
            "casting call bengaluru", "casting call mumbai", "casting call delhi", "bengaluru casting",
            "mumbai casting", "delhi casting", "london casting", "nyc casting", "la casting", "los angeles casting",
            "history casting", "now casting", "casting now",
            // Section-header phrases that contain "casting" but are not company names:
            "note on casting", "a note on casting", "casting note", "note casting"
        ]

        // Acronym or compound casting companies like Mukesh Chhabra Casting Company (MCCC)
        if firstMatch(#"(?i)\b(Mukesh\s+Chhabra\s+Casting\s+Company(?:\s*\(MCCC\))?|MCCC)\b"#, in: text) != nil {
            return "Mukesh Chhabra Casting Company (MCCC)"
        }

        if let office = labeled(["casting director", "casting office", "casting company", "casting agency", "casting by"], in: text) {
            let cleaned = clean(office)
            let lower = cleaned.lowercased()
            let isEditorialNote = lower.hasPrefix("note on casting") || lower.hasPrefix("a note on casting")
            if !cleaned.isEmpty && !isEditorialNote && !genericCastingWords.contains(lower) && !isNoiseLine(cleaned) {
                return cleaned.capitalized
            }
        }

        // Check for "Casting <Name>" (e.g. "Casting Bay", "Casting Collective", "Casting Works")
        if let v = firstMatch(#"(?im)^[\s>*•\-]*Casting[ \t]+([A-Z][A-Za-z0-9\-]+)(?:'|\b)"#, in: text) {
            let full = "Casting \(clean(v))"
            let lower = full.lowercased().replacingOccurrences(of: "\n", with: " ")
            if !genericCastingWords.contains(lower) && !lower.contains("call") && !lower.contains("notice") && !lower.contains("director") && !lower.contains("mumbai") {
                return full.capitalized
            }
        }
        if let v = firstMatch(#"\b(Casting[ \t]+[A-Z][A-Za-z0-9\-]+)\b"#, in: text) {
            let lower = v.lowercased().replacingOccurrences(of: "\n", with: " ")
            if !genericCastingWords.contains(lower) && !lower.contains("call") && !lower.contains("notice") && !lower.contains("director") && !lower.contains("sides") && !lower.contains("mumbai") {
                return clean(v).capitalized
            }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = clean(rawLine)
            let lower = line.lowercased()
            if lower.hasSuffix("casting") &&
                !genericCastingWords.contains(lower) &&
                !lower.contains("casting call") &&
                !lower.contains("casting sides") &&
                !lower.contains("download casting") &&
                !lower.contains("theater lab") &&
                !lower.contains("the lab") &&
                !lower.contains("pilgrimage casting") &&
                !lower.hasPrefix("note on") &&
                !lower.hasPrefix("a note on") &&
                !lower.hasPrefix("note:") &&
                !isNoiseLine(line) &&
                line.count <= 45 {
                return line.capitalized
            }
        }
        if let v = firstMatch(#"\b((?:[A-Z][A-Za-z0-9\-]+[ \t]+){1,2}Casting)\b"#, in: text, options: .caseInsensitive) {
            let cleaned = clean(v).replacingOccurrences(of: ".", with: "-")
            let lower = cleaned.lowercased()
            if !lower.hasPrefix("note on casting") && !lower.hasPrefix("a note on casting") &&
                !genericCastingWords.contains(lower) &&
                !lower.contains("casting call") &&
                !lower.contains("casting sides") &&
                !lower.contains("download casting") &&
                !lower.contains("pilgrimage casting") &&
                !isNoiseLine(cleaned) {
                return cleaned.capitalized
            }
        }
        if let v = firstMatch(#"@([A-Za-z0-9\-]+casting)\.[a-z]+"#, in: text, options: .caseInsensitive) {
            return clean(v).capitalized
        }
        // Match casting portal domain e.g. "apply at castingbay.app" -> "Casting Bay"
        if let domain = firstMatch(#"(?i)\b(?:apply\s+at\s+|visit\s+)?([a-z0-9\-]+casting|casting[a-z0-9\-]+)\.(?:app|com|in|co|org|net|io)\b"#, in: text) {
            let lowerDomain = domain.lowercased()
            if lowerDomain.hasPrefix("casting") {
                let name = String(lowerDomain.dropFirst("casting".count))
                if !name.isEmpty {
                    return "Casting \(name.capitalized)"
                }
            }
        }
        return nil
    }

    /// "Sides attached (2 scenes)" — any "<N> scene(s)" mention.
    private static func detectSceneCount(in text: String) -> Int? {
        guard let v = firstMatch(#"(\d+)\s+scenes?"#, in: text, options: .caseInsensitive) else { return nil }
        return Int(v)
    }

    /// "under 3 minutes", "no more than 2 min", "max 5 minutes".
    private static func detectLengthLimit(in text: String) -> Int? {
        let pattern = #"(?:under|less than|no more than|max(?:imum)?(?: of)?|up to|within)\s+(\d{1,2})\s*(?:min|minute)"#
        guard let v = firstMatch(pattern, in: text, options: .caseInsensitive) else { return nil }
        return Int(v)
    }

    /// Context-aware link classifier that inspects the text and labels immediately before each URL
    /// to determine whether each link is intended for tape upload/submission or for script sides/audition material.
    private static func detectClassifiedLinks(in text: String) -> (sidesLink: String?, submissionLink: String?) {
        let urlPattern = #"(?i)\b((?:https?:\/\/|www\.)[^\s<>"'\)]+|[a-zA-Z0-9.\-]+\.(?:com|org|net|io|in|co|us|uk|ca|gov|edu|me|ly|gl)\/[^\s<>"'\)]*)"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return (nil, nil) }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var sidesLink: String?
        var submissionLink: String?

        let uploadKeywords = [
            "upload", "upload tape", "upload your tape", "upload audition", "upload video", "upload here",
            "submit", "submit tape", "submit audition", "submit your tape", "submit here", "submission",
            "submission link", "submission form", "submission url", "send tape", "send your tape",
            "send audition", "send submissions", "send video", "apply", "apply here", "application form",
            "audition form", "tape link", "form to submit", "google form", "tape upload", "turn in",
            "drop tape", "share your tape", "link to submit", "link for tape", "link for submission"
        ]

        let sidesKeywords = [
            "sides", "sides link", "sides url", "sides folder", "audition sides", "dialogue sides", "casting sides",
            "script", "script link", "script url", "script folder", "full script", "screenplay", "lines",
            "download sides", "download script", "download scenes", "download material", "download lines",
            "scenes", "scene material", "audition material", "material link", "reading material", "packet",
            "find sides", "access sides", "sides attached", "sides available", "drive link for sides",
            "sides can be found", "script attached", "scene sides", "materials"
        ]

        for m in matches {
            guard let r = Range(m.range, in: text) else { continue }
            let link = clean(String(text[r]))
            guard !link.contains("@") else { continue }

            // 1. Inspect text immediately preceding this link (same line + preceding line, up to 160 characters)
            let lineRange = text.lineRange(for: r)

            var priorLine = ""
            if lineRange.lowerBound > text.startIndex {
                let prevIdx = text.index(before: lineRange.lowerBound)
                let prevLineRange = text.lineRange(for: prevIdx..<prevIdx)
                priorLine = String(text[prevLineRange]).lowercased()
            }

            let startOffset = max(text.startIndex, text.index(r.lowerBound, offsetBy: -160, limitedBy: text.startIndex) ?? text.startIndex)
            let contextBefore = String(text[startOffset..<r.lowerBound]).lowercased()

            // 2. Check for upload vs sides keywords in the preceding context
            var hasUpload = false
            var lastUploadIdx = -1
            for kw in uploadKeywords {
                if let range = contextBefore.range(of: kw, options: .backwards) {
                    hasUpload = true
                    let dist = contextBefore.distance(from: contextBefore.startIndex, to: range.lowerBound)
                    lastUploadIdx = max(lastUploadIdx, dist)
                } else if priorLine.contains(kw) {
                    hasUpload = true
                    lastUploadIdx = max(lastUploadIdx, 0)
                }
            }

            var hasSides = false
            var lastSidesIdx = -1
            for kw in sidesKeywords {
                if let range = contextBefore.range(of: kw, options: .backwards) {
                    hasSides = true
                    let dist = contextBefore.distance(from: contextBefore.startIndex, to: range.lowerBound)
                    lastSidesIdx = max(lastSidesIdx, dist)
                } else if priorLine.contains(kw) {
                    hasSides = true
                    lastSidesIdx = max(lastSidesIdx, 0)
                }
            }

            // 3. Classify based on text preceding the link
            if hasUpload && !hasSides {
                if submissionLink == nil { submissionLink = link }
            } else if hasSides && !hasUpload {
                if sidesLink == nil { sidesLink = link }
            } else if hasUpload && hasSides {
                // If both keywords appear, the keyword closest to the link wins
                if lastUploadIdx >= lastSidesIdx {
                    if submissionLink == nil { submissionLink = link }
                } else {
                    if sidesLink == nil { sidesLink = link }
                }
            } else {
                // 4. Neither keyword in preceding text: fall back to domain/service heuristics
                let lowerLink = link.lowercased()
                if lowerLink.contains("forms.gle") || lowerLink.contains("docs.google.com/forms") ||
                   lowerLink.contains("typeform.com") || lowerLink.contains("airtable.com") {
                    if submissionLink == nil { submissionLink = link }
                } else if lowerLink.contains("drive.google.com") || lowerLink.contains("docs.google.com/document") ||
                          lowerLink.contains("dropbox.com") || lowerLink.contains("1drv.ms") ||
                          lowerLink.contains("onedrive.live.com") || lowerLink.contains("box.com") {
                    if sidesLink == nil { sidesLink = link }
                } else {
                    // Check URL path clues
                    if lowerLink.contains("upload") || lowerLink.contains("submit") || lowerLink.contains("form") || lowerLink.contains("apply") {
                        if submissionLink == nil { submissionLink = link }
                    } else if lowerLink.contains("side") || lowerLink.contains("script") || lowerLink.contains("material") || lowerLink.contains("scene") {
                        if sidesLink == nil { sidesLink = link }
                    } else if submissionLink == nil {
                        submissionLink = link
                    }
                }
            }
        }

        return (sidesLink, submissionLink)
    }

    private static func detectSidesLink(in text: String) -> String? {
        detectClassifiedLinks(in: text).sidesLink
    }
}

// MARK: - Interactive Script Review & 1-Tap Line Editor ("Magic Highlighter")

struct ScriptReviewAndEditView: View {
    @Binding var scenes: [ScriptScene]
    @State private var editingLine: (sceneIndex: Int, lineIndex: Int)?
    @State private var editedText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { sIdx, scene in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(scene.heading)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(OT.accent)
                        Spacer()
                        Text("\(scene.lines.count) lines · ≈ \(scene.estimatedSeconds / 60):\(String(format: "%02d", scene.estimatedSeconds % 60))")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    .padding(.bottom, 2)

                    ForEach(Array(scene.lines.enumerated()), id: \.element.id) { lIdx, line in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 8) {
                                // 1-Tap Role Toggle Pill
                                Button {
                                    toggleSpeaker(sceneIndex: sIdx, lineIndex: lIdx)
                                    Haptics.tick()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: line.isMine ? "person.crop.circle.fill" : "person.2.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(line.isMine ? "\(line.character) (YOU)" : "\(line.character)")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(line.isMine ? OT.accentSoft : OT.reader.opacity(0.15))
                                            .overlay(
                                                Capsule().stroke(line.isMine ? OT.accent.opacity(0.35) : OT.reader.opacity(0.35), lineWidth: 1)
                                            )
                                    )
                                    .foregroundStyle(line.isMine ? OT.accent : OT.reader)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                // Merge with above button (if not first line)
                                if lIdx > 0 {
                                    Button {
                                        mergeWithAbove(sceneIndex: sIdx, lineIndex: lIdx)
                                        Haptics.tick()
                                    } label: {
                                        Image(systemName: "arrow.turn.left.up")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(OT.labelTertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Merge with above line")
                                }

                                // Delete line button
                                Button {
                                    deleteLine(sceneIndex: sIdx, lineIndex: lIdx)
                                    Haptics.tick()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(OT.labelTertiary.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete line")
                            }

                            // Editable Line Text
                            if line.isSilentReactionCue {
                                Button {
                                    editingLine = (sIdx, lIdx)
                                    editedText = line.text
                                } label: {
                                    SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: false)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(line.text)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(OT.labelPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(line.isMine ? OT.accentSoft.opacity(0.35) : OT.fillField)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(line.isMine ? OT.accent.opacity(0.25) : OT.separator.opacity(0.5), lineWidth: 1)
                                    )
                                    .onTapGesture {
                                        editingLine = (sIdx, lIdx)
                                        editedText = line.text
                                    }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(14)
                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(OT.separator, lineWidth: 1))
            }
        }
        .sheet(item: Binding(
            get: { editingLine.map { EditLinePayload(sceneIndex: $0.sceneIndex, lineIndex: $0.lineIndex) } },
            set: { if $0 == nil { editingLine = nil } }
        )) { payload in
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Edit Line Text")
                        .font(.otHeadline)
                        .padding(.top, 16)

                    TextEditor(text: $editedText)
                        .foregroundStyle(OT.labelPrimary)
                        .tint(OT.accent)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
                        .frame(minHeight: 120)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            editingLine = nil
                        }
                        .buttonStyle(.otSecondary)

                        Button("Save") {
                            if scenes.indices.contains(payload.sceneIndex),
                               scenes[payload.sceneIndex].lines.indices.contains(payload.lineIndex) {
                                scenes[payload.sceneIndex].lines[payload.lineIndex].text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            editingLine = nil
                            Haptics.success()
                        }
                        .buttonStyle(.otPrimary)
                    }
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .padding()
                .preferredColorScheme(.dark)
            }
            .presentationDetents([.height(300)])
        }
    }

    private func toggleSpeaker(sceneIndex: Int, lineIndex: Int) {
        guard scenes.indices.contains(sceneIndex),
              scenes[sceneIndex].lines.indices.contains(lineIndex) else { return }
        scenes[sceneIndex].lines[lineIndex].isMine.toggle()
    }

    private func deleteLine(sceneIndex: Int, lineIndex: Int) {
        guard scenes.indices.contains(sceneIndex),
              scenes[sceneIndex].lines.indices.contains(lineIndex) else { return }
        scenes[sceneIndex].lines.remove(at: lineIndex)
    }

    private func mergeWithAbove(sceneIndex: Int, lineIndex: Int) {
        guard scenes.indices.contains(sceneIndex),
              scenes[sceneIndex].lines.indices.contains(lineIndex),
              lineIndex > 0 else { return }
        let current = scenes[sceneIndex].lines[lineIndex]
        scenes[sceneIndex].lines[lineIndex - 1].text += " " + current.text
        scenes[sceneIndex].lines.remove(at: lineIndex)
    }
}

private struct EditLinePayload: Identifiable {
    var id: String { "\(sceneIndex)_\(lineIndex)" }
    let sceneIndex: Int
    let lineIndex: Int
}

// MARK: - 6.1 Draft sides sheet (Add or replace sides during audition creation)

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
        // `editableScenes` is refreshed after a short debounce. Calling the parser as a
        // computed fallback here would still parse the whole packet during every keystroke.
        editableScenes
    }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(
                title: draft.hasSides ? "Replace sides" : "Add sides",
                backLabel: "Cancel",
                onBack: { dismiss() }
            ) {
                Button(draft.hasSides ? "Replace" : "Add") {
                    commitSides()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 16) {
                    if let sidesLink = draft.sidesLink, !sidesLink.isEmpty {
                        sidesLinkCard(sidesLink)
                    }

                    // 4 Action Buttons Grid (replaces long text rows)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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
                                color: Color(uiColor: .systemIndigo)
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
                                color: Color(uiColor: .systemPurple)
                            )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(selection: $photoItems, matching: .images) {
                            SidesInputTile(
                                icon: "photo.on.rectangle",
                                title: "Photos",
                                subtitle: "Camera roll",
                                color: Color(uiColor: .systemTeal)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if reading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading pages and parsing sides…")
                                .font(.otSubhead)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                    }

                    // Script Text Area Card (Clean, centered, beautifully bordered)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SCRIPT TEXT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OT.labelSecondary)
                            Spacer()
                            if !text.isEmpty {
                                Button("Clear") {
                                    withAnimation {
                                        text = ""
                                        editableScenes = []
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OT.danger)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Or type/paste sides directly here...\nCues should be in CAPS (e.g. MAYA) or “Maya: dialogue”.")
                                    .font(.otCallout)
                                    .foregroundStyle(OT.labelTertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }

                            ScriptTextEditor(text: $text)
                                .frame(minHeight: 140, maxHeight: 220)
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
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                    }

                    // Detected from sides section
                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("DETECTED SIDES")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(OT.labelSecondary)
                                Spacer()
                                Text("Tap speaker or text to edit")
                                    .font(.system(size: 11))
                                    .foregroundStyle(OT.labelTertiary)
                            }

                            if !activeScenes.isEmpty {
                                HStack(spacing: 8) {
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
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(OT.labelTertiary)
                                    Text("No character lines recognised yet. Cues should be in CAPS (e.g. “MAYA”) or “Maya: dialogue”.")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelTertiary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, OT.gutter)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(draft.hasSides ? "Replace sides" : "Add sides") {
                    commitSides()
                }
                .buttonStyle(.otPrimary)
                .padding(.horizontal, OT.gutter)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
                        Task { @MainActor in reading = false }
                    }
                    let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)
                    await MainActor.run {
                        if let extracted, !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let cleaned = ScriptParser.cleanPastedText(extracted)
                            text = cleaned
                            editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: draft.role)
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
                        editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: draft.role)
                        reading = false
                        Haptics.success()
                    }
                }
            }
            .ignoresSafeArea()
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
                    editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: draft.role)
                    reading = false
                    photoItems = []
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
            editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: draft.role)
            Haptics.success()
        } else {
            emptyClipboardAlert = true
            Haptics.warning()
        }
    }

    private func commitSides() {
        draft.sourceText = text
        draft.customScenes = activeScenes
        if !activeScenes.isEmpty {
            draft.scenes = max(activeScenes.count, draft.scenes)
        }
        dismiss()
    }

    private func openScanner() {
        if VNDocumentCameraViewController.isSupported { showScanner = true } else { scannerUnavailable = true }
    }

    @ViewBuilder
    private func sidesLinkCard(_ sidesLink: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: sidesLink.contains("drive.google") ? "externaldrive.fill.badge.icloud" : "link")
                    .foregroundStyle(OT.accent)
                Text(sidesLink.contains("drive.google") ? "Google Drive sides attached" : "Sides link attached")
                    .font(.otHeadline)
            }
            Text("Open the link to download the PDF or copy script text, then import or paste it below.")
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
            if let url = URL(string: sidesLink.hasPrefix("http") ? sidesLink : "https://\(sidesLink)") {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("Open sides in browser")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
    }
}

// MARK: - 6.2 Missing details

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

    private var hasReaderLines: Bool {
        guard !store.auditionDraft.role.isEmpty, store.auditionDraft.hasSides else { return false }
        let parsed = store.auditionDraft.customScenes?.isEmpty == false
            ? store.auditionDraft.customScenes!
            : ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
        return parsed.contains { $0.lines.contains { !$0.isMine } }
    }

    private var missing: [String] { store.auditionDraft.missingRequiredDetails }

    private var missingSubtitle: String {
        if missing.isEmpty { return "Everything needed is ready." }
        if missing.count == 1 { return "I couldn't find the \(missing[0]) in the notice. Add it to continue." }
        if missing.count == 2 { return "I couldn't find the \(missing[0]) and \(missing[1]) in the notice. Add what you know to continue." }
        let allButLast = missing.dropLast().joined(separator: ", ")
        return "I couldn't find the \(allButLast), and \(missing.last!) in the notice. Add what you know to continue."
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            InContentNavHeader(backLabel: "Back", onBack: {
                store.popToRoot()
                store.pendingRouteAfterAdd = nil
                store.continueAfterAdd = nil
                store.showAddAudition = true
            })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(missing.isEmpty ? "All set" : missing.count == 1 ? "One thing missing" : "A few details missing")
                        .font(.otLargeTitle)
                    Text(missingSubtitle)
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Audition name").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                                if showValidationErrors && isProjectEmpty {
                                    Spacer()
                                    Text("Required").font(.otCaption.weight(.semibold)).foregroundStyle(Color.red)
                                }
                            }
                            Text("A label to help you find this casting call in your audition list.")
                                .font(.otCaption).foregroundStyle(OT.labelTertiary)
                            TextField("e.g. Alice audition", text: $store.auditionDraft.project)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .project)
                                .padding(12)
                                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(showValidationErrors && isProjectEmpty ? Color.red.opacity(0.8) : Color.clear, lineWidth: 1.5)
                                )

                            if showValidationErrors && isProjectEmpty {
                                Label("Please enter an audition name to continue", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Which role are you auditioning for?").font(.otCaption.weight(.bold)).foregroundStyle(OT.labelPrimary)
                                Spacer()
                                if showValidationErrors && isRoleEmpty {
                                    Text("Required").font(.otCaption.weight(.semibold)).foregroundStyle(Color.red)
                                }
                            }
                            Text("Select your character so OneTake knows which lines are yours to speak and which belong to your reader.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                            if !availableRoles.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
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
                                                HStack(spacing: 6) {
                                                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "person.fill")
                                                        .font(.system(size: 13, weight: .bold))
                                                    Text(char)
                                                        .font(.otSubhead.weight(isCurrent ? .bold : .semibold))
                                                }
                                                .foregroundStyle(isCurrent ? Color.white : OT.accent)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 9)
                                                .background(isCurrent ? OT.accent : OT.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }

                                if store.auditionDraft.hasSides && !store.auditionDraft.role.isEmpty {
                                    let parsed = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                                    let myLinesCount = parsed.flatMap(\.lines).filter(\.isMine).count
                                    let readerLines = parsed.flatMap(\.lines).filter { !$0.isMine }
                                    let readerLinesCount = readerLines.count
                                    let readerNames = Array(Set(readerLines.map { $0.character.capitalized })).sorted()

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
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
                                            HStack(spacing: 8) {
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
                                            HStack(spacing: 8) {
                                                Image(systemName: "sparkles")
                                                    .font(.caption)
                                                    .foregroundStyle(OT.labelTertiary)
                                                Text("Solo side · no reader lines needed")
                                                    .font(.otFootnote)
                                                    .foregroundStyle(OT.labelSecondary)
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            } else {
                                Label("No character names were found in the notice or script. Enter your role below.", systemImage: "text.magnifyingglass")
                                    .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                                TextField("e.g. Maya", text: $store.auditionDraft.role)
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .role)
                                    .padding(12)
                                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(showValidationErrors && isRoleEmpty ? Color.red.opacity(0.8) : Color.clear, lineWidth: 1.5)
                                    )
                            }

                            if showValidationErrors && isRoleEmpty {
                                Label("Please select or enter the character or role you are reading for", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Casting office (optional)").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                            TextField("e.g. Anti-Casting, Telsey + Co", text: $store.auditionDraft.castingOffice)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .castingOffice)
                                .padding(12)
                                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("When is it due?").font(.otHeadline)
                                Spacer()
                                DatePicker("Due date", selection: $picked, in: Date.now...)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Quick time")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        presetTimeChip("5:00 PM") { setPickedTime(hour: 17, minute: 0) }
                                        presetTimeChip("10:00 AM") { setPickedTime(hour: 10, minute: 0) }
                                        presetTimeChip("12:00 PM") { setPickedTime(hour: 12, minute: 0) }
                                        presetTimeChip("11:59 PM") { setPickedTime(hour: 23, minute: 59) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .otCard(radius: 20)

                    SectionLabel(text: "Script Sides")
                    let parsedScenes = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                    if parsedScenes.isEmpty {
                        if let sidesLink = store.auditionDraft.sidesLink, !sidesLink.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Image(systemName: sidesLink.contains("drive.google") ? "externaldrive.fill.badge.icloud" : "link.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(OT.accent)
                                        .frame(width: 34, height: 34)
                                        .background(OT.accentSoft, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
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
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .fixedSize()
                                }

                                if let url = URL(string: sidesLink.hasPrefix("http") ? sidesLink : "https://\(sidesLink)") {
                                    Link(destination: url) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "safari")
                                            Text("Open \(sidesLink.contains("drive.google") ? "Google Drive link" : "Sides link")")
                                            Image(systemName: "arrow.up.right")
                                        }
                                        .font(.otCaption.weight(.semibold))
                                        .foregroundStyle(OT.accent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(OT.accentSoft.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                            }
                            .padding(14)
                            .otCard(radius: 20)
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(OT.accent)
                                    .frame(width: 34, height: 34)
                                    .background(OT.accentSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
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
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(OT.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .fixedSize()
                            }
                            .padding(14)
                            .otCard(radius: 20)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OT.success)
                            let myCount = parsedScenes.flatMap(\.lines).filter(\.isMine).count
                            let readerCount = parsedScenes.flatMap(\.lines).filter { !$0.isMine }.count
                            VStack(alignment: .leading, spacing: 2) {
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
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .fixedSize()
                        }
                        .padding(14)
                        .otCard(radius: 20)
                    }

                    Button("Choose a different notice") {
                        store.pop()
                        store.showAddAudition = true
                    }
                    .buttonStyle(.plain)
                    .font(.otCallout)
                    .foregroundStyle(OT.accent)
                    .padding(.top, 8)
                }
                .padding(.horizontal, OT.gutter)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if showValidationErrors && !canContinue {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.red)
                        Text(isProjectEmpty && isRoleEmpty
                             ? "Audition name and character are required"
                             : (isProjectEmpty ? "Audition name is required" : "Your character is required"))
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(Color.red)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12), in: Capsule())
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
                .buttonStyle(.otPrimary)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 10)
            .background(OT.bgCanvas)
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
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

// MARK: - 6c Here's what they want (review + save)

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
        VStack(spacing: 0) {
            InContentNavHeader(backLabel: store.auditionsPath.contains(.missingDetails) ? "Back" : "Auditions", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Here's what they want").font(.otLargeTitle)
                    Text(store.auditionDraft.asks.isEmpty
                         ? "No recording requirements were detected. Review the details, then save."
                         : "\(store.auditionDraft.asks.count) requirement\(store.auditionDraft.asks.count == 1 ? "" : "s") found in the email. Tap any line to change it, then save.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)

                    SectionLabel(text: "Audition Type")
                    AuditionMaterialKindPicker(selected: $store.auditionDraft.materialKind)

                    SectionLabel(text: "Due")
                    if let due = store.auditionDraft.due {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.otTitle)
                            Text(due.formatted(date: .omitted, time: .shortened)).font(.otHeadline).foregroundStyle(OT.due)
                        }
                    } else {
                        DatePicker("Due", selection: Binding(get: { store.auditionDraft.due ?? .now.addingTimeInterval(86400) }, set: { store.auditionDraft.due = $0 })).labelsHidden()
                    }

                    if !store.auditionDraft.importantDates.isEmpty {
                        SectionLabel(text: "Milestone Dates")
                        MilestoneDatesListCard(dates: store.auditionDraft.importantDates)
                    }

                    SectionLabel(text: "Sides & Scenes")
                    let parsedScenes = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                    if store.auditionDraft.materialKind == .slateOnly {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OT.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Slate & Intro Only")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("No script dialogue required for this casting call")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if store.auditionDraft.materialKind == .monologue {
                        HStack(spacing: 12) {
                            Image(systemName: "person.wave.2.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OT.accent)
                            VStack(alignment: .leading, spacing: 2) {
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
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if store.auditionDraft.materialKind == .song || store.auditionDraft.materialKind == .movement {
                        HStack(spacing: 12) {
                            Image(systemName: store.auditionDraft.materialKind == .song ? "music.note" : "figure.dance")
                                .font(.system(size: 18))
                                .foregroundStyle(OT.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.auditionDraft.materialKind == .song ? "Vocal Audition Track" : "Physical / Dance Audition")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Recorded in full with framing guides and audio monitoring")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if parsedScenes.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(OT.accent)
                                .frame(width: 34, height: 34)
                                .background(OT.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
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
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .fixedSize()
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OT.success)
                            let myCount = parsedScenes.flatMap(\.lines).filter(\.isMine).count
                            let readerCount = parsedScenes.flatMap(\.lines).filter { !$0.isMine }.count
                            VStack(alignment: .leading, spacing: 2) {
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
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .fixedSize()
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    SectionLabel(text: "Requested by casting")
                    if !store.auditionDraft.aiGuidance.isEmpty {
                        Label(store.auditionDraft.aiGuidance, systemImage: "sparkles")
                            .font(.otCallout).foregroundStyle(OT.labelSecondary)
                            .padding(14).background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(OT.accent).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.auditionDraft.role.isEmpty ? "Character not selected" : "Your character: \(store.auditionDraft.role)")
                                    .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                                Text(store.auditionDraft.hasSides
                                     ? "\(store.auditionDraft.scenes) scene\(store.auditionDraft.scenes == 1 ? "" : "s") with lines found"
                                     : "No script sides are attached")
                                    .font(.otCaption).foregroundStyle(OT.labelSecondary)
                            }
                        }
                        ForEach(Array(store.auditionDraft.asks.enumerated()), id: \.offset) { _, ask in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: symbol(for: ask)).foregroundStyle(OT.accent).frame(width: 20)
                                Text(ask).font(.otFootnote).foregroundStyle(OT.labelPrimary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if store.auditionDraft.asks.contains(where: { $0.localizedCaseInsensitiveContains("resume") || $0.localizedCaseInsensitiveContains("résumé") }) {
                        AuditionResumePicker(
                            isIncluded: $store.auditionDraft.includeResume,
                            selectedURL: $store.auditionDraft.resumeURL
                        )
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Audition name").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                                if showValidationErrors && isProjectEmpty {
                                    Spacer()
                                    Text("Required").font(.otCaption.weight(.semibold)).foregroundStyle(Color.red)
                                }
                            }
                            Text("A label to help you find this casting call in your audition list.")
                                .font(.otCaption).foregroundStyle(OT.labelTertiary)
                            TextField("e.g. Alice audition", text: $store.auditionDraft.project)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .project)
                                .padding(12)
                                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(showValidationErrors && isProjectEmpty ? Color.red.opacity(0.8) : Color.clear, lineWidth: 1.5)
                                )

                            if showValidationErrors && isProjectEmpty {
                                Label("Please enter an audition name", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                            Text("Which character are you auditioning for?").font(.otCaption.weight(.bold)).foregroundStyle(OT.labelPrimary)
                                Spacer()
                                if showValidationErrors && isRoleEmpty {
                                    Text("Required").font(.otCaption.weight(.semibold)).foregroundStyle(Color.red)
                                }
                            }
                            Text("Choose the character named in the notice or script. This tells OneTake which dialogue is yours.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                            if !store.auditionDraft.roleBreakdowns.isEmpty {
                                VStack(spacing: 8) {
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
                                    HStack(spacing: 8) {
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
                                                HStack(spacing: 6) {
                                                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "person.fill")
                                                        .font(.system(size: 13, weight: .bold))
                                                    Text(char)
                                                        .font(.otSubhead.weight(isCurrent ? .bold : .semibold))
                                                }
                                                .foregroundStyle(isCurrent ? Color.white : OT.accent)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 9)
                                                .background(isCurrent ? OT.accent : OT.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }

                            if store.auditionDraft.hasSides && !store.auditionDraft.role.isEmpty {
                                let parsed = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                                let myLinesCount = parsed.flatMap(\.lines).filter(\.isMine).count
                                let readerLines = parsed.flatMap(\.lines).filter { !$0.isMine }
                                let readerLinesCount = readerLines.count
                                let readerNames = Array(Set(readerLines.map { $0.character.capitalized })).sorted()

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
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
                                        HStack(spacing: 8) {
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
                                        HStack(spacing: 8) {
                                            Image(systemName: "sparkles")
                                                .font(.caption)
                                                .foregroundStyle(OT.labelTertiary)
                                            Text("Solo side · no reader lines needed")
                                                .font(.otFootnote)
                                                .foregroundStyle(OT.labelSecondary)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            if availableRoles.isEmpty && store.auditionDraft.roleBreakdowns.isEmpty {
                                TextField("Your character", text: $store.auditionDraft.role)
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .role)
                                    .padding(12)
                                    .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(showValidationErrors && isRoleEmpty ? Color.red.opacity(0.8) : Color.clear, lineWidth: 1.5)
                                    )
                            }

                            if showValidationErrors && isRoleEmpty {
                                Label("Please select or enter your character or role", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red)
                            }
                        }

                        DisclosureGroup("Add a casting contact (optional)") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("This is the office or person’s name. Enter the submission email below.")
                                    .font(.otCaption).foregroundStyle(OT.labelTertiary)
                                TextField("Casting office or contact", text: $store.auditionDraft.castingOffice)
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .castingOffice)
                                    .padding(12)
                                    .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .padding(.top, 8)
                        }
                        .tint(OT.accent)

                        if let selectedScenes = store.auditionDraft.customScenes, !selectedScenes.isEmpty {
                            Label("\(selectedScenes.count) scene\(selectedScenes.count == 1 ? "" : "s") chosen", systemImage: "checkmark.circle.fill")
                                .font(.otFootnote.weight(.medium))
                                .foregroundStyle(OT.success)
                        } else if store.auditionDraft.hasSides {
                            Stepper("Scenes to prepare: \(store.auditionDraft.scenes)", value: $store.auditionDraft.scenes, in: 0...6)
                                .padding(.top, 4)
                        } else {
                            Label("No scene sides were included in this notice", systemImage: "doc.text")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                    }
                    .padding(16)
                    .otCard(radius: 20)

                    if let details = store.auditionDraft.projectDetails, details.hasReviewableContent {
                        ProjectDetailsCard(details: details)
                    }

                    SectionLabel(text: "Delivery & Destination")
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Destination", selection: $store.auditionDraft.destination) {
                            ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)

                        TextField(
                            store.auditionDraft.destination == .emailOrLink
                                ? "Email address or submission link"
                                : "\(store.auditionDraft.destination.rawValue) account or submission notes",
                            text: Binding(
                                get: { store.auditionDraft.destinationDetail ?? "" },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    store.auditionDraft.destinationDetail = trimmed.isEmpty ? nil : trimmed
                                }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(store.auditionDraft.destination == .emailOrLink ? .emailAddress : .default)
                        .padding(12)
                        .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(16)
                    .otCard(radius: 20)

                    SectionLabel(text: "Notes for this audition")
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Character details from casting").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                            Text("The character description or direction copied from the notice.")
                                .font(.otCaption).foregroundStyle(OT.labelTertiary)
                            TextField("Character breakdown, director notes", text: Binding(
                                get: { store.auditionDraft.castingNotes ?? "" },
                                set: { store.auditionDraft.castingNotes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                            ), axis: .vertical)
                            .lineLimit(4...10)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("My notes & understanding").font(.otCaption.weight(.medium)).foregroundStyle(OT.labelSecondary)
                            TextField("Scene objective, choices, subtext", text: Binding(
                                get: { store.auditionDraft.actorNotes ?? "" },
                                set: { store.auditionDraft.actorNotes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                            ), axis: .vertical)
                            .padding(12)
                            .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(16)
                    .otCard(radius: 20)

                    SectionLabel(text: "What to prepare")
                    VStack(alignment: .leading, spacing: 12) {
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
                    .padding(16)
                    .otCard(radius: 20)

                    if hasReaderLines {
                        SectionLabel(text: "Practice cues")
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
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
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                }
                .padding(.horizontal, OT.gutter)
                .padding(.top, 14)
                .padding(.bottom, 100)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if showValidationErrors && !canSave {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.red)
                        Text(isProjectEmpty && isRoleEmpty
                             ? "Audition name and character are required"
                             : (isProjectEmpty ? "Audition name is required" : "Your character is required"))
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(Color.red)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .transition(.opacity.combined(with: .scale))
                }

                Button(hasReaderLines && readerAudioPlan == .recordNow ? "Save & record practice cues" : "Save and start") {
                    saveAudition()
                }
                .buttonStyle(.otPrimary)
            }
            .padding(.horizontal, OT.gutter).padding(.bottom, 8)
            .background(OT.bgCanvas)
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
            // Push .reader onto the stack so tapping Back on "Who reads [role]" returns here!
            store.push(.reader(auditionID, sceneIndex: firstScene))
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
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OT.accent)
                .frame(width: 32, height: 32)
                .background(OT.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
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
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isOptional.wrappedValue ? OT.surfaceSunken : OT.accentSoft, in: Capsule())
            .foregroundStyle(isOptional.wrappedValue ? OT.labelSecondary : OT.accent)
            .accessibilityLabel("\(title), \(isOptional.wrappedValue ? "optional" : "required"). Tap to change.")
        }
        .frame(minHeight: 48)
    }

    private func field(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(OT.labelSecondary)
            Text(title).font(.otHeadline)
            if !detail.isEmpty { Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary) }
        }
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

// MARK: - S4 Notice couldn't be read

struct NoticeErrorView: View {
    var onRetry: () -> Void
    var onScan: () -> Void
    var onType: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(OT.warning)
            Text("We couldn't read this notice").font(.otLargeTitle)
            Text("No readable text was found — it may be a photo without text, blurry, or very small print. Nothing was lost — pick how to continue.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            Button(action: onRetry) { IconRow(symbol: "arrow.clockwise", title: "Try again", detail: "Go back and pick the photo, scan or file again") }.buttonStyle(.plain)
            Button(action: onScan) { IconRow(symbol: "doc.viewfinder", title: "Scan the pages instead", detail: "Clearer than a screenshot") }.buttonStyle(.plain)
            Button(action: onType) { IconRow(symbol: "keyboard", title: "Type the details", detail: "Name, role and due date — 30 seconds") }.buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, OT.gutter)
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}
