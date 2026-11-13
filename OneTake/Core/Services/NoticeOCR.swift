import UIKit
import Vision
import PDFKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Structured errors surfaced during notice/sides document extraction.
enum NoticeImportError: Error, LocalizedError, Sendable, Equatable {
    case encryptedPDF
    case corruptDocument
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .encryptedPDF:
            return "This PDF is password-protected. Unlock or export an unencrypted copy and try again."
        case .corruptDocument:
            return "This document could not be read. It may be damaged or incomplete."
        case .unsupportedFormat:
            return "This file format is not supported for text extraction."
        }
    }
}

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
                var matchedSupported: [String] = []
                for pref in preferredLanguages {
                    let prefix = String(pref.prefix(2))
                    if let match = supported.first(where: { $0.hasPrefix(prefix) && !matchedSupported.contains($0) }) {
                        matchedSupported.append(match)
                    }
                }
                if !matchedSupported.isEmpty {
                    request.recognitionLanguages = matchedSupported
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
        recognizeLayout(in: image, pageIndex: 0).text
    }

    static func recognizeLayout(in image: UIImage, pageIndex: Int) -> (lines: [LayoutLine], text: String) {
        autoreleasepool {
            guard let cgImage = normalizedCGImage(image) else {
                print("[NoticeOCR] no CGImage for this UIImage")
                return ([], "")
            }
            // Pass 1: Try normalized CGImage directly (preserves fine glyphs, periods, email syntax)
            let primaryBoxes = performVisionOCRBoxes(on: cgImage)
            var mergedBoxes = primaryBoxes
            var bestResult = OCRLayoutReconstructor.reconstruct(boxes: mergedBoxes)

            // Upscale once when the source photo is modest resolution (<1400px, e.g. screenshots or compressed flyers)
            // so secondary passes can read fine white text like submission emails in poster corners.
            let longest = max(cgImage.width, cgImage.height)
            let secondarySource: CGImage = {
                if longest < 1400 {
                    let scale = min(2.0, 2048.0 / CGFloat(max(longest, 1)))
                    return scaledCGImage(cgImage, scale: scale) ?? cgImage
                }
                return cgImage
            }()

            // Posters often combine dark headlines with white-on-colored emails/body text.
            // When OCR looks weak OR no email/link was found yet, probe contrast-stretched and
            // inverted passes and merge ONLY non-overlapping missing boxes so clean dark text stays intact.
            let missingContactInfo = !bestResult.contains("@") && !bestResult.lowercased().contains("http")
            if isWeakOCR(bestResult) || missingContactInfo {
                if let processedImage = enhancedCGImage(secondarySource) {
                    let processedBoxes = performVisionOCRBoxes(on: processedImage)
                    let processedText = OCRLayoutReconstructor.reconstruct(boxes: processedBoxes)
                    if isWeakOCR(bestResult), isBetterOCRResult(processedText, than: bestResult) {
                        mergedBoxes = processedBoxes
                        bestResult = processedText
                    } else if !processedBoxes.isEmpty {
                        mergedBoxes = mergeNonOverlappingBoxes(base: mergedBoxes, additions: processedBoxes)
                        bestResult = OCRLayoutReconstructor.reconstruct(boxes: mergedBoxes)
                    }
                }
            }

            if isWeakOCR(bestResult) || !bestResult.contains("@") {
                if let invertedImage = enhancedCGImage(secondarySource, forceInvert: true) {
                    let invertedBoxes = performVisionOCRBoxes(on: invertedImage)
                    let invertedText = OCRLayoutReconstructor.reconstruct(boxes: invertedBoxes)
                    if isWeakOCR(bestResult), isBetterOCRResult(invertedText, than: bestResult) {
                        mergedBoxes = invertedBoxes
                        bestResult = invertedText
                    } else if !invertedBoxes.isEmpty {
                        mergedBoxes = mergeNonOverlappingBoxes(base: mergedBoxes, additions: invertedBoxes)
                        bestResult = OCRLayoutReconstructor.reconstruct(boxes: mergedBoxes)
                    }
                }
            }

            // If still missing an email/URL, probe the bottom footer strip with local contrast enhancement
            // so small white or low-contrast corner emails aren't drowned out by headline contrast.
            if !bestResult.contains("@") && !bestResult.lowercased().contains("http") {
                let footerBoxes = recoverFooterContactBoxes(from: cgImage)
                if !footerBoxes.isEmpty {
                    mergedBoxes = mergeNonOverlappingBoxes(base: mergedBoxes, additions: footerBoxes)
                    bestResult = OCRLayoutReconstructor.reconstruct(boxes: mergedBoxes)
                }
            }

            // Pass 4: Bounded enlargement retry for very small-print flyers if still weak
            if isWeakOCR(bestResult) {
                let maxBound: CGFloat = 4096
                let candidateCG: CGImage?
                if longest < 2500 {
                    let scale = min(2.0, maxBound / CGFloat(max(longest, 1)))
                    candidateCG = scaledCGImage(cgImage, scale: scale)
                } else {
                    candidateCG = cgImage
                }

                if let candidateCG {
                    let candidateBuilders: [() -> CGImage?] = [
                        { candidateCG },
                        { enhancedCGImage(candidateCG) },
                        { enhancedCGImage(candidateCG, forceInvert: true) }
                    ]
                    for buildVariant in candidateBuilders {
                        guard isWeakOCR(bestResult) else { break }
                        guard let variant = buildVariant() else { continue }
                        let variantBoxes = performVisionOCRBoxes(on: variant)
                        let variantText = OCRLayoutReconstructor.reconstruct(boxes: variantBoxes)
                        if isBetterOCRResult(variantText, than: bestResult) {
                            mergedBoxes = variantBoxes
                            bestResult = variantText
                        }
                    }
                }
            }

            let layoutLines = mergedBoxes.map {
                LayoutLine(text: $0.text, rect: $0.rect, pageIndex: pageIndex)
            }
            return (layoutLines, bestResult)
        }
    }

    /// Crops the bottom contact band and runs locally-stretched normal and inverted OCR at enlarged scale
    /// so small low-contrast submission emails in poster footers are recovered reliably.
    private static func recoverFooterContactBoxes(from cgImage: CGImage) -> [OCRLayoutReconstructor.TextBoundingBox] {
        let stripFraction: CGFloat = 0.28
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: 0,
            y: height * (1 - stripFraction),
            width: width,
            height: height * stripFraction
        ).integral
        guard cropRect.width > 20, cropRect.height > 20,
              let cropped = cgImage.cropping(to: cropRect) else { return [] }

        let targetSource = scaledCGImage(cropped, scale: 2.5) ?? cropped
        var recovered: [OCRLayoutReconstructor.TextBoundingBox] = []
        let variants: [CGImage] = [
            targetSource,
            enhancedCGImage(targetSource),
            enhancedCGImage(targetSource, forceInvert: true)
        ].compactMap { $0 }

        for variant in variants {
            let boxes = performVisionOCRBoxes(on: variant)
            for box in boxes where box.text.contains("@") || box.text.lowercased().contains("http") || box.text.lowercased().contains(".in") || box.text.lowercased().contains(".com") {
                let mappedRect = CGRect(
                    x: box.rect.minX,
                    y: box.rect.minY * stripFraction,
                    width: box.rect.width,
                    height: box.rect.height * stripFraction
                )
                recovered.append(OCRLayoutReconstructor.TextBoundingBox(
                    text: box.text,
                    rect: mappedRect,
                    confidence: box.confidence
                ))
            }
            if recovered.contains(where: { $0.text.contains("@") }) {
                break
            }
        }
        return recovered
    }

    /// Merges text boxes discovered by secondary passes (e.g. inverted luminance for white text on posters)
    /// only where primary passes detected nothing, preventing duplicate overlapping lines.
    private static func mergeNonOverlappingBoxes(
        base: [OCRLayoutReconstructor.TextBoundingBox],
        additions: [OCRLayoutReconstructor.TextBoundingBox]
    ) -> [OCRLayoutReconstructor.TextBoundingBox] {
        var result = base
        for candidate in additions {
            let trimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let overlapsExisting = result.contains { existing in
                let intersection = existing.rect.intersection(candidate.rect)
                guard !intersection.isNull, !intersection.isEmpty else { return false }
                let interArea = intersection.width * intersection.height
                let minArea = max(min(existing.rect.width * existing.rect.height, candidate.rect.width * candidate.rect.height), 1e-6)
                let verticalAlign = abs(existing.rect.midY - candidate.rect.midY) < max(existing.rect.height, candidate.rect.height) * 0.6
                return (interArea / minArea) > 0.28 || (verticalAlign && intersection.width > min(existing.rect.width, candidate.rect.width) * 0.35)
            }
            if !overlapsExisting {
                result.append(candidate)
            }
        }
        return result
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
        let colorSpace = CGColorSpaceCreateDeviceRGB()
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

    /// Performs Vision OCR and returns raw 2D bounding boxes before layout reconstruction.
    private static func performVisionOCRBoxes(on cgImage: CGImage) -> [OCRLayoutReconstructor.TextBoundingBox] {
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
                let chosen = (best.confidence >= minimumLineConfidence || (best.string.contains("@") && best.confidence >= 0.15))
                    ? best
                    : candidates.first(where: { ($0.confidence >= minimumLineConfidence && $0.string.filter(\.isLetter).count >= 2) || ($0.string.contains("@") && $0.confidence >= 0.15) })
                guard let candidate = chosen else { return nil }
                return OCRLayoutReconstructor.TextBoundingBox(
                    text: candidate.string,
                    rect: observation.boundingBox,
                    confidence: candidate.confidence
                )
            }

            if !boxes.isEmpty { return boxes }
        }
        return []
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
