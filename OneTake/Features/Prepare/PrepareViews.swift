import SwiftUI
import AVFoundation

// MARK: - 11 Prepare

struct PrepareView: View {
    enum Mode: String, CaseIterable, Identifiable { case full = "Full lines", firstLetters = "First letters", hide = "Hide mine"; var id: String { rawValue } }

    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .full
    @State private var peeked: ScriptLine.ID?
    @State private var showPrompterSettings = false

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let scene = a.scenes[sceneIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(scene.title).font(.otLargeTitle)
                    HStack {
                        Text("\(learned(scene)) of \(scene.lines.filter(\.isMine).count) lines learned").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        Spacer()
                        Button { store.push(.reader(a.id)) } label: {
                            let readerName = scene.lines.first(where: { !$0.isMine })?.character.capitalized ?? "Reader"
                            Label("\(readerName) · your recording", systemImage: "circle.fill").labelStyle(DotLabelStyle(color: OT.reader))
                                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.reader)
                        }
                    }
                    ForEach(scene.lines) { line in lineView(line) }
                }
                .padding(.horizontal, OT.gutter)
                .padding(.bottom, 120)
            }
            .otCanvas()
            .navigationTitle("Scene \(scene.number) of \(a.scenes.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPrompterSettings = true } label: { Image(systemName: "textformat.size") }.accessibilityLabel("Text size")
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar(a) }
            .sheet(isPresented: $showPrompterSettings) { PrompterSettingsSheet().presentationDetents([.medium]) }
        }
    }

    /// Real progress from the matching Practice piece, if one exists for this scene — not a constant.
    private func learned(_ s: ScriptScene) -> Int {
        store.practice.first(where: { $0.scene?.id == s.id })?.linesLearned ?? 0
    }

    @ViewBuilder private func lineView(_ line: ScriptLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.isMine ? "\(line.character) · YOU" : line.character)
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(line.isMine ? OT.accent : OT.reader)
            HStack(alignment: .top, spacing: 10) {
                if line.isMine { Capsule().fill(OT.accent).frame(width: 3) }
                Text(display(line))
                    .font(line.isMine ? .system(size: 19, weight: .semibold) : .otBody)
                    .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
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
            Menu {
                Picker("Lines", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
            } label: {
                Label(mode.rawValue, systemImage: "chevron.up.chevron.down").labelStyle(TrailingIconLabelStyle())
                    .font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                    .padding(.horizontal, 14).frame(height: 44).background(OT.fillField, in: Capsule())
            }
            Button { store.push(.runLines(a.id, sceneIndex: sceneIndex)) } label: {
                Label("Run lines", systemImage: "play.fill").labelStyle(TrailingIconLabelStyle())
                    .font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                    .padding(.horizontal, 14).frame(height: 44).background(OT.fillField, in: Capsule())
            }
            Button { store.push(.shootSetup(a.id)) } label: {
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
    @AppStorage("prompter.mirror") private var mirror = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teleprompter").font(.otHeadline)
            Text("Because every time I tried")
                .font(.system(size: [20, 26, 34][min(max(size, 0), 2)], weight: .semibold))
                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 72)
                .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .scaleEffect(x: mirror ? -1 : 1, y: 1)
            Text("Sized to read from your mark, about 6 ft away").font(.otFootnote).foregroundStyle(OT.labelTertiary).frame(maxWidth: .infinity)
            SectionLabel(text: "Text size")
            Picker("Size", selection: $size) { Text("Regular").tag(0); Text("Large").tag(1); Text("Big print").tag(2) }.pickerStyle(.segmented)
            SectionLabel(text: "Scroll")
            Picker("Scroll", selection: $followVoice) { Text("Follows my voice").tag(true); Text("Timed").tag(false) }.pickerStyle(.segmented)
            Toggle(isOn: $mirror) { VStack(alignment: .leading) { Text("Mirror text"); Text("For a beam-splitter prompter").font(.otFootnote).foregroundStyle(OT.labelTertiary) } }
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
    @State private var follower = SpeechFollower()
    /// Plays the reader lines you recorded yourself (Record Maya). No synthetic or second-device voices.
    @State private var readerPlayer = ReaderTrackPlayer()
    /// The pending auto-advance after a reader line. Kept so a manual skip, pause or leaving the
    /// screen cancels it instead of letting it fire later and skip an extra line.
    @State private var readerAdvance: Task<Void, Never>?

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex), !a.scenes[sceneIndex].lines.isEmpty {
            let lines = a.scenes[sceneIndex].lines
            VStack(alignment: .leading, spacing: 18) {
                // progress
                HStack(spacing: 4) {
                    ForEach(lines.indices, id: \.self) { i in
                        Capsule().fill(i < index ? (lines[i].isMine ? OT.accent : OT.reader) : (i == index ? OT.labelPrimary : OT.fillQuiet)).frame(height: 4)
                    }
                }
                Text("Line \(index + 1) of \(lines.count)").font(.otFootnote).foregroundStyle(OT.labelTertiary)

                if finished {
                    RunFinishedView(lines: lines) { index = 0; finished = false; speakIfReader(lines) } onClose: { dismiss() }
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
                        Label("\(line.character.capitalized) · your recording", systemImage: "waveform")
                            .font(.otCaption.weight(.semibold)).foregroundStyle(OT.reader)
                        Text(line.text).font(.system(size: 30, weight: .bold))
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button { stopReader(); finished = true } label: { Image(systemName: "pause.fill").frame(width: 52, height: 52).background(OT.fillField, in: Circle()) }
                        Button(prompted ? "Whole line" : "Line?") { prompted.toggle(); Haptics.tick() }.buttonStyle(.otPrimary)
                        Button { advance(lines) } label: { Image(systemName: "forward.fill").frame(width: 52, height: 52).background(OT.fillField, in: Circle()) }
                    }
                    .foregroundStyle(OT.labelPrimary)
                }
            }
            .padding(.horizontal, OT.gutter)
            .otCanvas()
            .navigationTitle("Run lines").navigationBarTitleDisplayMode(.inline)
            .onAppear { speakIfReader(lines) }
            .onChange(of: follower.spokenWordCount) { _, count in
                if lines[index].isMine, count >= lines[index].text.split(separator: " ").count { advance(lines) }
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
        prompted = false
        follower.reset()
        if index + 1 < lines.count { index += 1; speakIfReader(lines) } else { finished = true; Haptics.success() }
    }

    private func speakIfReader(_ lines: [ScriptLine]) {
        guard !lines[index].isMine else { return }
        let readerLineIndex = lines[..<index].filter { !$0.isMine }.count
        readerPlayer.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerLineIndex)
        readerAdvance?.cancel()
        let delay = Double(lines[index].text.count) * 0.06 + 0.8
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
        for (i, w) in text.split(separator: " ").enumerated() {
            var part = AttributedString(String(w) + " ")
            part.foregroundColor = i < follower.spokenWordCount ? OT.accent : OT.labelTertiary
            out += part
        }
        return out
    }
}

struct RunFinishedView: View {
    let lines: [ScriptLine]
    var onAgain: () -> Void
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "This run")
            HStack(alignment: .firstTextBaseline) {
                Text("2").font(.system(size: 64, weight: .bold))
                Text("of \(lines.filter(\.isMine).count)").font(.otTitle).foregroundStyle(OT.labelSecondary)
            }
            Text("on your own. You needed a start on one line.").font(.otCallout).foregroundStyle(OT.labelSecondary)
            ForEach(lines) { l in
                HStack(alignment: .top) {
                    Image(systemName: l.isMine ? "checkmark.square.fill" : "m.square").foregroundStyle(l.isMine ? OT.accent : OT.labelTertiary)
                    Text(l.text).font(l.isMine ? .otHeadline : .otCallout).foregroundStyle(l.isMine ? OT.labelPrimary : OT.labelTertiary)
                }
            }
            Spacer()
            Button("Run again", action: onAgain).buttonStyle(.otPrimary)
            Button("Done", action: onClose).buttonStyle(.otSecondary)
        }
    }
}

// MARK: - 12 Reader

struct ReaderView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var player = ReaderTrackPlayer()
    @State private var playingLine: Int?
    @AppStorage("readerVolume") private var volume = "Quieter"

    private var readerLines: [ScriptLine] {
        store.audition(auditionID)?.scenes.first?.lines.filter { !$0.isMine } ?? []
    }
    private var readerName: String { readerLines.first?.character.capitalized ?? "your reader" }

    var body: some View {
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
                        let recorded = FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: index).path)
                        HStack(spacing: 12) {
                            Button {
                                if recorded {
                                    if playingLine == index { player.stop(); playingLine = nil }
                                    else { player.play(auditionID: auditionID, sceneIndex: 0, lineIndex: index); playingLine = index }
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
                Button { store.push(.recordReader(auditionID)) } label: { IconRow(symbol: "mic", title: "Record a new track", detail: "Your voice · we leave pauses for your lines") }
                    .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Who reads \(readerName)?")
        .safeAreaInset(edge: .bottom) {
            Button("Continue") { dismiss() }.buttonStyle(.otPrimary).padding(OT.gutter)
        }
        .onDisappear { player.stop() }
    }
}

// MARK: - 13 Record the reader yourself

struct RecordReaderView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lineIndex = 0
    @State private var recording = false
    @State private var recorder = ReaderLineRecorder()

    var body: some View {
        if let a = store.audition(auditionID), let firstScene = a.scenes.first {
            let readerLines = firstScene.lines.filter { !$0.isMine }
            let readerName = readerLines.first?.character.capitalized ?? "Reader"
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 4) { ForEach(readerLines.indices, id: \.self) { i in Capsule().fill(i < lineIndex ? OT.reader : (i == lineIndex ? OT.accent : OT.fillQuiet)).frame(height: 4) } }
                if lineIndex < readerLines.count {
                    SectionLabel(text: "\(readerName) · line \(lineIndex + 1)")
                    Text(readerLines[lineIndex].text).font(.system(size: 26, weight: .bold))
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).otCard(radius: 20)
                    Text("A little softer than you'd act it. We add the pauses.").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    Spacer()
                    Text(recording ? "Tap stop when you've said the line" : "Tap record when you're ready").font(.otFootnote).foregroundStyle(OT.labelTertiary).frame(maxWidth: .infinity)
                    RecordButton(isRecording: recording) {
                        if recording { recorder.stop(); lineIndex += 1; Haptics.success() }
                        else { recorder.start(auditionID: auditionID, sceneIndex: 0, lineIndex: lineIndex) }
                        recording.toggle()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("All \(readerLines.count) lines done").font(.otLargeTitle)
                    Text("Pauses come from how long your lines took in Run lines.").font(.otCallout).foregroundStyle(OT.labelSecondary)
                    Spacer()
                    Button("Save track") { dismiss() }.buttonStyle(.otPrimary)
                }
            }
            .padding(OT.gutter)
            .otCanvas()
            .navigationTitle("Record \(readerName)").navigationBarTitleDisplayMode(.inline)
        }
    }
}
