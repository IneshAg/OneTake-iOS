import SwiftUI

/// First-letter recall text. Each masked word is an individual, accessible hint target.
struct RecallWordHintText: View {
    let text: String
    let revealedWords: Set<Int>
    let font: Font
    let color: Color
    let onRevealWord: (Int) -> Void

    private var words: [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var body: some View {
        RecallWordsLayout(spacing: 3, lineSpacing: 2) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Button { onRevealWord(index) } label: {
                    Text(revealedWords.contains(index) ? word : masked(word))
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealedWords.contains(index) ? word : "Hidden word, tap to reveal")
                .accessibilityHint("Reveals this word for your practice hint")
            }
        }
    }

    private func masked(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first) + (word.count > 1 ? "—" : "")
    }
}
