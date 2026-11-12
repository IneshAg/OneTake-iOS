import SwiftUI

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
            VStack(spacing: 0) {
                InContentNavHeader(title: "Scene \(scene.number) of \(a.scenes.count)", backLabel: "Back", onBack: { store.pop() })
                    .padding(.horizontal, OT.gutter)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(scene.title).font(.otLargeTitle)
                        Picker("Practice display", selection: $displayMode) {
                            ForEach(RecallDisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        ForEach(scene.lines) { line in lineView(line) }
                    }
                    .padding(.horizontal, OT.gutter)
                    .padding(.bottom, 100)
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Done") { store.pop() }.buttonStyle(.otPrimary).padding(OT.gutter)
                }
            }
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(line.isMine ? "\(line.character) · YOU" : line.character)
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(line.isMine ? OT.accent : OT.reader)
            HStack(alignment: .top, spacing: 10) {
                if line.isMine { Capsule().fill(OT.accent).frame(width: 3) }
                if line.isMine && displayMode == .firstLetters && peeked != line.id {
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
                } else if line.isMine && displayMode == .gaps && peeked != line.id {
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
                    Text(otLineDisplay(line, mode: lineDisplayMode, peeked: peeked == line.id))
                        .font(line.isMine ? .system(size: 19, weight: .semibold) : .otBody)
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
        .padding(.vertical, 4)
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

// MARK: - Hands-Free Audio Walk — loops the whole scene's audio, no screen interaction

struct AudioWalkView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var walker = AudioWalkPlayer()
    @State private var playing = false

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let scene = a.scenes[sceneIndex]
            VStack(spacing: 20) {
                InContentNavHeader(title: "Audio Walk", backLabel: "Back", onBack: { walker.stop(); store.pop() })
                    .padding(.top, 4)

                Spacer()
                Image(systemName: "headphones").font(.system(size: 56)).foregroundStyle(OT.accent)
                Text(playing ? "Looping \(scene.title)…" : "Ready to loop \(scene.title)").font(.otTitle)
                Text("Your recorded reader lines, with a pause the length of each of yours, on repeat. Say your lines into the gaps.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary).multilineTextAlignment(.center)
                let _ = store.readerTrackVersion
                let unowned = scene.lines.filter { !$0.isMine }
                let readerLines = unowned.count
                let recorded = (0..<readerLines).filter {
                    ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: $0)
                }.count
                if recorded < readerLines {
                    Text("\(recorded) of \(readerLines) reader lines recorded. Record the rest before starting the Audio Walk.")
                        .font(.otFootnote).foregroundStyle(OT.warning)
                    Button { store.push(.recordReader(auditionID, sceneIndex: sceneIndex)) } label: { Label("Record the reader", systemImage: "mic") }
                        .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 12))
                }
                if readerLines == 0 {
                    Text("This scene has no reader lines to play.")
                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                }
                Text("The screen stays on while it loops, so it keeps going in your pocket.")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary).multilineTextAlignment(.center)
                Spacer()
                Button(playing ? "Stop" : "Start looping") {
                    playing.toggle()
                    if playing { walker.loop(scene: scene, auditionID: auditionID, sceneIndex: sceneIndex) } else { walker.stop() }
                }
                .buttonStyle(.otPrimary)
                .disabled(readerLines == 0 || recorded < readerLines)
                Button("Done") { walker.stop(); dismiss() }.buttonStyle(.otSecondary)
            }
            .padding(.horizontal, OT.gutter).padding(.bottom, OT.gutter)
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            // Auto-Lock would suspend the app and stop the loop.
            .keepScreenAwake()
            .onDisappear { walker.stop() }
        }
    }
}

/// Loops a scene's reader tracks and your own line timings continuously, hands-free.
/// Reuses the same on-device reader recordings as Run Lines — no synthetic voice.
@MainActor
@Observable
final class AudioWalkPlayer {
    private var task: Task<Void, Never>?
    private let reader = ReaderTrackPlayer()

    func loop(scene: ScriptScene, auditionID: Audition.ID, sceneIndex: Int) {
        stop()
        let readerLines = scene.lines.filter { !$0.isMine }.count
        guard readerLines > 0,
              (0..<readerLines).allSatisfy({ index in
                  FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: index).path)
              }) else { return }
        task = Task {
            while !Task.isCancelled {
                var readerIndex = 0
                for line in scene.lines {
                    if Task.isCancelled { return }
                    if line.isMine {
                        try? await Task.sleep(for: .seconds(Double(line.text.count) * 0.06 + 0.6))
                    } else {
                        reader.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerIndex)
                        readerIndex += 1
                        try? await Task.sleep(for: .seconds(Double(line.text.count) * 0.06 + 0.8))
                    }
                }
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        reader.stop()
    }
}
