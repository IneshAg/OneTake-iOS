import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 11 Prepare

struct PrepareView: View {
    enum Mode: String, CaseIterable, Identifiable { case full = "Full lines", firstLetters = "First letters", hide = "Hide mine"; var id: String { rawValue } }

    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .full
    @State private var peeked: ScriptLine.ID?
    @State private var showPrompterSettings = false
    @State private var showSides = false
    @AppStorage("prompter.size") private var prompterSize = 1
    @AppStorage("prompter.mirror") private var mirrorPrompter = false

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let scene = a.scenes[sceneIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    InContentNavHeader(title: "Scene \(scene.number) of \(a.scenes.count)", backLabel: "Back", onBack: { store.pop() }) {
                        Button { showPrompterSettings = true } label: {
                            Image(systemName: "textformat.size")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(OT.labelPrimary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Text size")
                    }
                    .padding(.top, 4)

                    Text(scene.title).font(.otLargeTitle)
                    Picker("Lines", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("\(learned(scene)) of \(scene.lines.filter(\.isMine).count) lines learned").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        Spacer()
                        Button { store.push(.reader(a.id, sceneIndex: sceneIndex)) } label: {
                            let readerName = scene.lines.first(where: { !$0.isMine })?.character.capitalized ?? "Reader"
                            let readerLines = scene.lines.filter { !$0.isMine }
                            let recorded = readerLines.indices.filter {
                                FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: a.id, sceneIndex: sceneIndex, line: $0).path)
                            }.count
                            Label("\(readerName) · \(recorded) of \(readerLines.count) recorded", systemImage: recorded == readerLines.count && !readerLines.isEmpty ? "waveform" : "mic")
                                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.reader)
                        }
                    }
                    if let notes = a.castingNotes {
                        // Casting's adjustment for this round, seen before every pass at the scene.
                        Label { Text(notes).font(.otCallout) } icon: { Image(systemName: "quote.opening") }
                            .foregroundStyle(OT.labelPrimary)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(OT.scriptHighlight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    ForEach(scene.lines) { line in lineView(line) }
                }
                .padding(.horizontal, OT.gutter)
                .padding(.bottom, 120)
            }
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) { bottomBar(a) }
            .sheet(isPresented: $showPrompterSettings) { PrompterSettingsSheet().presentationDetents([.medium]) }
        } else {
            // No scenes were read from what was added — say so and offer the fix instead of a blank page.
            VStack(spacing: 14) {
                InContentNavHeader(title: "Sides", backLabel: "Back", onBack: { store.pop() })
                    .padding(.top, 4)
                Spacer()
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(OT.labelTertiary)
                Text("No sides yet").font(.otLargeTitle)
                Text("OneTake couldn’t find any character lines in what was added. Paste, import or scan the pages and it will split them into scenes. Cues work as NAME on its own line, or “Maya: line”.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary).multilineTextAlignment(.center)
                Button("Add sides") { showSides = true }.buttonStyle(.otPrimary)
                Spacer()
            }
            .padding(OT.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showSides) { RevisedSidesSheet(auditionID: auditionID) }
        }
    }

    /// Real progress from the matching Practice piece, if one exists for this scene — not a constant.
    private func learned(_ s: ScriptScene) -> Int {
        store.practice.first(where: { $0.scene?.id == s.id })?.linesLearned ?? 0
    }

    @ViewBuilder private func lineView(_ line: ScriptLine) -> some View {
        let textSize = [19, 25, 32][min(max(prompterSize, 0), 2)]
        VStack(alignment: .leading, spacing: 4) {
            Text(line.isMine ? "\(line.character) · YOU" : line.character)
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(line.isMine ? OT.accent : OT.reader)
            HStack(alignment: .top, spacing: 10) {
                if line.isMine { Capsule().fill(OT.accent).frame(width: 3) }
                Text(display(line))
                    .font(line.isMine ? .system(size: CGFloat(textSize), weight: .semibold) : .system(size: CGFloat(textSize - 2)))
                    .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
                    .scaleEffect(x: mirrorPrompter ? -1 : 1, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { if line.isMine && mode != .full { peeked = peeked == line.id ? nil : line.id; Haptics.tick() } }
            }
        }
        .padding(.vertical, 4)
    }

    /// Same transform Practice's First-Letter / Mask & Reveal drills use — implemented once, in `otLineDisplay`.
    private func display(_ line: ScriptLine) -> String {
        let shared: LineDisplayMode = switch mode { case .full: .full; case .hide: .hide; case .firstLetters: .firstLetters }
        return otLineDisplay(line, mode: shared, peeked: peeked == line.id)
    }

    private func bottomBar(_ a: Audition) -> some View {
        HStack(spacing: 8) {
            Button { store.push(.runLines(a.id, sceneIndex: sceneIndex)) } label: {
                Label("Run lines", systemImage: "play.fill").labelStyle(TrailingIconLabelStyle())
                    .font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                    .padding(.horizontal, 14).frame(height: 44).background(OT.fillField, in: Capsule())
            }
            Button { store.push(.shootSetup(a.id, scene: sceneIndex)) } label: {
                Label("Record", systemImage: "record.circle").labelStyle(TrailingIconLabelStyle())
                    .font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelOnAccent)
                    .padding(.horizontal, 16).frame(height: 44).background(OT.accent, in: Capsule())
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 6)
    }
}

struct DotLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 7, height: 7); configuration.title }
    }
}

// MARK: - 11.2 Teleprompter settings

struct PrompterSettingsSheet: View {
    @AppStorage("prompter.size") private var size = 1
    @AppStorage("prompter.followVoice") private var followVoice = true
    /// Off by default: mirrored text only makes sense behind a beam-splitter glass.
    @AppStorage("prompter.mirror") private var mirror = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teleprompter").font(.otHeadline)
            Text("Because every time I tried")
                .font(.system(size: [20, 26, 34][min(max(size, 0), 2)], weight: .semibold))
                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 72)
                .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .scaleEffect(x: mirror ? -1 : 1, y: 1)
            SectionLabel(text: "Text size")
            Picker("Size", selection: $size) { Text("Regular").tag(0); Text("Large").tag(1); Text("Big print").tag(2) }.pickerStyle(.segmented)
            SectionLabel(text: "Scroll")
            Picker("Scroll", selection: $followVoice) { Text("Follows my voice").tag(true); Text("Timed").tag(false) }.pickerStyle(.segmented)
            Toggle("Mirror text", isOn: $mirror)
        }
        .padding(OT.gutter)
    }
}

// MARK: - 11.3–11.6 Run lines

struct RunLinesView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var prompted = false
    @State private var finished = false
    /// What this run actually showed: your lines said out loud without a prompt, and the ones that
    /// needed "Line?". Lines skipped with the forward button count as neither.
    @State private var onYourOwn: Set<Int> = []
    @State private var neededStart: Set<Int> = []
    @State private var reachedEnd = false
    @State private var follower = SpeechFollower()
    /// Plays the reader lines you recorded yourself (Record Maya). No synthetic or second-device voices.
    @State private var readerPlayer = ReaderTrackPlayer()
    @State private var readerAudioMissing = false
    /// The pending auto-advance after a reader line. Kept so a manual skip, pause or leaving the
    /// screen cancels it instead of letting it fire later and skip an extra line.
    @State private var readerAdvance: Task<Void, Never>?

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex), !a.scenes[sceneIndex].lines.isEmpty {
            let lines = a.scenes[sceneIndex].lines
            VStack(alignment: .leading, spacing: 18) {
                InContentNavHeader(title: "Run lines", backLabel: "Back", onBack: { dismiss() })
                    .padding(.top, 4)

                // progress
                HStack(spacing: 4) {
                    ForEach(lines.indices, id: \.self) { i in
                        Capsule().fill(i < index ? (lines[i].isMine ? OT.accent : OT.reader) : (i == index ? OT.labelPrimary : OT.fillQuiet)).frame(height: 4)
                    }
                }
                Text("Line \(index + 1) of \(lines.count)").font(.otFootnote).foregroundStyle(OT.labelTertiary)

                if finished {
                    RunFinishedView(lines: lines, onYourOwn: onYourOwn, neededStart: neededStart,
                                    reachedEnd: reachedEnd, heardYou: follower.isListening) {
                        index = 0; finished = false; reachedEnd = false; onYourOwn = []; neededStart = []
                        follower.reset()
                        speakIfReader(lines)
                    } onClose: { dismiss() }
                } else {
                    if index > 0 {
                        SectionLabel(text: lines[index - 1].isMine ? "You said" : "\(lines[index - 1].character.capitalized) said")
                        Text(lines[index - 1].text).font(.otCallout).foregroundStyle(OT.labelTertiary)
                    }
                    let line = lines[index]
                    if line.isMine {
                        Label(prompted ? "Your line · quiet for 3 s" : "Your line · listening", systemImage: "waveform")
                            .font(.otCaption.weight(.semibold)).foregroundStyle(OT.reader)
                        Text(prompted ? AttributedString(firstWords(line.text)) : highlighted(line.text))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(OT.labelPrimary)
                        Label("The highlight follows your voice", systemImage: "line.3.horizontal").font(.otFootnote).foregroundStyle(OT.accent)
                    } else {
                        Label(readerAudioMissing ? "\(line.character.capitalized) · no recording" : "\(line.character.capitalized) · your recording", systemImage: readerAudioMissing ? "mic.slash" : "waveform")
                            .font(.otCaption.weight(.semibold)).foregroundStyle(OT.reader)
                        Text(line.text).font(.system(size: 30, weight: .bold))
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button { stopReader(); finished = true } label: { Image(systemName: "pause.fill").frame(width: 52, height: 52).background(OT.fillField, in: Circle()) }
                        if line.isMine {
                            Button(prompted ? "Whole line" : "Line?") { prompted.toggle(); Haptics.tick() }.buttonStyle(.otPrimary)
                        } else if readerAudioMissing {
                            Button("Continue") { advance(lines) }.buttonStyle(.otPrimary)
                        } else {
                            Label("Reader audio", systemImage: "waveform")
                                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.labelSecondary)
                                .frame(maxWidth: .infinity)
                        }
                        Button { advance(lines) } label: { Image(systemName: "forward.fill").frame(width: 52, height: 52).background(OT.fillField, in: Circle()) }
                            .accessibilityLabel("Skip line")
                    }
                    .foregroundStyle(OT.labelPrimary)
                }
            }
            .padding(.horizontal, OT.gutter)
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .onAppear { speakIfReader(lines) }
            .onChange(of: follower.transcript) { _, transcript in
                guard !finished, lines[index].isMine,
                      SpokenLineMatcher.matchedWordIndices(in: lines[index].text, transcript: transcript).count >= SpokenLineMatcher.requiredMatches(for: lines[index].text) else { return }
                if !prompted { onYourOwn.insert(index) }
                advance(lines)
            }
            // "Line?" out loud — same as tapping the button, so you never have to touch the phone.
            .onChange(of: follower.lastCommand) { _, cmd in
                if cmd?.word == "line", lines[index].isMine, !prompted { prompted = true; Haptics.tick() }
            }
            .task { if await SpeechFollower.requestAccess() { follower.start() } }
            .onDisappear { follower.stop(); stopReader() }
        }
    }

    private func advance(_ lines: [ScriptLine]) {
        stopReader()
        if prompted, lines[index].isMine { neededStart.insert(index) }
        prompted = false
        follower.reset()
        if index + 1 < lines.count {
            index += 1
            speakIfReader(lines)
        } else {
            finished = true
            reachedEnd = true
            // Only a complete run updates "lines learned" — a paused one would undercount.
            store.recordRun(auditionID: auditionID, sceneIndex: sceneIndex, linesOnYourOwn: onYourOwn.count)
            Haptics.success()
        }
    }

    private func speakIfReader(_ lines: [ScriptLine]) {
        guard !lines[index].isMine else { return }
        readerAdvance?.cancel()
        readerAdvance = nil
        readerAudioMissing = false
        let readerLineIndex = lines[..<index].filter { !$0.isMine }.count
        guard readerPlayer.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerLineIndex) else {
            readerAudioMissing = true
            return
        }
        let delay = (readerPlayer.duration ?? (Double(lines[index].text.count) * 0.06)) + 0.45
        readerAdvance = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            advance(lines)
        }
    }

    private func stopReader() {
        readerAdvance?.cancel()
        readerAdvance = nil
        readerPlayer.stop()
    }

    private func firstWords(_ text: String) -> String { text.split(separator: " ").prefix(3).joined(separator: " ") + "…" }

    private func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString()
        let matched = SpokenLineMatcher.matchedWordIndices(in: text, transcript: follower.transcript)
        for (i, w) in text.split(separator: " ").enumerated() {
            var part = AttributedString(String(w) + " ")
            part.foregroundColor = matched.contains(i) ? OT.accent : OT.labelTertiary
            out += part
        }
        return out
    }

}

struct RunFinishedView: View {
    let lines: [ScriptLine]
    /// Indices into `lines`.
    let onYourOwn: Set<Int>
    let neededStart: Set<Int>
    /// False when the run was paused before the last line.
    let reachedEnd: Bool
    /// Whether speech recognition was listening; without it nothing can count as said on your own.
    let heardYou: Bool
    var onAgain: () -> Void
    var onClose: () -> Void

    private var summary: String {
        guard heardYou else { return "on your own. Voice listening was off, so lines you skipped past can't count — turn on Speech Recognition for OneTake in Settings." }
        var text = reachedEnd ? "on your own" : "on your own before you paused"
        switch neededStart.count {
        case 0: text += "."
        case 1: text += ". You needed a start on one line."
        default: text += ". You needed a start on \(neededStart.count) lines."
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "This run")
            HStack(alignment: .firstTextBaseline) {
                Text("\(onYourOwn.count)").font(.system(size: 64, weight: .bold))
                Text("of \(lines.filter(\.isMine).count)").font(.otTitle).foregroundStyle(OT.labelSecondary)
            }
            Text(summary).font(.otCallout).foregroundStyle(OT.labelSecondary)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                HStack(alignment: .top) {
                    Image(systemName: symbol(i, l)).foregroundStyle(onYourOwn.contains(i) ? OT.accent : neededStart.contains(i) ? OT.warning : OT.labelTertiary)
                    Text(l.text).font(l.isMine ? .otHeadline : .otCallout).foregroundStyle(l.isMine ? OT.labelPrimary : OT.labelTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(l.isMine ? "\(onYourOwn.contains(i) ? "Said on your own" : neededStart.contains(i) ? "Needed a start" : "Not said"): \(l.text)" : "Reader: \(l.text)")
            }
            Spacer()
            Button("Run again", action: onAgain).buttonStyle(.otPrimary)
            Button("Done", action: onClose).buttonStyle(.otSecondary)
        }
    }

    private func symbol(_ i: Int, _ line: ScriptLine) -> String {
        guard line.isMine else { return "text.bubble" }
        if onYourOwn.contains(i) { return "checkmark.square.fill" }
        if neededStart.contains(i) { return "questionmark.square" }
        return "square"
    }
}

// MARK: - 12 Reader

struct ReaderView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var player = ReaderTrackPlayer()
    @State private var playingLine: Int?
    @State private var showAudioImporter = false
    @State private var importError: String?
    @AppStorage("readerVolume") private var volume = "Quieter"

    private var readerLines: [ScriptLine] {
        guard let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return [] }
        return scenes[sceneIndex].lines.filter { !$0.isMine }
    }
    private var readerName: String { readerLines.first?.character.capitalized ?? "your reader" }

    var body: some View {
        // Reader recordings are files, so this observable counter makes the file status update
        // as soon as Record Reader saves a line.
        let readerTrackVersion = store.readerTrackVersion
        VStack(spacing: 0) {
            InContentNavHeader(title: "Who reads \(readerName)?", backLabel: "Back", onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            List {
                Section {
                    Text("Record \(readerName)’s lines in your own voice. We leave the pauses for yours, and it plays under your takes.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                }
                .listRowBackground(Color.clear)
                Section("Your reader tracks") {
                    if readerLines.isEmpty {
                        Text("No reader lines in this scene yet.").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    } else {
                        ForEach(Array(readerLines.enumerated()), id: \.offset) { index, line in
                            let recorded = readerTrackVersion >= 0 && FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: index).path)
                            HStack(spacing: 12) {
                                Button {
                                    if recorded {
                                        if playingLine == index { player.stop(); playingLine = nil }
                                        else { player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: index); playingLine = index }
                                    }
                                } label: {
                                    Image(systemName: recorded ? (playingLine == index ? "pause.fill" : "play.fill") : "mic.slash")
                                        .foregroundStyle(recorded ? OT.labelPrimary : OT.labelTertiary)
                                        .frame(width: 36, height: 36).background(OT.accentSoft, in: Circle())
                                }.buttonStyle(.plain).disabled(!recorded)
                                VStack(alignment: .leading) {
                                    Text("Line \(index + 1)").font(.otBody)
                                    Text(recorded ? "Recorded · \"\(line.text.prefix(40))\"" : "Not recorded yet").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    Picker("\(readerName)’s volume on the tape", selection: $volume) { ForEach(["Same as me", "Quieter", "Much quieter"], id: \.self) { Text($0) } }
                }
                Section {
                    Button { store.push(.recordReader(auditionID, sceneIndex: sceneIndex)) } label: { IconRow(symbol: "mic", title: "Record reader audio", detail: "Record each cue in your own voice") }
                        .buttonStyle(.plain)
                    Button { showAudioImporter = true } label: { IconRow(symbol: "waveform.badge.plus", title: "Add an audio file", detail: "Uses the next reader cue that is not recorded") }
                        .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            Button("Continue") { dismiss() }.buttonStyle(.otPrimary).padding(OT.gutter)
        }
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
            importReaderAudio(result)
        }
        .alert("Audio could not be added", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "")
        }
        .onDisappear { player.stop() }
    }

    private func importReaderAudio(_ result: Result<URL, Error>) {
        guard case .success(let sourceURL) = result else {
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError { importError = error.localizedDescription }
            return
        }
        guard let nextLine = readerLines.indices.first(where: {
            !FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: $0).path)
        }) else {
            importError = "Every reader cue already has audio. Delete or re-record one to replace it."
            return
        }
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let destination = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: nextLine)
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.removeItem(at: destination)
            try manager.copyItem(at: sourceURL, to: destination)
            store.readerTracksDidChange()
            Haptics.success()
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: - 13 Record the reader yourself

struct RecordReaderView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lineIndex = 0
    @State private var recording = false
    @State private var microphoneAllowed = false
    @State private var recordingError: String?
    @State private var recorder = ReaderLineRecorder()

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let readerLines = a.scenes[sceneIndex].lines.filter { !$0.isMine }
            let readerName = readerLines.first?.character.capitalized ?? "Reader"
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(title: "Record \(readerName)", backLabel: "Back", onBack: { dismiss() })
                    .padding(.top, 4)
                HStack(spacing: 4) { ForEach(readerLines.indices, id: \.self) { i in Capsule().fill(i < lineIndex ? OT.reader : (i == lineIndex ? OT.accent : OT.fillQuiet)).frame(height: 4) } }
                if lineIndex < readerLines.count {
                    SectionLabel(text: "\(readerName) · line \(lineIndex + 1)")
                    Text(readerLines[lineIndex].text).font(.system(size: 26, weight: .bold))
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).otCard(radius: 20)
                    if let recordingError {
                        Text(recordingError).font(.otFootnote).foregroundStyle(OT.warning)
                    }
                    Spacer()
                    Text(recording ? "Tap stop when you've said the line" : "Tap record when you're ready").font(.otFootnote).foregroundStyle(OT.labelTertiary).frame(maxWidth: .infinity)
                    RecordButton(isRecording: recording) {
                        if recording {
                            recording = false
                            if recorder.stop() { store.readerTracksDidChange(); lineIndex += 1; Haptics.success() }
                            else { recordingError = "No audio was saved. Try recording this line again."; Haptics.warning() }
                        } else if !microphoneAllowed {
                            recordingError = "Allow microphone access in Settings to record reader lines."
                        } else if recorder.start(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex) {
                            recordingError = nil
                            recording = true
                        } else {
                            recordingError = "Recording couldn't start. Check microphone access and try again."
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("All \(readerLines.count) lines done").font(.otLargeTitle)
                    Spacer()
                    Button("Save track") { dismiss() }.buttonStyle(.otPrimary)
                }
            }
            .padding(OT.gutter)
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .task {
                microphoneAllowed = await AVAudioApplication.requestRecordPermission()
                if let audition = store.audition(auditionID), audition.scenes.indices.contains(sceneIndex) {
                    let scene = audition.scenes[sceneIndex]
                    let readerLines = scene.lines.filter { !$0.isMine }
                    lineIndex = readerLines.indices.first(where: {
                        !FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: $0).path)
                    }) ?? readerLines.count
                }
            }
            .onDisappear { if recording { _ = recorder.stop() } }
        }
    }
}
