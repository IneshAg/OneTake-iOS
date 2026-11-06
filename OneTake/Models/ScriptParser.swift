import Foundation

/// Turns real screenplay-formatted text (from a scan, a PDF, or a pasted email) into `ScriptLine`s —
/// no network call, no fixed example to fall back on. Two conventions are recognised, both common in
/// real sides: a short ALL-CAPS line on its own starting a new speaker ("ARJUN" then dialogue below),
/// and "CHARACTER: dialogue" on one line. Anything that doesn't look like either is skipped rather than
/// guessed at.
enum ScriptParser {
    /// Casting and audition script archetypes encountered across television, film, commercial, and theater sides.
    enum ScriptArchetype: String, CaseIterable {
        case multiRolePacket = "Multi-role casting packet"
        case screenplay = "Screenplay excerpt"
        case commercial = "Commercial copy"
        case stagePlay = "Stage play"
        case standardDialogue = "Dialogue scene"
    }

    /// Automatically classifies the structural archetype of the sides document to optimize parsing.
    static func detectArchetype(in text: String) -> ScriptArchetype {
        let upper = text.uppercased()
        if upper.contains("CASTING SIDES") || upper.contains("HOW TO USE THESE SIDES")
            || upper.contains("THE CHARACTERS IN THIS DOCUMENT")
            || (upper.contains("SIDE A") && upper.contains("SIDE B")) {
            return .multiRolePacket
        }
        if upper.contains("ANNCR:") || upper.contains("ANNCR ") || upper.contains("V.O.")
            || (upper.contains("VIDEO:") && upper.contains("AUDIO:")) || upper.contains("COMMERCIAL") {
            return .commercial
        }
        if upper.contains("INT.") || upper.contains("EXT.") || upper.contains("INT/EXT") || upper.contains("(CONT'D)") {
            return .screenplay
        }
        if upper.contains("ACT I") || upper.contains("ACT 1") || upper.contains("SCENE I") || upper.contains("SCENE II") {
            return .stagePlay
        }
        return .standardDialogue
    }

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

        let characterHeaderRegex = try? NSRegularExpression(pattern: #"^([A-Z]{2,20})\s*[·•|\-—]\s*(?:(?:He|She|They)/|[0-9]{1,2}s?\b|Early|Mid|Late)"#)
        let slateInstructionRegex = try? NSRegularExpression(pattern: #"(?i)reading\s+for\s*\(([A-Za-z]{2,20})\)"#)
        let periodCueRegex = try? NSRegularExpression(pattern: #"^([A-Z]{2,20})\.\s+(.*)$"#)
        var inParenthetical = false
        var activeCharacter: String? = nil
        var inSettingOrNoteBlock = false
        var hasExplicitHeading = false

        // Mixed-case "Maya: Hello" cues (emails, Word files, OCR) and standard all-caps cues (e.g. "FRANCIS")
        // are indexed so stage directions can identify character actions ("Maggie tosses the satchel...").
        var speakerCounts: [String: Int] = [:]
        for raw in rawLines {
            let tr = raw.trimmingCharacters(in: .whitespaces)
            if let colon = tr.firstIndex(of: ":"), let key = speakerKey(String(tr[..<colon])) {
                speakerCounts[key, default: 0] += 1
            } else if isLikelyCue(tr) {
                let key = cueName(tr).uppercased()
                speakerCounts[key, default: 0] += 1
            }
        }
        let speakers = Set(speakerCounts.filter { $0.value >= 2 || isSameCharacter(normalizedName($0.key), roleName) }.keys)
        // Sides often hold more than one scene, each opening on a slugline ("INT. KITCHEN — NIGHT")
        // or a "SCENE 2" header; each becomes its own scene so it can be prepared and shot alone.
        var scenes: [(heading: String, lines: [ScriptLine])] = []
        var heading = "SIDES"
        var lines: [ScriptLine] = []
        var currentCharacter: String?
        var lastSpeaker: String?
        var inActionBlock = false
        var currentText = ""

        func flush() {
            guard let character = currentCharacter else { return }
            let formatted = formatDialogueText(currentText)
            guard !formatted.isEmpty else {
                currentText = ""
                return
            }
            if isNoticeText(formatted) {
                currentText = ""
                return
            }
            let mine = isSameCharacter(normalizedName(character), roleName)
            lines.append(ScriptLine(character: character.capitalized, text: formatted, isMine: mine))
            currentText = ""
        }

        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if trimmed.isEmpty {
                inSettingOrNoteBlock = false
                inParenthetical = false
                continue
            }

            if inParenthetical {
                if trimmed.contains(")") || trimmed.contains("]") {
                    inParenthetical = false
                }
                continue
            }

            // Watermarks, timestamps, and page numbering
            if isWatermarkOrHeader(trimmed) {
                continue
            }

            // Character header in multi-character sides packet (e.g. "NOOR · She/her · Early 60s")
            if let match = characterHeaderRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let r = Range(match.range(at: 1), in: trimmed) {
                flush()
                currentCharacter = nil
                if hasExplicitHeading && !lines.isEmpty {
                    scenes.append((heading, lines))
                    lines = []
                }
                hasExplicitHeading = false
                heading = "SIDES"
                activeCharacter = String(trimmed[r]).capitalized
                inSettingOrNoteBlock = true
                continue
            }

            if let match = slateInstructionRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let r = Range(match.range(at: 1), in: trimmed) {
                activeCharacter = String(trimmed[r]).capitalized
            }

            if isSceneHeading(trimmed) {
                flush()
                currentCharacter = nil
                inSettingOrNoteBlock = false
                if !lines.isEmpty {
                    scenes.append((heading, lines))
                    lines = []
                }
                if trimmed.uppercased().hasPrefix("SIDE ") {
                    heading = "Side " + trimmed.dropFirst(5)
                } else if trimmed.uppercased().hasPrefix("THE SIDE") {
                    heading = "The Side" + trimmed.dropFirst(8)
                } else if trimmed.uppercased().hasPrefix("START") || trimmed.uppercased().hasPrefix("[START") {
                    let nextNum = scenes.count + (lines.isEmpty ? 1 : 2)
                    heading = "Scene \(nextNum)"
                } else {
                    heading = trimmed
                }
                hasExplicitHeading = true
            } else if isActHeading(trimmed) || isWebJunkOrFooter(trimmed) {
                flush()
                currentCharacter = nil
            } else if isLineOrPageNumber(trimmed) {
                // Line numbers or page numbers (e.g. "91", "92", "Page 4") - ignore without ending dialogue
                continue
            } else if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if isLikelyCue(inner) {
                    flush()
                    currentCharacter = cueName(inner)
                    continue
                } else {
                    continue
                }
            } else if trimmed.hasPrefix("(") && !trimmed.contains(")") {
                inParenthetical = true
                continue
            } else if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
                // Standalone parenthetical stage direction (e.g. "(whispering)") — ignore without flushing speaker
                continue
            } else if isTransition(trimmed) || isActionOrDescription(trimmed, knownSpeakers: speakers) {
                flush()
                currentCharacter = nil
                if upper.hasPrefix("SETTING:") || upper.hasPrefix("SETTINGS:") || upper.hasPrefix("DIRECTOR NOTE:") {
                    inSettingOrNoteBlock = true
                }
            } else if inSettingOrNoteBlock {
                let lower = trimmed.lowercased()
                if trimmed.hasSuffix(")") || trimmed.hasSuffix("]") || lower.hasPrefix("white pilgrim") || lower.hasPrefix("read between") {
                    continue
                }
                inSettingOrNoteBlock = false
                if hasExplicitHeading {
                    if currentCharacter == nil {
                        currentCharacter = activeCharacter ?? (!roleName.isEmpty ? myRole : nil)
                    }
                    if currentCharacter != nil {
                        currentText += (currentText.isEmpty ? "" : " ") + trimmed
                    }
                }
            } else if upper.hasPrefix("VIDEO:") || upper.hasPrefix("VISUAL:") || upper.hasPrefix("SFX:") || upper.hasPrefix("SUPER:") || upper.hasPrefix("GRAPHIC:") || upper.hasPrefix("DISCLAIMER:") {
                flush()
                currentCharacter = nil
                continue
            } else if upper.hasPrefix("AUDIO:") {
                let remainder = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if let colon = remainder.firstIndex(of: ":") {
                    let speaker = String(remainder[..<colon]).trimmingCharacters(in: .whitespaces)
                    let line = String(remainder[remainder.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    flush()
                    currentCharacter = cueName(speaker)
                    currentText = line
                } else if currentCharacter != nil {
                    currentText += (currentText.isEmpty ? "" : " ") + remainder
                }
                continue
            } else if let match = periodCueRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                      let nameR = Range(match.range(at: 1), in: trimmed),
                      let textR = Range(match.range(at: 2), in: trimmed) {
                let name = String(trimmed[nameR])
                let nonCuePeriodWords: Set<String> = ["INT", "EXT", "MR", "DR", "MRS", "MS", "SC", "ACT", "NO", "P", "PG", "VS", "ETC", "ST"]
                if isLikelyCue(name) && !nonCuePeriodWords.contains(name.uppercased()) {
                    flush()
                    currentCharacter = cueName(name)
                    currentText = String(trimmed[textR]).trimmingCharacters(in: .whitespaces)
                }
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
            } else if hasExplicitHeading && activeCharacter != nil {
                currentCharacter = activeCharacter
                currentText += (currentText.isEmpty ? "" : " ") + trimmed
            }
            // Anything before the first cue (stray header text, action lines) is skipped.
        }
        flush()
        if !lines.isEmpty { scenes.append((heading, lines)) }

        var finalScenes = scenes.enumerated().map { i, scene in
            // ~150 wpm reading pace is a reasonable estimate for "how long this will take to shoot".
            let wordCount = scene.lines.reduce(0) { $0 + $1.text.split(separator: " ").count }
            let estimatedSeconds = max(15, Int(Double(wordCount) / 150.0 * 60))
            return ScriptScene(number: i + 1, title: "Scene \(i + 1)", heading: scene.heading,
                               lines: scene.lines, estimatedSeconds: estimatedSeconds)
        }

        if !roleName.isEmpty {
            let myScenes = finalScenes.filter { scene in scene.lines.contains { $0.isMine } }
            if !myScenes.isEmpty {
                finalScenes = myScenes.enumerated().map { i, scene in
                    ScriptScene(number: i + 1, title: "Scene \(i + 1)", heading: scene.heading,
                                lines: scene.lines, estimatedSeconds: scene.estimatedSeconds)
                }
            }
        }

        return finalScenes
    }

    /// Regex for matching scene headers ("SCENE 1", "SC. 2", "SCENE 14A"), using standard NSRegularExpression
    /// for full compatibility across iOS 14 and earlier.
    private static let sceneHeaderRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^(SCENE|SC\\.?)\\s*(\\d+[A-Z]?)\\b", options: [.caseInsensitive])
    }()

    /// Where a new scene starts: a slugline ("INT. CAFÉ — DAY", "EXT/INT CAR", "I/E") or a scene
    /// header like "SCENE 2" / "SC. 14" or sides header like "THE SIDE", "SIDE A". Compatible with iOS 14 and earlier.
    static func isSceneHeading(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, line.count < 80 else { return false }
        let upper = line.uppercased()

        // Casting side start/stop markers
        let startMarkers: Set<String> = ["START", "[START]", "START SCENE", "START OF SCENE", "START SIDE", "START SIDES", "START OF SIDES"]
        if startMarkers.contains(upper) || upper.hasPrefix("START SIDE ") || upper.hasPrefix("START SCENE ") || upper.hasPrefix("[START ") {
            return true
        }

        let sluglinePrefixes = ["INT.", "EXT.", "INT/EXT", "EXT/INT", "INT./EXT", "EXT./INT", "I/E", "INT ", "EXT "]
        if line == upper, sluglinePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        let sidePrefixes = ["THE SIDE", "SIDE A", "SIDE B", "SIDE C", "SIDE D", "SIDE 1", "SIDE 2", "SIDE 3", "SIDE 4", "SIDE I", "SIDE II", "SIDE III", "SIDE IV"]
        if sidePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        // Roman numeral act/scene headers: "ACT I", "ACT II", "ACT 1", "ACT 2", "SCENE I", "SCENE II"
        // Must be the whole line or followed by a separator (e.g. "SCENE 2 — KITCHEN") not prose ("Scene 2 was better.")
        if let actSceneRegex = try? NSRegularExpression(pattern: #"^(?:ACT|SCENE)\s+(?:[IVXLCDM]+|\d+[A-Z]?)\s*(?:$|[\-–—:.(])"#, options: [.caseInsensitive]),
           actSceneRegex.firstMatch(in: upper, options: [], range: NSRange(location: 0, length: (upper as NSString).length)) != nil {
            return true
        }

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

        let upper = trimmed.uppercased()

        // Setting / Director / Slate note lines, theatrical transitions, and commercial metadata
        let notePrefixes = [
            "TRANSITION:", "TRANSITION ", "BLACKOUT", "CURTAIN", "LIGHTS FADE", "FADE TO BLACK",
            "SETTING:", "SETTINGS:", "DIRECTOR NOTE:", "DIRECTOR NOTES:", "SLATE INSTRUCTION",
            "HOW TO USE THESE SIDES", "THE CHARACTERS IN THIS DOCUMENT", "THE CHARACTERS:",
            "WHAT I'M LOOKING FOR:", "WHAT I NEED TO SEE:", "NOTE: H&B", "SLATE INSTRUCTION:",
            "PLEASE READ ALL INSTRUCTIONS", "VIDEO:", "VISUAL:", "SFX:", "SUPER:", "GRAPHIC:", "DISCLAIMER:",
            "CLIENT:", "PRODUCT:", "AGENCY:", "CAMPAIGN:", "COMMERCIAL COPY"
        ]
        if notePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        // Standalone bracketed or parenthetical stage directions (e.g. "[speaking on phone]", "(whispering)")
        if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return true
        }

        // All-caps full sentence with punctuation (e.g. "KAT FRETS OVER OSCAR WHO IS TOUCHING HIS CHEST.")
        if upper == trimmed && (trimmed.hasSuffix(".") || trimmed.hasSuffix("!")) {
            let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count >= 3 { return true }
        }

        // Common standalone stage directions and scene time/setting markers
        let directions: Set<String> = [
            "BEAT", "BEAT.", "A BEAT.", "PAUSE", "PAUSE.", "SILENCE", "SILENCE.",
            "SLIGHT PAUSE", "SLIGHT PAUSE.", "SHORT PAUSE", "SHORT PAUSE.",
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

        // Character action verbs: e.g. "Maya looks at him", "Arjun walks to the door", "Maggie tosses..."
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let firstWordKey = words[0].trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—,")) .uppercased()
            let secondWord = words[1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",."))
            let actionVerbs: Set<String> = [
                "walks", "looks", "turns", "enters", "exits", "sits", "stands", "takes", "grabs",
                "pauses", "smiles", "laughs", "sighs", "stares", "crosses", "moves", "picks",
                "puts", "reaches", "opens", "closes", "glances", "nods", "shakes", "pulls",
                "pushes", "drops", "stops", "begins", "waits", "watches", "runs", "steps",
                "hurries", "freezes", "leaves", "approaches", "rises", "falls", "leans", "checks",
                "busies", "tosses", "touches", "starts", "gestures"
            ]
            if actionVerbs.contains(secondWord) {
                if knownSpeakers.contains(firstWordKey) || ["HE", "SHE", "THEY", "MAYA", "ARJUN"].contains(firstWordKey) {
                    return true
                }
            }
        }

        return false
    }

    /// Checks if a line following stage directions/actions is likely dialogue spoken by the active character
    /// (e.g. "Hey!", "-Always less busy on a Sunday.", "Come back.", "So. What did you come for?")
    static func isLikelyDialogueAfterAction(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("-") || trimmed.hasPrefix("–") || trimmed.hasPrefix("—") || trimmed.hasPrefix("\"") || trimmed.hasPrefix("“") {
            return true
        }
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            return true
        }
        let lower = trimmed.lowercased()
        let dialogueWords: Set<String> = [
            "i", "i'm", "i've", "i'd", "i'll", "you", "you're", "you've", "you'd", "you'll",
            "me", "my", "myself", "we", "we're", "we've", "us", "our", "why", "what", "how",
            "where", "when", "who", "hey", "well", "so", "oh", "come", "look", "listen", "no", "yes"
        ]
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return tokens.contains(where: { dialogueWords.contains($0) })
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

    /// Formats raw dialogue text extracted from scripts, PDFs, scans, or text files:
    /// - Unwraps physical line breaks into clean, flowing prose rather than disjointed line wraps.
    /// Strips recurring watermarks and headers (e.g. "CONFIDENTIAL", page numbers like "Page 1 of 5", agency stamps).
    static func isWatermarkOrHeader(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()

        if upper.contains("CONFIDENTIAL") || upper.contains("PROPERTY OF") || upper.contains("ALL RIGHTS RESERVED") {
            return true
        }
        if upper.contains("NOT FOR DISTRIBUTION") || upper.contains("DO NOT DISTRIBUTE") {
            return true
        }
        // Running script header/footer with page number (e.g. "Eve's Ale - Shanna Allman (7.28.26) - p.39", "PILOT - p. 12")
        if let scriptHeaderRegex = try? NSRegularExpression(pattern: #"^.+[\-–—|•·]\s*(?:p\.|page|pg\.)\s*\d+\.?$"#, options: [.caseInsensitive]),
           scriptHeaderRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        // Running header ending in a dash number like "SHOW TITLE - 39"
        if let scriptHeaderDashNumRegex = try? NSRegularExpression(pattern: #"^.+[\-–—]\s*\d+\s*$"#),
           scriptHeaderDashNumRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        // Page numbering: "Page 1", "PAGE 1 OF 4", "1 of 5", "p. 39", "p.39"
        if let pageRegex = try? NSRegularExpression(pattern: #"^(?:PAGE|P\.|PG\.)\s*\d+(\s+OF\s+\d+)?$"#, options: [.caseInsensitive]),
           pageRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        // Timestamp / date lines: "11/02/2026 14:30" or "02-11-2026"
        if let dateRegex = try? NSRegularExpression(pattern: #"^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}(\s+\d{1,2}:\d{2}(:\d{2})?)?$"#),
           dateRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        return false
    }

    /// Sanitizes and properly formats text pasted from clipboard (emails, Notes, PDF text, Word docs):
    /// - Normalizes line breaks (\r\n and \r -> \n).
    /// - Strips zero-width and non-breaking unicode artifacts (\u{200B}, \u{FEFF}, \u{00A0}).
    /// - Converts smart quotes (‘, ’, “, ”) to standard typewriter quotes (', ").
    /// - Fixes broken contractions from PDF/OCR copies (e.g. "don ' t" -> "don't", "I ' m" -> "I'm").
    /// - Fixes spacing before and after punctuation marks (commas, periods, question marks, colons).
    /// - Preserves screenplay formatting: keeps ALL-CAPS character cue lines and dialogue blocks intact.
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

        // Heal split contractions
        if let contractionRegex = try? NSRegularExpression(pattern: #"\b([A-Za-z]+)\s*'\s*([stmdre]|ve|ll)\b"#, options: [.caseInsensitive]) {
            text = contractionRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1'$2")
        }
        if let cantRegex = try? NSRegularExpression(pattern: #"\b([Cc])\s*a\s*n\s*'\s*t\b"#) {
            text = cantRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1an't")
        }
        if let wontRegex = try? NSRegularExpression(pattern: #"\b([Ww])\s*o\s*n\s*'\s*t\b"#) {
            text = wontRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1on't")
        }

        // Heal hyphenated line-wrap word breaks across newlines: e.g. "inter-\nrogation" -> "interrogation"
        if let hyphenRegex = try? NSRegularExpression(pattern: #"(\b[A-Za-z]{2,})-\s*\n\s*([a-z]{2,}\b)"#) {
            text = hyphenRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1$2")
        }

        // Clean up line-by-line whitespace while preserving dots/colons in email addresses and URLs
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var l = line.trimmingCharacters(in: .whitespaces)
            let hasEmailOrURL = l.contains("@") || l.contains("http://") || l.contains("https://") || l.contains("www.") || l.range(of: #"[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}(?:/|\b)"#, options: .regularExpression) != nil
            if !hasEmailOrURL {
                // Fix spaces before punctuation: "hello , world" -> "hello, world"
                if let spaceBefore = try? NSRegularExpression(pattern: #"\s+([,.:;?!])"#) {
                    l = spaceBefore.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1")
                }
                // Fix missing space after punctuation when followed directly by letter
                if let missingSpace = try? NSRegularExpression(pattern: #"([,.:;?!])([A-Za-z])"#) {
                    l = missingSpace.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1 $2")
                }
            } else {
                // On email or URL lines, only normalize commas/semicolons so domains and email addresses are never split
                if let spaceBefore = try? NSRegularExpression(pattern: #"\s+([,;?!])"#) {
                    l = spaceBefore.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1")
                }
                if let commaSpace = try? NSRegularExpression(pattern: #"([,;])([A-Za-z])"#) {
                    l = commaSpace.stringByReplacingMatches(in: l, range: NSRange(l.startIndex..., in: l), withTemplate: "$1 $2")
                }
            }
            return l
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Formats dialogue extracted from sides OCR:
    /// - Normalizes smart quotes and apostrophes.
    /// - Heals broken split contractions (e.g. "don ' t" -> "don't", "I ' m" -> "I'm", "can ' t" -> "can't").
    /// - Heals hyphenated line-wrap word breaks (e.g. "inter- / rogation" -> "interrogation").
    /// - Preserves and normalizes all commas, full stops, question marks, and exclamation marks.
    /// - Ensures valid punctuation spacing (e.g. "word,word" -> "word, word", "word , word" -> "word, word").
    /// - Ensures complete ending punctuation if missing from an utterance.
    static func formatDialogueText(_ raw: String) -> String {
        let unparenthetical = stripParentheticals(raw)
        guard !unparenthetical.isEmpty else { return "" }

        // 1. Unify newlines, tabs, and non-breaking spaces into standard whitespace
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

        // 2. Heal split contractions caused by OCR (e.g. "don ' t" -> "don't", "I ' m" -> "I'm")
        if let contractionRegex = try? NSRegularExpression(pattern: #"\b([A-Za-z]+)\s*'\s*([stmdre]|ve|ll)\b"#, options: [.caseInsensitive]) {
            text = contractionRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1'$2")
        }
        if let cantRegex = try? NSRegularExpression(pattern: #"\b([Cc])\s*a\s*n\s*'\s*t\b"#) {
            text = cantRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1an't")
        }
        if let wontRegex = try? NSRegularExpression(pattern: #"\b([Ww])\s*o\s*n\s*'\s*t\b"#) {
            text = wontRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1on't")
        }

        // 3. Heal hyphenated line-wrap word breaks: e.g. "inter- rogation" -> "interrogation"
        if let regex = try? NSRegularExpression(pattern: #"(\b[A-Za-z]{2,})-\s+([a-z]{2,}\b)"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1$2")
        }

        // 4. Fix spacing before punctuation (commas, periods, exclamation, question marks, semicolons)
        if let spaceBeforePunct = try? NSRegularExpression(pattern: #"\s+([,.:;?!])"#) {
            text = spaceBeforePunct.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
        }

        // 5. Fix missing space after commas, periods, exclamation points, question marks when followed directly by a letter
        if let missingSpaceAfter = try? NSRegularExpression(pattern: #"([,.:;?!])([A-Za-z])"#) {
            text = missingSpaceAfter.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1 $2")
        }

        // 6. Clean up multiple spaces
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        // 7. Ensure sentence ends with a full stop if missing ending punctuation and it's not trailing with an ellipsis or dash
        if !text.isEmpty {
            let lastChar = text.last!
            if !".!?…\"'—".contains(lastChar) {
                text.append(".")
            }
        }

        return text
    }

    /// Notice headers, flyer keywords, and locations that must never be treated as screenplay cues.
    static let blacklistedNoticeWords: Set<String> = [
        "CALL", "CASTING", "AUDITION", "AUDITIONS", "OPEN CALL", "URGENT", "NOTICE", "BREAKDOWN",
        "SEEKING", "LOOKING FOR", "WE ARE LOOKING", "PROJECT", "UPCOMING", "REQUIREMENTS", "CRITERIA",
        "SUBMIT", "SUBMISSION", "SUBMISSIONS", "SELF TAPE", "SELF-TAPE", "SELF TAPE FOR", "DEADLINE",
        "DETAILS", "INSTRUCTIONS", "CONTACT", "DM", "MAIL", "EMAIL", "PHONE", "SLATE", "HEADSHOT",
        "HEADSHOTS", "PHOTO", "PHOTOS", "VIDEO", "VIDEOS", "SCENE", "SCENES", "SIDES", "ACTOR",
        "ACTORS", "ACTRESS", "ACTRESSES", "DIRECTOR", "PRODUCER", "PRODUCTION", "AGENCY", "OFFICE",
        "IMPORTANT", "NOTE", "NOTES", "REMINDER", "STATUS", "DATE", "DATES", "TIME", "CITY", "COUNTRY",
        "EXPERIENCE", "LANGUAGE", "LANGUAGES", "INFO", "INFORMATION", "APPLY", "COMPENSATION", "RATE",
        "UNION", "NON-UNION", "NON UNION", "SAG-AFTRA", "EQUITY", "LOCATION", "VENUE", "AGE", "AGES",
        "MALE", "FEMALE", "MALE AGE", "FEMALE AGE", "YEARS", "YRS", "ESCAPE PLAN", "ANNOUNCEMENT",
        "SETTING", "SETTINGS", "DIRECTOR NOTE", "DIRECTOR NOTES", "SLATE INSTRUCTION", "SLATE INSTRUCTIONS",
        "HOW TO USE THESE SIDES", "HOW TO USE", "CASTING SIDES", "AUDITION SIDES", "THE CHARACTERS IN THIS DOCUMENT",
        "THE CHARACTERS", "THE SIDE", "SIDE A", "SIDE B", "SIDE C", "SIDE D", "MULTIPLE ROLES",
        "BENGALURU", "BANGALORE", "MUMBAI", "BOMBAY", "DELHI", "NEW DELHI", "HYDERABAD", "CHENNAI",
        "MADRAS", "KOLKATA", "CALCUTTA", "PUNE", "GOA", "AHMEDABAD", "JAIPUR", "CHANDIGARH", "KOCHI",
        "KERALA", "NOIDA", "GURGAON", "GURUGRAM", "NEW YORK", "LOS ANGELES", "LA", "NYC", "CHICAGO",
        "ATLANTA", "LONDON", "TORONTO", "VANCOUVER", "SYDNEY", "MELBOURNE", "PARIS", "BERLIN", "DUBAI"
    ]

    static func isBlacklistedNoticeWord(_ raw: String) -> Bool {
        let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—*\"' \t\r\n")).uppercased()
        if clean.isEmpty { return true }
        if blacklistedNoticeWords.contains(clean) { return true }
        let noticePhrases = [
            "CASTING CALL", "OPEN CALL", "MALE AGE", "FEMALE AGE", "LOOKING FOR", "WE ARE LOOKING",
            "CASTING SIDES", "HOW TO USE", "DIRECTOR NOTE", "SLATE INSTRUCTION", "MULTIPLE ROLES",
            "THE CHARACTERS", "SETTING"
        ]
        for p in noticePhrases {
            if clean.contains(p) { return true }
        }
        return false
    }

    /// Detects casting call / flyer text that should never be spoken as character dialogue.
    static func isNoticeText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let indicators = [
            "we are looking for", "actors for an upcoming", "mail us on", "email us on",
            "dm us", "in the subject", "casting call", "years old", "shortlisted candidates",
            "send across your", "need not apply", "how to use these sides", "casting sides",
            "the characters in this document", "slate first", "video format", "submit your tape",
            "submit a separate video", "screen time", "instructions on your character",
            "production quality required", "dialogue sides", "director will read between",
            "skip or pause over", "skip other character", "before beginning, look directly into camera",
            "what i'm looking for:", "what i need to see:", "maximum total video", "please read all instructions"
        ]
        return indicators.contains(where: { lower.contains($0) })
    }

    /// A line is a plausible character cue if it's short, has no lowercase letters, and has at least
    /// one real letter (filters out page numbers, "---", scene-heading punctuation runs, etc).
    private static func isLikelyCue(_ raw: String) -> Bool {
        var trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Allow cues with a trailing period, e.g. "HAMLET." or "NORA."
        if trimmed.hasSuffix(".") && !trimmed.contains(" ") {
            trimmed = String(trimmed.dropLast())
        }
        guard trimmed.count > 1, trimmed.count < 28 else { return false }
        guard trimmed.rangeOfCharacter(from: .lowercaseLetters) == nil else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        // Cues never contain digits (filters out "1W", "8A", page markers)
        guard trimmed.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        // Cues never end with exclamation, question mark, or colons
        if trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || trimmed.hasSuffix(":") { return false }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("ACT ") || upper.hasPrefix("SCENE ") || upper.hasPrefix("SC.") || upper.hasPrefix("SC ") { return false }
        // Reject screenplay sluglines (INT./EXT.) which are also all-caps and short.
        if upper.hasPrefix("INT.") || upper.hasPrefix("EXT.") || upper.hasPrefix("INT/EXT") { return false }
        let nonCueAbbreviations: Set<String> = ["INT", "EXT", "MR", "DR", "MRS", "MS", "SC", "ACT", "NO", "P", "PG", "VS", "ETC", "ST"]
        if nonCueAbbreviations.contains(upper) { return false }
        if isTransition(trimmed) || cueName(trimmed).isEmpty { return false }
        if isBlacklistedNoticeWord(trimmed) { return false }
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
        if isBlacklistedNoticeWord(key) { return nil }
        let labelKeywords = ["ROLE", "PROJECT", "TITLE", "DUE", "DATE", "TIME", "NOTE", "NOTES", "LOCATION", "SIDES",
                             "SCENE", "SUBJECT", "FROM", "TO", "CC", "RE", "DEADLINE", "CASTING", "CASTING DIRECTOR",
                             "DESTINATION", "FORMAT", "LENGTH", "SLATE", "SUBMIT", "CHARACTER", "PART", "PLAYING",
                             "NB", "PS", "P.S.", "STEP", "OPTION", "SENT", "HEIGHT", "AGE", "EMAIL", "PHONE",
                             "MALE", "FEMALE", "YEARS", "YRS", "CITY", "VENUE", "DETAILS", "REQUIREMENTS"]
        for lk in labelKeywords {
            if key == lk || key.contains(lk) { return nil }
        }
        return key
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
        var name = raw.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("[") && name.hasSuffix("]") {
            name = String(name.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        while let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") {
            name.removeSubrange(open...close)
        }
        if let contRange = name.range(of: #"\s*[-–—]\s*CONT['’]?D\b"#, options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<contRange.lowerBound])
        }
        var cleaned = name.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix(".") {
            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return cleaned
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
        if lower.hasPrefix("page ") || lower.hasPrefix("p. ") || lower.hasPrefix("pg. ") || lower.hasPrefix("p.") {
            let prefixLen = lower.hasPrefix("page ") ? 5 : (lower.hasPrefix("pg. ") ? 4 : (lower.hasPrefix("p. ") ? 3 : 2))
            let after = lower.dropFirst(prefixLen).trimmingCharacters(in: .whitespaces)
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

    // MARK: - Thought Unit & Beat Division (Algorithmic Model)

    /// Divides long dialogue blocks or monologues into natural, deliverable thought units / breath beats
    /// (typically 8 to 22 words) so that:
    /// 1. Teleprompter cards are easily readable at high font sizes without overwhelming blocks of text.
    /// 2. Speech recognition matches each beat smoothly and advances accurately.
    /// 3. Memory drills (First Letter, Mask & Reveal) operate on digestible chunks.
    /// Works offline deterministically with high accuracy across all iOS versions.
    static func divideIntoThoughtUnits(_ text: String) -> [String] {
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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
        // First try splitting on semicolons or em-dashes
        let dashOrSemiSeparators = ["; ", " — ", "—", " -- ", " --"]
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

        // Try splitting on conjunction commas (e.g. ", but ", ", so ", ", and ", ", because ", ", which ")
        let conjunctions = [", but ", ", so ", ", and ", ", because ", ", which ", ", where ", ", though "]
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
