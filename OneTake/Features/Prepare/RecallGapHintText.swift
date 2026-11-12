import SwiftUI
import OneTakeUI

/// Meaningful-word gaps. Each underscore is tappable and reveals its original word as a clue.
struct RecallGapHintText: View {
    let text: String
    let hiddenWords: Set<Int>
    let revealedWords: Set<Int>
    let font: Font
    let color: Color
    let onToggleWord: (Int) -> Void

    private var words: [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }

    var body: some View {
        RecallWordsLayout(spacing: 3, lineSpacing: 2) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let isHidden = hiddenWords.contains(index) && !revealedWords.contains(index)
                Button { if hiddenWords.contains(index) { onToggleWord(index) } } label: {
                    Text(isHidden ? masked(word) : word)
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.vertical, OTSpace.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hiddenWords.contains(index))
                .accessibilityLabel(isHidden ? "Hidden word, tap to reveal" : word)
                .accessibilityHint("Shows the full word as a practice clue")
            }
        }
    }

    private func masked(_ word: String) -> String {
        String(word.map { $0.isLetter || $0.isNumber ? "_" : $0 })
    }
}

