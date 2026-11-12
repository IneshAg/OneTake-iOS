import Foundation

// MARK: - ScriptParser Dialogue Normalization & Text Sanitization

extension ScriptParser {
    /// Strips punctuation, extra whitespace, and case differences while preserving the spoken content.
    static func normalizeDialogue(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Strips parentheticals like "(whispering)" or "[laughing]" from dialogue lines
    static func stripParentheticals(_ text: String) -> String {
        var result = text
        while let open = result.firstIndex(of: "("), let close = result[open...].firstIndex(of: ")") {
            result.removeSubrange(open...close)
        }
        while let open = result.firstIndex(of: "["), let close = result[open...].firstIndex(of: "]") {
            result.removeSubrange(open...close)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sanitizes and properly formats text pasted from clipboard (emails, Notes, PDF text, Word docs)
    static func cleanPastedText(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }

        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")

        if let contractionRegex = try? NSRegularExpression(pattern: #"\b([A-Za-z]+)\s*'\s*([stmdre]|ve|ll)\b"#, options: [.caseInsensitive]) {
            text = contractionRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1'$2")
        }
        if let cantRegex = try? NSRegularExpression(pattern: #"\b([Cc])\s*a\s*n\s*'\s*t\b"#) {
            text = cantRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1an't")
        }
        if let wontRegex = try? NSRegularExpression(pattern: #"\b([Ww])\s*o\s*n\s*'\s*t\b"#) {
            text = wontRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1on't")
        }
        if let hyphenRegex = try? NSRegularExpression(pattern: #"(\b[A-Za-z]{2,})-\s*\n\s*([a-z]{2,}\b)"#) {
            text = hyphenRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1$2")
        }

        let lines = text.components(separatedBy: "\n").map { line -> String in
            let leadingIndentation = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            var l = line.trimmingCharacters(in: .whitespaces)
            let hasEmailOrURL = l.contains("@") || l.contains("http://") || l.contains("https://") || l.contains("www.") || l.range(of: #"[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}(?:/|\b)"#, options: .regularExpression) != nil
            if !hasEmailOrURL {
                if let spaceBefore = try? NSRegularExpression(pattern: #"\s+([,.:;?!])"#) {
                    l = spaceBefore.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1")
                }
                if let missingSpace = try? NSRegularExpression(pattern: #"([,.:;?!])([A-Za-z])"#) {
                    l = missingSpace.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1 $2")
                }
            } else {
                if let spaceBefore = try? NSRegularExpression(pattern: #"\s+([,;?!])"#) {
                    l = spaceBefore.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1")
                }
                if let commaSpace = try? NSRegularExpression(pattern: #"([,;])([A-Za-z])"#) {
                    l = commaSpace.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1 $2")
                }
            }
            if leadingIndentation.count >= 14, isLikelyCue(l) {
                return leadingIndentation + l
            }
            return l
        }

        var formattedLines: [String] = []
        for line in lines {
            if !line.isEmpty, isLikelyCue(line), let previous = formattedLines.last, !previous.isEmpty {
                formattedLines.append("")
            }
            formattedLines.append(line)
        }

        return formattedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Formats dialogue extracted from sides OCR and normalizes quotes, contractions, and punctuation
    static func formatDialogueText(_ raw: String) -> String {
        let unparenthetical = stripParentheticals(raw)
        guard !unparenthetical.isEmpty else { return "" }

        var text = unparenthetical
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")

        if let contractionRegex = try? NSRegularExpression(pattern: #"\b([A-Za-z]+)\s*'\s*([stmdre]|ve|ll)\b"#, options: [.caseInsensitive]) {
            text = contractionRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1'$2")
        }
        if let cantRegex = try? NSRegularExpression(pattern: #"\b([Cc])\s*a\s*n\s*'\s*t\b"#) {
            text = cantRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1an't")
        }
        if let wontRegex = try? NSRegularExpression(pattern: #"\b([Ww])\s*o\s*n\s*'\s*t\b"#) {
            text = wontRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1on't")
        }
        if let regex = try? NSRegularExpression(pattern: #"(\b[A-Za-z]{2,})-\s+([a-z]{2,}\b)"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1$2")
        }
        if let spaceBeforePunct = try? NSRegularExpression(pattern: #"\s+([,.:;?!])"#) {
            text = spaceBeforePunct.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
        }
        if let missingSpaceAfter = try? NSRegularExpression(pattern: #"([,.:;?!])([A-Za-z])"#) {
            text = missingSpaceAfter.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1 $2")
        }

        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            let lastChar = text.last!
            if !".?!\"'…".contains(lastChar) {
                text.append(".")
            }
        }

        return text
    }
}
