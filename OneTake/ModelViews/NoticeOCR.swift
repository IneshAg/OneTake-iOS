import UIKit
import Vision
import PDFKit

/// Real, on-device text extraction for Add Audition's "bring it in" paths — a photo, a scan, or a
/// file all end up as plain text here, which is what actually gets parsed. Nothing leaves the
/// iPhone: Vision OCR and PDFKit both run entirely on-device.
enum NoticeOCR {
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

    private static func recognizeText(in image: UIImage) -> String {
        autoreleasepool {
            guard let cgImage = normalizedCGImage(image) else {
                print("[NoticeOCR] no CGImage for this UIImage")
                return ""
            }
            // .accurate first; if it errors (it does on some Simulators: "Could not create inference
            // context") or finds nothing, retry with .fast so one failing path doesn't mean no text.
            for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = level
                request.usesLanguageCorrection = level == .accurate
                request.recognitionLanguages = ["en-US"]
                // The image is already drawn upright by `normalizedCGImage`.
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                do {
                    try handler.perform([request])
                } catch {
                    print("[NoticeOCR] \(level == .accurate ? "accurate" : "fast") failed: \(error)")
                    continue
                }
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                if !lines.isEmpty { return lines.joined(separator: "\n") }
            }
            return ""
        }
    }

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

    /// True when OCR output looks like real writing rather than nothing or noise from a photo with no
    /// text in it (a landscape, a selfie): at least three words that contain letters.
    static func looksReadable(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.filter(\.isLetter).count >= 2 }
        return words.count >= 3
    }

    /// Extracts text from a file the user picked with the file importer: PDF via PDFKit, RTF via
    /// NSAttributedString, anything else as plain text. Caller is responsible for the security-scoped
    /// resource around `url`.
    static func extractText(fromFileAt url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return nil }
            var text = ""
            for i in 0..<doc.pageCount { text += (doc.page(at: i)?.string ?? "") + "\n" }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { return nil }
            return attributed.string
        default:
            return try? String(contentsOf: url, encoding: .utf8)
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
