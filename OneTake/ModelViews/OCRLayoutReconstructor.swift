import Foundation
import CoreGraphics

/// 2D visual layout reconstructor for OCR observations.
/// Solves multi-column casting breakdown pairing ("Role: Lead", "Date: 25 Nov") and
/// prevents watermarks, column interleaving, or out-of-order column lines from corrupting dialogue flow.
struct OCRLayoutReconstructor {
    struct TextBoundingBox {
        let text: String
        let rect: CGRect // normalized [0, 1] coordinates (Vision: 0,0 is bottom-left, 1,1 is top-right)
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

    private struct TwoColumnPartition {
        let gutterX: CGFloat
        let headerBoxes: [TextBoundingBox]
        let leftBoxes: [TextBoundingBox]
        let rightBoxes: [TextBoundingBox]
        let footerBoxes: [TextBoundingBox]
    }

    /// Reconstructs a list of bounding boxes into reading-order lines with table-column pairing
    /// and gutter-aware multi-column separation.
    static func reconstruct(boxes: [TextBoundingBox]) -> String {
        guard !boxes.isEmpty else { return "" }

        // Step 1: Check if the document has a 2-column layout (common in casting flyers & Instagram calls)
        if let partition = detectTwoColumns(boxes: boxes) {
            var sections: [String] = []
            let headerText = reconstructRows(boxes: partition.headerBoxes)
            if !headerText.isEmpty { sections.append(headerText) }

            let leftText = reconstructRows(boxes: partition.leftBoxes)
            if !leftText.isEmpty { sections.append(leftText) }

            let rightText = reconstructRows(boxes: partition.rightBoxes)
            if !rightText.isEmpty { sections.append(rightText) }

            let footerText = reconstructRows(boxes: partition.footerBoxes)
            if !footerText.isEmpty { sections.append(footerText) }

            let result = sections.joined(separator: "\n\n")
            if !result.isEmpty { return result }
        }

        // Default single-column / table layout reconstruction
        return reconstructRows(boxes: boxes)
    }

    /// Internal row grouping and reconstruction algorithm.
    private static func reconstructRows(boxes: [TextBoundingBox]) -> String {
        guard !boxes.isEmpty else { return "" }

        // Sort descending by vertical position (Vision Y=0 is bottom, Y=1 is top)
        // Group into horizontal visual rows if Y-overlap is significant
        let sorted = boxes.sorted { a, b in
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
        var previousRowBottom: CGFloat?
        var previousRowHeight: CGFloat = 0

        for row in rows {
            // Sort items in this visual row from left to right
            let sortedRow = row.sorted { $0.rect.minX < $1.rect.minX }
            let rowTop = row.map(\.rect.maxY).max() ?? 0
            let rowBottom = row.map(\.rect.minY).min() ?? rowTop
            let rowHeight = max(rowTop - rowBottom, 0.001)

            // OCR observations contain one box per printed line, so joining every row with a
            // single newline erases the vertical blank lines that separate speaker turns and
            // paragraphs in sides. Restore one empty line when the page has a clear paragraph gap.
            if let previousRowBottom {
                let verticalGap = previousRowBottom - rowTop
                let paragraphThreshold = max(min(previousRowHeight, rowHeight) * 0.7, 0.006)
                if verticalGap > paragraphThreshold, !reconstructedLines.isEmpty {
                    reconstructedLines.append("")
                }
            }
            previousRowBottom = rowBottom
            previousRowHeight = rowHeight

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
            let indent = sortedRow.count == 1 ? centeredCueIndent(for: sortedRow[0]) : 0
            reconstructedLines.append(String(repeating: " ", count: indent) + lineText)
        }

        return reconstructedLines.joined(separator: "\n")
    }

    /// Screenplay character cues are short, all-caps, and centered. Preserve their measured
    /// horizontal placement as leading spaces so ScriptParser can distinguish them from left-aligned
    /// all-caps dialogue. Notice parsing trims these spaces before reading fields.
    private static func centeredCueIndent(for box: TextBoundingBox) -> Int {
        let text = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2..<28).contains(text.count),
              text.rangeOfCharacter(from: .lowercaseLetters) == nil,
              text.rangeOfCharacter(from: .letters) != nil,
              text.rangeOfCharacter(from: .decimalDigits) == nil,
              box.rect.midX >= 0.38, box.rect.midX <= 0.64,
              box.rect.width <= 0.32 else { return 0 }
        let measured = Int((box.rect.minX * 40).rounded())
        return measured >= 14 ? min(measured, 28) : 0
    }

    /// Detects a vertical column gutter separating independent columns (e.g. Left: Roles, Right: Dates).
    private static func detectTwoColumns(boxes: [TextBoundingBox]) -> TwoColumnPartition? {
        guard boxes.count >= 6 else { return nil }

        // Test potential gutter split boundaries in the middle 35% - 65% of the page
        let candidateXs: [CGFloat] = [0.38, 0.40, 0.42, 0.45, 0.48, 0.50, 0.52, 0.55, 0.58, 0.60, 0.62]
        let margin: CGFloat = 0.025

        var bestPartition: TwoColumnPartition? = nil
        var bestScore: Int = -1

        for gutterX in candidateXs {
            var headerBoxes: [TextBoundingBox] = []
            var leftBoxes: [TextBoundingBox] = []
            var rightBoxes: [TextBoundingBox] = []
            var footerBoxes: [TextBoundingBox] = []
            var crossingBodyBoxes: [TextBoundingBox] = []

            // Preliminary classification
            for box in boxes {
                let isLeft = box.rect.maxX <= gutterX + margin
                let isRight = box.rect.minX >= gutterX - margin
                let spansGutter = box.rect.minX < gutterX - margin && box.rect.maxX > gutterX + margin

                if isLeft {
                    leftBoxes.append(box)
                } else if isRight {
                    rightBoxes.append(box)
                } else if spansGutter {
                    crossingBodyBoxes.append(box)
                }
            }

            // Must have substantial content in both columns
            guard leftBoxes.count >= 3, rightBoxes.count >= 3 else { continue }

            // Vertical range of columns
            let leftTop = leftBoxes.map(\.rect.maxY).max() ?? 0
            let leftBottom = leftBoxes.map(\.rect.minY).min() ?? 0
            let rightTop = rightBoxes.map(\.rect.maxY).max() ?? 0
            let rightBottom = rightBoxes.map(\.rect.minY).min() ?? 0

            let columnTop = max(leftTop, rightTop)
            let columnBottom = min(leftBottom, rightBottom)

            // Require both columns to occupy the same vertical band and a real blank gutter
            // between their text. Without these checks, left-aligned and right-aligned blocks
            // elsewhere on a poster can be mistaken for two columns.
            let sharedHeight = min(leftTop, rightTop) - max(leftBottom, rightBottom)
            let leftEdge = leftBoxes.map(\.rect.maxX).max() ?? 0
            let rightEdge = rightBoxes.map(\.rect.minX).min() ?? 1
            let gutterWidth = rightEdge - leftEdge
            guard sharedHeight > 0.15, gutterWidth >= 0.08 else { continue }

            // Classify crossing boxes: top crossing boxes are headers, bottom crossing boxes are footers
            var unassignedCrossing: [TextBoundingBox] = []
            for box in crossingBodyBoxes {
                if box.rect.minY >= columnTop - 0.05 {
                    headerBoxes.append(box)
                } else if box.rect.maxY <= columnBottom + 0.05 {
                    footerBoxes.append(box)
                } else {
                    unassignedCrossing.append(box)
                }
            }

            // A middle line spanning both columns has no reliable place in column-first reading
            // order. Fall back to normal row ordering instead of silently moving it to the footer.
            guard unassignedCrossing.isEmpty else { continue }

            let totalColumnBoxes = leftBoxes.count + rightBoxes.count

            // Distinguish 2-column layout from a simple 2-item key-value table:
            // In a key-value table, left items are short labels that match table keys and correspond 1:1 with right values.
            if isSimpleKeyValueTable(left: leftBoxes, right: rightBoxes) {
                continue
            }

            // Score cleanly separated, substantial column content.
            let score = totalColumnBoxes + Int(sharedHeight * 10) + Int(gutterWidth * 10)
            if score > bestScore {
                bestScore = score
                bestPartition = TwoColumnPartition(
                    gutterX: gutterX,
                    headerBoxes: headerBoxes,
                    leftBoxes: leftBoxes,
                    rightBoxes: rightBoxes,
                    footerBoxes: footerBoxes + unassignedCrossing
                )
            }
        }

        return bestPartition
    }

    /// Returns true if the two sets of boxes are merely key-value label pairs on the same line.
    private static func isSimpleKeyValueTable(left: [TextBoundingBox], right: [TextBoundingBox]) -> Bool {
        guard !left.isEmpty, !right.isEmpty else { return false }
        var pairedCount = 0
        var labelKeyCount = 0

        for lBox in left {
            let clean = lBox.text.trimmingCharacters(in: CharacterSet(charactersIn: ":.- ")).lowercased()
            let isLabel = tableLabelKeys.contains(clean) || clean.hasPrefix("role") || clean.hasPrefix("due")
            if isLabel { labelKeyCount += 1 }

            // Check if there is a right box on the exact same vertical line
            if right.contains(where: { abs($0.rect.midY - lBox.rect.midY) < 0.015 }) {
                pairedCount += 1
            }
        }

        // If >= 60% of left boxes are label keys and matched on the same line, it's a key-value form, not independent columns
        let labelRatio = Double(labelKeyCount) / Double(left.count)
        let pairedRatio = Double(pairedCount) / Double(left.count)
        return labelRatio >= 0.60 && pairedRatio >= 0.60
    }
}
