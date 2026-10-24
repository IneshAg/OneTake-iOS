import Foundation

/// Turns real screenplay-formatted text (from a scan, a PDF, or a pasted email) into `ScriptLine`s —
/// no network call, no fixed example to fall back on. Two conventions are recognised, both common in
/// real sides: a short ALL-CAPS line on its own starting a new speaker ("ARJUN" then dialogue below),
/// and "CHARACTER: dialogue" on one line. Anything that doesn't look like either is skipped rather than
/// guessed at.
enum ScriptParser {
    static func parseScenes(from text: String, myRole: String) -> [ScriptScene] {
        // Blank lines are kept: in screenplay format a blank line ends a dialogue block, and whatever
        // follows (action, description) belongs to no one until the next cue.
        let rawLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let roleName = normalizedName(myRole)
        // Sides often hold more than one scene, each opening on a slugline ("INT. KITCHEN — NIGHT")
        // or a "SCENE 2" header; each becomes its own scene so it can be prepared and shot alone.
        var scenes: [(heading: String, lines: [ScriptLine])] = []
        var heading = "SIDES"
        var lines: [ScriptLine] = []
        var currentCharacter: String?
        var currentText = ""

        func flush() {
            guard let character = currentCharacter, !currentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let mine = isSameCharacter(normalizedName(character), roleName)
            lines.append(ScriptLine(character: character.capitalized, text: currentText.trimmingCharacters(in: .whitespaces), isMine: mine))
            currentText = ""
        }

        for raw in rawLines {
            if isSceneHeading(raw) {
                flush()
                currentCharacter = nil
                if !lines.isEmpty {
                    scenes.append((heading, lines))
                    lines = []
                }
                heading = raw
            } else if raw.isEmpty {
                // End of the dialogue block. A blank line straight after a cue (before any dialogue)
                // is tolerated, since PDF/OCR text often spaces lines out.
                if !currentText.isEmpty {
                    flush()
                    currentCharacter = nil
                }
            } else if isTransition(raw) {
                flush()
                currentCharacter = nil
            } else if let colon = raw.firstIndex(of: ":"), isLikelyCue(String(raw[..<colon])) {
                flush()
                currentCharacter = cueName(String(raw[..<colon]))
                currentText = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else if isLikelyCue(raw) {
                flush()
                currentCharacter = cueName(raw)
            } else if currentCharacter != nil {
                currentText += (currentText.isEmpty ? "" : " ") + raw
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

    /// Where a new scene starts: a slugline ("INT. CAFÉ — DAY", "EXT/INT CAR", "I/E") or a scene
    /// header like "SCENE 2" / "SC. 14".
    static func isSceneHeading(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, line.count < 80 else { return false }
        let upper = line.uppercased()
        let sluglinePrefixes = ["INT.", "EXT.", "INT/EXT", "EXT/INT", "INT./EXT", "EXT./INT", "I/E", "INT ", "EXT "]
        if line == upper, sluglinePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }
        // "SCENE 2", "Scene 2:", "SC. 14A — KITCHEN": a number, then nothing or a separator — so a
        // line of dialogue like "Scene two was better" isn't taken for a heading.
        guard let match = upper.firstMatch(of: #/^(SCENE|SC\.?)\s*(\d+[A-Z]?)\b/#) else { return false }
        let rest = upper[match.range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.first.map { ":.-–—(".contains($0) } ?? true
    }

    /// A line is a plausible character cue if it's short, has no lowercase letters, and has at least
    /// one real letter (filters out page numbers, "---", scene-heading punctuation runs, etc).
    private static func isLikelyCue(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 1, trimmed.count < 28 else { return false }
        guard trimmed.rangeOfCharacter(from: .lowercaseLetters) == nil else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        // Reject screenplay sluglines (INT./EXT.) which are also all-caps and short.
        if trimmed.hasPrefix("INT.") || trimmed.hasPrefix("EXT.") || trimmed.hasPrefix("INT/EXT") { return false }
        if isTransition(trimmed) || cueName(trimmed).isEmpty { return false }
        return true
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

    /// Whole-word match, so a cue of "MAYA" matches the role "Maya Kapoor" (and vice versa) but a
    /// short cue like "AN" no longer matches "Anaya" the way a substring check did.
    private static func isSameCharacter(_ cue: [String], _ role: [String]) -> Bool {
        guard !cue.isEmpty, !role.isEmpty else { return false }
        let cueSet = Set(cue), roleSet = Set(role)
        return cueSet.isSubset(of: roleSet) || roleSet.isSubset(of: cueSet)
    }
}
