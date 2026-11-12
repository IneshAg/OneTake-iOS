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
    /// Preferred recognition languages ordered by priority. Includes Indian English and Hindi so casting
    /// notices with Devanagari names or bilingual text are handled correctly.
    private static let preferredLanguages: [String] = ["en-US", "en-IN", "hi-IN"]

    /// Dynamically queries Vision at runtime for supported recognition languages for the given level and revision,
    /// filtering our preferred languages against system capabilities.
    private static func configureSupportedLanguages(for request: VNRecognizeTextRequest) {
        if #available(iOS 15.0, *) {
            if let supported = try? request.supportedRecognitionLanguages() {
                let supportedSet = Set(supported)
                let matched = preferredLanguages.filter { supportedSet.contains($0) }
                if !matched.isEmpty {
                    request.recognitionLanguages = matched
                    return
                }
                let prefixMatched = preferredLanguages.filter { pref in
                    let prefix = String(pref.prefix(2))
                    return supported.contains(where: { $0.hasPrefix(prefix) })
                }
                if !prefixMatched.isEmpty {
                    request.recognitionLanguages = prefixMatched
                    return
                }
                request.recognitionLanguages = supported.contains("en-US") ? ["en-US"] : Array(supported.prefix(3))
                return
            }
        }
        request.recognitionLanguages = preferredLanguages
    }

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
        let pages = await recognizePages(in: images)
        return pages.filter { !looksBlankPage($0) }.joined(separator: "\n\n")
    }

    /// Same OCR path as `recognizeText`, retaining original page boundaries and indices for role and side selection.
    /// Preserves empty string entries for blank pages so that page indices accurately match document page numbers (1-indexed).
    static func recognizePages(in images: [UIImage]) async -> [String] {
        var results: [String] = []
        for image in images {
            let text = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    recognizeText(in: image)
                }
            }.value
            // Always preserve entry for each page to maintain exact 1-to-1 page alignment
            results.append(text)
        }
        return results
    }

    private static func looksBlankPage(_ text: String) -> Bool {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Single-image recognition

    private static func recognizeText(in image: UIImage) -> String {
        autoreleasepool {
            guard let cgImage = normalizedCGImage(image) else {
                print("[NoticeOCR] no CGImage for this UIImage")
                return ""
            }
            // Pass 1: Try normalized CGImage directly (preserves fine glyphs, periods, email syntax)
            var bestResult = performVisionOCR(on: cgImage)

            // Pass 2: Adaptive image pre-processing (grayscale, contrast stretch, sharpen)
            if isWeakOCR(bestResult), let processedImage = enhancedCGImage(cgImage) {
                let processedResult = performVisionOCR(on: processedImage)
                if isBetterOCRResult(processedResult, than: bestResult) {
                    bestResult = processedResult
                }
            }

            // Pass 3: Inverted luminance pass if text is still weak (for light text on dark backgrounds)
            if isWeakOCR(bestResult), let invertedImage = enhancedCGImage(cgImage, forceInvert: true) {
                let invertedResult = performVisionOCR(on: invertedImage)
                if isBetterOCRResult(invertedResult, than: bestResult) {
                    bestResult = invertedResult
                }
            }

            // Pass 4: Bounded enlargement retry for small-print flyers
            // When fine text drops below Vision's character detector threshold,
            // upscale up to 2.0x (bounded to maxDimension 4096) to bring glyphs into readable range.
            if isWeakOCR(bestResult) {
                let sourceCG = image.cgImage ?? cgImage
                let longest = max(sourceCG.width, sourceCG.height)
                let maxBound: CGFloat = 4096
                let candidateCG: CGImage?
                if longest < 2500 {
                    let scale = min(2.0, maxBound / CGFloat(max(longest, 1)))
                    candidateCG = scaledCGImage(sourceCG, scale: scale)
                } else {
                    candidateCG = sourceCG
                }

                if let candidateCG {
                    // Try clean high-res CoreGraphics scaled image first!
                    let cleanEnlargedResult = performVisionOCR(on: candidateCG)
                    if isBetterOCRResult(cleanEnlargedResult, than: bestResult) {
                        bestResult = cleanEnlargedResult
                    }
                    if isWeakOCR(bestResult), let processedEnlarged = enhancedCGImage(candidateCG) {
                        let enlargedResult = performVisionOCR(on: processedEnlarged)
                        if isBetterOCRResult(enlargedResult, than: bestResult) {
                            bestResult = enlargedResult
                        } else if let invertedEnlarged = enhancedCGImage(candidateCG, forceInvert: true) {
                            let invertedResult = performVisionOCR(on: invertedEnlarged)
                            if isBetterOCRResult(invertedResult, than: bestResult) {
                                bestResult = invertedResult
                            }
                        }
                    }
                }
            }

            return bestResult
        }
    }

    /// Evaluates whether OCR output is weak (empty, unreadable, or very few recognized words/lines).
    private static func isWeakOCR(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || !looksReadable(trimmed) { return true }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.filter(\.isLetter).count >= 2 }
        let lines = trimmed.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return words.count < 6 || lines.count < 2
    }

    /// Measures quality of OCR text based on recognized letter words and line count.
    private static func ocrScore(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.filter(\.isLetter).count >= 2 }
        let lines = trimmed.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return (words.count * 3) + (lines.count * 2)
    }

    private static func isBetterOCRResult(_ candidate: String, than current: String) -> Bool {
        return ocrScore(candidate) > ocrScore(current)
    }

    /// High-quality Core Graphics enlargement for fine-print notices and flyers whose character heights
    /// fall below Apple Vision's character detector threshold.
    private static func scaledCGImage(_ source: CGImage, scale: CGFloat) -> CGImage? {
        guard scale > 1.0 else { return source }
        let newWidth = Int(CGFloat(source.width) * scale)
        let newHeight = Int(CGFloat(source.height) * scale)
        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    /// Performs Vision OCR across accurate and fast recognition levels.
    private static func performVisionOCR(on cgImage: CGImage) -> String {
        // .accurate first; if it errors (it does on some Simulators: "Could not create inference
        // context") or finds nothing, retry with .fast so one failing path doesn't mean no text.
        for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = level == .accurate
            // Query Vision for supported recognition languages at runtime
            configureSupportedLanguages(for: request)
            // The image is already drawn upright by `normalizedCGImage`.
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                print("[NoticeOCR] \(level == .accurate ? "accurate" : "fast") failed: \(error)")
                continue
            }

            // Extract observations into 2D layout boxes with coordinates and confidence
            let boxes: [OCRLayoutReconstructor.TextBoundingBox] = (request.results ?? []).compactMap { observation in
                let candidates = observation.topCandidates(3)
                guard let best = candidates.first else { return nil }
                let chosen = (best.confidence >= minimumLineConfidence)
                    ? best
                    : candidates.first(where: { $0.confidence >= minimumLineConfidence && $0.string.filter(\.isLetter).count >= 2 })
                guard let candidate = chosen else { return nil }
                return OCRLayoutReconstructor.TextBoundingBox(
                    text: candidate.string,
                    rect: observation.boundingBox,
                    confidence: candidate.confidence
                )
            }

            let reconstructed = OCRLayoutReconstructor.reconstruct(boxes: boxes)
            if !reconstructed.isEmpty { return reconstructed }
        }
        return ""
    }

    // MARK: - Image pre-processing (Core Image)

    /// Converts to grayscale, adaptively checks background darkness, and boosts contrast before Vision OCR.
    /// Grayscale alone improves recognition by ~10–15% on coloured flyers; dark-background inversion
    /// transforms white-on-dark text into black-on-white text which Apple Vision's neural network resolves best.
    private static func enhancedCGImage(_ source: CGImage, forceInvert: Bool = false) -> CGImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var image = CIImage(cgImage: source)

        let profile = luminanceProfile(source)
        let isDark = forceInvert || profile.mean < 0.38

        // Step 1 — convert to greyscale; colours are irrelevant for text recognition
        //          and removing them reduces false-positive detection noise.
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)  // greyscale
            filter.setValue(1.0, forKey: kCIInputContrastKey)
            if let output = filter.outputImage { image = output }
        }

        // Stretch the useful luminance range from sampled 3rd/97th percentiles. A fixed contrast
        // boost crushes text in some dark posters and washes out bright social graphics.
        let low = max(0, profile.low - 0.015)
        let high = min(1, profile.high + 0.015)
        let range = max(high - low, 0.12)
        let scale = min(3.5, max(0.85, 0.94 / range))
        let bias = 0.03 - low * scale
        if let filter = CIFilter(name: "CIColorMatrix") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
            filter.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
            filter.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
            filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            filter.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
            if let output = filter.outputImage { image = output }
        }

        // Step 2 — if dark background detected, invert colors so light text becomes dark text
        if isDark, let invertFilter = CIFilter(name: "CIColorInvert") {
            invertFilter.setValue(image, forKey: kCIInputImageKey)
            if let output = invertFilter.outputImage { image = output }
        }

        // Step 3 — sharpens text edges so Vision's neural net resolves fine glyphs better.
        if let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(isDark ? 0.65 : 0.55, forKey: kCIInputSharpnessKey)
            if let output = filter.outputImage { image = output }
        }

        return context.createCGImage(image, from: image.extent)
    }

    private struct LuminanceProfile {
        var mean: CGFloat
        var low: CGFloat
        var high: CGFloat
    }

    /// Samples a small thumbnail so contrast decisions are cheap even for full-resolution photos.
    private static func luminanceProfile(_ source: CGImage) -> LuminanceProfile {
        let width = 32, height = 32, bytesPerRow = 32 * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return LuminanceProfile(mean: 0.5, low: 0.05, high: 0.95) }

        var values: [CGFloat] = []
        values.reserveCapacity(width * height)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[offset]) / 255
            let g = CGFloat(pixels[offset + 1]) / 255
            let b = CGFloat(pixels[offset + 2]) / 255
            values.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
        values.sort()
        guard !values.isEmpty else { return LuminanceProfile(mean: 0.5, low: 0.05, high: 0.95) }
        let mean = values.reduce(0, +) / CGFloat(values.count)
        let low = values[min(values.count - 1, values.count * 3 / 100)]
        let high = values[min(values.count - 1, values.count * 97 / 100)]
        return LuminanceProfile(mean: mean, low: low, high: max(low, high))
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Must contain at least 2 words that are themselves mostly letters (to support short sides/dialogue).
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.filter(\.isLetter).count >= 2 }
        guard words.count >= 2 else { return false }
        // Reject output that looks like pure noise: if >60% of all characters are non-printable/control,
        // it is likely binary junk or scanner calibration artifact.
        let totalChars = trimmed.count
        guard totalChars > 0 else { return false }
        let printableCount = trimmed.filter { $0.isLetter || $0.isWhitespace || $0.isNewline || $0.isPunctuation || $0.isNumber }.count
        return Double(printableCount) / Double(totalChars) >= 0.40
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

    /// Extracts a multi-page document preserving page boundaries for hierarchical chunking.
    static func extractDocument(fromFileAt url: URL) async -> ExtractedDocument? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap { PDFDocument(data: $0) }
            guard let doc else { return nil }
            var pages: [String] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else {
                    pages.append("")
                    continue
                }
                let extractedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if looksReadable(extractedText) {
                    pages.append(extractedText)
                } else if let image = renderPDFPage(page) {
                    // PDFs can mix selectable text and scanned/image-only pages. OCR each page
                    // independently so a readable first page doesn't hide missing later pages.
                    let recognized = await recognizeText(in: [image]).trimmingCharacters(in: .whitespacesAndNewlines)
                    pages.append(looksReadable(recognized) ? recognized : extractedText)
                } else {
                    pages.append(extractedText)
                }
            }
            let document = ExtractedDocument(pages: pages)
            return looksReadable(document.fullText) ? document : nil
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { return nil }
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksReadable(text) else { return nil }
            let rawPages = text.components(separatedBy: "\u{000C}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return ExtractedDocument(pages: rawPages.isEmpty ? [text] : rawPages)
        default:
            if let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap({ PDFDocument(data: $0) }), doc.pageCount > 0 {
                var pages: [String] = []
                for i in 0..<doc.pageCount {
                    let pageStr = doc.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    pages.append(pageStr)
                }
                if looksReadable(pages.joined(separator: "\n")) {
                    return ExtractedDocument(pages: pages)
                }
            }
            if let str = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksReadable(trimmed) {
                    let rawPages = trimmed.components(separatedBy: "\u{000C}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    return ExtractedDocument(pages: rawPages.isEmpty ? [trimmed] : rawPages)
                }
            }
            return nil
        }
    }

    /// Extracts text from a file the user picked with the file importer: PDF via PDFKit, RTF via
    /// NSAttributedString, anything else as plain text. If a PDF is an image-only scan (photocopy)
    /// without selectable text, automatically rasterizes its pages and runs Apple Vision OCR.
    /// Caller is responsible for the security-scoped resource around `url`.
    static func extractText(fromFileAt url: URL) async -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            return await extractDocument(fromFileAt: url)?.fullText
        }
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
            if doc.pageCount > 30 {
                #if DEBUG
                print("[NoticeOCR] Note: Scanned PDF has \(doc.pageCount) pages; processing first \(pageLimit) pages to protect memory.")
                #endif
            }
            for i in 0..<pageLimit {
                if let page = doc.page(at: i), let img = renderPDFPage(page) {
                    images.append(img)
                }
            }
            if !images.isEmpty {
                let ocrText = await recognizeText(in: images)
                let ocrTrimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksReadable(ocrTrimmed) { return ocrTrimmed }
            }
            // If OCR produced nothing but digital PDF text was extracted and readable, return it
            return looksReadable(trimmed) ? trimmed : nil
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { return nil }
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return looksReadable(text) ? text : nil
        default:
            if let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap({ PDFDocument(data: $0) }), doc.pageCount > 0 {
                var text = ""
                for i in 0..<doc.pageCount {
                    if let pageStr = doc.page(at: i)?.string {
                        text += pageStr + "\n"
                    }
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksReadable(trimmed) { return trimmed }
            }
            if let str = try? String(contentsOf: url, encoding: .utf8), looksReadable(str) { return str }
            if let str = try? String(contentsOf: url, encoding: .ascii), looksReadable(str) { return str }
            if let str = try? String(contentsOf: url, encoding: .isoLatin1), looksReadable(str) { return str }
            if let data = try? Data(contentsOf: url), let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii), looksReadable(str) {
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
            return looksReadable(trimmed) ? trimmed : nil
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { return nil }
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return looksReadable(text) ? text : nil
        default:
            if let doc = PDFDocument(url: url) ?? (try? Data(contentsOf: url)).flatMap({ PDFDocument(data: $0) }), doc.pageCount > 0 {
                var text = ""
                for i in 0..<doc.pageCount {
                    if let pageStr = doc.page(at: i)?.string {
                        text += pageStr + "\n"
                    }
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksReadable(trimmed) { return trimmed }
            }
            if let str = try? String(contentsOf: url, encoding: .utf8), looksReadable(str) { return str }
            if let str = try? String(contentsOf: url, encoding: .ascii), looksReadable(str) { return str }
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
