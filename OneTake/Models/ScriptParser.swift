import Foundation

/// Turns real screenplay-formatted text (from a scan, a PDF, or a pasted email) into `ScriptLine`s —
/// no network call, no fixed example to fall back on. Two conventions are recognised, both common in
/// real sides: a short ALL-CAPS line on its own starting a new speaker ("ARJUN" then dialogue below),
/// and "CHARACTER: dialogue" on one line. Anything that doesn't look like either is skipped rather than
/// guessed at.
enum ScriptParser {
    /// Reclassifies the already parsed dialogue when the actor corrects their role name.
    static func reclassify(_ scenes: [ScriptScene], myRole: String) -> [ScriptScene] {
        let roleName = normalizedName(myRole)
        return scenes.map { scene in
            var scene = scene
            scene.lines = scene.lines.map { line in
                var line = line
                line.isMine = isSameCharacter(normalizedName(line.character), roleName)
                return line
            }
            return scene
        }
    }

    /// Extracts all unique character names found in script dialogue cues, ranked by frequency.
    static func extractCharacters(from text: String) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let scenes = parseScenes(from: text, myRole: "")
        var counts: [String: Int] = [:]
        var order: [String] = []
        for scene in scenes {
            for line in scene.lines {
                let char = line.character.trimmingCharacters(in: .whitespaces)
                guard !char.isEmpty else { continue }
                if counts[char] == nil {
                    order.append(char)
                }
                counts[char, default: 0] += 1
            }
        }
        return order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    static func parseScenes(from text: String, myRole: String) -> [ScriptScene] {
        // Blank lines are kept: in screenplay format a blank line ends a dialogue block, and whatever
        // follows (action, description) belongs to no one until the next cue.
        let rawLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let roleName = normalizedName(myRole)

        // Mixed-case "Maya: Hello" cues (emails, Word files, OCR) aren't all-caps, so they used to be
        // skipped and the sides came out empty. A name counts as a speaker when it speaks more than
        // once or is the actor's own role, so one-off labels ("Note: …") stay out.
        var speakerCounts: [String: Int] = [:]
        for raw in rawLines {
            guard let colon = raw.firstIndex(of: ":"), let key = speakerKey(String(raw[..<colon])) else { continue }
            speakerCounts[key, default: 0] += 1
        }
        let speakers = Set(speakerCounts.filter { $0.value >= 2 || isSameCharacter(normalizedName($0.key), roleName) }.keys)
        // Sides often hold more than one scene, each opening on a slugline ("INT. KITCHEN — NIGHT")
        // or a "SCENE 2" header; each becomes its own scene so it can be prepared and shot alone.
        var scenes: [(heading: String, lines: [ScriptLine])] = []
        var heading = "SIDES"
        var lines: [ScriptLine] = []
        var currentCharacter: String?
        var currentText = ""

        func flush() {
            guard let character = currentCharacter else { return }
            let cleaned = stripParentheticals(currentText)
            guard !cleaned.isEmpty else {
                currentText = ""
                return
            }
            let mine = isSameCharacter(normalizedName(character), roleName)
            lines.append(ScriptLine(character: character.capitalized, text: cleaned, isMine: mine))
            currentText = ""
        }

        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // End of the dialogue block
                if !currentText.isEmpty {
                    flush()
                    currentCharacter = nil
                }
                continue
            }

            if isSceneHeading(trimmed) {
                flush()
                currentCharacter = nil
                if !lines.isEmpty {
                    scenes.append((heading, lines))
                    lines = []
                }
                heading = trimmed
            } else if isActHeading(trimmed) || isWebJunkOrFooter(trimmed) {
                flush()
                currentCharacter = nil
            } else if isLineOrPageNumber(trimmed) {
                // Line numbers or page numbers (e.g. "91", "92", "Page 4") - ignore without ending dialogue
                continue
            } else if isTransition(trimmed) || isActionOrDescription(trimmed, knownSpeakers: speakers) {
                flush()
                currentCharacter = nil
            } else if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
                // Standalone parenthetical stage direction (e.g. "(whispering)") — ignore without flushing speaker
                continue
            } else if let colon = trimmed.firstIndex(of: ":"),
                      isLikelyCue(String(trimmed[..<colon])) || speakerKey(String(trimmed[..<colon])).map({ speakers.contains($0) }) == true {
                flush()
                currentCharacter = cueName(String(trimmed[..<colon]))
                currentText = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else if isLikelyCue(trimmed) {
                flush()
                currentCharacter = cueName(trimmed)
            } else if currentCharacter != nil {
                currentText += (currentText.isEmpty ? "" : " ") + trimmed
            }
            // Anything before the first cue (stray header text, action lines) is skipped.
        }
        flush()
        if !lines.isEmpty { scenes.append((heading, lines)) }

        return scenes.enumerated().map { i, scene in
            // ~150 wpm reading pace is a reasonable estimate for "how long this will take to shoot".
            let wordCount = scene.lines.reduce(0) { $0 + $1.text.split(separator: " ").count }
            let estimatedSeconds = max(15, Int(Double(wordCount) / 150.0 * 60))
            return ScriptScene(number: i + 1, title: "Scene \(i + 1)", heading: scene.heading,
                               lines: scene.lines, estimatedSeconds: estimatedSeconds)
        }
    }

    /// Regex for matching scene headers ("SCENE 1", "SC. 2", "SCENE 14A"), using standard NSRegularExpression
    /// for full compatibility across iOS 14 and earlier.
    private static let sceneHeaderRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^(SCENE|SC\\.?)\\s*(\\d+[A-Z]?)\\b", options: [.caseInsensitive])
    }()

    /// Where a new scene starts: a slugline ("INT. CAFÉ — DAY", "EXT/INT CAR", "I/E") or a scene
    /// header like "SCENE 2" / "SC. 14". Compatible with iOS 14 and earlier.
    static func isSceneHeading(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, line.count < 80 else { return false }
        let upper = line.uppercased()
        let sluglinePrefixes = ["INT.", "EXT.", "INT/EXT", "EXT/INT", "INT./EXT", "EXT./INT", "I/E", "INT ", "EXT "]
        if line == upper, sluglinePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        guard let regex = sceneHeaderRegex,
              let match = regex.firstMatch(in: upper, options: [], range: NSRange(location: 0, length: (upper as NSString).length)),
              let range = Range(match.range, in: upper) else { return false }
        let rest = upper[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.first.map { ":.-–—(".contains($0) } ?? true
    }

    /// Identifies stage directions or action/scene descriptions that should not be spoken
    static func isActionOrDescription(_ raw: String, knownSpeakers: Set<String> = []) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Entirely a parenthetical or bracketed stage direction
        if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return true
        }

        let upper = trimmed.uppercased()

        // All-caps full sentence with punctuation (e.g. "KAT FRETS OVER OSCAR WHO IS TOUCHING HIS CHEST.")
        if upper == trimmed && (trimmed.hasSuffix(".") || trimmed.hasSuffix("!")) {
            let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count >= 3 { return true }
        }

        // Common standalone stage directions and scene time/setting markers
        let directions: Set<String> = [
            "BEAT", "BEAT.", "A BEAT.", "PAUSE", "PAUSE.", "SILENCE", "SILENCE.",
            "MOMENT", "MOMENT.", "LONG PAUSE.", "CONTINUOUS", "LATER", "MOMENTS LATER",
            "SAME TIME", "FLASHBACK", "DAY", "NIGHT", "DUSK", "DAWN", "MORNING", "EVENING"
        ]
        if directions.contains(upper) { return true }

        // Camera directions
        let cameraPrefixes = ["ANGLE ON", "CLOSE ON", "CLOSE-UP", "WIDE SHOT", "INSERT", "P.O.V.", "POV", "SOUND OF", "WE HEAR", "WE SEE", "CAMERA", "IN THE DISTANCE"]
        if cameraPrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        // Third-person narration starts: "He ", "She ", "They ", "The door ", etc.
        let narrationPrefixes = ["HE ", "SHE ", "THEY ", "BOTH ", "THE DOOR ", "THE PHONE ", "A CAR ", "SUDDENLY ", "HER EYES ", "HIS EYES "]
        if narrationPrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        // Character action verbs: e.g. "Maya looks at him", "Arjun walks to the door"
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let firstWordKey = words[0].trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—,")) .uppercased()
            let secondWord = words[1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",."))
            let actionVerbs: Set<String> = [
                "walks", "looks", "turns", "enters", "exits", "sits", "stands", "takes", "grabs",
                "pauses", "smiles", "laughs", "sighs", "stares", "crosses", "moves", "picks",
                "puts", "reaches", "opens", "closes", "glances", "nods", "shakes", "pulls",
                "pushes", "drops", "stops", "begins", "waits", "watches", "runs", "steps",
                "hurries", "freezes", "leaves", "approaches", "rises", "falls", "leans", "checks"
            ]
            if actionVerbs.contains(secondWord) {
                if knownSpeakers.contains(firstWordKey) || ["HE", "SHE", "THEY", "MAYA", "ARJUN"].contains(firstWordKey) {
                    return true
                }
            }
        }

        return false
    }

    /// Strips parentheticals like "(whispering)" or "[laughing]" from dialogue lines so actor/reader
    /// doesn't read stage directions out loud.
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

    /// A line is a plausible character cue if it's short, has no lowercase letters, and has at least
    /// one real letter (filters out page numbers, "---", scene-heading punctuation runs, etc).
    private static func isLikelyCue(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 1, trimmed.count < 28 else { return false }
        guard trimmed.rangeOfCharacter(from: .lowercaseLetters) == nil else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        // Cues never end with sentence-ending punctuation or colons
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || trimmed.hasSuffix(":") { return false }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("ACT ") || upper.hasPrefix("SCENE ") || upper.hasPrefix("SC.") || upper.hasPrefix("SC ") { return false }
        // Reject screenplay sluglines (INT./EXT.) which are also all-caps and short.
        if upper.hasPrefix("INT.") || upper.hasPrefix("EXT.") || upper.hasPrefix("INT/EXT") { return false }
        if isTransition(trimmed) || cueName(trimmed).isEmpty { return false }
        return true
    }

    /// "Maya" / "Dr. Rao" / "Maya Kapoor" before a colon — a short, capitalised name, not a label like
    /// "Note" or "Due". Returns the upper-cased key used to count how often someone speaks.
    private static func speakerKey(_ raw: String) -> String? {
        let name = cueName(raw.trimmingCharacters(in: .whitespaces))
        guard name.count >= 2, name.count <= 24 else { return nil }
        let words = name.split(separator: " ")
        guard (1...3).contains(words.count) else { return nil }
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "'.-"))
        for word in words {
            guard word.unicodeScalars.allSatisfy({ allowed.contains($0) }), word.first?.isUppercase == true else { return nil }
        }
        let key = name.uppercased()
        let labels: Set<String> = ["ROLE", "PROJECT", "TITLE", "DUE", "DATE", "TIME", "NOTE", "NOTES", "LOCATION", "SIDES",
                                   "SCENE", "SUBJECT", "FROM", "TO", "CC", "RE", "DEADLINE", "CASTING", "CASTING DIRECTOR",
                                   "DESTINATION", "FORMAT", "LENGTH", "SLATE", "SUBMIT", "CHARACTER", "PART", "PLAYING",
                                   "NB", "PS", "P.S.", "STEP", "OPTION", "SENT", "HEIGHT", "AGE", "EMAIL", "PHONE"]
        return labels.contains(key) ? nil : key
    }

    /// Scene transitions and page furniture: all-caps and short like a cue, but nobody says them.
    private static func isTransition(_ raw: String) -> Bool {
        guard raw.rangeOfCharacter(from: .lowercaseLetters) == nil else { return false }
        let bare = raw.trimmingCharacters(in: CharacterSet(charactersIn: ":.").union(.whitespaces))
        let exact: Set<String> = ["FADE IN", "FADE OUT", "FADE TO BLACK", "CUT TO BLACK", "THE END",
                                  "CONTINUED", "(CONTINUED)", "MORE", "(MORE)", "BACK TO SCENE", "INTERCUT"]
        if exact.contains(bare) { return true }
        // "CUT TO:", "SMASH CUT TO:", "DISSOLVE TO:", "MATCH CUT TO:" …
        return bare.hasSuffix(" TO") && bare.count < 28
    }

    /// The speaker's name with screenplay extensions dropped: "ARJUN (CONT'D)" / "ARJUN (V.O.)" → "ARJUN".
    private static func cueName(_ raw: String) -> String {
        var name = raw
        while let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") {
            name.removeSubrange(open...close)
        }
        return name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalizedName(_ raw: String) -> [String] {
        cueName(raw).uppercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
    }

    static func isSameRole(_ cueString: String, _ roleString: String) -> Bool {
        isSameCharacter(normalizedName(cueString), normalizedName(roleString))
    }

    /// Whole-word match, so a cue of "MAYA" matches the role "Maya Kapoor" (and vice versa) but a
    /// short cue like "AN" no longer matches "Anaya" the way a substring check did.
    private static func isSameCharacter(_ cue: [String], _ role: [String]) -> Bool {
        guard !cue.isEmpty, !role.isEmpty else { return false }
        let cueSet = Set(cue), roleSet = Set(role)
        if cueSet.isSubset(of: roleSet) || roleSet.isSubset(of: cueSet) { return true }
        if cueSet.contains(where: { c in c.count >= 3 && roleSet.contains(where: { r in r.hasPrefix(c) || c.hasPrefix(r) }) }) {
            return true
        }
        return false
    }

    /// Standalone line numbers, page counters, or script numbering (e.g. "91", "92", "p. 14")
    private static func isLineOrPageNumber(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.allSatisfy(\.isNumber) { return true }
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#.-–— "))
        if !stripped.isEmpty && stripped.allSatisfy(\.isNumber) { return true }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("page ") || lower.hasPrefix("p. ") || lower.hasPrefix("pg. ") {
            let after = lower.dropFirst(lower.hasPrefix("page ") ? 5 : 3).trimmingCharacters(in: .whitespaces)
            if after.allSatisfy(\.isNumber) { return true }
        }
        return false
    }

    /// Web search chrome, URL fragments, watermarks, and browser UI artifacts from screenshots
    private static func isWebJunkOrFooter(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.count == 1 && "<>«»‹›•@|".contains(trimmed) { return true }
        let lower = trimmed.lowercased()
        if lower.contains("%2f") || lower.contains("http://") || lower.contains("https://") || lower.contains("www.") || lower.contains("image%2b") || lower.contains(".jpg") || lower.contains(".png") || lower.contains("%2b") {
            return true
        }
        let chromePhrases = ["visit ›", "visit >", "share", "@ share", "• save", "save", "bookmark", "view on", "click here", "read more"]
        if chromePhrases.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasSuffix(" " + $0) }) {
            return true
        }
        if trimmed.hasPrefix("• ") || trimmed.hasPrefix("› ") || trimmed.hasSuffix(" ›") || trimmed.hasSuffix(" >") {
            return true
        }
        if lower.contains("writers guild") || lower.contains("spec script") || lower.contains("all rights reserved") || lower.contains("copyright ©") {
            return true
        }
        return false
    }

    /// Screenplay act markers (e.g. "ACT TWO", "COLD OPEN", "PROLOGUE")
    private static func isActHeading(_ raw: String) -> Bool {
        let upper = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return upper.hasPrefix("ACT ") || upper.hasPrefix("ACT ONE") || upper.hasPrefix("ACT TWO") || upper.hasPrefix("COLD OPEN") || upper.hasPrefix("PROLOGUE") || upper.hasPrefix("EPILOGUE")
    }
}
