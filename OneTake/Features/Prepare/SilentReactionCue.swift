import SwiftUI
import OneTakeUI

/// Makes a printed `?` or silent reaction cue read as a playable non-verbal expression while retaining its script meaning.
struct SilentReactionCue: View {
    var cueText: String = "?"
    var isMine: Bool = true
    var inPrompter: Bool = false

    private var cueSymbol: String {
        let trimmed = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "?" { return "?" }
        if trimmed == "..." || trimmed == "…" { return "…" }
        if trimmed == "." { return "•" }
        return "•"
    }

    private var headingText: String {
        let trimmed = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "?" {
            return isMine ? "Questioning expression" : "Questioning beat"
        } else if trimmed == "..." || trimmed == "…" || trimmed == "." {
            return "Silent pause"
        } else if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            return String(trimmed.dropFirst().dropLast()).capitalized
        }
        return "Silent reaction"
    }

    private var instructionText: String {
        if inPrompter {
            return isMine ? "React in character · hold your expression" : "Non-verbal beat · continuing..."
        } else {
            return isMine ? "React in character with this expression. No spoken line." : "Non-verbal beat. No reader recording needed."
        }
    }

    var body: some View {
        if inPrompter {
            HStack(spacing: OTSpace.m) {
                ZStack {
                    Circle()
                        .fill(isMine ? OT.prompterGold.opacity(0.22) : OT.reader.opacity(0.22))
                        .frame(width: 38, height: 38) // ot-lint:allow
                    Text(cueSymbol)
                        .font(.system(size: 22, weight: .bold, design: .rounded)) // ot-lint:allow
                        .foregroundStyle(isMine ? OT.prompterGold : OT.reader)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OTSpace.xs) {
                        Text(headingText)
                            .font(.system(size: 15, weight: .bold, design: .monospaced)) // ot-lint:allow
                            .foregroundStyle(Color.white) // ot-lint:allow
                        Text("[ \(cueText) ]")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced)) // ot-lint:allow
                            .foregroundStyle(OT.labelSecondary)
                    }
                    Text(instructionText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced)) // ot-lint:allow
                        .foregroundStyle(OT.labelPrimary)
                }
            }
            .padding(.vertical, OTSpace.xxs)
        } else {
            HStack(alignment: .center, spacing: OTSpace.m) {
                Text(cueSymbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded)) // ot-lint:allow
                    .foregroundStyle(isMine ? OT.accent : OT.reader)
                    .frame(width: 36, height: 36) // ot-lint:allow
                    .background(isMine ? OT.accentSoft : OT.reader.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OTSpace.xs) {
                        Text(headingText)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                        Text("[ \(cueText) ]")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced)) // ot-lint:allow
                            .foregroundStyle(OT.labelTertiary)
                    }
                    Text(instructionText)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }
            }
            .padding(OTSpace.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .otCard(.grouped)
            .accessibilityElement(children: .combine)
        }
    }
}
