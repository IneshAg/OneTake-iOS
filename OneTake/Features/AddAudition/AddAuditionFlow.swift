import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import UserNotifications
import PDFKit
import OneTakeUI

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
    @State private var importError: NoticeImportError?
    @State private var emptyClipboardAlert = false
    /// Parsed draft pending the actor's review — shown in OCRReviewSheet before being committed.
    @State private var pendingReviewDraft: NoticeParser.Draft? = nil
    @State private var isProcessing = false
    @State private var processingTitle = "Processing notice & sides…"
    @State private var processingStatus = "Reading pages and extracting roles…"
    @State private var detents: Set<PresentationDetent> = [.height(315)]
    @State private var selectedDetent: PresentationDetent = .height(315)
    @Namespace private var reviewMorphNamespace

    var body: some View {
        Group {
            if let draft = pendingReviewDraft {
                OCRReviewSheet(draft: draft, sourcePreview: pendingReviewImage) { confirmedDraft, readerPlan in
                    pendingReviewDraft = nil
                    pendingReviewImage = nil
                    if confirmedDraft.missingRequiredDetails.isEmpty {
                        store.commitAuditionDraft(confirmedDraft, readerAudioPlan: readerPlan)
                    } else {
                        store.startAuditionDraft(confirmedDraft)
                    }
                } onDiscard: {
                    withAnimation(OTMotion.smooth) {
                        pendingReviewDraft = nil
                        pendingReviewImage = nil
                        detents = [.height(315)]
                        selectedDetent = .height(315)
                    }
                }
                .matchedGeometryEffect(id: "addAuditionContainer", in: reviewMorphNamespace)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if isProcessing {
                processingView
                    .matchedGeometryEffect(id: "addAuditionContainer", in: reviewMorphNamespace)
                    .transition(.opacity)
            } else {
                capture
                    .matchedGeometryEffect(id: "addAuditionContainer", in: reviewMorphNamespace)
                    .transition(.opacity)
            }
        }
        .animation(OTMotion.smooth, value: pendingReviewDraft != nil)
        .animation(OTMotion.smooth, value: isProcessing)
        .presentationDetents(detents, selection: $selectedDetent)
        .presentationDragIndicator(pendingReviewDraft != nil ? .visible : .hidden)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                isProcessing = true
                processingTitle = "Scanning \(pages.count) \(pages.count == 1 ? "page" : "pages")…"
                processingStatus = "Recognizing text and analyzing layout…"
                Task {
                    let pageTexts = await NoticeOCR.recognizePages(in: pages)
                    let text = pageTexts.joined(separator: "\n\n")
                    if !NoticeOCR.looksReadable(text) {
                        await MainActor.run {
                            isProcessing = false
                            unreadableNoticeError = true
                        }
                    } else {
                        await MainActor.run {
                            processingStatus = "Parsing project, roles, and sides…"
                        }
                        let draft = await NoticeParser.parseAsync(text, pages: pageTexts, sourceDocuments: [AuditionSource(name: "Scanned notice", kind: .castingNotice, pageCount: pageTexts.count)])
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await MainActor.run {
                            isProcessing = false
                            pendingReviewImage = pages.first
                            withAnimation(OTMotion.smooth) {
                                detents = [.large]
                                selectedDetent = .large
                                pendingReviewDraft = draft
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: NoticeOCR.supportedImportContentTypes) { result in
            switch result {
            case .success(let url):
                isProcessing = true
                processingTitle = "Reading \(url.lastPathComponent)…"
                processingStatus = "Extracting text and analyzing page layout…"
                pendingReviewImage = nil
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                let pdfPreview = resolved.url.pathExtension.lowercased() == "pdf"
                    ? PDFDocument(url: resolved.url)?.page(at: 0)?.thumbnail(of: CGSize(width: 1200, height: 1600), for: .mediaBox) // ot-lint:allow
                    : nil
                Task {
                    defer { resolved.cleanup() }
                    do {
                        let doc = try await NoticeOCR.extractLayoutDocument(fromFileAt: resolved.url)
                        await MainActor.run {
                            processingStatus = "Parsing project, roles, and sides…"
                        }
                        let draft = await NoticeParser.parseAsync(
                            doc.fullText,
                            pages: doc.reconstructedPages,
                            sourceDocuments: [AuditionSource(name: resolved.url.lastPathComponent, kind: .castingNotice, url: resolved.url, pageCount: doc.pageCount)]
                        )
                        await MainActor.run {
                            isProcessing = false
                            pendingReviewImage = pdfPreview
                            withAnimation(OTMotion.smooth) {
                                detents = [.large]
                                selectedDetent = .large
                                pendingReviewDraft = draft
                            }
                        }
                    } catch let error as NoticeImportError {
                        await MainActor.run {
                            isProcessing = false
                            importError = error
                        }
                    } catch {
                        await MainActor.run {
                            isProcessing = false
                            unreadableNoticeError = true
                        }
                    }
                }
            case .failure:
                isProcessing = false
                unreadableNoticeError = true
            }
        }
        .alert(
            importErrorTitle,
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("Type details") {
                importError = nil
                store.startAuditionDraft(NoticeParser.Draft.blank)
            }
            Button("Cancel", role: .cancel) { importError = nil }
        } message: {
            Text(importError?.localizedDescription ?? "This file couldn't be imported.")
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
            isProcessing = true
            processingTitle = "Scanning photo…"
            processingStatus = "Recognizing text and casting notice details…"
            pendingReviewImage = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    await MainActor.run {
                        isProcessing = false
                        unreadableNoticeError = true
                    }
                    return
                }
                let text = await NoticeOCR.recognizeText(in: [image])
                if !NoticeOCR.looksReadable(text) {
                    await MainActor.run {
                        isProcessing = false
                        unreadableNoticeError = true
                    }
                } else {
                    await MainActor.run {
                        processingStatus = "Extracting casting details and sides…"
                    }
                    let draft = await NoticeParser.parseAsync(text, pages: [text])
                    await MainActor.run {
                        isProcessing = false
                        pendingReviewImage = image
                        withAnimation(OTMotion.smooth) {
                            detents = [.large]
                            selectedDetent = .large
                            pendingReviewDraft = draft
                        }
                    }
                }
            }
        }
    }

    private var importErrorTitle: String {
        switch importError {
        case .encryptedPDF: return "This PDF is locked"
        case .corruptDocument: return "We couldn't read this file"
        case .unsupportedFormat, .none: return "Unsupported file format"
        }
    }

    private func openScanner() {
        if VNDocumentCameraViewController.isSupported { showScanner = true } else { scannerUnavailable = true }
    }

    private func readSharedNotice() async {
        guard let item = store.incomingShare else { return }
        await MainActor.run {
            isProcessing = true
            processingTitle = "Importing shared notice…"
            processingStatus = "Extracting document contents…"
        }
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
            await MainActor.run {
                isProcessing = false
                unreadableNoticeError = true
            }
        } else {
            await MainActor.run {
                processingStatus = "Parsing project, roles, and sides…"
            }
            let draft = await NoticeParser.parseAsync(text, pages: pageTexts, sourceDocuments: sourceDocuments)
            await MainActor.run {
                isProcessing = false
                pendingReviewImage = images.first
                withAnimation(OTMotion.smooth) {
                    detents = [.large]
                    selectedDetent = .large
                    pendingReviewDraft = draft
                }
            }
        }
    }

    private func handlePasteNotice(providedText: String? = nil) {
        let raw = providedText ?? UIPasteboard.general.string ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emptyClipboardAlert = true
            Haptics.tick()
        } else {
            Haptics.success()
            isProcessing = true
            processingTitle = "Processing pasted text…"
            processingStatus = "Parsing project, roles, and sides…"
            let cleaned = ScriptParser.cleanPastedText(trimmed)
            Task {
                let draft = await NoticeParser.parseAsync(cleaned)
                await MainActor.run {
                    isProcessing = false
                    withAnimation(OTMotion.smooth) {
                        detents = [.large]
                        selectedDetent = .large
                        pendingReviewDraft = draft
                    }
                }
            }
        }
    }

    private var processingView: some View {
        NavigationStack {
            VStack(spacing: OTSpace.l) {
                Spacer()

                VStack(spacing: OTSpace.m) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(OT.accent)

                    VStack(spacing: OTSpace.xs) {
                        Text(processingTitle)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                            .multilineTextAlignment(.center)

                        Text(processingStatus)
                            .font(.otSubhead)
                            .foregroundStyle(OT.labelSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, OTSpace.gutter)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .otCanvas()
            .navigationTitle("Reading audition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isProcessing = false
                        dismiss()
                    }
                }
            }
        }
    }

    private var capture: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    Button {
                        handlePasteNotice()
                    } label: {
                        HStack(spacing: OTSpace.m) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.otIcon(.m))
                                .foregroundStyle(OT.accent)
                                .frame(width: 40, height: 40) // ot-lint:allow
                                .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))

                            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                Text("Copied notice or sides?")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Tap to paste breakdown, email, or sides")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }

                            Spacer()

                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                                    .font(.otCaption.weight(.bold))
                                Text("Paste")
                                    .font(.otCaption.weight(.bold))
                            }
                            .padding(.horizontal, OTSpace.m)
                            .padding(.vertical, OTSpace.xs)
                            .background(OT.accent, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                            .foregroundStyle(OT.labelOnAccent)
                        }
                        .padding(OTSpace.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OT.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    OTSectionLabel("Or bring in notice or sides")
                    HStack {
                        PhotosPicker(selection: $photoItem, matching: .images) { way("photo", "Photo") }
                        Button { openScanner() } label: { way("doc.viewfinder", "Scan") }
                        Button { showFileImporter = true } label: { way("folder", "File") }
                        Button { store.startAuditionDraft(NoticeParser.Draft.blank, directToReview: true) } label: { way("keyboard", "Type it") }
                    }
                    .buttonStyle(.plain)

                    Label("Faster: in Mail or WhatsApp, Share → OneTake", systemImage: "square.and.arrow.up")
                        .font(.otFootnote).foregroundStyle(OT.accent)
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.xs)
                .padding(.bottom, OTSpace.m)
            }
            .scrollBounceBehavior(.basedOnSize)
            .otCanvas()
            .navigationTitle("Add an audition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func way(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: OTSpace.xs) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(OT.labelPrimary)
                .frame(width: 52, height: 52) // ot-lint:allow
                .background(OT.fillField, in: Circle()) // ot-lint:allow
            Text(title).font(.otFootnote).foregroundStyle(OT.labelSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
