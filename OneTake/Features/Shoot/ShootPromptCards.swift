import SwiftUI
import OneTakeUI

// MARK: - Prompt Cards & Floating Result Cards

extension ShootFlow {
    func cameraChoice(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.otFootnote.weight(.semibold))
            .foregroundStyle(Color.white) // ot-lint:allow
            .padding(.horizontal, OTSpace.m)
            .frame(height: 36) // ot-lint:allow
            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
    }

    func chip(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text).font(.otCaption.weight(.semibold))
        }
        .foregroundStyle(text == "Exposure locked" ? OT.due : Color.white) // ot-lint:allow
        .padding(.horizontal, 9) // ot-lint:allow
        .frame(height: 26) // ot-lint:allow
        .background(Color.black.opacity(0.55), in: Capsule()) // ot-lint:allow
    }

    @ViewBuilder
    func promptCard(eyebrow: String, text: String, mine: Bool = true) -> some View {
        let spokenWords = mine ? SpokenLineMatcher.matchedWordIndices(in: text, transcript: follower.transcript) : []
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced)) // ot-lint:allow
                .tracking(0.6)
                .foregroundStyle(mine ? OT.prompterGold : OT.reader)
            highlightedPrompterText(text, matchedWords: spokenWords, mine: mine)
                .font(.system(size: [16, 19, 23][min(max(prompterSize, 0), 2)], weight: .semibold)) // ot-lint:allow
                .scaleEffect(x: mirrorPrompter ? -1 : 1, y: 1)
        }
        .padding(.horizontal, OTSpace.m)
        .padding(.vertical, OTSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous)
                .fill(Color.black.opacity(0.45)) // ot-lint:allow
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1) // ot-lint:allow
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    func highlightedPrompterText(_ text: String, matchedWords: Set<Int>, mine: Bool) -> Text {
        let words = text.split(separator: " ")
        var result = Text("")
        for (index, word) in words.enumerated() {
            let piece = Text(String(word) + (index < words.count - 1 ? " " : ""))
            if mine && matchedWords.contains(index) {
                result = result + piece.foregroundColor(OT.prompterGold)
            } else if mine {
                result = result + piece.foregroundColor(Color.white) // ot-lint:allow
            } else {
                result = result + piece.foregroundColor(Color.white.opacity(0.8)) // ot-lint:allow
            }
        }
        return result
    }

    func resultCard(
        title: String,
        detail: String,
        primary: (String, () -> Void),
        secondary: (String, () -> Void),
        more: [(String, () -> Void)] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            Text(title).font(.otTitle).foregroundStyle(OT.labelPrimary)
            Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
            HStack {
                Button(secondary.0, action: secondary.1).buttonStyle(.otSecondary)
                Button(primary.0, action: primary.1).buttonStyle(.otPrimary)
            }
            ForEach(Array(more.enumerated()), id: \.offset) { _, item in
                Button(item.0, action: item.1).font(.otHeadline).foregroundStyle(OT.accent)
            }
        }
        .padding(OTSpace.cardInset)
        .otCard(.elevated)
        .padding(.top, 140) // ot-lint:allow
    }
}
