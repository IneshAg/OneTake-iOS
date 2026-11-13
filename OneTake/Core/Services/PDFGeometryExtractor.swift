import Foundation
import PDFKit
import CoreGraphics

/// Extracts normalized `[0, 1]` line-level geometry from selectable `PDFPage` text.
/// Preserves horizontal indentation (e.g. screenplay margins) and separates multi-column
/// baselines so digital PDFs enter the same layout pipeline as Vision OCR scans.
enum PDFGeometryExtractor {
    private struct Fragment {
        let text: String
        let rect: CGRect
        let hasLeadingWhitespace: Bool
        let hasTrailingWhitespace: Bool
    }

    private static let maxWordMergeGap: CGFloat = 0.045
    private static let kerningJoinThreshold: CGFloat = 0.0008

    /// Extracts normalized `[0, 1]` Vision-oriented `LayoutLine`s from a `PDFPage`.
    static func extractLines(from page: PDFPage, pageIndex: Int) -> [LayoutLine] {
        guard let rawText = page.string,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let pageBounds = effectiveBounds(for: page)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return syntheticLines(from: rawText, pageIndex: pageIndex)
        }

        let nsText = rawText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let fullSelection = page.selection(for: fullRange) else {
            return syntheticLines(from: rawText, pageIndex: pageIndex)
        }

        let lineSelections = fullSelection.selectionsByLine()
        guard !lineSelections.isEmpty else {
            return syntheticLines(from: rawText, pageIndex: pageIndex)
        }

        var fragments: [Fragment] = []
        fragments.reserveCapacity(lineSelections.count)

        for lineSelection in lineSelections {
            let extracted = extractFragments(
                from: lineSelection,
                on: page,
                nsText: nsText,
                pageBounds: pageBounds
            )
            fragments.append(contentsOf: extracted)
        }

        guard !fragments.isEmpty else {
            return syntheticLines(from: rawText, pageIndex: pageIndex)
        }

        return clusterFragments(fragments, pageIndex: pageIndex)
    }

    /// Creates top-to-bottom synthetic `LayoutLine`s for non-geometric text sources or empty selections.
    static func syntheticLines(
        from text: String,
        pageIndex: Int,
        preserveIndentation: Bool = false
    ) -> [LayoutLine] {
        let rawLines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !rawLines.isEmpty else { return [] }

        let usableHeight: CGFloat = 0.88
        let lineStep = usableHeight / CGFloat(rawLines.count)
        let lineHeight = min(0.025, lineStep * 0.85)

        return rawLines.enumerated().map { idx, rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxY = 0.94 - CGFloat(idx) * lineStep
            let minY = max(0.02, maxY - lineHeight)
            if preserveIndentation {
                let leadingSpaces = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                let indent = min(0.55, max(0.08, CGFloat(leadingSpaces) / 40.0))
                let width = max(0.15, 0.92 - indent)
                let rect = CGRect(x: indent, y: minY, width: width, height: lineHeight)
                return LayoutLine(text: trimmed, rect: rect, pageIndex: pageIndex, estimatedIndent: indent)
            } else {
                let rect = CGRect(x: 0.08, y: minY, width: 0.84, height: lineHeight)
                return LayoutLine(text: trimmed, rect: rect, pageIndex: pageIndex)
            }
        }
    }

    // MARK: - Selection decomposition

    private static func extractFragments(
        from lineSelection: PDFSelection,
        on page: PDFPage,
        nsText: NSString,
        pageBounds: CGRect
    ) -> [Fragment] {
        guard let rawLineText = lineSelection.string,
              !rawLineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let rawBounds = lineSelection.bounds(for: page)
        guard !rawBounds.isNull, !rawBounds.isEmpty,
              let normLineRect = normalizeToVision(rawBounds, pageBounds: pageBounds, rotation: page.rotation) else {
            return []
        }

        // PDFKit's `selectionsByLine()` can merge left/right columns on the same baseline into one
        // selection. Probe token bounds only when there are multiple text ranges or wide multi-word
        // lines that could span a column gutter, preserving whitespace-separated word boundaries.
        let hasMultipleRanges = lineSelection.numberOfTextRanges(on: page) > 1
        let hasInternalWhitespace = rawLineText.trimmingCharacters(in: .whitespacesAndNewlines)
            .contains(where: \.isWhitespace)
        if hasMultipleRanges || (normLineRect.width > 0.18 && hasInternalWhitespace) {
            let split = splitSelectionAtWideGaps(
                lineSelection: lineSelection,
                on: page,
                nsText: nsText,
                pageBounds: pageBounds
            )
            if !split.isEmpty {
                return split
            }
        }

        let trimmed = rawLineText.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            Fragment(
                text: trimmed,
                rect: normLineRect,
                hasLeadingWhitespace: rawLineText.first?.isWhitespace == true,
                hasTrailingWhitespace: rawLineText.last?.isWhitespace == true
            )
        ]
    }

    private static func splitSelectionAtWideGaps(
        lineSelection: PDFSelection,
        on page: PDFPage,
        nsText: NSString,
        pageBounds: CGRect
    ) -> [Fragment] {
        let rangeCount = lineSelection.numberOfTextRanges(on: page)
        guard rangeCount > 0 else { return [] }

        var columnFragments: [Fragment] = []
        for idx in 0..<rangeCount {
            let range = lineSelection.range(at: idx, on: page)
            guard range.location != NSNotFound, range.length > 0,
                  NSMaxRange(range) <= nsText.length else { continue }

            let segment = nsText.substring(with: range)
            let tokenRanges = nonWhitespaceTokenRanges(in: segment, baseOffset: range.location)
            guard !tokenRanges.isEmpty else { continue }

            // Single-token segment: keep the full segment selection directly.
            if tokenRanges.count == 1, rangeCount == 1 {
                return []
            }

            let segmentLeadingSpace = segment.first?.isWhitespace == true
            let segmentTrailingSpace = segment.last?.isWhitespace == true

            // Merge consecutive whitespace-separated tokens within the same column using " "
            // so tightly tracked/italic prose never loses spaces via kerning thresholds.
            var activeText: String?
            var activeRect: CGRect?
            var activeLeadingSpace = segmentLeadingSpace

            for (tokenIndex, tokenRange) in tokenRanges.enumerated() {
                let tokenText = nsText.substring(with: tokenRange)
                guard !tokenText.isEmpty,
                      let sel = page.selection(for: tokenRange) else { continue }
                let tokenBounds = sel.bounds(for: page)
                guard !tokenBounds.isNull, !tokenBounds.isEmpty,
                      let normRect = normalizeToVision(tokenBounds, pageBounds: pageBounds, rotation: page.rotation) else {
                    continue
                }

                if let currentText = activeText, let currentRect = activeRect {
                    let gap = normRect.minX - currentRect.maxX
                    if gap <= maxWordMergeGap {
                        activeText = currentText + " " + tokenText
                        activeRect = currentRect.union(normRect)
                    } else {
                        columnFragments.append(
                            Fragment(
                                text: currentText,
                                rect: currentRect,
                                hasLeadingWhitespace: activeLeadingSpace,
                                hasTrailingWhitespace: true
                            )
                        )
                        activeText = tokenText
                        activeRect = normRect
                        activeLeadingSpace = true
                    }
                } else {
                    activeText = tokenText
                    activeRect = normRect
                    activeLeadingSpace = tokenIndex == 0 ? segmentLeadingSpace : true
                }
            }

            if let finalText = activeText, let finalRect = activeRect {
                columnFragments.append(
                    Fragment(
                        text: finalText,
                        rect: finalRect,
                        hasLeadingWhitespace: activeLeadingSpace,
                        hasTrailingWhitespace: segmentTrailingSpace
                    )
                )
            }
        }

        return columnFragments
    }

    private static func nonWhitespaceTokenRanges(in text: String, baseOffset: Int) -> [NSRange] {
        let nsSegment = text as NSString
        var ranges: [NSRange] = []
        var tokenStart: Int?

        for i in 0..<nsSegment.length {
            let ch = nsSegment.character(at: i)
            let isSpace = UnicodeScalar(ch).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
            if isSpace {
                if let start = tokenStart {
                    ranges.append(NSRange(location: baseOffset + start, length: i - start))
                    tokenStart = nil
                }
            } else if tokenStart == nil {
                tokenStart = i
            }
        }
        if let start = tokenStart {
            ranges.append(NSRange(location: baseOffset + start, length: nsSegment.length - start))
        }
        return ranges
    }

    // MARK: - Fragment clustering

    private static func clusterFragments(_ fragments: [Fragment], pageIndex: Int) -> [LayoutLine] {
        let sorted = fragments.sorted { a, b in
            if abs(a.rect.midY - b.rect.midY) > 0.005 {
                return a.rect.midY > b.rect.midY
            }
            return a.rect.minX < b.rect.minX
        }

        // Group fragments sharing a visual baseline (tight Y-tolerance).
        var bands: [[Fragment]] = []
        for fragment in sorted {
            if let lastBand = bands.last, let rep = lastBand.first,
               sharesBaseline(rep.rect, fragment.rect) {
                bands[bands.count - 1].append(fragment)
            } else {
                bands.append([fragment])
            }
        }

        var lines: [LayoutLine] = []
        lines.reserveCapacity(bands.count)

        for band in bands {
            let ordered = band.sorted { $0.rect.minX < $1.rect.minX }
            var currentText = ordered[0].text
            var currentRect = ordered[0].rect
            var currentTrailingWhitespace = ordered[0].hasTrailingWhitespace

            for fragment in ordered.dropFirst() {
                let gap = fragment.rect.minX - currentRect.maxX
                if gap <= maxWordMergeGap {
                    let hasExplicitSpace = currentTrailingWhitespace || fragment.hasLeadingWhitespace
                    let separator = (!hasExplicitSpace && gap <= kerningJoinThreshold) ? "" : " "
                    currentText += separator + fragment.text
                    currentRect = currentRect.union(fragment.rect)
                    currentTrailingWhitespace = fragment.hasTrailingWhitespace
                } else {
                    lines.append(LayoutLine(text: currentText, rect: currentRect, pageIndex: pageIndex))
                    currentText = fragment.text
                    currentRect = fragment.rect
                    currentTrailingWhitespace = fragment.hasTrailingWhitespace
                }
            }
            lines.append(LayoutLine(text: currentText, rect: currentRect, pageIndex: pageIndex))
        }

        return lines
    }

    private static func sharesBaseline(_ a: CGRect, _ b: CGRect) -> Bool {
        let minHeight = min(a.height, b.height)
        let yOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let midYDelta = abs(a.midY - b.midY)
        let tolerance = max(minHeight * 0.45, 0.006)
        return midYDelta <= tolerance && yOverlap > -0.002
    }

    // MARK: - Coordinate normalization

    private static func effectiveBounds(for page: PDFPage) -> CGRect {
        let crop = page.bounds(for: .cropBox)
        if crop.width > 0, crop.height > 0 {
            return crop
        }
        return page.bounds(for: .mediaBox)
    }

    private static func normalizeToVision(
        _ rect: CGRect,
        pageBounds: CGRect,
        rotation: Int
    ) -> CGRect? {
        let nx = (rect.minX - pageBounds.minX) / pageBounds.width
        let ny = (rect.minY - pageBounds.minY) / pageBounds.height
        let nw = rect.width / pageBounds.width
        let nh = rect.height / pageBounds.height

        let rotated: CGRect
        switch ((rotation % 360) + 360) % 360 {
        case 90:
            rotated = CGRect(x: ny, y: 1 - nx - nw, width: nh, height: nw)
        case 180:
            rotated = CGRect(x: 1 - nx - nw, y: 1 - ny - nh, width: nw, height: nh)
        case 270:
            rotated = CGRect(x: 1 - ny - nh, y: nx, width: nh, height: nw)
        default:
            rotated = CGRect(x: nx, y: ny, width: nw, height: nh)
        }

        let minX = max(0, min(1, rotated.minX))
        let minY = max(0, min(1, rotated.minY))
        let maxX = max(minX, min(1, rotated.maxX))
        let maxY = max(minY, min(1, rotated.maxY))
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
