import Foundation

// MARK: - ScriptParser Dialogue Normalization

extension ScriptParser {
    /// Strips punctuation, extra whitespace, and case differences while preserving the spoken content.
    static func normalizeDialogue(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
