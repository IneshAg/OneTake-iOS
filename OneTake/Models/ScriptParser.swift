import Foundation

/// Turns real screenplay-formatted text (from a scan, a PDF, or a pasted email) into `ScriptLine`s —
/// no network call, no fixed example to fall back on. Two conventions are recognised, both common in
/// real sides: a short ALL-CAPS line on its own starting a new speaker ("ARJUN" then dialogue below),
/// and "CHARACTER: dialogue" on one line. Anything that doesn't look like either is skipped rather than
/// guessed at.
enum ScriptParser {
    static func parseScenes(from text: String, myRole: String) -> [ScriptScene] {
        let rawLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var lines: [ScriptLine] = []
        var currentCharacter: String?
        var currentText = ""

        func flush() {
            guard let character = currentCharacter, !currentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let mine = !myRole.isEmpty &&
                (character.localizedCaseInsensitiveContains(myRole) || myRole.localizedCaseInsensitiveContains(character))
            lines.append(ScriptLine(character: character.capitalized, text: currentText.trimmingCharacters(in: .whitespaces), isMine: mine))
            currentText = ""
        }

        for raw in rawLines {
            if let colon = raw.firstIndex(of: ":"), isLikelyCue(String(raw[..<colon])) {
                flush()
                currentCharacter = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
                currentText = String(raw[raw.index(after: colon)...])
            } else if isLikelyCue(raw) {
                flush()
                currentCharacter = raw
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
        return true
    }
}
