import Foundation
import CoreGraphics

/// 2D visual layout reconstructor for OCR observations.
/// Solves multi-column casting breakdown pairing ("Role: Lead", "Date: 25 Nov") and
/// prevents watermarks or out-of-order column lines from corrupting dialogue flow.
struct OCRLayoutReconstructor {
    struct TextBoundingBox {
        let text: String
        let rect: CGRect // normalized [0, 1] coordinates
        let confidence: Float
    }

    private static let tableLabelKeys: Set<String> = [
        "project", "project title", "production", "film", "series", "show", "title",
        "type", "project type", "format", "medium",
        "role", "roles", "character", "character name", "role size", "billing",
        "casting", "casting director", "casting office", "cd", "director", "producer", "writer",
        "due", "deadline", "submission deadline", "self-tape due", "self tape due", "tape due",
        "submit", "submit via", "submission", "submissions", "platform", "deliver to",
        "dates", "shoot", "shoot dates", "callback", "callbacks",
        "location", "rate", "pay", "union", "status",
        "notes", "note", "callback notes", "instructions", "wardrobe", "slate", "sides", "synopsis", "storyline"
    ]

    /// Reconstructs a list of bounding boxes into reading-order lines with table-column pairing.
    static func reconstruct(boxes: [TextBoundingBox]) -> String {
        guard !boxes.isEmpty else { return "" }

        // Sort descending by vertical position (Vision Y=0 is bottom, Y=1 is top)
        // Group into horizontal visual rows if Y-overlap is significant
        let sorted = boxes.sorted { a, b in
            // Compare Y (top-down)
            if abs(a.rect.midY - b.rect.midY) > 0.015 {
                return a.rect.midY > b.rect.midY
            }
            return a.rect.minX < b.rect.minX
        }

        var rows: [[TextBoundingBox]] = []
        for box in sorted {
            if let lastRow = rows.last, let rep = lastRow.first {
                let yOverlap = min(rep.rect.maxY, box.rect.maxY) - max(rep.rect.minY, box.rect.minY)
                let minH = min(rep.rect.height, box.rect.height)
                if yOverlap > minH * 0.45 {
                    rows[rows.count - 1].append(box)
                    continue
                }
            }
            rows.append([box])
        }

        var reconstructedLines: [String] = []

        for row in rows {
            // Sort items in this visual row from left to right
            let sortedRow = row.sorted { $0.rect.minX < $1.rect.minX }

            if sortedRow.count == 2 {
                let leftText = sortedRow[0].text.trimmingCharacters(in: .whitespaces)
                let rightText = sortedRow[1].text.trimmingCharacters(in: .whitespaces)
                let cleanKey = leftText.trimmingCharacters(in: CharacterSet(charactersIn: ":.- ")).lowercased()

                if tableLabelKeys.contains(cleanKey) || cleanKey.hasPrefix("role") || cleanKey.hasPrefix("due") {
                    let sep = leftText.hasSuffix(":") ? " " : ": "
                    reconstructedLines.append("\(leftText)\(sep)\(rightText)")
                    continue
                }
            }

            // Normal line or multi-item line
            let lineText = sortedRow.map(\.text).joined(separator: " ")
            reconstructedLines.append(lineText)
        }

        return reconstructedLines.joined(separator: "\n")
    }
}
