import UIKit
import PDFKit
import UniformTypeIdentifiers

extension NoticeOCR {
    /// Allowed document types for `.fileImporter` across audition, sides, and practice flows.
    static let supportedImportContentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .rtf, .text]
        for ext in ["fdx", "fountain", "docx"] {
            if let utType = UTType(filenameExtension: ext) {
                types.append(utType)
            }
        }
        return types
    }()

    // MARK: - Security-scoped file resolution

    /// Safely resolves a security-scoped URL (e.g. from `.fileImporter`), copying it into the
    /// app's sandboxed temporary directory so that asynchronous tasks (PDFKit, Vision OCR)
    /// can read it reliably without permission revocation or race conditions.
    /// Uses NSFileCoordinator to coordinate reading across iCloud Drive and external document providers.
    /// Always call the returned `cleanup()` closure (e.g. in a `defer` block) when finished.
    static func resolveSecurityScopedFile(at url: URL) -> (url: URL, cleanup: () -> Void) {
        let accessed = url.startAccessingSecurityScopedResource()
        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        var didCopy = false

        // Strategy 1: Coordinated read (handles iCloud Drive, external providers, sandbox boundaries)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { coordinatedURL in
            if let data = try? Data(contentsOf: coordinatedURL) {
                if (try? data.write(to: tempURL, options: .atomic)) != nil {
                    didCopy = true
                }
            } else if (try? FileManager.default.copyItem(at: coordinatedURL, to: tempURL)) != nil {
                didCopy = true
            }
        }

        // Strategy 2: Direct read/copy if coordinator did not copy
        if !didCopy {
            if let data = try? Data(contentsOf: url) {
                if (try? data.write(to: tempURL, options: .atomic)) != nil {
                    didCopy = true
                }
            } else if (try? FileManager.default.copyItem(at: url, to: tempURL)) != nil {
                didCopy = true
            }
        }

        if didCopy {
            if accessed { url.stopAccessingSecurityScopedResource() }
            return (tempURL, {
                try? FileManager.default.removeItem(at: tempURL)
            })
        } else {
            return (url, {
                if accessed { url.stopAccessingSecurityScopedResource() }
            })
        }
    }

    /// A structured extracted document preserving page boundaries for hierarchical chunking.
    struct ExtractedDocument: Sendable {
        var pages: [String] = []
        var fullText: String { pages.joined(separator: "\n\n") }
        var pageCount: Int { pages.count }
        /// Pass 1 text: Feeds only Pages 1–2 (breakdown table and director's note)
        var noticeHeaderPagesText: String {
            pages.prefix(2).joined(separator: "\n\n")
        }
    }

    /// Extracts a multi-page `LayoutDocument` and, for structured script formats (`.fdx`, `.fountain`),
    /// preserves the directly parsed `[ScriptScene]` AST so callers avoid lossy flat-text re-parsing.
    static func extractSidesDocument(
        fromFileAt url: URL
    ) async throws -> (layoutDocument: LayoutDocument, preParsedScenes: [ScriptScene]?) {
        switch url.pathExtension.lowercased() {
        case "pdf":
            let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap { PDFDocument(data: $0) }
            guard let doc else { throw NoticeImportError.corruptDocument }
            return (try await extractPDFLayoutDocument(from: doc), nil)
        case "rtf", "fdx", "fountain", "docx":
            return try extractNonPDFDocument(fromFileAt: url)
        default:
            let fileData = try? Data(contentsOf: url)
            if let doc = PDFDocument(url: url) ?? fileData.flatMap({ PDFDocument(data: $0) }) {
                return (try await extractPDFLayoutDocument(from: doc), nil)
            }
            if fileData?.starts(with: Data("%PDF-".utf8)) == true {
                throw NoticeImportError.corruptDocument
            }
            return try extractNonPDFDocument(fromFileAt: url, preloadedData: fileData)
        }
    }

    /// Extracts a multi-page `LayoutDocument` preserving normalized line geometry and page boundaries.
    static func extractLayoutDocument(fromFileAt url: URL) async throws -> LayoutDocument {
        try await extractSidesDocument(fromFileAt: url).layoutDocument
    }

    private static func extractNonPDFDocument(
        fromFileAt url: URL,
        preloadedData: Data? = nil
    ) throws -> (layoutDocument: LayoutDocument, preParsedScenes: [ScriptScene]?) {
        switch url.pathExtension.lowercased() {
        case "rtf":
            guard let data = preloadedData ?? (try? Data(contentsOf: url)),
                  let attributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                  ) else {
                throw NoticeImportError.corruptDocument
            }
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksReadable(text) else { throw NoticeImportError.corruptDocument }
            return (syntheticLayoutDocument(from: text), nil)
        case "fdx":
            guard let data = preloadedData ?? (try? Data(contentsOf: url)) else {
                throw NoticeImportError.corruptDocument
            }
            let (scenes, layoutDoc) = try StructuredDocumentParsers.parseFDX(data: data)
            guard looksReadable(layoutDoc.fullText) else { throw NoticeImportError.corruptDocument }
            return (layoutDoc, scenes.isEmpty ? nil : scenes)
        case "fountain":
            guard let data = preloadedData ?? (try? Data(contentsOf: url)),
                  let text = decodeReadablePlainText(from: data) else {
                throw NoticeImportError.corruptDocument
            }
            let (scenes, layoutDoc) = StructuredDocumentParsers.parseFountain(text: text)
            guard looksReadable(layoutDoc.fullText) else { throw NoticeImportError.corruptDocument }
            return (layoutDoc, scenes.isEmpty ? nil : scenes)
        case "docx":
            let layoutDoc = try StructuredDocumentParsers.parseDOCX(url: url)
            guard looksReadable(layoutDoc.fullText) else { throw NoticeImportError.corruptDocument }
            return (layoutDoc, nil)
        default:
            guard let fileData = preloadedData ?? (try? Data(contentsOf: url)) else {
                throw NoticeImportError.corruptDocument
            }
            if let text = decodeReadablePlainText(from: fileData) {
                return (syntheticLayoutDocument(from: text), nil)
            }
            if !fileData.contains(0x00), String(data: fileData, encoding: .utf8) != nil {
                throw NoticeImportError.corruptDocument
            }
            throw NoticeImportError.unsupportedFormat
        }
    }

    private static func decodeReadablePlainText(from data: Data) -> String? {
        if !data.contains(0x00), let utf8 = String(data: data, encoding: .utf8) {
            let trimmed = utf8.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksReadable(trimmed) { return trimmed }
        }
        if (data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])),
           let utf16 = String(data: data, encoding: .utf16) {
            let trimmed = utf16.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksReadable(trimmed) { return trimmed }
        }
        if !data.contains(0x00), let latin1 = String(data: data, encoding: .isoLatin1) {
            let trimmed = latin1.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksReadable(trimmed) { return trimmed }
        }
        return nil
    }

    private static func extractPDFLayoutDocument(from doc: PDFDocument) async throws -> LayoutDocument {
        if doc.isEncrypted && doc.isLocked {
            throw NoticeImportError.encryptedPDF
        }
        guard doc.pageCount > 0 else {
            throw NoticeImportError.corruptDocument
        }

        var layoutPages: [[LayoutLine]] = []
        var reconstructedPages: [String] = []
        layoutPages.reserveCapacity(doc.pageCount)
        reconstructedPages.reserveCapacity(doc.pageCount)

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else {
                layoutPages.append([])
                reconstructedPages.append("")
                continue
            }
            let geometryLines = PDFGeometryExtractor.extractLines(from: page, pageIndex: i)
            let reconstructed = OCRLayoutReconstructor.reconstruct(layoutLines: geometryLines)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if looksReadable(reconstructed) {
                layoutPages.append(geometryLines)
                reconstructedPages.append(reconstructed)
            } else if let image = renderPDFPage(page) {
                // PDFs can mix selectable text and scanned/image-only pages. OCR each page
                // independently so a readable first page doesn't hide missing later pages.
                let recognized = await Task.detached(priority: .userInitiated) {
                    recognizeLayout(in: image, pageIndex: i)
                }.value
                let ocrText = recognized.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksReadable(ocrText) {
                    layoutPages.append(recognized.lines)
                    reconstructedPages.append(ocrText)
                } else {
                    layoutPages.append(geometryLines)
                    reconstructedPages.append(reconstructed)
                }
            } else {
                layoutPages.append(geometryLines)
                reconstructedPages.append(reconstructed)
            }
        }

        let document = LayoutDocument(pages: layoutPages, reconstructedPages: reconstructedPages)
        guard looksReadable(document.fullText) else {
            throw NoticeImportError.corruptDocument
        }
        return document
    }

    private static func syntheticLayoutDocument(from text: String) -> LayoutDocument {
        let rawPages = text
            .components(separatedBy: "\u{000C}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let pagesText = rawPages.isEmpty ? [text] : rawPages
        let layoutPages = pagesText.enumerated().map { idx, pageText in
            PDFGeometryExtractor.syntheticLines(from: pageText, pageIndex: idx)
        }
        return LayoutDocument(pages: layoutPages, reconstructedPages: pagesText)
    }

    /// Extracts a multi-page document preserving page boundaries for hierarchical chunking.
    static func extractDocument(fromFileAt url: URL) async -> ExtractedDocument? {
        guard let layoutDocument = try? await extractLayoutDocument(fromFileAt: url) else {
            return nil
        }
        let document = ExtractedDocument(pages: layoutDocument.reconstructedPages)
        return looksReadable(document.fullText) ? document : nil
    }

    /// Extracts text from a file the user picked with the file importer. If a PDF is an image-only
    /// scan without selectable text, automatically rasterizes its pages and runs Apple Vision OCR.
    /// Caller is responsible for the security-scoped resource around `url`.
    static func extractText(fromFileAt url: URL) async -> String? {
        if let doc = await extractDocument(fromFileAt: url) {
            return doc.fullText
        }
        return extractSynchronousText(fromFileAt: url)
    }

    /// Synchronous quick extraction for digital text and structured files.
    static func extractText(fromFileAt url: URL) -> String? {
        extractSynchronousText(fromFileAt: url)
    }

    private static func extractSynchronousText(fromFileAt url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" || !["rtf", "fdx", "fountain", "docx"].contains(ext) {
            if let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap({ PDFDocument(data: $0) }),
               !(doc.isEncrypted && doc.isLocked),
               doc.pageCount > 0 {
                var text = ""
                for i in 0..<doc.pageCount {
                    if let pageStr = doc.page(at: i)?.string {
                        text += pageStr + "\n"
                    }
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksReadable(trimmed) || ext == "pdf" {
                    return looksReadable(trimmed) ? trimmed : nil
                }
            } else if ext == "pdf" {
                return nil
            }
        }
        return (try? extractNonPDFDocument(fromFileAt: url).layoutDocument.fullText)
    }

    /// Renders a PDF page to a crisp 2048px UIImage upright for Apple Vision OCR.
    static func renderPDFPage(_ page: PDFPage, targetWidth: CGFloat = 2048) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }
        let scale = targetWidth / pageRect.width
        let targetSize = CGSize(width: targetWidth, height: pageRect.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            ctx.cgContext.saveGState()
            // Invert coordinate system to match PDF bottom-left origin
            ctx.cgContext.translateBy(x: 0, y: targetSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
    }
}
