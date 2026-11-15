import SwiftUI
import OneTakeUI

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
    @State private var showScriptEditor = false
    @State private var showReaderSheet = false
    @State private var milestone: OTMilestoneBannerItem?

    private var piece: PracticePiece? {
        if let id = savedSampleID ?? pieceID {
            return store.practice.first { $0.id == id }
        }
        if isSample { return samplePiece }
        return nil
    }
    private var scene: ScriptScene? { piece?.scene }

    private var ensuredSavedPieceID: PracticePiece.ID? {
        if let saved = savedSampleID ?? pieceID { return saved }
        return nil
    }

    @discardableResult
    private func ensurePersistedPiece() -> PracticePiece.ID? {
        if let saved = savedSampleID ?? pieceID { return saved }
        guard isSample, let scene else { return nil }
        let saved = store.addStandalonePracticePiece(
            title: samplePiece.title,
            character: samplePiece.character,
            scene: scene,
            detail: "Sample scene"
        )
        savedSampleID = saved.id
        return saved.id
    }

    var body: some View {
        ScrollView {
            Group {
                if let piece, let scene {
                    VStack(alignment: .leading, spacing: OTSpace.m) {
                    Text(piece.title).font(.otTitle).foregroundStyle(OT.labelPrimary)
                    Text("Your role: \(piece.character)").font(.otFootnote).foregroundStyle(OT.labelTertiary)

                    Picker("Practice display", selection: $displayMode) {
                        Text("Full").tag(StandaloneDisplay.full)
                        Text("First letters").tag(StandaloneDisplay.firstLetters)
                        Text("Gaps").tag(StandaloneDisplay.gaps)
                        Text("Hide my lines").tag(StandaloneDisplay.hideMine)
                    }
                    .pickerStyle(.segmented)

                    let readerLines = scene.lines.filter { !$0.isMine }
                    if !readerLines.isEmpty {
                        let scope: ReaderTrackScope? = {
                            if let audID = piece.auditionID, let sIdx = piece.sceneIndex {
                                return .audition(audID, sceneIndex: sIdx)
                            }
                            if let pid = ensuredSavedPieceID { return .practice(pid) }
                            return nil
                        }()
                        let recordedCues = scope.map { sc in
                            readerLines.indices.filter {
                                store.readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(scope: sc, line: $0)
                            }.count
                        } ?? 0
                        Button {
                            _ = ensurePersistedPiece()
                            showReaderSheet = true
                        } label: {
                            OTIconRow(
                                symbol: recordedCues == readerLines.count ? "waveform.circle.fill" : "person.wave.2.fill",
                                title: "Another person's voice",
                                detail: recordedCues == 0
                                    ? "Record \(readerLines.count) partner cue\(readerLines.count == 1 ? "" : "s")"
                                    : "\(recordedCues) of \(readerLines.count) cues recorded",
                                tint: OT.reader
                            )
                            .otCard(.grouped)
                        }
                        .buttonStyle(OTPressStyle(.card))
                    }

                    ForEach(scene.lines) { line in
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            HStack(spacing: OTSpace.s) {
                                Text(line.isMine ? "\(line.character) · YOU" : line.character)
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(line.isMine ? OT.accent : OT.reader)

                                Spacer()

                                if line.isMine {
                                    Button {
                                        if let targetID = ensurePersistedPiece(),
                                           let result = store.toggleLineLearned(pieceID: targetID, lineID: line.id) {
                                            if result.allLearned {
                                                Haptics.celebrate()
                                                milestone = OTMilestoneBannerItem(
                                                    title: "All lines learned!",
                                                    subtitle: piece.title
                                                )
                                            } else if result.nowLearned {
                                                Haptics.stepDone()
                                            } else {
                                                Haptics.tick()
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: OTSpace.xs) {
                                            Image(systemName: line.isLearned ? "checkmark.circle.fill" : "circle")
                                                .font(.otSubhead.weight(.semibold))
                                            Text(line.isLearned ? "Learned" : "Mark learned")
                                                .font(.otCaption.weight(.semibold))
                                        }
                                        .foregroundStyle(line.isLearned ? OT.success : OT.labelTertiary)
                                        .padding(.horizontal, OTSpace.s)
                                        .padding(.vertical, OTSpace.xs)
                                        .background(
                                            Capsule().fill(line.isLearned ? OT.success.opacity(0.14) : OT.fillField)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .animation(OTMotion.bouncy, value: line.isLearned)
                                    .accessibilityLabel(line.isLearned ? "Line learned, tap to unmark" : "Mark line as learned")
                                }
                            }

                            if line.isSilentReactionCue {
                                SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: false)
                            } else {
                                HStack(alignment: .top, spacing: OTSpace.s) {
                                    if line.isMine {
                                        Capsule().fill(OT.accent).frame(width: 3) // ot-lint:allow
                                    }

                                    if line.isMine && displayMode == .firstLetters && !revealed.contains(line.id) {
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
                                    } else if line.isMine && displayMode == .gaps && !revealed.contains(line.id) {
                                        RecallGapHintText(
                                            text: line.text,
                                            hiddenWords: hiddenGapWords[line.id, default: []],
                                            revealedWords: revealedWords[line.id, default: []],
                                            font: .system(size: 19, weight: .semibold), // ot-lint:allow
                                            color: OT.labelPrimary
                                        ) { wordIndex in
                                            var words = revealedWords[line.id, default: []]
                                            if words.contains(wordIndex) { words.remove(wordIndex) } else { words.insert(wordIndex) }
                                            revealedWords[line.id] = words
                                            Haptics.tick()
                                        }
                                    } else {
                                        Text(displayText(for: line))
                                            .font(line.isMine ? .system(size: 19, weight: .semibold) : .otBody) // ot-lint:allow
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
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(OT.accent)
                            } else if displayMode == .firstLetters && line.isMine && !line.isSilentReactionCue {
                                Text("Tap any word to reveal it")
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            } else if displayMode == .gaps && line.isMine && !line.isSilentReactionCue {
                                Text("Tap a gap to reveal its word")
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                        }
                        .padding(OTSpace.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .otCard(.grouped)
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
                                    store.markAllLinesLearned(pieceID: targetID, learned: false)
                                    samplePiece.linesLearned = 0
                                    Haptics.tick()
                                }
                                .buttonStyle(.otCompact)
                            } else {
                                HStack(spacing: OTSpace.s) {
                                    if activePiece.linesLearned > 0 {
                                        Button("Reset") {
                                            store.markAllLinesLearned(pieceID: targetID, learned: false)
                                            samplePiece.linesLearned = 0
                                            Haptics.tick()
                                        }
                                        .buttonStyle(.otCompact)
                                    }
                                    Button("Mark lines learned") {
                                        store.markAllLinesLearned(pieceID: targetID, learned: true)
                                        samplePiece.linesLearned = activePiece.linesTotal
                                        Haptics.celebrate()
                                        milestone = OTMilestoneBannerItem(
                                            title: "All lines learned!",
                                            subtitle: activePiece.title
                                        )
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
                                if let saved = ensurePersistedPiece() {
                                    store.markAllLinesLearned(pieceID: saved, learned: true)
                                    samplePiece.linesLearned = scene.lines.filter(\.isMine).count
                                    Haptics.celebrate()
                                    milestone = OTMilestoneBannerItem(
                                        title: "All lines learned!",
                                        subtitle: piece.title
                                    )
                                }
                            }
                            .buttonStyle(.otCompact)
                        }
                    }
                    }
                } else {
                    ContentUnavailableView("Scene unavailable", systemImage: "theatermasks")
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
        }
        .otCanvas()
        .otMilestoneBanner($milestone)
        .navigationTitle(isSample ? "Sample scene" : "Practice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showScriptEditor = true
                }
            }
        }
        .sheet(isPresented: $showScriptEditor) {
            if let piece, let scene {
                ScriptTextEditSheet(
                    title: "Edit script text",
                    roleName: piece.character,
                    initialText: formattedScriptText(from: scene)
                ) { updatedText in
                    if let targetID = ensurePersistedPiece() {
                        store.updateStandaloneSceneScript(pieceID: targetID, scriptText: updatedText)
                    }
                }
            }
        }
        .sheet(isPresented: $showReaderSheet) {
            if let pid = ensuredSavedPieceID, let scene {
                if let audID = piece?.auditionID, let sIdx = piece?.sceneIndex {
                    NavigationStack {
                        RecordReaderView(auditionID: audID, sceneIndex: sIdx)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showReaderSheet = false }
                                }
                            }
                    }
                } else {
                    StandaloneReaderSheet(pieceID: pid, scene: scene)
                }
            }
        }
        .otBottomBar {
            HStack(spacing: OTSpace.m) {
                Button {
                    launchPractice(mode: .voiceOnly)
                } label: {
                    HStack(spacing: OTSpace.xs) {
                        Image(systemName: "mic.fill")
                        Text("Run voice")
                    }
                }
                .buttonStyle(.ot(.glass, size: .large))

                Button {
                    launchPractice(mode: .camera)
                } label: {
                    HStack(spacing: OTSpace.xs) {
                        Image(systemName: "video.fill")
                        Text("Record take")
                    }
                }
                .buttonStyle(.ot(.primary, size: .large))
            }
        }
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
                let saved = store.addStandalonePracticePiece(
                    title: piece.title,
                    character: piece.character,
                    scene: scene,
                    detail: "Sample scene"
                )
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

    private func formattedScriptText(from scene: ScriptScene) -> String {
        scene.lines.map { "\($0.character.uppercased())\n\($0.text)" }.joined(separator: "\n\n")
    }
}

private enum PracticeSample {
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
