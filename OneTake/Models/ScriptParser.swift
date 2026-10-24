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
            if raw.isEmpty {
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
            // Lines before any cue is found (sluglines like "INT. ROOM — NIGHT", stray header text) are skipped.
        }
        flush()

        guard !lines.isEmpty else { return [] }
        // ~150 wpm reading pace is a reasonable estimate for "how long this will take to shoot".
        let wordCount = lines.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let estimatedSeconds = max(15, Int(Double(wordCount) / 150.0 * 60))
        return [ScriptScene(number: 1, title: "Scene 1", heading: "SIDES", lines: lines, estimatedSeconds: estimatedSeconds)]
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
