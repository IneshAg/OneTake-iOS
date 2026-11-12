import SwiftUI

// MARK: - Standalone Practice View (Full / Gaps / Cold Read Drill)

struct StandalonePracticeView: View {
    let pieceID: PracticePiece.ID?
    var isSample = false
    @Environment(AppStore.self) private var store
    @State private var displayMode = StandaloneDisplay.full
    @State private var revealed: Set<ScriptLine.ID> = []
    @State private var revealedWords: [ScriptLine.ID: Set<Int>] = [:]
    @State private var hiddenGapWords: [ScriptLine.ID: Set<Int>] = [:]
    @State private var samplePiece = PracticeSample.make()
    @State private var savedSampleID: PracticePiece.ID?

    private var piece: PracticePiece? {
        if let id = savedSampleID ?? pieceID {
            return store.practice.first { $0.id == id }
        }
        if isSample { return samplePiece }
        return nil
    }
    private var scene: ScriptScene? { piece?.scene }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: isSample ? "Sample scene" : "Practice", backLabel: "Back", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            Group {
                if let piece, let scene {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(piece.title).font(.otTitle).foregroundStyle(OT.labelPrimary)
                            Text("Your role: \(piece.character)").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            Picker("Practice display", selection: $displayMode) {
                                Text("Full").tag(StandaloneDisplay.full)
                                Text("First letters").tag(StandaloneDisplay.firstLetters)
                                Text("Gaps").tag(StandaloneDisplay.gaps)
                                Text("Hide my lines").tag(StandaloneDisplay.hideMine)
                            }
                            .pickerStyle(.segmented)
                            ForEach(scene.lines) { line in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(line.isMine ? "\(line.character) · YOU" : line.character)
                                        .font(.otCaption.weight(.semibold))
                                        .foregroundStyle(line.isMine ? OT.accent : OT.reader)
                                    if line.isSilentReactionCue {
                                        SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: false)
                                    } else {
                                        HStack(alignment: .top, spacing: 10) {
                                            if line.isMine { Capsule().fill(OT.accent).frame(width: 3) }
                                            if line.isMine && displayMode == .firstLetters && !revealed.contains(line.id) {
                                                RecallWordHintText(
                                                    text: line.text,
                                                    revealedWords: revealedWords[line.id, default: []],
                                                    font: .system(size: 19, weight: .semibold),
                                                    color: OT.labelPrimary
                                                ) { wordIndex in
                                                    var words = revealedWords[line.id, default: []]
                                                    if words.contains(wordIndex) { words.remove(wordIndex) }
                                                    else { words.insert(wordIndex) }
                                                    revealedWords[line.id] = words
                                                    Haptics.tick()
                                                }
                                            } else if line.isMine && displayMode == .gaps && !revealed.contains(line.id) {
                                                RecallGapHintText(text: line.text,
                                                                  hiddenWords: hiddenGapWords[line.id, default: []],
                                                                  revealedWords: revealedWords[line.id, default: []],
                                                                  font: .system(size: 19, weight: .semibold), color: OT.labelPrimary) { wordIndex in
                                                    var words = revealedWords[line.id, default: []]
                                                    if words.contains(wordIndex) { words.remove(wordIndex) } else { words.insert(wordIndex) }
                                                    revealedWords[line.id] = words
                                                    Haptics.tick()
                                                }
                                            } else {
                                                Text(displayText(for: line))
                                                    .font(line.isMine ? .system(size: 19, weight: .semibold) : .otBody)
                                                    .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        guard line.isMine, displayMode == .hideMine else { return }
                                                        if revealed.contains(line.id) { revealed.remove(line.id) }
                                                        else { revealed.insert(line.id) }
                                                        Haptics.tick()
                                                    }
                                            }
                                        }
                                    }
                                    if displayMode == .hideMine && line.isMine && !line.isSilentReactionCue {
                                        Button(revealed.contains(line.id) ? "Hide line" : "Reveal line") {
                                            if revealed.contains(line.id) { revealed.remove(line.id) } else { revealed.insert(line.id) }
                                        }
                                        .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent)
                                    } else if displayMode == .firstLetters && line.isMine && !line.isSilentReactionCue {
                                        Text("Tap any word to reveal it")
                                            .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    } else if displayMode == .gaps && line.isMine && !line.isSilentReactionCue {
                                        Text("Tap a gap to reveal its word")
                                            .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading).otCard(radius: 16)
                            }
                            let targetPieceID: PracticePiece.ID? = isSample ? (savedSampleID ?? pieceID) : pieceID
                            if let targetID = targetPieceID {
                                let activePiece = piece
                                HStack {
                                    Label("\(activePiece.linesLearned) of \(activePiece.linesTotal) learned",
                                          systemImage: activePiece.linesLearned >= activePiece.linesTotal && activePiece.linesTotal > 0 ? "checkmark.circle.fill" : "checkmark.circle")
                                        .font(.otFootnote)
                                        .foregroundStyle(activePiece.linesLearned >= activePiece.linesTotal && activePiece.linesTotal > 0 ? OT.accent : OT.labelTertiary)
                                    Spacer()
                                    if activePiece.linesLearned >= activePiece.linesTotal && activePiece.linesTotal > 0 {
                                        Button("Mark unlearned") {
                                            store.recordStandaloneRun(pieceID: targetID, linesOnYourOwn: 0)
                                            samplePiece.linesLearned = 0
                                            Haptics.tick()
                                        }
                                        .buttonStyle(.otCompact)
                                    } else {
                                        HStack(spacing: 8) {
                                            if activePiece.linesLearned > 0 {
                                                Button("Reset") {
                                                    store.recordStandaloneRun(pieceID: targetID, linesOnYourOwn: 0)
                                                    samplePiece.linesLearned = 0
                                                    Haptics.tick()
                                                }
                                                .buttonStyle(.otCompact)
                                            }
                                            Button("Mark lines learned") {
                                                store.recordStandaloneRun(pieceID: targetID, linesOnYourOwn: activePiece.linesTotal)
                                                samplePiece.linesLearned = activePiece.linesTotal
                                                Haptics.success()
                                            }
                                            .buttonStyle(.otCompact)
                                        }
                                    }
                                }
                            } else if isSample && !scene.lines.isEmpty {
                                HStack {
                                    Label("\(samplePiece.linesLearned) of \(scene.lines.filter(\.isMine).count) learned",
                                          systemImage: samplePiece.linesLearned >= scene.lines.filter(\.isMine).count && !scene.lines.isEmpty ? "checkmark.circle.fill" : "checkmark.circle")
                                        .font(.otFootnote)
                                        .foregroundStyle(samplePiece.linesLearned >= scene.lines.filter(\.isMine).count ? OT.accent : OT.labelTertiary)
                                    Spacer()
                                    Button("Mark lines learned") {
                                        let saved = store.addStandalonePracticePiece(title: piece.title,
                                                                                    character: piece.character,
                                                                                    scene: scene, detail: "Sample scene")
                                        savedSampleID = saved.id
                                        samplePiece.linesLearned = scene.lines.filter(\.isMine).count
                                        store.recordStandaloneRun(pieceID: saved.id, linesOnYourOwn: scene.lines.filter(\.isMine).count)
                                        Haptics.success()
                                    }
                                    .buttonStyle(.otCompact)
                                }
                            }
                        }
                        .padding(.horizontal, OT.gutter).padding(.bottom, 120)
                    }
                    .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 12) {
                            Button {
                                launchPractice(mode: .voiceOnly)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "mic.fill")
                                    Text("Run voice")
                                }
                                .font(.otHeadline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .modifier(GlassCapsuleButtonCompatibility())

                            Button {
                                launchPractice(mode: .camera)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "video.fill")
                                    Text("Record take")
                                }
                                .font(.otHeadline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .modifier(GlassProminentCapsuleButtonCompatibility())
                        }
                        .padding(.horizontal, OT.gutter)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .background(.ultraThinMaterial)
                    }
                } else {
                    ContentUnavailableView("Scene unavailable", systemImage: "theatermasks")
                }
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task(id: displayMode) {
            guard displayMode == .gaps, let lines = scene?.lines else { return }
            var selections: [ScriptLine.ID: Set<Int>] = [:]
            for line in lines where line.isMine && !line.isSilentReactionCue {
                selections[line.id] = await RecallGapSelectionStore.hiddenWordIndices(for: line.text)
            }
            hiddenGapWords = selections
        }
        .onChange(of: displayMode) { _, _ in
            revealed.removeAll()
            revealedWords.removeAll()
        }
    }

    private func launchPractice(mode: PracticeRecordMode) {
        guard let piece, let scene else { return }
        let targetID: PracticePiece.ID
        if isSample {
            if let savedSampleID {
                store.promotePracticePiece(savedSampleID)
                targetID = savedSampleID
            } else {
                let saved = store.addStandalonePracticePiece(title: piece.title, character: piece.character,
                                                            scene: scene, detail: "Sample scene")
                savedSampleID = saved.id
                store.promotePracticePiece(saved.id)
                targetID = saved.id
            }
        } else if let pieceID {
            store.promotePracticePiece(pieceID)
            targetID = pieceID
        } else {
            targetID = piece.id
        }
        store.camera = .practiceTake(pieceID: targetID, initialDisplayMode: displayMode, initialRecordMode: mode)
    }

    private func displayText(for line: ScriptLine) -> String {
        guard line.isMine else { return line.text }
        switch displayMode {
        case .full: return line.text
        case .firstLetters: return otLineDisplay(line, mode: .firstLetters, peeked: revealed.contains(line.id))
        case .gaps: return line.text
        case .hideMine:
            return revealed.contains(line.id) ? line.text : String(repeating: "• ", count: min(line.text.split(separator: " ").count, 8))
        }
    }
}

// MARK: - Sample Piece Generator

enum PracticeSample {
    static func make() -> PracticePiece {
        let role = "Maya"
        let scene = ScriptScene(number: 1, title: "A late goodbye", heading: "INT. STATION — NIGHT", lines: [
            ScriptLine(character: "Maya", text: "I know the train leaves at six. I just didn't think you'd come.", isMine: true),
            ScriptLine(character: "Reader", text: "You asked me to.", isMine: false),
            ScriptLine(character: "Maya", text: "I asked you to say goodbye.", isMine: true),
            ScriptLine(character: "Reader", text: "Is that all you want?", isMine: false),
            ScriptLine(character: "Maya", text: "No. But it's all I know how to ask for.", isMine: true)
        ], estimatedSeconds: 30)
        return PracticePiece(title: scene.title, detail: "Sample · not saved", linesLearned: 0,
                             linesTotal: scene.lines.filter(\.isMine).count, character: role, scene: scene)
    }
}
