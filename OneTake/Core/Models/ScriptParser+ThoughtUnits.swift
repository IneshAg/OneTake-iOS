import Foundation

extension ScriptParser {
    // MARK: - Thought Unit & Beat Division (Algorithmic Model)

    /// Divides long dialogue blocks or monologues into natural, deliverable thought units / breath beats
    /// (typically 8 to 22 words) so that:
    /// 1. Teleprompter cards are easily readable at high font sizes without overwhelming blocks of text.
    /// 2. Speech recognition matches each beat smoothly and advances accurately.
    /// 3. Memory drills (First Letter, Mask & Reveal) operate on digestible chunks.
    /// Works offline deterministically with high accuracy across all iOS versions.
    static func divideIntoThoughtUnits(_ text: String) -> [String] {
        // Strip parenthetical/bracketed stage directions like (beat) or [whispering]
        let stripped = text.replacingOccurrences(of: #"\([^\)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        let cleaned = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // Short lines (under 22 words) stay intact
        let words = cleaned.split(separator: " ")
        if words.count <= 22 {
            return [cleaned]
        }

        // 1. Split into raw sentences using punctuation boundaries (. ! ? …) while protecting abbreviations
        let rawSentences = splitIntoSentences(cleaned)
        guard rawSentences.count > 1 || words.count > 28 else {
            return [cleaned]
        }

        var units: [String] = []
        var currentUnit = ""
        var currentWordCount = 0

        for sentence in rawSentences {
            let sTrimmed = sentence.trimmingCharacters(in: .whitespaces)
            guard !sTrimmed.isEmpty else { continue }
            let sWords = sTrimmed.split(separator: " ").count

            // If a single sentence is very long (> 28 words), split it at clause boundaries
            if sWords > 28 {
                if !currentUnit.isEmpty {
                    units.append(currentUnit)
                    currentUnit = ""
                    currentWordCount = 0
                }
                let clauses = splitLongSentenceIntoClauses(sTrimmed)
                for clause in clauses {
                    units.append(clause)
                }
                continue
            }

            // If adding this sentence keeps the unit under ~20 words, group them (e.g. short question + short answer)
            if currentUnit.isEmpty {
                currentUnit = sTrimmed
                currentWordCount = sWords
            } else if currentWordCount + sWords <= 20 {
                currentUnit += " " + sTrimmed
                currentWordCount += sWords
            } else {
                units.append(currentUnit)
                currentUnit = sTrimmed
                currentWordCount = sWords
            }
        }

        if !currentUnit.isEmpty {
            units.append(currentUnit)
        }

        return units.isEmpty ? [cleaned] : units
    }

    /// Splits text into sentences by looking for punctuation followed by whitespace,
    /// protecting common titles, abbreviations, initials, and decimal numbers.
    private static func splitIntoSentences(_ text: String) -> [String] {
        var protected = text

        // Known abbreviations
        let abbrevs = [
            "Mr.", "Mrs.", "Ms.", "Dr.", "Prof.", "Rev.", "Capt.", "Lt.", "Col.", "Gen.", "Sgt.", "St.",
            "U.S.", "U.K.", "E.U.", "N.Y.", "D.C.", "e.g.", "i.e.", "etc.", "vs.", "a.m.", "p.m.",
            "I-H-R-A-M."
        ]
        let token = "\u{FFFC}"
        for abbrev in abbrevs {
            let escaped = abbrev.replacingOccurrences(of: ".", with: token)
            protected = protected.replacingOccurrences(of: abbrev, with: escaped)
            protected = protected.replacingOccurrences(of: abbrev.lowercased(), with: escaped.lowercased())
        }

        // Single letter initials like "J. Doe" or "A. Smith"
        if let regex = try? NSRegularExpression(pattern: #"\b([A-Za-z])\."#) {
            let range = NSRange(protected.startIndex..., in: protected)
            protected = regex.stringByReplacingMatches(in: protected, range: range, withTemplate: "$1\(token)")
        }

        // Decimals like "3.5"
        if let regex = try? NSRegularExpression(pattern: #"(\d)\.(\d)"#) {
            let range = NSRange(protected.startIndex..., in: protected)
            protected = regex.stringByReplacingMatches(in: protected, range: range, withTemplate: "$1\(token)$2")
        }

        // Split on sentence terminals: . ! ? … followed by whitespace or quotes
        var sentences: [String] = []
        var current = ""
        let chars = Array(protected)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)

            let isTerminal = (c == "." || c == "!" || c == "?" || c == "…")
            if isTerminal {
                // Check if followed by quote and then whitespace, or directly whitespace
                var peek = i + 1
                while peek < chars.count && (chars[peek] == "\"" || chars[peek] == "”" || chars[peek] == "’" || chars[peek] == "'") {
                    current.append(chars[peek])
                    peek += 1
                    i = peek - 1
                }

                if peek < chars.count && chars[peek].isWhitespace {
                    let restored = current.replacingOccurrences(of: token, with: ".").trimmingCharacters(in: .whitespaces)
                    if !restored.isEmpty {
                        sentences.append(restored)
                        current = ""
                    }
                    while peek < chars.count && chars[peek].isWhitespace {
                        peek += 1
                    }
                    i = peek - 1
                }
            }
            i += 1
        }

        let remaining = current.replacingOccurrences(of: token, with: ".").trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }

        return sentences
    }

    /// Breaks a long sentence (> 28 words) at natural clause boundaries (semicolons, dashes, or conjunction commas)
    private static func splitLongSentenceIntoClauses(_ sentence: String) -> [String] {
        // First try splitting on semicolons, em-dashes, or ellipses
        let dashOrSemiSeparators = ["; ", " — ", "—", " -- ", " --", " ... ", "… "]
        for sep in dashOrSemiSeparators {
            if sentence.contains(sep) {
                let parts = sentence.components(separatedBy: sep)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if parts.count > 1 && parts.allSatisfy({ $0.split(separator: " ").count >= 5 }) {
                    return parts
                }
            }
        }

        // Try splitting on conjunction commas
        let conjunctions = [", but ", ", so ", ", and ", ", because ", ", which ", ", where ", ", though ", ", although ", ", while ", ", yet ", ", unless "]
        for conj in conjunctions {
            if let range = sentence.range(of: conj) {
                let first = String(sentence[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let second = String(sentence[range.lowerBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
                let fCount = first.split(separator: " ").count
                let sCount = second.split(separator: " ").count
                if fCount >= 8 && sCount >= 8 {
                    return [first, second]
                }
            }
        }

        return [sentence]
    }

    // MARK: - Hierarchical Scene Portion Chunking (Pass 2)

    /// A bounded, independently parseable chunk of a sides document representing a single scene or monologue.
    struct ScenePortion: Identifiable, Hashable, Sendable {
        var id: String
        var number: Int
        var heading: String
        var characters: [String]
        var rawText: String
        var lineCount: Int
        var pageNumber: Int?

        var displayTitle: String {
            if heading.isEmpty { return "Scene \(number)" }
            return heading
        }
    }

    /// Identifies individual scene portions from a multi-page sides document without parsing all lines yet.
    /// Splits by scene headings (e.g. ACT ONE SCENE SIX, INT. / EXT., SCENE 1) or monologue cuts.
    static func identifyScenePortions(from text: String, pages: [String] = []) -> [ScenePortion] {
        var portions: [ScenePortion] = []

        let sceneHeadingRegex = try? NSRegularExpression(
            pattern: #"(?im)^[\s>*—\-\[\]]*(?:ACT\s+(?:ONE|TWO|THREE|[0-9IVX]+)(?:[\s,]+SCENE\s+[0-9IVX]+)?|(?:INT\.|EXT\.|INT/EXT|EXT/INT)\s+.*|SCENE\s+[0-9A-Z]+|For\s+(?:Female|Male|Any)\s+(?:Identifying|Gender)|[A-Z]{2,20}\s*[-—–]\s*(?:Page|Pg\.?)\s*\d+)\b"#
        )

        let lines = text.components(separatedBy: .newlines)
        var currentHeading: String? = nil
        var currentLines: [String] = []
        var sceneCounter = 1

        func saveCurrentPortion() {
            guard !currentLines.isEmpty else { return }
            let rawChunk = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawChunk.isEmpty, rawChunk.count > 40 else { return }

            let chars = extractCharacters(from: rawChunk).map { $0.uppercased() }
            // A heading alone (or a casting notice page) is not a selectable scene. Require
            // actual dialogue cues so page chunks cannot create empty/fake scene checklist items.
            guard !chars.isEmpty else { return }

            let heading = currentHeading ?? "Scene \(sceneCounter)"
            let estimatedLines = rawChunk.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count

            let portion = ScenePortion(
                id: "scene-\(sceneCounter)-\(abs(heading.hashValue))",
                number: sceneCounter,
                heading: heading,
                characters: chars,
                rawText: rawChunk,
                lineCount: estimatedLines,
                pageNumber: nil
            )
            portions.append(portion)
            sceneCounter += 1
            currentLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHeading: Bool
            if let regex = sceneHeadingRegex,
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               match.range.location == 0 {
                isHeading = true
            } else {
                isHeading = false
            }

            if isHeading {
                saveCurrentPortion()
                currentHeading = trimmed
                currentLines.append(line)
            } else {
                currentLines.append(line)
            }
        }
        saveCurrentPortion()

        // Fallback: If no explicit headings split the text but multiple pages exist, use page boundaries
        if portions.count <= 1 && pages.count > 1 {
            portions.removeAll()
            let startIdx = pages.count >= 3 ? 1 : 0
            for (idx, pageText) in pages[startIdx...].enumerated() {
                let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let chars = extractCharacters(from: trimmed).map { $0.uppercased() }
                guard !chars.isEmpty else { continue }
                let firstLine = trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? "Page \(idx + startIdx + 1)"
                portions.append(
                    ScenePortion(
                        id: "page-\(idx + startIdx + 1)",
                        number: idx + 1,
                        heading: firstLine,
                        characters: chars,
                        rawText: trimmed,
                        lineCount: trimmed.components(separatedBy: .newlines).count,
                        pageNumber: idx + startIdx + 1
                    )
                )
            }
        }

        return portions
    }

    /// Pass 2: Parses only the user-selected scene portions independently, then concatenates them
    /// into a unified list of [ScriptScene] with consistent sequential numbering.
    static func parseSelectedPortions(_ portions: [ScenePortion], myRole: String) -> [ScriptScene] {
        var allScenes: [ScriptScene] = []
        var sceneNumber = 1

        for portion in portions {
            let scenes = parseScenes(from: portion.rawText, myRole: myRole)
            for s in scenes {
                let renumbered = ScriptScene(
                    number: sceneNumber,
                    title: "Scene \(sceneNumber)",
                    heading: portion.heading.isEmpty ? s.heading : portion.heading,
                    lines: s.lines,
                    estimatedSeconds: s.estimatedSeconds
                )
                allScenes.append(renumbered)
                sceneNumber += 1
            }
        }
        return allScenes
    }
}
