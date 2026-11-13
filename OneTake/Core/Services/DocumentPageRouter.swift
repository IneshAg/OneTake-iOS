import Foundation
import CoreGraphics

/// Result of routing a multi-page `LayoutDocument` into notice/breakdown pages vs script sides pages.
struct RoutedDocument: Sendable, Equatable {
    let noticeTextSlice: String
    let noticePages: [Int]
    let sidesPages: [Int]
    let sidesLayoutLines: [LayoutLine]
}

/// Classifies document pages as `.notice` (casting calls, breakdowns, submission instructions)
/// or `.sides` (script scenes/monologues), and builds a token-bounded notice slice for on-device models.
enum DocumentPageRouter {
    /// Hard ceiling matching Needle 3's 1,024-token context envelope.
    static let maxNeedleTokenBudget = 1024

    private enum PageKind {
        case notice
        case sides
    }

    private struct PageScore {
        let kind: PageKind
        let sidesScore: Int
        let noticeScore: Int
    }

    private struct SliceLine {
        let pageOrder: Int
        let lineOrder: Int
        let text: String
        let wordCount: Int
        let priority: Int
    }

    // MARK: - Public API

    /// Routes every non-empty page of `document` into `noticePages` or `sidesPages`,
    /// preserving top front-matter, requirement blocks, and footer contact blocks inside `tokenBudget`.
    static func route(_ document: LayoutDocument, tokenBudget: Int = 900) -> RoutedDocument {
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            return RoutedDocument(noticeTextSlice: "", noticePages: [], sidesPages: [], sidesLayoutLines: [])
        }

        let clampedBudget = min(max(tokenBudget, 1), maxNeedleTokenBudget)
        let tokensPerWord = clampedBudget > 900 ? 1.3 : 1.2
        let maxWords = max(1, Int(floor(Double(clampedBudget) / tokensPerWord)))

        var pageTexts: [String] = []
        pageTexts.reserveCapacity(pageCount)
        for index in 0..<pageCount {
            if index < document.reconstructedPages.count {
                pageTexts.append(document.reconstructedPages[index])
            } else if index < document.pages.count {
                pageTexts.append(OCRLayoutReconstructor.reconstruct(layoutLines: document.pages[index]))
            } else {
                pageTexts.append("")
            }
        }

        var noticePages: [Int] = []
        var sidesPages: [Int] = []
        var sidesLayoutLines: [LayoutLine] = []
        var previousKind: PageKind?

        for pageIndex in 0..<pageCount {
            let layoutLines = pageIndex < document.pages.count ? document.pages[pageIndex] : []
            let pageText = pageTexts[pageIndex]
            let trimmedPage = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPage.isEmpty || !layoutLines.isEmpty else { continue }

            let score = classifyPage(
                text: trimmedPage,
                layoutLines: layoutLines,
                pageIndex: pageIndex,
                previousKind: previousKind
            )
            previousKind = score.kind

            switch score.kind {
            case .notice:
                noticePages.append(pageIndex)
            case .sides:
                sidesPages.append(pageIndex)
                if !layoutLines.isEmpty {
                    sidesLayoutLines.append(contentsOf: layoutLines)
                } else if !trimmedPage.isEmpty {
                    sidesLayoutLines.append(contentsOf: PDFGeometryExtractor.syntheticLines(from: trimmedPage, pageIndex: pageIndex))
                }
            }
        }

        let noticeTextSlice = buildNoticeSlice(
            pageTexts: noticePages.map { pageTexts[$0] },
            maxWords: maxWords
        )

        return RoutedDocument(
            noticeTextSlice: noticeTextSlice,
            noticePages: noticePages,
            sidesPages: sidesPages,
            sidesLayoutLines: sidesLayoutLines
        )
    }

    // MARK: - Page Classification

    private static func classifyPage(
        text: String,
        layoutLines: [LayoutLine],
        pageIndex: Int,
        previousKind: PageKind?
    ) -> PageScore {
        let linePairs: [(raw: String, trimmed: String)] = text
            .components(separatedBy: .newlines)
            .compactMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : (raw, trimmed)
            }
        guard !linePairs.isEmpty else {
            return PageScore(kind: .notice, sidesScore: 0, noticeScore: 0)
        }

        // Map centered/indented geometric cues from `LayoutLine` so digital PDFs & OCR boxes contribute directly.
        let geometricCueTexts = Set(
            layoutLines.compactMap { line -> String? in
                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let isCentered = line.rect.midX >= 0.35 && line.rect.midX <= 0.68 && line.rect.width <= 0.36
                let isIndented = line.estimatedIndent >= 0.22 && line.rect.width <= 0.40
                guard isCentered || isIndented else { return nil }
                if ScriptParser.isLikelyCue(trimmed) || isIndentedMixedCaseCue(trimmed) {
                    return trimmed.uppercased()
                }
                return nil
            }
        )

        var contentLineCount = 0
        var sluglineCount = 0
        var sideSectionCount = 0
        var dialogueCueCount = 0
        var centeredCueCount = 0
        var parentheticalCount = 0

        var strongNoticeHeaderHits = 0
        var noticeKeywordHits = 0
        var contactHits = 0
        var breakdownLineHits = 0
        var metadataLabelHits = 0

        for idx in linePairs.indices {
            let (rawLine, trimmed) = linePairs[idx]
            let leadingSpaces = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
            let nextLine = idx + 1 < linePairs.count ? linePairs[idx + 1].trimmed : ""

            if isPageFurniture(trimmed) { continue }
            contentLineCount += 1

            let lower = trimmed.lowercased()
            let upper = trimmed.uppercased()

            // --- Sides signals ---
            if isScriptSluglineOrActScene(trimmed) {
                sluglineCount += 1
                continue
            }

            if isSideSectionHeading(trimmed) {
                sideSectionCount += 1
                continue
            }

            if isParentheticalDirection(trimmed) {
                parentheticalCount += 1
            }

            if isDialogueCueLine(
                trimmed,
                leadingSpaces: leadingSpaces,
                nextLine: nextLine,
                geometricCueTexts: geometricCueTexts
            ) {
                dialogueCueCount += 1
                if leadingSpaces >= 10 || geometricCueTexts.contains(upper) {
                    centeredCueCount += 1
                }
            }

            // --- Notice signals ---
            if containsStrongNoticeHeader(lower) {
                strongNoticeHeaderHits += 1
            }
            if containsContactOrSubmissionRoute(trimmed, lower: lower) {
                contactHits += 1
            }
            if isCharacterBreakdownOrIndexLine(trimmed, lower: lower) {
                breakdownLineHits += 1
            }
            if isNoticeMetadataLabelLine(trimmed, lower: lower) {
                metadataLabelHits += 1
            }
            noticeKeywordHits += countNoticeKeywords(in: lower)
        }

        let cueRatio = Double(dialogueCueCount) / Double(max(contentLineCount, 1))
        var sidesScore = sluglineCount * 4
            + sideSectionCount * 6
            + dialogueCueCount * 2
            + centeredCueCount * 2
            + min(parentheticalCount, 3)

        if dialogueCueCount >= 2 && cueRatio >= 0.08 {
            sidesScore += 3
        } else if dialogueCueCount >= 1 && cueRatio >= 0.20 && contentLineCount <= 8 {
            // Short trailing dialogue pages (e.g. 5-line exchange with 2 cues)
            sidesScore += 3
        }

        let noticeScore = strongNoticeHeaderHits * 5
            + contactHits * 4
            + breakdownLineHits * 3
            + metadataLabelHits * 2
            + min(noticeKeywordHits, 6)

        if sidesScore == 0 && noticeScore == 0 {
            // Neutral continuation page after a sides page (e.g. second page of a prose monologue)
            let kind: PageKind = (pageIndex > 0 && previousKind == .sides) ? .sides : .notice
            return PageScore(kind: kind, sidesScore: sidesScore, noticeScore: noticeScore)
        }

        // Pages with explicit side headings (`THE SIDE`, `SIDE A`, `INT.`) or real dialogue cue density
        // win unless overwhelmed by strong notice-only evidence (cover letters, breakdown tables, contact footers).
        let isSides = sidesScore > 0 && sidesScore >= noticeScore
        return PageScore(kind: isSides ? .sides : .notice, sidesScore: sidesScore, noticeScore: noticeScore)
    }

    // MARK: - Line-Level Detectors

    private static func isPageFurniture(_ line: String) -> Bool {
        if line.allSatisfy(\.isNumber) { return true }
        let lower = line.lowercased()
        if lower.hasPrefix("page ") || lower.hasPrefix("p. ") || lower.hasPrefix("pg. ") {
            return true
        }
        return false
    }

    private static func isScriptSluglineOrActScene(_ line: String) -> Bool {
        let upper = line.uppercased()
        // Breakdown/TOC lines end with "PAGE 3" — never treat them as script scene headings.
        if upper.range(of: #"\bPAGE\s+\d+\s*$"#, options: .regularExpression) != nil {
            return false
        }
        if upper.hasPrefix("INT.") || upper.hasPrefix("EXT.") || upper.hasPrefix("INT/EXT") || upper.hasPrefix("EXT/INT") {
            return true
        }
        if upper.range(
            of: #"^(?:ACT|SCENE)\s+(?:ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN|[IVXLCDM]+|\d+[A-Z]?)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return ScriptParser.isSceneHeading(line) && !isSideSectionHeading(line)
    }

    private static func isSideSectionHeading(_ line: String) -> Bool {
        let upper = line.uppercased()
        let prefixes = [
            "THE SIDE", "SIDE A", "SIDE B", "SIDE C", "SIDE D",
            "SIDE 1", "SIDE 2", "SIDE 3", "SIDE 4",
            "START SIDE", "START SCENE", "[START"
        ]
        if prefixes.contains(where: { upper.hasPrefix($0) }) {
            return true
        }
        if upper.range(of: #"^(?:THE\s+)?MONOLOGUE\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isParentheticalDirection(_ line: String) -> Bool {
        guard line.hasPrefix("("), line.hasSuffix(")"), line.count <= 60 else { return false }
        let lower = line.lowercased()
        return !lower.contains("optional") && !lower.contains("lead") && !lower.contains("supporting")
    }

    private static func isIndentedMixedCaseCue(_ line: String) -> Bool {
        ScriptParser.isLikelyIndentedCue(line, raw: "                " + line)
    }

    private static func isDialogueCueLine(
        _ line: String,
        leadingSpaces: Int,
        nextLine: String,
        geometricCueTexts: Set<String>
    ) -> Bool {
        if let colonIndex = line.firstIndex(of: ":") {
            let prefix = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let suffix = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            let lowerPrefix = prefix.lowercased()
            guard !prefix.isEmpty, prefix.count <= 28 else { return false }
            guard !lowerPrefix.hasPrefix("http"), !lowerPrefix.hasPrefix("mailto") else { return false }
            guard !isNoticeLabelPrefix(lowerPrefix), !ScriptParser.isBlacklistedNoticeWord(prefix) else { return false }
            if looksLikeCharacterBioText(suffix) { return false }
            let words = prefix.split(separator: " ")
            guard (1...4).contains(words.count) else { return false }
            let allStartUpper = words.allSatisfy { word in
                word == "&" || word.first?.isUppercase == true
            }
            return allStartUpper && prefix.rangeOfCharacter(from: .decimalDigits) == nil
        }

        let upper = line.uppercased()
        let lower = line.lowercased()
        let isGeometricCue = geometricCueTexts.contains(upper)
            && !isNoticeLabelPrefix(lower)
            && !ScriptParser.isBlacklistedNoticeWord(line)
        if ScriptParser.isLikelyCue(line)
            || (leadingSpaces >= 12 && isIndentedMixedCaseCue(line))
            || isGeometricCue {
            if looksLikeCharacterBioText(nextLine) { return false }
            return true
        }
        return false
    }

    private static func isNoticeLabelPrefix(_ lowerPrefix: String) -> Bool {
        let noticeLabels: Set<String> = [
            "project", "project title", "title", "production", "production company", "produced by",
            "director", "director note", "director notes", "producer", "writer", "casting",
            "casting director", "casting office", "role", "roles", "character", "characters",
            "age", "age group", "age range", "male age", "female age", "gender",
            "due", "deadline", "submission deadline", "self-tape due", "self tape due", "tape due",
            "submit", "submit via", "submission", "submissions", "submission route", "deliver to",
            "slate", "slate instruction", "slate instructions", "video format", "format", "orientation",
            "callback", "callbacks", "callback date", "callback dates", "shoot", "shoot date", "shoot dates",
            "filming date", "filming dates", "dates", "date", "time",
            "location", "production location", "filming location", "venue", "rate", "pay", "compensation", "union",
            "usage", "wardrobe", "special skills", "conflicts", "parking", "logline", "overview",
            "note", "notes", "requirement", "requirements", "what to submit", "instructions",
            "setting", "settings", "synopsis", "storyline", "email", "phone", "contact", "whatsapp",
            "client", "product", "agency", "campaign", "dialogue sides"
        ]
        if noticeLabels.contains(lowerPrefix) { return true }
        return lowerPrefix.hasPrefix("role ") || lowerPrefix.hasPrefix("director note") || lowerPrefix.hasPrefix("slate ")
    }

    private static func looksLikeCharacterBioText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.range(of: #"\b\d{1,2}\s*[-–—]\s*\d{1,2}\s*(?:years|yrs|yo)?\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b(?:lead|supporting|co-?star|day player|principal|series regular)\b"#, options: .regularExpression) != nil &&
            lower.range(of: #"\b(?:male|female|non-?binary|he/him|she/her|they/them|\d{2}s)\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func containsStrongNoticeHeader(_ lower: String) -> Bool {
        let headers = [
            "casting call", "open call", "audition notice", "casting notice", "currently casting",
            "how to use these sides", "audition sides page breakdown", "sides page breakdown",
            "the characters in this document", "character breakdown", "character breakdowns",
            "a message from the director", "what to submit", "submission instructions",
            "submission requirements", "audition requirements", "self tape submission",
            "self-tape submission", "callback instructions", "callback & production notes",
            "we are looking for", "we're looking for", "seeking actors", "kindly send"
        ]
        return headers.contains(where: lower.contains)
    }

    private static func containsContactOrSubmissionRoute(_ line: String, lower: String) -> Bool {
        if line.range(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(
            of: #"(?:https?://|www\.|forms\.gle|docs\.google\.com/forms|drive\.google\.com|dropbox\.com|wetransfer\.com|wa\.me/|[a-z0-9.-]+\.(?:com|org|net|in|co|io)/[a-z0-9_./-]+)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return ["actors access", "backstage", "casting networks", "spotlight", "whatsapp"]
            .contains(where: lower.contains)
    }

    private static func isCharacterBreakdownOrIndexLine(_ line: String, lower: String) -> Bool {
        if line.range(of: #"(?i)\b(?:page|pg\.?)\s*\d+\s*$"#, options: .regularExpression) != nil,
           line.count >= 8 {
            return true
        }
        if line.range(of: #"(?i)^[A-Z][A-Za-z'\- ]{1,25}\s*(?:\([^)]*(?:lead|supporting|male|female|age|\d{2}s|\d{1,2}\s*[-–]\s*\d{1,2})[^)]*\)|[-–—]\s*(?:M|F|NB|Male|Female)\b|[·•|]\s*(?:He|She|They)/)"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\bage(?:\s+group|\s+range)?\s*[:\-]\s*\d{1,2}"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isNoticeMetadataLabelLine(_ line: String, lower: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        let prefix = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
        return isNoticeLabelPrefix(prefix) && prefix != "setting" && prefix != "settings"
    }

    private static func countNoticeKeywords(in lower: String) -> Int {
        let keywords = [
            "slate", "submission", "submit", "deadline", "callback", "self tape", "self-tape",
            "headshot", "resume", "résumé", "full-body", "full body", "landscape", "horizontal",
            "audition", "casting", "requirements", "shoot dates", "compensation", "stipend",
            "sag-aftra", "non-union", "rate of pay"
        ]
        var hits = 0
        for keyword in keywords where lower.contains(keyword) {
            hits += 1
        }
        return hits
    }

    // MARK: - Bounded Notice Slice

    private static func buildNoticeSlice(pageTexts: [String], maxWords: Int) -> String {
        let nonEmptyPages = pageTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !nonEmptyPages.isEmpty else { return "" }

        let joined = nonEmptyPages.joined(separator: "\n\n")
        if wordCount(joined) <= maxWords {
            return joined
        }

        var rawEntries: [SliceLine] = []
        for (pageOrder, pageText) in nonEmptyPages.enumerated() {
            let lines = pageText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let lineTotal = lines.count

            for (lineOrder, lineText) in lines.enumerated() {
                let lower = lineText.lowercased()
                let isFirstPageFrontMatter = pageOrder == 0 && lineOrder < 5
                let isLaterPageHeader = pageOrder > 0 && lineOrder < 2
                let isFooter = lineOrder >= max(0, lineTotal - 3)
                let isContact = containsContactOrSubmissionRoute(lineText, lower: lower)
                let isStrongHeader = containsStrongNoticeHeader(lower)
                let isRequirementOrMeta = countNoticeKeywords(in: lower) > 0
                    || isNoticeMetadataLabelLine(lineText, lower: lower)
                    || isCharacterBreakdownOrIndexLine(lineText, lower: lower)

                let priority: Int
                if isContact || isFirstPageFrontMatter || (isFooter && (isRequirementOrMeta || isContact)) {
                    priority = 4
                } else if isStrongHeader || isRequirementOrMeta || isLaterPageHeader {
                    priority = 3
                } else {
                    priority = 1
                }

                rawEntries.append(
                    SliceLine(
                        pageOrder: pageOrder,
                        lineOrder: lineOrder,
                        text: lineText,
                        wordCount: max(1, wordCount(lineText)),
                        priority: priority
                    )
                )
            }
        }

        // Promote immediate neighbors of priority >= 3 lines to priority 2 so multi-line requirements stay intact.
        var promotedEntries = rawEntries
        for index in rawEntries.indices where rawEntries[index].priority >= 3 {
            for offset in [-1, 1] {
                let neighbor = index + offset
                if rawEntries.indices.contains(neighbor),
                   rawEntries[neighbor].pageOrder == rawEntries[index].pageOrder,
                   promotedEntries[neighbor].priority < 2 {
                    let existing = promotedEntries[neighbor]
                    promotedEntries[neighbor] = SliceLine(
                        pageOrder: existing.pageOrder,
                        lineOrder: existing.lineOrder,
                        text: existing.text,
                        wordCount: existing.wordCount,
                        priority: 2
                    )
                }
            }
        }

        let selectionOrder = promotedEntries.indices.sorted { a, b in
            if promotedEntries[a].priority != promotedEntries[b].priority {
                return promotedEntries[a].priority > promotedEntries[b].priority
            }
            if promotedEntries[a].pageOrder != promotedEntries[b].pageOrder {
                return promotedEntries[a].pageOrder < promotedEntries[b].pageOrder
            }
            return promotedEntries[a].lineOrder < promotedEntries[b].lineOrder
        }

        var selectedIndices: [Int] = []
        var usedWords = 0
        for index in selectionOrder {
            let cost = promotedEntries[index].wordCount
            if usedWords + cost <= maxWords {
                selectedIndices.append(index)
                usedWords += cost
            }
        }

        if selectedIndices.isEmpty, let firstIndex = selectionOrder.first {
            let truncated = promotedEntries[firstIndex].text
                .split(whereSeparator: \.isWhitespace)
                .prefix(maxWords)
                .joined(separator: " ")
            return truncated
        }

        selectedIndices.sort { a, b in
            if promotedEntries[a].pageOrder != promotedEntries[b].pageOrder {
                return promotedEntries[a].pageOrder < promotedEntries[b].pageOrder
            }
            return promotedEntries[a].lineOrder < promotedEntries[b].lineOrder
        }

        var groupedByPage: [Int: [String]] = [:]
        for index in selectedIndices {
            let entry = promotedEntries[index]
            groupedByPage[entry.pageOrder, default: []].append(entry.text)
        }

        return groupedByPage.keys.sorted()
            .compactMap { groupedByPage[$0]?.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
