import SwiftUI

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
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isMine ? OT.prompterGold.opacity(0.22) : OT.reader.opacity(0.22))
                        .frame(width: 38, height: 38)
                    Text(cueSymbol)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(isMine ? OT.prompterGold : OT.reader)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(headingText)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("[ \(cueText) ]")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Text(instructionText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .padding(.vertical, 4)
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(cueSymbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isMine ? OT.accent : OT.reader)
                    .frame(width: 36, height: 36)
                    .background(isMine ? OT.accentSoft : OT.reader.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(headingText)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                        Text("[ \(cueText) ]")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(OT.labelTertiary)
                    }
                    Text(instructionText)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }
}
