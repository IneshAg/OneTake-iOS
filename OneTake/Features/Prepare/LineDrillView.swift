import SwiftUI
import OneTakeUI

// MARK: - First-Letter Prompts / Mask & Reveal — same mechanic as Prepare's toggle, run as a drill

struct LineDrillView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @State private var displayMode: RecallDisplayMode
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var peeked: ScriptLine.ID?
    @State private var revealedWords: [ScriptLine.ID: Set<Int>] = [:]
    @State private var hiddenGapWords: [ScriptLine.ID: Set<Int>] = [:]

    init(auditionID: Audition.ID, sceneIndex: Int, mode: LineLearningMode) {
        self.auditionID = auditionID
        self.sceneIndex = sceneIndex
        _displayMode = State(initialValue: mode == .firstLetter ? .firstLetters : mode == .gapRecall ? .gaps : .hideMine)
    }

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let scene = a.scenes[sceneIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    Text(scene.title).font(.otLargeTitle)
                    Picker("Practice display", selection: $displayMode) {
                        ForEach(RecallDisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ForEach(scene.lines) { line in lineView(line) }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .padding(.bottom, OTSpace.xl)
            }
            .otCanvas()
            .navigationTitle("Scene \(scene.number) of \(a.scenes.count)")
            .navigationBarTitleDisplayMode(.inline)
            .otBottomBar {
                Button("Done") { store.pop() }
                    .buttonStyle(.ot(.primary))
            }
            .task(id: displayMode) {
                guard displayMode == .gaps else { return }
                await loadGapSelections(scene.lines)
            }
            .onChange(of: displayMode) { _, _ in
                peeked = nil
                revealedWords.removeAll()
            }
        }
    }

    @ViewBuilder private func lineView(_ line: ScriptLine) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            Text(line.isMine ? "\(line.character) · YOU" : line.character)
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(line.isMine ? OT.accent : OT.reader)
            HStack(alignment: .top, spacing: OTSpace.s) {
                if line.isMine { Capsule().fill(OT.accent).frame(width: 3) } // ot-lint:allow
                if line.isMine && displayMode == .firstLetters && peeked != line.id {
                    RecallWordHintText(
                        text: line.text,
                        revealedWords: revealedWords[line.id, default: []],
                        font: .system(size: 19, weight: .semibold), // ot-lint:allow
                        color: OT.labelPrimary
                    ) { wordIndex in
                        var words = revealedWords[line.id, default: []]
                        if words.contains(wordIndex) { words.remove(wordIndex) }
                        else { words.insert(wordIndex) }
                        revealedWords[line.id] = words
                        Haptics.tick()
                    }
                } else if line.isMine && displayMode == .gaps && peeked != line.id {
                    RecallGapHintText(text: line.text,
                                      hiddenWords: hiddenGapWords[line.id, default: []],
                                      revealedWords: revealedWords[line.id, default: []],
                                      font: .system(size: 19, weight: .semibold), color: OT.labelPrimary) { wordIndex in // ot-lint:allow
                        var words = revealedWords[line.id, default: []]
                        if words.contains(wordIndex) { words.remove(wordIndex) } else { words.insert(wordIndex) }
                        revealedWords[line.id] = words
                        Haptics.tick()
                    }
                } else {
                    Text(otLineDisplay(line, mode: lineDisplayMode, peeked: peeked == line.id))
                        .font(line.isMine ? .otHeadline : .otBody)
                        .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if line.isMine && displayMode == .hideMine {
                Button(peeked == line.id ? "Hide line" : "Reveal line") {
                    peeked = peeked == line.id ? nil : line.id
                    Haptics.tick()
                }
                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent)
            } else if line.isMine && displayMode == .firstLetters {
                Text("Tap any word to reveal it")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
            } else if line.isMine && displayMode == .gaps {
                Text("Tap a gap to reveal its word")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
            }
        }
        .padding(.vertical, OTSpace.xs)
    }

    private var lineDisplayMode: LineDisplayMode {
        switch displayMode {
        case .full: .full
        case .firstLetters: .firstLetters
        case .gaps: .masked(level: 2)
        case .hideMine: .hide
        }
    }

    private func loadGapSelections(_ lines: [ScriptLine]) async {
        var selections: [ScriptLine.ID: Set<Int>] = [:]
        for line in lines where line.isMine && !line.isSilentReactionCue {
            selections[line.id] = await RecallGapSelectionStore.hiddenWordIndices(for: line.text)
        }
        hiddenGapWords = selections
    }
}

private enum RecallDisplayMode: String, CaseIterable, Hashable {
    case full = "Full lines"
    case firstLetters = "First letters"
    case gaps = "Gaps"
    case hideMine = "Hide mine"
}
