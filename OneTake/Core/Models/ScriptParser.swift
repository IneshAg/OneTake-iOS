import Foundation
import CoreGraphics

/// Turns real screenplay-formatted text (from a scan, a PDF, or a pasted email) into `ScriptLine`s —
/// powered by on-device Core ML element classification (`ScriptElementClassifier`) with a deterministic
/// fallback guardrail for full backward compatibility across all iOS versions.
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

    /// Parses scenes from screenplay or sides text by wrapping lines into synthetic `LayoutLine`s
    /// and delegating to the contextual geometry-aware parser.
    static func parseScenes(from text: String, myRole: String) -> [ScriptScene] {
        let layoutLines = syntheticLayoutLines(from: text)
        return parseScenes(from: layoutLines, myRole: myRole)
    }

    /// Parses scenes from geometry-preserving `LayoutLine`s using contextual Core ML classification
    /// (`CoreMLScriptParserRunner.classifyContextual`) alongside deterministic script guardrails.
    static func parseScenes(from layoutLines: [LayoutLine], myRole: String) -> [ScriptScene] {
        guard !layoutLines.isEmpty else { return [] }
        let roleName = normalizedName(myRole)

        let characterHeaderRegex = try? NSRegularExpression(pattern: #"^([A-Z]{2,20})\s*[·•|\-—]\s*(?:(?:He|She|They)/|[0-9]{1,2}s?\b|Early|Mid|Late)"#)
        let slateInstructionRegex = try? NSRegularExpression(pattern: #"(?i)reading\s+for\s*\(([A-Za-z]{2,20})\)"#)
        let periodCueRegex = try? NSRegularExpression(pattern: #"^([A-Z]{2,20})\.\s+(.*)$"#)
        var inParenthetical = false
        var activeCharacter: String? = nil
        var inSettingOrNoteBlock = false
        var hasExplicitHeading = false
        var hadBlankLine = true
        var previousContentLine: LayoutLine?

        let contextualClasses = CoreMLScriptParserRunner.shared.classifyContextual(lines: layoutLines)

        // Index speaker cues across the document to assist narration action filtering
        var speakerCounts: [String: Int] = [:]
        for (index, layoutLine) in layoutLines.enumerated() {
            let tr = layoutLine.text.trimmingCharacters(in: .whitespaces)
            guard !tr.isEmpty else { continue }
            let smallIndent = smallIndentHint(for: layoutLine.estimatedIndent)
            if let colon = tr.firstIndex(of: ":"), let key = speakerKey(String(tr[..<colon])) {
                speakerCounts[key, default: 0] += 1
            } else if isPlausibleCueName(tr),
                      contextualClasses[index] == .characterCue,
                      !isTransition(tr),
                      !isBlacklistedNoticeWord(tr) {
                let key = cueName(tr).uppercased()
                speakerCounts[key, default: 0] += 1
            } else if isLikelyCue(tr, indentation: smallIndent)
                        || isLikelyIndentedCue(tr, estimatedIndent: layoutLine.estimatedIndent) {
                let key = cueName(tr).uppercased()
                speakerCounts[key, default: 0] += 1
            }
        }
        let speakers = Set(speakerCounts.filter { $0.value >= 2 || isSameCharacter(normalizedName($0.key), roleName) }.keys)

        var scenes: [(heading: String, lines: [ScriptLine])] = []
        var heading = "SIDES"
        var lines: [ScriptLine] = []
        var currentCharacter: String?
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

        for (index, layoutLine) in layoutLines.enumerated() {
            let trimmed = layoutLine.text.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if trimmed.isEmpty {
                inSettingOrNoteBlock = false
                inParenthetical = false
                hadBlankLine = true
                continue
            }

            // Watermarks, timestamps, and page numbering must not disrupt vertical neighbor context.
            if isWatermarkOrHeader(trimmed) || isLineOrPageNumber(trimmed) {
                continue
            }

            if let prev = previousContentLine {
                if CoreMLScriptParserRunner.verticalGapIndicatesBlank(between: prev, and: layoutLine) {
                    inSettingOrNoteBlock = false
                    inParenthetical = false
                    hadBlankLine = true
                } else if prev.pageIndex != layoutLine.pageIndex {
                    inSettingOrNoteBlock = false
                    inParenthetical = false
                    if currentCharacter == nil {
                        hadBlankLine = true
                    }
                }
            }
            previousContentLine = layoutLine

            if inParenthetical {
                if trimmed.contains(")") || trimmed.contains("]") {
                    inParenthetical = false
                }
                continue
            }

            // Casting sides character overview block (e.g. "NOOR · She/her · Early 60s")
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
                hadBlankLine = false
                continue
            }

            if let match = slateInstructionRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let r = Range(match.range(at: 1), in: trimmed) {
                activeCharacter = String(trimmed[r]).capitalized
            }

            // Contextual Core ML Line Evaluation
            let mlClass = contextualClasses[index]
            let smallIndent = smallIndentHint(for: layoutLine.estimatedIndent)

            let isCue = isPlausibleCueName(trimmed) && (
                isLikelyCue(trimmed, indentation: smallIndent)
                || (mlClass == .characterCue)
                || isLikelyIndentedCue(trimmed, estimatedIndent: layoutLine.estimatedIndent)
            )

            let isMLHeading = !isCue && mlClass == .sceneHeading && trimmed.contains(where: \.isLetter) && !trimmed.hasSuffix(".") && !trimmed.hasSuffix("!") && !trimmed.hasSuffix("?")

            if isSceneHeading(trimmed) || isMLHeading {
                flush()
                currentCharacter = nil
                inSettingOrNoteBlock = false
                if !lines.isEmpty {
                    scenes.append((heading, lines))
                    lines = []
                }
                if upper.hasPrefix("SIDE ") {
                    heading = "Side " + trimmed.dropFirst(5)
                } else if upper.hasPrefix("THE SIDE") {
                    heading = "The Side" + trimmed.dropFirst(8)
                } else if upper.hasPrefix("START") || upper.hasPrefix("[START") {
                    let nextNum = scenes.count + (lines.isEmpty ? 1 : 2)
                    heading = "Scene \(nextNum)"
                } else {
                    heading = trimmed
                }
                hasExplicitHeading = true
                hadBlankLine = false
            } else if isActHeading(trimmed) || isWebJunkOrFooter(trimmed) {
                flush()
                currentCharacter = nil
                hadBlankLine = false
            } else if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if isLikelyCue(inner) || (isPlausibleCueName(inner) && mlClass == .characterCue) {
                    flush()
                    currentCharacter = cueName(inner)
                    hadBlankLine = false
                    continue
                } else {
                    continue
                }
            } else if upper.hasPrefix("VIDEO:") || upper.hasPrefix("VISUAL:") || upper.hasPrefix("SFX:") || upper.hasPrefix("SUPER:") || upper.hasPrefix("GRAPHIC:") || upper.hasPrefix("DISCLAIMER:") || (!isCue && mlClass == .metadata) {
                flush()
                currentCharacter = nil
                hadBlankLine = false
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
                hadBlankLine = false
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
                    hadBlankLine = false
                }
            } else if let colon = trimmed.firstIndex(of: ":"),
                      isLikelyCue(String(trimmed[..<colon])) || speakerKey(String(trimmed[..<colon])).map({ speakers.contains($0) }) == true {
                flush()
                currentCharacter = cueName(String(trimmed[..<colon]))
                currentText = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                hadBlankLine = false
            } else if isCue {
                flush()
                currentCharacter = cueName(trimmed)
                hadBlankLine = false
            } else if trimmed.hasPrefix("(") && !trimmed.contains(")") {
                inParenthetical = true
                continue
            } else if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || (!isCue && mlClass == .parenthetical) {
                // Standalone parenthetical stage direction (e.g. "(whispering)") — ignore without flushing speaker
                continue
            } else if isTransition(trimmed) || isActionOrDescription(trimmed, knownSpeakers: speakers) || (!isCue && (currentCharacter == nil || (hadBlankLine && !currentText.isEmpty)) && mlClass == .action && (trimmed.hasSuffix(".") || trimmed.hasSuffix("!"))) {
                flush()
                currentCharacter = nil
                hadBlankLine = false
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
                hadBlankLine = false
            } else if currentCharacter != nil {
                currentText += (currentText.isEmpty ? "" : " ") + trimmed
                hadBlankLine = false
            } else if hasExplicitHeading && activeCharacter != nil {
                currentCharacter = activeCharacter
                currentText += (currentText.isEmpty ? "" : " ") + trimmed
                hadBlankLine = false
            }
        }
        flush()
        if !lines.isEmpty { scenes.append((heading, lines)) }

        var finalScenes = scenes.enumerated().map { i, scene in
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

    private static func syntheticLayoutLines(from text: String) -> [LayoutLine] {
        let rawLines = text.components(separatedBy: .newlines)
        guard !rawLines.isEmpty else { return [] }

        let step: CGFloat = 0.015
        let lineHeight: CGFloat = 0.010
        var result: [LayoutLine] = []
        result.reserveCapacity(rawLines.count)

        for (slotIndex, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let hasTab = rawLine.contains("\t")
            let leadingWhitespace = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
            let indentColumns = leadingWhitespace.reduce(0) { $0 + ($1 == "\t" ? 8 : 1) }

            let estimatedIndent: CGFloat
            if indentColumns == 0 {
                estimatedIndent = 0.08
            } else if !hasTab && indentColumns < 4 {
                estimatedIndent = 0.12
            } else {
                estimatedIndent = min(0.55, 0.30 + CGFloat(indentColumns) * 0.015)
            }

            let y = 0.94 - CGFloat(slotIndex) * step
            let width = max(0.15, 0.92 - estimatedIndent)
            result.append(
                LayoutLine(
                    text: trimmed,
                    rect: CGRect(x: estimatedIndent, y: y, width: width, height: lineHeight),
                    pageIndex: 0,
                    estimatedIndent: estimatedIndent
                )
            )
        }
        return result
    }

    private static func smallIndentHint(for estimatedIndent: CGFloat) -> Int? {
        (estimatedIndent > 0.09 && estimatedIndent < 0.30) ? 4 : nil
    }

    private static let sceneHeaderRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^(SCENE|SC\\.?)\\s*(\\d+[A-Z]?)\\b", options: [.caseInsensitive])
    }()

    /// Identifies where a new scene starts: sluglines, scene headers, and sides markers.
    static func isSceneHeading(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, line.count < 80 else { return false }
        let upper = line.uppercased()

        let startMarkers: Set<String> = ["START", "[START]", "START SCENE", "START OF SCENE", "START SIDE", "START SIDES", "START OF SIDES"]
        if startMarkers.contains(upper) || upper.hasPrefix("START SIDE ") || upper.hasPrefix("START SCENE ") || upper.hasPrefix("[START ") {
            return true
        }

        let sluglinePrefixes = ["INT.", "EXT.", "INT/EXT", "EXT/INT", "INT./EXT", "EXT./INT", "I/E", "INT ", "EXT "]
        if line == upper, sluglinePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        let sidePrefixes = ["THE SIDE", "SIDE A", "SIDE B", "SIDE C", "SIDE D", "SIDE 1", "SIDE 2", "SIDE 3", "SIDE 4", "SIDE I", "SIDE II", "SIDE III", "SIDE IV"]
        if sidePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

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

        let notePrefixes = [
            "TRANSITION:", "TRANSITION ", "BLACKOUT", "CURTAIN", "LIGHTS FADE", "FADE TO BLACK",
            "SETTING:", "SETTINGS:", "DIRECTOR NOTE:", "DIRECTOR NOTES:", "SLATE INSTRUCTION",
            "HOW TO USE THESE SIDES", "THE CHARACTERS IN THIS DOCUMENT", "THE CHARACTERS:",
            "WHAT I'M LOOKING FOR:", "WHAT I NEED TO SEE:", "NOTE: H&B", "SLATE INSTRUCTION:",
            "PLEASE READ ALL INSTRUCTIONS", "VIDEO:", "VISUAL:", "SFX:", "SUPER:", "GRAPHIC:", "DISCLAIMER:",
            "CLIENT:", "PRODUCT:", "AGENCY:", "CAMPAIGN:", "COMMERCIAL COPY"
        ]
        if notePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return true
        }

        if upper == trimmed && (trimmed.hasSuffix(".") || trimmed.hasSuffix("!")) {
            let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count >= 3 { return true }
        }

        let directions: Set<String> = [
            "BEAT", "BEAT.", "A BEAT.", "PAUSE", "PAUSE.", "SILENCE", "SILENCE.",
            "SLIGHT PAUSE", "SLIGHT PAUSE.", "SHORT PAUSE", "SHORT PAUSE.",
            "MOMENT", "MOMENT.", "LONG PAUSE.", "CONTINUOUS", "LATER", "MOMENTS LATER",
            "SAME TIME", "FLASHBACK", "DAY", "NIGHT", "DUSK", "DAWN", "MORNING", "EVENING"
        ]
        if directions.contains(upper) { return true }

        let cameraPrefixes = ["ANGLE ON", "CLOSE ON", "CLOSE-UP", "WIDE SHOT", "INSERT", "P.O.V.", "POV", "SOUND OF", "WE HEAR", "WE SEE", "CAMERA", "IN THE DISTANCE"]
        if cameraPrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        let narrationPrefixes = ["HE ", "SHE ", "THEY ", "BOTH ", "THE DOOR ", "THE PHONE ", "A CAR ", "SUDDENLY ", "HER EYES ", "HIS EYES "]
        if narrationPrefixes.contains(where: { upper.hasPrefix($0) }) { return true }

        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let firstWordKey = words[0].trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—,")).uppercased()
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

    /// Strips recurring watermarks, timestamps, and page numbering headers
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
        if let scriptHeaderRegex = try? NSRegularExpression(pattern: #"^.+[\-–—|•·]\s*(?:p\.|page|pg\.)\s*\d+\.?$"#, options: [.caseInsensitive]),
           scriptHeaderRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        if let scriptHeaderDashNumRegex = try? NSRegularExpression(pattern: #"^.+[\-–—]\s*\d+\s*$"#),
           scriptHeaderDashNumRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        if let pageRegex = try? NSRegularExpression(pattern: #"^(?:PAGE|P\.|PG\.)\s*\d+(\s+OF\s+\d+)?$"#, options: [.caseInsensitive]),
           pageRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        if let dateRegex = try? NSRegularExpression(pattern: #"^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}(\s+\d{1,2}:\d{2}(:\d{2})?)?$"#),
           dateRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        return false
    }

    /// Notice headers, flyer keywords, and locations that must never be treated as screenplay cues.
    static let blacklistedNoticeWords: Set<String> = [
        "CALL", "CASTING", "AUDITION", "AUDITIONS", "OPEN CALL", "URGENT", "NOTICE", "BREAKDOWN",
        "SEEKING", "LOOKING FOR", "WE ARE LOOKING", "PROJECT", "UPCOMING", "REQUIREMENT", "REQUIREMENTS", "CRITERIA",
        "SUBMIT", "SUBMISSION", "SUBMISSIONS", "SELF TAPE", "SELF-TAPE", "SELF TAPE FOR", "DEADLINE",
        "DETAILS", "INSTRUCTIONS", "CONTACT", "DM", "MAIL", "EMAIL", "PHONE", "SLATE", "HEADSHOT",
        "HEADSHOTS", "PHOTO", "PHOTOS", "PICTURE", "PICTURES", "VIDEO", "VIDEOS", "SCENE", "SCENES", "SIDES", "ACTOR",
        "ACTORS", "ACTRESS", "ACTRESSES", "DIRECTOR", "PRODUCER", "PRODUCTION", "AGENCY", "OFFICE",
        "IMPORTANT", "NOTE", "NOTES", "REMINDER", "STATUS", "DATE", "DATES", "TIME", "CITY", "COUNTRY",
        "EXPERIENCE", "LANGUAGE", "LANGUAGES", "INFO", "INFORMATION", "APPLY", "COMPENSATION", "RATE",
        "UNION", "NON-UNION", "NON UNION", "SAG-AFTRA", "EQUITY", "LOCATION", "VENUE", "AGE", "AGES",
        "TURBAN", "SIKH", "INTRO", "INTRODUCTION",
        "RATE OF PAY", "PAY RATE", "VIDEO USAGE", "USAGE", "AGENCY FEE", "PRINCIPAL ROLE", "SECONDARY ROLE",
        "MALE", "FEMALE", "MALE AGE", "FEMALE AGE", "YEARS", "YRS", "ESCAPE PLAN", "ANNOUNCEMENT",
        "CLIENT", "PRODUCT", "CAMPAIGN", "COMMERCIAL COPY",
        "SETTING", "SETTINGS", "DIRECTOR NOTE", "DIRECTOR NOTES", "SLATE INSTRUCTION", "SLATE INSTRUCTIONS",
        "HOW TO USE THESE SIDES", "HOW TO USE", "CASTING SIDES", "AUDITION SIDES", "THE CHARACTERS IN THIS DOCUMENT",
        "THE CHARACTERS", "THE SIDE", "SIDE A", "SIDE B", "SIDE C", "SIDE D", "MULTIPLE ROLES",
        "BENGALURU", "BANGALORE", "MUMBAI", "BOMBAY", "DELHI", "NEW DELHI", "HYDERABAD", "CHENNAI",
        "MADRAS", "KOLKATA", "CALCUTTA", "PUNE", "GOA", "AHMEDABAD", "JAIPUR", "CHANDIGARH", "KOCHI",
        "KERALA", "NOIDA", "GURGAON", "GURUGRAM", "BHOPAL", "NEW YORK", "LOS ANGELES", "LA", "NYC", "CHICAGO",
        "ATLANTA", "LONDON", "TORONTO", "VANCOUVER", "SYDNEY", "MELBOURNE", "PARIS", "BERLIN", "DUBAI"
    ]

    static func isBlacklistedNoticeWord(_ raw: String) -> Bool {
        let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—*\"' \t\r\n•·▪▫|#<>")).uppercased()
        if clean.isEmpty { return true }
        if blacklistedNoticeWords.contains(clean) { return true }
        let tokens = clean.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if tokens.contains(where: { ["GENDER", "REQUIREMENT", "REQUIREMENTS", "CASTING", "CALL", "AUDITION", "SUBMIT", "SUBMISSION", "DEADLINE", "TURBAN", "PICTURES", "HEADSHOT", "RESUME", "INTRODUCTION", "CONTACT"].contains($0) }) {
            return true
        }
        let noticePhrases = [
            "CASTING CALL", "OPEN CALL", "MALE AGE", "FEMALE AGE", "LOOKING FOR", "WE ARE LOOKING",
            "WE'RE LOOKING", "CASTING SIDES", "HOW TO USE", "DIRECTOR NOTE", "SLATE INSTRUCTION", "MULTIPLE ROLES",
            "THE CHARACTERS", "SETTING", "KINDLY SEND", "SEND IN", "CONTACT NUMBER", "RECENT PICTURES",
            "MUST WEAR", "UPCOMING PROJECT"
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
            "we are looking for", "we're looking for", "actors for an upcoming", "mail us on", "email us on",
            "dm us", "in the subject", "casting call", "years old", "shortlisted candidates",
            "send across your", "need not apply", "how to use these sides", "casting sides",
            "the characters in this document", "slate first", "video format", "submit your tape",
            "submit a separate video", "screen time", "instructions on your character",
            "production quality required", "dialogue sides", "director will read between",
            "skip or pause over", "skip other character", "before beginning, look directly into camera",
            "what i'm looking for:", "what i need to see:", "maximum total video", "please read all instructions",
            "must wear a turban", "kindly send in your", "recent pictures", "detailed introduction",
            "contact number", "upcoming project", "@mccc.in", "based in bhopal", "requirement:"
        ]
        return indicators.contains(where: { lower.contains($0) })
    }

    /// A line is a plausible character cue if it's short, uppercase, and not punctuation or notice keyword.
    static func isLikelyCue(_ raw: String, indentation: Int? = nil) -> Bool {
        var trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "•·▪▫*-–—| \t\r\n"))
        if let indentation, indentation > 0, indentation < 14, !raw.contains("\t") {
            let words = trimmed.split(separator: " ")
            if words.count > 3 { return false }
        }
        if trimmed.hasSuffix(".") && !trimmed.contains(" ") {
            trimmed = String(trimmed.dropLast())
        }
        guard trimmed.count > 1, trimmed.count < 28 else { return false }
        guard trimmed.rangeOfCharacter(from: .lowercaseLetters) == nil else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        if trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || trimmed.hasSuffix(":") { return false }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("ACT ") || upper.hasPrefix("SCENE ") || upper.hasPrefix("SC.") || upper.hasPrefix("SC ") { return false }
        if upper.hasPrefix("INT.") || upper.hasPrefix("EXT.") || upper.hasPrefix("INT/EXT") { return false }
        let nonCueAbbreviations: Set<String> = ["INT", "EXT", "MR", "DR", "MRS", "MS", "SC", "ACT", "NO", "P", "PG", "VS", "ETC", "ST"]
        if nonCueAbbreviations.contains(upper) { return false }
        if isTransition(trimmed) || cueName(trimmed).isEmpty { return false }
        if isBlacklistedNoticeWord(trimmed) { return false }
        return true
    }

    /// Verifies whether a line can plausibly be a character cue (e.g. capitalized name, no lowercase sentence prose)
    static func isPlausibleCueName(_ trimmed: String) -> Bool {
        let clean = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "•·▪▫*-–—| \t\r\n"))
        guard clean.count >= 2, clean.count < 35 else { return false }
        if clean.contains(":") { return false }
        if clean.hasSuffix("!") || clean.hasSuffix("?") || clean.hasSuffix(",") || clean.hasSuffix(";") {
            return false
        }
        let allowedSingleWordPeriod: Set<String> = ["DR.", "MR.", "MRS.", "MS.", "PROF.", "CAPT.", "LT.", "SGT.", "REV."]
        if clean.hasSuffix(".") && !allowedSingleWordPeriod.contains(clean.uppercased()) {
            return false
        }
        if isTransition(clean) || isBlacklistedNoticeWord(clean) || isActHeading(clean) || isSceneHeading(clean) {
            return false
        }
        let bareName = cueName(clean)
        guard !bareName.isEmpty else { return false }
        let words = bareName.split(separator: " ")
        guard (1...4).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first else { return false }
            return first.isUppercase || first.isNumber || first == "#"
        }
    }

    /// Indented cues with tabs or spaces, supporting standard screenplay margin offsets and mixed-case cues
    static func isLikelyIndentedCue(_ trimmed: String, raw: String) -> Bool {
        let hasIndent = raw.hasPrefix(" ") || raw.hasPrefix("\t")
        guard hasIndent else { return false }
        return isLikelyIndentedCueBody(trimmed)
    }

    /// Indented cues using normalized geometric `estimatedIndent` (screenplay cue column >= 0.30).
    static func isLikelyIndentedCue(_ trimmed: String, estimatedIndent: CGFloat) -> Bool {
        guard estimatedIndent >= 0.30 else { return false }
        return isLikelyIndentedCueBody(trimmed)
    }

    private static func isLikelyIndentedCueBody(_ trimmed: String) -> Bool {
        guard trimmed.count >= 2, trimmed.count <= 25 else { return false }
        guard !trimmed.hasSuffix("."), !trimmed.hasSuffix("!"), !trimmed.hasSuffix("?"), !trimmed.hasSuffix(",") else { return false }
        guard !isTransition(trimmed), !isBlacklistedNoticeWord(trimmed), !isActHeading(trimmed), !isSceneHeading(trimmed) else { return false }
        let words = trimmed.split(separator: " ")
        guard (1...3).contains(words.count) else { return false }
        return words.allSatisfy { word in
            word.first?.isUppercase == true && word.unicodeScalars.allSatisfy { CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).contains($0) }
        }
    }

    /// "Maya" / "Dr. Rao" / "Maya Kapoor" before a colon — a short, capitalised name.
    private static func speakerKey(_ raw: String) -> String? {
        let name = cueName(raw.trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—*\"' \t\r\n•·▪▫|#<>")))
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
                             "MALE", "FEMALE", "YEARS", "YRS", "CITY", "VENUE", "DETAILS", "REQUIREMENTS",
                             "RATE", "PAY", "UNION", "STATUS", "USAGE", "FEE", "COMPENSATION", "PRODUCTION", "COMPANY"]
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
        return bare.hasSuffix(" TO") && bare.count < 28
    }

    /// The speaker's name with screenplay extensions dropped: "ARJUN (CONT'D)" / "ARJUN (V.O.)" → "ARJUN".
    private static func cueName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—*\"' \t\r\n•·▪▫|#<>"))
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

    /// Whole-word match, so a cue of "MAYA" matches the role "Maya Kapoor" (and vice versa).
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
    static func isLineOrPageNumber(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.allSatisfy(\.isNumber) { return true }
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#.-–— "))
        if !stripped.isEmpty && stripped.allSatisfy(\.isNumber) { return true }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("page ") || lower.hasPrefix("p. ") || lower.hasPrefix("pg. ") || lower.hasPrefix("p.") {
            let prefixLen = lower.hasPrefix("page ") ? 5 : (lower.hasPrefix("pg. ") ? 4 : (lower.hasPrefix("p. ") ? 3 : 2))
            let after = lower.dropFirst(prefixLen).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty && after.allSatisfy(\.isNumber) { return true }
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
        return false
    }

    /// Screenplay act markers (e.g. "ACT TWO", "COLD OPEN", "PROLOGUE")
    private static func isActHeading(_ raw: String) -> Bool {
        let upper = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return upper.hasPrefix("ACT ") || upper.hasPrefix("ACT ONE") || upper.hasPrefix("ACT TWO") || upper.hasPrefix("COLD OPEN") || upper.hasPrefix("PROLOGUE") || upper.hasPrefix("EPILOGUE")
    }
}
