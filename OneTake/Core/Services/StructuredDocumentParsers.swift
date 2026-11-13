import Foundation
import CoreGraphics

/// Deterministic offline parsers for structured screenplay and word-processing documents
/// (`.fdx` Final Draft XML, `.fountain` screenplay markup, and `.docx` OpenXML packages).
enum StructuredDocumentParsers {

    // MARK: - Shared Helpers

    private enum ScreenplayIndent {
        static let leftMargin: CGFloat = 0.15
        static let dialogue: CGFloat = 0.29
        static let parenthetical: CGFloat = 0.35
        static let character: CGFloat = 0.42
        static let transition: CGFloat = 0.65
    }

    private struct LayoutInputLine {
        let text: String
        let indent: CGFloat
        var pageBreakBefore: Bool = false
    }

    private struct SceneAccumulator {
        private var scenes: [(heading: String, lines: [ScriptLine])] = []
        private var currentHeading = "SIDES"
        private var currentLines: [ScriptLine] = []
        private var currentCharacter: String?
        private var dialogueParts: [String] = []

        mutating func startScene(heading: String) {
            flushDialogue()
            currentCharacter = nil
            if !currentLines.isEmpty {
                scenes.append((currentHeading, currentLines))
                currentLines = []
            }
            let cleaned = heading.trimmingCharacters(in: .whitespacesAndNewlines)
            currentHeading = cleaned.isEmpty ? "SIDES" : cleaned.uppercased()
        }

        mutating func startCharacter(_ rawName: String) {
            flushDialogue()
            let cleaned = cleanCharacterName(rawName)
            currentCharacter = cleaned.isEmpty ? nil : cleaned
        }

        mutating func appendDialogue(_ text: String) {
            guard currentCharacter != nil else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            dialogueParts.append(trimmed)
        }

        mutating func endDialogueTurn() {
            flushDialogue()
            currentCharacter = nil
        }

        mutating func flushDialogue() {
            guard let character = currentCharacter else {
                dialogueParts.removeAll()
                return
            }
            let combined = dialogueParts
                .joined(separator: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            dialogueParts.removeAll()
            guard !combined.isEmpty else { return }
            currentLines.append(ScriptLine(character: character, text: combined, isMine: false))
        }

        mutating func buildScenes() -> [ScriptScene] {
            flushDialogue()
            if !currentLines.isEmpty {
                scenes.append((currentHeading, currentLines))
                currentLines = []
            }
            return scenes.enumerated().map { index, scene in
                let wordCount = scene.lines.reduce(0) { $0 + $1.text.split(separator: " ").count }
                let estimatedSeconds = max(15, Int(Double(wordCount) / 150.0 * 60))
                return ScriptScene(
                    number: index + 1,
                    title: "Scene \(index + 1)",
                    heading: scene.heading,
                    lines: scene.lines,
                    estimatedSeconds: estimatedSeconds
                )
            }
        }
    }

    private static func cleanCharacterName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix("^") {
            name = String(name.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") {
            name.removeSubrange(open...close)
        }
        if let contRange = name.range(of: #"\s*[-–—]\s*CONT['’]?D\b"#, options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<contRange.lowerBound])
        }
        return name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildLayoutDocument(from items: [LayoutInputLine]) -> LayoutDocument {
        guard !items.isEmpty else { return LayoutDocument(pages: [], reconstructedPages: []) }
        let maxLinesPerPage = 50
        var pages: [[LayoutLine]] = []
        var reconstructedPages: [String] = []
        var currentPageItems: [LayoutInputLine] = []

        func flushPage() {
            guard !currentPageItems.isEmpty else { return }
            let pageIndex = pages.count
            let lines = currentPageItems.enumerated().map { lineIdx, item -> LayoutLine in
                let y = max(0.04, 0.92 - CGFloat(lineIdx) * 0.016)
                let width = min(0.85, max(0.10, 0.92 - item.indent))
                let rect = CGRect(x: item.indent, y: y, width: width, height: 0.014)
                return LayoutLine(text: item.text, rect: rect, pageIndex: pageIndex, estimatedIndent: item.indent)
            }
            pages.append(lines)
            reconstructedPages.append(currentPageItems.map(\.text).joined(separator: "\n"))
            currentPageItems.removeAll()
        }

        for item in items {
            if (item.pageBreakBefore && !currentPageItems.isEmpty) || currentPageItems.count >= maxLinesPerPage {
                flushPage()
            }
            currentPageItems.append(item)
        }
        flushPage()
        return LayoutDocument(pages: pages, reconstructedPages: reconstructedPages)
    }

    // MARK: - Final Draft (.fdx)

    private struct FDXParagraph {
        let type: String
        let text: String
    }

    private final class FDXParserDelegate: NSObject, XMLParserDelegate {
        var sawFinalDraftRoot = false
        var paragraphs: [FDXParagraph] = []

        private var elementStack: [String] = []
        private var currentParagraphType: String?
        private var currentParagraphText = ""
        private var insideTextElement = false

        private static let ignoredContainers: Set<String> = [
            "HeaderAndFooter", "Header", "Footer", "TitlePage", "ScriptNote", "Note", "Watermarking"
        ]

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let local = elementName.components(separatedBy: ":").last ?? elementName
            elementStack.append(local)
            if local == "FinalDraft" {
                sawFinalDraftRoot = true
            }
            guard !elementStack.contains(where: { Self.ignoredContainers.contains($0) }) else { return }

            if local == "Paragraph" {
                currentParagraphType = attributeDict["Type"] ?? "Action"
                currentParagraphText = ""
            } else if local == "Text", currentParagraphType != nil {
                insideTextElement = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard insideTextElement,
                  !elementStack.contains(where: { Self.ignoredContainers.contains($0) }) else { return }
            currentParagraphText.append(string)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let local = elementName.components(separatedBy: ":").last ?? elementName
            if local == "Text" {
                insideTextElement = false
            } else if local == "Paragraph", let type = currentParagraphType {
                let trimmed = currentParagraphText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    paragraphs.append(FDXParagraph(type: type, text: trimmed))
                }
                currentParagraphType = nil
                currentParagraphText = ""
            }
            if !elementStack.isEmpty {
                elementStack.removeLast()
            }
        }
    }

    static func parseFDX(data: Data) throws -> ([ScriptScene], LayoutDocument) {
        guard !data.isEmpty else { throw NoticeImportError.corruptDocument }
        let delegate = FDXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil,
              delegate.sawFinalDraftRoot || !delegate.paragraphs.isEmpty else {
            throw NoticeImportError.corruptDocument
        }

        var accumulator = SceneAccumulator()
        var layoutItems: [LayoutInputLine] = []

        for paragraph in delegate.paragraphs {
            let normalizedType = paragraph.type.lowercased()
            switch normalizedType {
            case "scene heading":
                accumulator.startScene(heading: paragraph.text)
                layoutItems.append(LayoutInputLine(text: paragraph.text, indent: ScreenplayIndent.leftMargin))
            case "character":
                let displayName = cleanCharacterName(paragraph.text)
                accumulator.startCharacter(paragraph.text)
                layoutItems.append(LayoutInputLine(
                    text: displayName.isEmpty ? paragraph.text : displayName,
                    indent: ScreenplayIndent.character
                ))
            case "parenthetical":
                layoutItems.append(LayoutInputLine(text: paragraph.text, indent: ScreenplayIndent.parenthetical))
            case "dialogue":
                accumulator.appendDialogue(paragraph.text)
                layoutItems.append(LayoutInputLine(text: paragraph.text, indent: ScreenplayIndent.dialogue))
            case "transition":
                accumulator.endDialogueTurn()
                layoutItems.append(LayoutInputLine(text: paragraph.text, indent: ScreenplayIndent.transition))
            default:
                accumulator.endDialogueTurn()
                layoutItems.append(LayoutInputLine(text: paragraph.text, indent: ScreenplayIndent.leftMargin))
            }
        }

        return (accumulator.buildScenes(), buildLayoutDocument(from: layoutItems))
    }

    // MARK: - Fountain (.fountain)

    static func parseFountain(text: String) -> ([ScriptScene], LayoutDocument) {
        let stripped = stripFountainComments(text)
        let rawLines = stripped.components(separatedBy: .newlines)

        var bodyStartIndex = 0
        var layoutItems: [LayoutInputLine] = []
        let titleKeyRegex = try? NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z0-9 ]{0,24}:\s*"#)

        // Skip leading Fountain Title Page key/value block before first blank line
        if let first = rawLines.first?.trimmingCharacters(in: .whitespaces),
           let titleKeyRegex,
           titleKeyRegex.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)) != nil {
            while bodyStartIndex < rawLines.count {
                let trimmed = rawLines[bodyStartIndex].trimmingCharacters(in: .whitespaces)
                bodyStartIndex += 1
                if trimmed.isEmpty { break }
                layoutItems.append(LayoutInputLine(text: trimmed, indent: ScreenplayIndent.leftMargin))
            }
        }

        var accumulator = SceneAccumulator()
        var inDialogueBlock = false
        var prevWasBlankOrStart = true

        for idx in bodyStartIndex..<rawLines.count {
            let trimmed = rawLines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if inDialogueBlock {
                    accumulator.endDialogueTurn()
                    inDialogueBlock = false
                }
                prevWasBlankOrStart = true
                continue
            }

            if trimmed.hasPrefix("===") {
                accumulator.endDialogueTurn()
                inDialogueBlock = false
                prevWasBlankOrStart = true
                continue
            }

            if trimmed.hasPrefix("#") || trimmed.hasPrefix("=") {
                accumulator.endDialogueTurn()
                inDialogueBlock = false
                prevWasBlankOrStart = false
                continue
            }

            if let heading = fountainSceneHeading(trimmed) {
                inDialogueBlock = false
                accumulator.startScene(heading: heading)
                layoutItems.append(LayoutInputLine(text: heading, indent: ScreenplayIndent.leftMargin))
                prevWasBlankOrStart = false
                continue
            }

            if isFountainTransition(trimmed) {
                accumulator.endDialogueTurn()
                inDialogueBlock = false
                let cleanTransition = trimmed.hasPrefix(">") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) : trimmed
                layoutItems.append(LayoutInputLine(text: cleanTransition, indent: ScreenplayIndent.transition))
                prevWasBlankOrStart = false
                continue
            }

            if trimmed.hasPrefix(">") && trimmed.hasSuffix("<") && trimmed.count >= 2 {
                accumulator.endDialogueTurn()
                inDialogueBlock = false
                let centered = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !centered.isEmpty {
                    layoutItems.append(LayoutInputLine(text: centered, indent: ScreenplayIndent.character))
                }
                prevWasBlankOrStart = false
                continue
            }

            if !inDialogueBlock, prevWasBlankOrStart, isFountainCharacterCue(trimmed, nextLine: nextNonEmptyLineInBlock(rawLines, after: idx)) {
                let displayName = cleanCharacterName(trimmed)
                accumulator.startCharacter(trimmed)
                inDialogueBlock = true
                layoutItems.append(LayoutInputLine(
                    text: displayName.isEmpty ? trimmed : displayName,
                    indent: ScreenplayIndent.character
                ))
                prevWasBlankOrStart = false
                continue
            }

            if inDialogueBlock {
                if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
                    layoutItems.append(LayoutInputLine(text: trimmed, indent: ScreenplayIndent.parenthetical))
                } else {
                    accumulator.appendDialogue(trimmed)
                    layoutItems.append(LayoutInputLine(text: trimmed, indent: ScreenplayIndent.dialogue))
                }
                prevWasBlankOrStart = false
                continue
            }

            let actionText = trimmed.hasPrefix("!") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) : trimmed
            layoutItems.append(LayoutInputLine(text: actionText, indent: ScreenplayIndent.leftMargin))
            prevWasBlankOrStart = false
        }

        return (accumulator.buildScenes(), buildLayoutDocument(from: layoutItems))
    }

    private static func stripFountainComments(_ text: String) -> String {
        var result = text
        if let boneyard = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#) {
            result = boneyard.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let inlineNote = try? NSRegularExpression(pattern: #"\[\[[\s\S]*?\]\]"#) {
            result = inlineNote.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
    }

    private static func fountainSceneHeading(_ trimmed: String) -> String? {
        if trimmed.hasPrefix(".") && !trimmed.hasPrefix("..") {
            let forced = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            return forced.isEmpty ? nil : forced
        }
        let upper = trimmed.uppercased()
        let prefixes = ["INT.", "EXT.", "EST.", "INT./EXT.", "INT/EXT.", "I/E.", "INT ", "EXT ", "I/E "]
        if prefixes.contains(where: { upper.hasPrefix($0) }) {
            return trimmed
        }
        return nil
    }

    private static func isFountainTransition(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix(">") && !trimmed.hasSuffix("<") {
            return true
        }
        guard trimmed.rangeOfCharacter(from: .lowercaseLetters) == nil else { return false }
        return trimmed.hasSuffix("TO:") && trimmed.count < 32
    }

    private static func nextNonEmptyLineInBlock(_ lines: [String], after index: Int) -> String? {
        guard index + 1 < lines.count else { return nil }
        let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return next.isEmpty ? nil : next
    }

    private static func isFountainCharacterCue(_ trimmed: String, nextLine: String?) -> Bool {
        guard nextLine != nil else { return false }
        if trimmed.hasPrefix("@") {
            return !cleanCharacterName(trimmed).isEmpty
        }
        var candidate = trimmed
        if candidate.hasSuffix("^") {
            candidate = String(candidate.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !candidate.isEmpty, candidate.count <= 40 else { return false }
        guard candidate.rangeOfCharacter(from: .lowercaseLetters) == nil,
              candidate.rangeOfCharacter(from: .letters) != nil else { return false }
        if fountainSceneHeading(candidate) != nil || isFountainTransition(candidate) {
            return false
        }
        return !cleanCharacterName(candidate).isEmpty
    }

    // MARK: - Word OpenXML (.docx)

    private final class DOCXParserDelegate: NSObject, XMLParserDelegate {
        var lines: [LayoutInputLine] = []

        private var inParagraph = false
        private var inTextRun = false
        private var inDeletedText = false
        private var currentText = ""
        private var currentIndentTwips: CGFloat = 0
        private var currentAlignment: String?
        private var pageBreakPending = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let local = elementName.components(separatedBy: ":").last ?? elementName
            switch local {
            case "p":
                inParagraph = true
                currentText = ""
                currentIndentTwips = 0
                currentAlignment = nil
            case "ind":
                if inParagraph {
                    let leftStr = attributeDict["w:left"] ?? attributeDict["left"] ?? attributeDict["w:start"] ?? attributeDict["start"]
                    if let leftStr, let value = Double(leftStr) {
                        currentIndentTwips = CGFloat(value)
                    }
                }
            case "jc":
                if inParagraph {
                    currentAlignment = (attributeDict["w:val"] ?? attributeDict["val"])?.lowercased()
                }
            case "delText":
                inDeletedText = true
            case "t":
                if inParagraph && !inDeletedText {
                    inTextRun = true
                }
            case "tab":
                if inParagraph && !inDeletedText {
                    currentText.append(" ")
                }
            case "br":
                let brType = (attributeDict["w:type"] ?? attributeDict["type"])?.lowercased()
                if brType == "page" {
                    pageBreakPending = true
                } else if inParagraph && !inDeletedText {
                    currentText.append("\n")
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inParagraph, inTextRun, !inDeletedText else { return }
            currentText.append(string)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let local = elementName.components(separatedBy: ":").last ?? elementName
            switch local {
            case "t":
                inTextRun = false
            case "delText":
                inDeletedText = false
            case "p":
                let indent: CGFloat = {
                    if currentIndentTwips > 0 {
                        return min(0.85, max(0.05, 0.12 + currentIndentTwips / 12240.0))
                    }
                    if currentAlignment == "center" {
                        return ScreenplayIndent.character
                    }
                    return 0.12
                }()
                let sublines = currentText.components(separatedBy: .newlines)
                for subline in sublines {
                    let trimmed = subline.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    lines.append(LayoutInputLine(text: trimmed, indent: indent, pageBreakBefore: pageBreakPending))
                    pageBreakPending = false
                }
                inParagraph = false
                inTextRun = false
                currentText = ""
            default:
                break
            }
        }
    }

    static func parseDOCX(url: URL) throws -> LayoutDocument {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try ZipArchive.extract(from: url, to: tempDir)
        } catch {
            throw NoticeImportError.corruptDocument
        }

        let documentXMLURL = tempDir.appendingPathComponent("word/document.xml")
        guard let xmlData = try? Data(contentsOf: documentXMLURL), !xmlData.isEmpty else {
            throw NoticeImportError.corruptDocument
        }

        let delegate = DOCXParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil, !delegate.lines.isEmpty else {
            throw NoticeImportError.corruptDocument
        }

        return buildLayoutDocument(from: delegate.lines)
    }
}
