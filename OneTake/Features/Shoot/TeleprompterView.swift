import SwiftUI
import OneTakeUI

// MARK: - Sides Teleprompter (mirrors Figma 17_Recording.html / 17.2_RecYourLine.html / 24e_PracticeRecording.html)

typealias TeleprompterView = SidesPrompterView

struct SidesPrompterView: View {
    let lines: [ScriptLine]
    let currentIndex: Int
    var spokenTranscript: String = ""
    var prompterSize: Int = 1 // 0: Regular, 1: Big, 2: Huge
    var mirror: Bool = false
    var readerIsPlaying: Bool = false
    var readerAudioMissing: Bool = false
    var displayMode: StandaloneDisplay = .full
    var hiddenGapWords: [ScriptLine.ID: Set<Int>] = [:]
    var revealedLines: Set<ScriptLine.ID> = []
    var onAdvance: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onToggleReveal: ((ScriptLine.ID) -> Void)? = nil
    var onCycleSize: (() -> Void)? = nil

    private var currentLine: ScriptLine? {
        lines.indices.contains(currentIndex) ? lines[currentIndex] : nil
    }

    private var prevLine: ScriptLine? {
        currentIndex > 0 && lines.indices.contains(currentIndex - 1) ? lines[currentIndex - 1] : nil
    }

    private var nextLine: ScriptLine? {
        currentIndex + 1 < lines.count ? lines[currentIndex + 1] : nil
    }

    private var fontSize: CGFloat {
        switch prompterSize {
        case 0: return 18  // Regular: compact, clean & focused
        case 2: return 38  // Huge: massive font for tripod / distance reading
        default: return 26 // Big: standard comfortable prompter
        }
    }

    private var prompterMaxHeight: CGFloat {
        switch prompterSize {
        case 0: return 118  // Regular: ultra-compact, leaves camera framing completely clear
        case 2: return 280  // Huge: spacious box to fit large 38pt text without cramping
        default: return 195 // Big: standard height
        }
    }

    private var progress: Double {
        guard !lines.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(lines.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: prompterSize == 0 ? 6 : 10) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: prompterSize == 0 ? 6 : 12) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            let isCurrent = (index == currentIndex)
                            let isPast = (index < currentIndex)

                            VStack(alignment: .leading, spacing: prompterSize == 0 ? 3 : 6) {
                                // Header tag
                                HStack(spacing: 8) {
                                    Text(line.isMine ? "\(line.character.uppercased()) · YOU" : line.character.uppercased())
                                        .font(.system(size: isCurrent ? (prompterSize == 0 ? 12 : 13) : 11, weight: .bold, design: .monospaced)) // ot-lint:allow
                                        .tracking(0.8)
                                        .foregroundStyle(isCurrent ? (line.isMine ? OT.prompterGold : OT.reader) : Color.white.opacity(0.40)) // ot-lint:allow

                                    if isCurrent {
                                        if !line.isMine {
                                            if readerIsPlaying {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "waveform")
                                                        .font(.system(size: 11, weight: .semibold)) // ot-lint:allow
                                                    Text("Reading")
                                                        .font(.system(size: 11, weight: .semibold, design: .monospaced)) // ot-lint:allow
                                                }
                                                .foregroundStyle(OT.reader)
                                            } else if readerAudioMissing {
                                                Text("No audio · auto-playing")
                                                    .font(.system(size: 11, weight: .medium, design: .monospaced)) // ot-lint:allow
                                                    .foregroundStyle(OT.due)
                                            }
                                        }
                                    }

                                    Spacer()

                                    if isCurrent {
                                        // Clickable prompter size badge right on the prompter line header
                                        if let onCycleSize {
                                            Button {
                                                onCycleSize()
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "textformat.size")
                                                        .font(.system(size: 9, weight: .bold)) // ot-lint:allow
                                                    Text(["Regular", "Big", "Huge"][min(max(prompterSize, 0), 2)])
                                                        .font(.system(size: 10, weight: .bold, design: .monospaced)) // ot-lint:allow
                                                }
                                                .foregroundStyle(Color.white.opacity(0.88)) // ot-lint:allow
                                                .padding(.horizontal, 7) // ot-lint:allow
                                                .padding(.vertical, 3) // ot-lint:allow
                                                .background(Color.white.opacity(0.16), in: Capsule()) // ot-lint:allow
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        Text("\(index + 1) of \(lines.count)")
                                            .font(.system(size: prompterSize == 0 ? 11 : 12, weight: .semibold, design: .monospaced)) // ot-lint:allow
                                            .foregroundStyle(Color.white.opacity(0.50)) // ot-lint:allow
                                    }
                                }

                                // Dialogue content
                                if isCurrent {
                                    if line.isSilentReactionCue {
                                        SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: true)
                                    } else if line.isMine {
                                        let matchedIndices = SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: spokenTranscript)
                                        let isRev = revealedLines.contains(line.id)
                                        attributedPromptText(
                                            line.text,
                                            matchedIndices: matchedIndices,
                                            displayMode: displayMode,
                                            isRevealed: isRev,
                                            hiddenWords: hiddenGapWords[line.id, default: []]
                                        )
                                        .font(.system(size: fontSize, weight: .bold, design: .monospaced)) // ot-lint:allow
                                        .shadow(
                                            color: matchedIndices.isEmpty ? .clear : OT.prompterGold.opacity(0.65),
                                            radius: matchedIndices.isEmpty ? 0 : 7
                                        )
                                        .scaleEffect(x: mirror ? -1 : 1, y: 1)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if displayMode != .full {
                                            Button {
                                                onToggleReveal?(line.id)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: isRev ? "eye.slash" : "eye")
                                                    Text(isRev ? "Hide hint" : displayMode == .firstLetters ? "Show full line hint" : "Reveal line hint")
                                                }
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced)) // ot-lint:allow
                                                .foregroundStyle(OT.prompterGold)
                                                .padding(.horizontal, 9) // ot-lint:allow
                                                .padding(.vertical, 4) // ot-lint:allow
                                                .background(Color.white.opacity(0.14), in: Capsule()) // ot-lint:allow
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.top, OTSpace.xxs)
                                        }
                                    } else {
                                        Text(line.text)
                                            .font(.system(size: fontSize, weight: .medium, design: .monospaced)) // ot-lint:allow
                                            .italic()
                                            .foregroundStyle(Color.white.opacity(0.88)) // ot-lint:allow
                                            .scaleEffect(x: mirror ? -1 : 1, y: 1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else if isPast {
                                    Text(line.isSilentReactionCue ? "[ \(line.text) ] Reaction beat" : line.text)
                                        .font(.system(size: prompterSize == 0 ? 11 : 12, weight: .regular, design: .monospaced)) // ot-lint:allow
                                        .foregroundStyle(Color.white.opacity(0.25)) // ot-lint:allow
                                        .lineLimit(1)
                                } else {
                                    // Upcoming lines left below the active line (compact peek)
                                    let isImmediateNext = (index == currentIndex + 1)
                                    let nextLimit = isImmediateNext ? (prompterSize == 0 ? 1 : 2) : 1
                                    let nextOpacity = isImmediateNext ? 0.55 : 0.20
                                    if line.isSilentReactionCue {
                                        Text("[ \(line.text) ] \(line.isMine ? "Questioning expression" : "Reaction beat")")
                                            .font(.system(size: prompterSize == 0 ? 12 : 13, weight: .semibold, design: .monospaced)) // ot-lint:allow
                                            .foregroundStyle(Color.white.opacity(nextOpacity)) // ot-lint:allow
                                            .lineLimit(1)
                                    } else if line.isMine && displayMode == .firstLetters {
                                        Text(promptFirstLettersString(line.text))
                                            .font(.system(size: prompterSize == 0 ? 12 : 13, weight: .medium, design: .monospaced)) // ot-lint:allow
                                            .foregroundStyle(Color.white.opacity(nextOpacity)) // ot-lint:allow
                                            .lineLimit(nextLimit)
                                    } else if line.isMine && displayMode == .hideMine && !revealedLines.contains(line.id) {
                                        Text(String(repeating: "• ", count: min(line.text.split(separator: " ").count, 8)))
                                            .font(.system(size: prompterSize == 0 ? 12 : 13, weight: .medium, design: .monospaced)) // ot-lint:allow
                                            .foregroundStyle(Color.white.opacity(nextOpacity)) // ot-lint:allow
                                            .lineLimit(1)
                                    } else {
                                        Text(line.text)
                                            .font(.system(size: prompterSize == 0 ? 12 : 13, weight: .medium, design: .monospaced)) // ot-lint:allow
                                            .foregroundStyle(Color.white.opacity(nextOpacity)) // ot-lint:allow
                                            .lineLimit(nextLimit)
                                    }
                                }
                            }
                            .id("prompter_line_\(index)")
                            .padding(.vertical, isCurrent ? (prompterSize == 0 ? 2 : 4) : 1)
                        }
                    }
                    .padding(.top, OTSpace.xs)
                    .padding(.bottom, prompterMaxHeight * 0.85) // ot-lint:allow
                }
                .frame(maxHeight: prompterMaxHeight) // ot-lint:allow
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.02),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: currentIndex) { _, newIndex in
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
                        proxy.scrollTo("prompter_line_\(newIndex)", anchor: .top)
                    }
                }
                .onAppear {
                    proxy.scrollTo("prompter_line_\(currentIndex)", anchor: .top)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 3) // ot-lint:allow
                    Capsule().fill(Color.white) // ot-lint:allow
                        .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 3) // ot-lint:allow
                }
            }
            .frame(height: 3) // ot-lint:allow
            .padding(.top, 6) // ot-lint:allow
        }
        .padding(OTSpace.cardInset)
        .background(
            RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous)
                .fill(Color.black.opacity(0.55)) // ot-lint:allow
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1) // ot-lint:allow
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onAdvance() }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width > 60 { onPrevious() }
                else if value.translation.width < -60 { onAdvance() }
            }
        )
    }

    private func promptFirstLettersString(_ text: String) -> String {
        text.split(separator: " ").map { w in
            guard let f = w.first else { return "" }
            let punct = w.filter { $0.isPunctuation }
            return String(f) + "—" + (punct.isEmpty ? "" : String(punct))
        }.joined(separator: " ")
    }

    private func attributedPromptText(
        _ text: String,
        matchedIndices: Set<Int>,
        displayMode: StandaloneDisplay = .full,
        isRevealed: Bool = false,
        hiddenWords: Set<Int> = []
    ) -> Text {
        let words = text.split(separator: " ").map(String.init)
        var result = Text("")
        for (idx, word) in words.enumerated() {
            let isMatched = matchedIndices.contains(idx)
            let displayText: String
            switch displayMode {
            case .full:
                displayText = word
            case .firstLetters:
                if isRevealed {
                    displayText = word
                } else {
                    let first = word.first.map(String.init) ?? ""
                    let punct = word.filter { $0.isPunctuation }
                    displayText = first + "—" + (punct.isEmpty ? "" : String(punct))
                }
            case .gaps:
                if isRevealed || isMatched || !hiddenWords.contains(idx) {
                    displayText = word
                } else {
                    let letters = word.filter(\.isLetter)
                    let suffix = word.filter { !$0.isLetter && !$0.isNumber }
                    displayText = String(repeating: "_", count: min(max(2, letters.count), 8)) + suffix
                }
            case .hideMine:
                if isRevealed || isMatched {
                    displayText = word
                } else {
                    let punct = word.filter { $0.isPunctuation }
                    let dots = String(repeating: "•", count: max(2, min(word.count, 5)))
                    displayText = dots + (punct.isEmpty ? "" : String(punct))
                }
            }
            let space = (idx < words.count - 1 ? " " : "")
            let wordText = Text(displayText + space)
            if isMatched {
                result = result + wordText.foregroundColor(OT.prompterGold).fontWeight(.heavy)
            } else {
                result = result + wordText.foregroundColor(Color.white.opacity(displayMode == .hideMine && !isRevealed ? 0.55 : 1.0)) // ot-lint:allow
            }
        }
        return result
    }
}
