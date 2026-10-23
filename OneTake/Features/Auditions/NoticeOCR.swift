import UIKit
import Vision
import PDFKit

/// Real, on-device text extraction for Add Audition's "bring it in" paths — a photo, a scan, or a
/// file all end up as plain text here, which is what actually gets parsed. Nothing leaves the
/// iPhone: Vision OCR and PDFKit both run entirely on-device.
enum NoticeOCR {
    /// Runs Vision text recognition over one or more pages (a single photo, or every page VisionKit
    /// scanned) and concatenates the result.
    static func recognizeText(in images: [UIImage]) async -> String {
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    (index, recognizeText(in: image))
                }
            }
            var pages = [Int: String](minimumCapacity: images.count)
            for await (index, text) in group { pages[index] = text }
            return images.indices.compactMap { pages[$0] }.joined(separator: "\n\n")
        }
    }

    private static func recognizeText(in image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        try? handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
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
