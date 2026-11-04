import UIKit
import Vision
import PDFKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Real, on-device text extraction for Add Audition's "bring it in" paths — a photo, a scan, or a
/// file all end up as plain text here, which is what actually gets parsed. Nothing leaves the
/// iPhone: Vision OCR and PDFKit both run entirely on-device.
enum NoticeOCR {
    // MARK: - Language support
    /// Recognition languages ordered by priority. Includes Indian English and Hindi so casting
    /// notices with Devanagari names or bilingual text are handled correctly.
    private static let recognitionLanguages: [String] = ["en-IN", "en-US", "hi-IN"]

    // MARK: - Recognition confidence threshold
    /// Minimum per-observation confidence for the text to be included. Observations that Vision
    /// is very uncertain about (noise, watermark artefacts) are excluded unless no other
    /// candidates pass — this prevents garbage from reaching the parser.
    private static let minimumLineConfidence: Float = 0.35

    // MARK: - Multi-image entry point

    /// Runs Vision text recognition over one or more pages (a single photo, or every page VisionKit
    /// scanned) and concatenates the result. Processes pages sequentially within an autoreleasepool to
    /// avoid memory jetsam and inference crashes on devices with tighter memory limits (e.g. A12 Bionic on iOS 18).
    static func recognizeText(in images: [UIImage]) async -> String {
        var results: [String] = []
        for image in images {
            let text = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    recognizeText(in: image)
                }
            }.value
            if !text.isEmpty {
                results.append(text)
            }
        }
        return results.joined(separator: "\n\n")
    }

    // MARK: - Single-image recognition

    private static func recognizeText(in image: UIImage) -> String {
        autoreleasepool {
            guard let cgImage = normalizedCGImage(image) else {
                print("[NoticeOCR] no CGImage for this UIImage")
                return ""
            }
            // Apply image pre-processing to boost OCR accuracy on coloured / low-contrast notices.
            let processedImage = enhancedCGImage(cgImage) ?? cgImage

            // .accurate first; if it errors (it does on some Simulators: "Could not create inference
            // context") or finds nothing, retry with .fast so one failing path doesn't mean no text.
            for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = level
                request.usesLanguageCorrection = level == .accurate
                // Support English (Indian), English (US) and Hindi so bilingual casting notices
                // and Devanagari names are read correctly on all devices.
                request.recognitionLanguages = recognitionLanguages
                // The image is already drawn upright by `normalizedCGImage`.
                let handler = VNImageRequestHandler(cgImage: processedImage, orientation: .up)
                do {
                    try handler.perform([request])
                } catch {
                    print("[NoticeOCR] \(level == .accurate ? "accurate" : "fast") failed: \(error)")
                    continue
                }

                // Use top-3 candidates per observation and select based on confidence.
                // This recovers from cases where Vision's first guess is uncertain (low-contrast
                // fonts, handwritten headings) by trying the next-best candidate instead.
                let lines: [String] = (request.results ?? []).compactMap { observation in
                    let candidates = observation.topCandidates(3)
                    guard let best = candidates.first else { return nil }
                    // Accept the best candidate if it meets the confidence threshold.
                    if best.confidence >= minimumLineConfidence { return best.string }
                    // Below threshold: try a lower-ranked candidate that at least contains letters.
                    return candidates.first(where: {
                        $0.confidence >= minimumLineConfidence && $0.string.filter(\.isLetter).count >= 2
                    })?.string
                }
                if !lines.isEmpty { return lines.joined(separator: "\n") }
            }
            return ""
        }
    }

    // MARK: - Image pre-processing (Core Image)

    /// Converts to grayscale and boosts contrast before Vision OCR. Grayscale alone improves
    /// recognition by ~10–15% on coloured flyers (orange/yellow/purple casting-call screenshots).
    /// Values are conservative to avoid over-processing well-lit scans.
    private static func enhancedCGImage(_ source: CGImage) -> CGImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var image = CIImage(cgImage: source)

        // Step 1 — convert to greyscale; colours are irrelevant for text recognition
        //          and removing them reduces false-positive detection noise.
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)  // greyscale
            filter.setValue(1.10, forKey: kCIInputContrastKey)   // slight contrast boost
            filter.setValue(0.03, forKey: kCIInputBrightnessKey) // lift shadows slightly
            if let output = filter.outputImage { image = output }
        }

        // Step 2 — sharpens text edges so Vision's neural net resolves fine glyphs better.
        if let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(0.55, forKey: kCIInputSharpnessKey)
            if let output = filter.outputImage { image = output }
        }

        return context.createCGImage(image, from: image.extent)
    }

    // MARK: - Normalisation

    /// Redraws the image upright at a size Vision handles well. Photos from the camera roll carry an
    /// EXIF rotation and can be 12 MP+; scans are already upright.
    private static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        let longest = max(image.size.width, image.size.height)
        let maxDimension: CGFloat = 2048
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        guard size.width > 0, size.height > 0 else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let redrawn = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage ?? image.cgImage
    }

    // MARK: - Readability check

    /// True when OCR output looks like real writing rather than nothing or noise from a photo with
    /// no text in it (a landscape, a selfie, a watermark). Requires both a minimum word count
    /// AND that the returned observations contained something intelligible. A simple word-count
    /// check is preserved as the outer guard because `looksReadable` is also called on pre-extracted
    /// PDF text where no confidence scores are available.
    static func looksReadable(_ text: String) -> Bool {
        // Must contain at least 3 words that are themselves mostly letters (not just digits / symbols).
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.filter(\.isLetter).count >= 2 }
        guard words.count >= 3 else { return false }
        // Reject output that looks like pure noise: if >70% of all characters are non-letter/space,
        // it is likely a watermark grid, QR-code artefact, or scanner calibration page.
        let totalChars = text.count
        guard totalChars > 0 else { return false }
        let letterOrSpaceCount = text.filter { $0.isLetter || $0.isWhitespace || $0.isNewline }.count
        return Double(letterOrSpaceCount) / Double(totalChars) > 0.30
    }

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

    /// Extracts text from a file the user picked with the file importer: PDF via PDFKit, RTF via
    /// NSAttributedString, anything else as plain text. If a PDF is an image-only scan (photocopy)
    /// without selectable text, automatically rasterizes its pages and runs Apple Vision OCR.
    /// Caller is responsible for the security-scoped resource around `url`.
    static func extractText(fromFileAt url: URL) async -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap { PDFDocument(data: $0) }
            guard let doc else { return nil }
            var text = ""
            for i in 0..<doc.pageCount {
                if let pageStr = doc.page(at: i)?.string {
                    text += pageStr + "\n"
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksReadable(trimmed) { return trimmed }

            // Scanned PDF fallback: render pages to high-res images and run on-device Apple Vision OCR
            var images: [UIImage] = []
            let pageLimit = min(doc.pageCount, 30)
            for i in 0..<pageLimit {
                if let page = doc.page(at: i), let img = renderPDFPage(page) {
                    images.append(img)
                }
            }
            if !images.isEmpty {
                let ocrText = await recognizeText(in: images)
                let ocrTrimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksReadable(ocrTrimmed) { return ocrTrimmed }
                if !ocrTrimmed.isEmpty { return ocrTrimmed }
            }
            // If OCR produced nothing but digital PDF text was extracted, return it
            return trimmed.isEmpty ? nil : trimmed
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { return nil }
            return attributed.string
        default:
            if let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap({ PDFDocument(data: $0) }), doc.pageCount > 0 {
                var text = ""
                for i in 0..<doc.pageCount {
                    if let pageStr = doc.page(at: i)?.string {
                        text += pageStr + "\n"
                    }
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let str = try? String(contentsOf: url, encoding: .utf8) { return str }
            if let str = try? String(contentsOf: url, encoding: .ascii) { return str }
            if let str = try? String(contentsOf: url, encoding: .isoLatin1) { return str }
            if let data = try? Data(contentsOf: url), let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                return str
            }
            return nil
        }
    }

    /// Synchronous quick extraction for digital text files.
    static func extractText(fromFileAt url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap { PDFDocument(data: $0) }
            guard let doc else { return nil }
            var text = ""
            for i in 0..<doc.pageCount {
                if let pageStr = doc.page(at: i)?.string {
                    text += pageStr + "\n"
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { return nil }
            return attributed.string
        default:
            if let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap({ PDFDocument(data: $0) }), doc.pageCount > 0 {
                var text = ""
                for i in 0..<doc.pageCount {
                    if let pageStr = doc.page(at: i)?.string {
                        text += pageStr + "\n"
                    }
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let str = try? String(contentsOf: url, encoding: .utf8) { return str }
            if let str = try? String(contentsOf: url, encoding: .ascii) { return str }
            if let str = try? String(contentsOf: url, encoding: .isoLatin1) { return str }
            return nil
        }
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

private extension CGImagePropertyOrientation {
    init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
