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
        let _ = store.readerTrackVersion
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
                        HStack(spacing: 8) {
                            Button { store.push(.sceneAudioFlow(a.id, sceneIndex: sceneIndex)) } label: {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(OT.accent)
                                    .padding(6)
                                    .background(OT.accentSoft, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Scene audio flow")

                            Button { store.push(.reader(a.id, sceneIndex: sceneIndex)) } label: {
                                let readerLines = scene.lines.filter { !$0.isMine }
                                let readerName = readerLines.first?.character.capitalized ?? "Reader"
                                let specificReaderLines = readerLines.filter { $0.character.caseInsensitiveCompare(readerName) == .orderedSame }
                                let recorded = specificReaderLines.indices.filter {
                                    ReaderTrackPlayer.hasRecording(auditionID: a.id, sceneIndex: sceneIndex, line: $0)
                                }.count
                                Label("\(readerName) · \(recorded) of \(specificReaderLines.count) recorded", systemImage: recorded == specificReaderLines.count && !specificReaderLines.isEmpty ? "waveform" : "mic")
                                    .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.reader)
                            }
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
                InContentNavHeader(title: "Run lines", backLabel: "Back", onBack: { store.pop() })
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
                    } onClose: { store.pop() }
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
    @State private var expandedLine: Int?
    @State private var showAudioImporter = false
    @State private var importError: String?
    @AppStorage("readerVolume") private var volume = "Quieter"
    @State private var selectedReader: String? = nil

    private var myRole: String {
        store.audition(auditionID)?.role ?? ""
    }

    private var availableReaders: [String] {
        guard let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return [] }
        let unowned = scenes[sceneIndex].lines.filter { !$0.isMine }
        var seen = Set<String>()
        var list: [String] = []
        for line in unowned {
            let name = line.character.capitalized
            if !seen.contains(name.lowercased()) {
                seen.insert(name.lowercased())
                list.append(name)
            }
        }
        return list
    }

    private var effectiveReaderName: String {
        if let selected = selectedReader, availableReaders.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            return selected.capitalized
        }
        return availableReaders.first?.capitalized ?? "your reader"
    }

    private var readerLines: [ScriptLine] {
        guard let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return [] }
        let allLines = scenes[sceneIndex].lines
        let unowned = allLines.filter { !$0.isMine }
        let target = effectiveReaderName
        return unowned.filter { $0.character.caseInsensitiveCompare(target) == .orderedSame }
    }

    var body: some View {
        // Reader recordings are files, so this observable counter makes the file status update
        // as soon as Record Reader saves a line.
        let readerTrackVersion = store.readerTrackVersion
        VStack(spacing: 0) {
            InContentNavHeader(title: "Who reads \(effectiveReaderName)?", backLabel: "Back", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            List {
                Section {
                    Text("Record \(effectiveReaderName)’s lines in your own voice. We leave the pauses for yours, and it plays under your takes.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                }
                .listRowBackground(Color.clear)

                if availableReaders.count > 1 {
                    Section {
                        HStack(spacing: 8) {
                            Text("Reader:").font(.otCaption).foregroundStyle(OT.labelTertiary)
                            ForEach(availableReaders, id: \.self) { char in
                                let isCurrent = char.caseInsensitiveCompare(effectiveReaderName) == .orderedSame
                                Button {
                                    selectedReader = char
                                    player.stop()
                                    playingLine = nil
                                    Haptics.tick()
                                } label: {
                                    Text(char)
                                        .font(.otCaption.weight(isCurrent ? .bold : .medium))
                                        .foregroundStyle(isCurrent ? OT.bgCanvas : OT.reader)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isCurrent ? OT.reader : OT.fillField, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // Scene Audio Flow Shortcut
                Section {
                    Button {
                        player.stop()
                        playingLine = nil
                        store.push(.sceneAudioFlow(auditionID, sceneIndex: sceneIndex))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(OT.accent)
                                .frame(width: 40, height: 40)
                                .background(OT.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scene Audio Flow & Walkthrough")
                                    .font(.otSubhead.weight(.semibold))
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Play from any line in the scene · Scrub between seconds")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(OT.labelTertiary)
                        }
                        .padding(14)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)

                Section("\(effectiveReaderName)’s reader tracks") {
                    if readerLines.isEmpty {
                        Text("No reader lines for \(effectiveReaderName) in this scene.").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    } else {
                        ForEach(Array(readerLines.enumerated()), id: \.offset) { index, line in
                            let recorded = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: index)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    Button {
                                        if recorded {
                                            if playingLine == index && player.isPlaying {
                                                player.pause()
                                            } else if playingLine == index && !player.isPlaying {
                                                player.resume()
                                            } else {
                                                player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: index)
                                                playingLine = index
                                                expandedLine = index
                                            }
                                        }
                                    } label: {
                                        Image(systemName: recorded ? (playingLine == index && player.isPlaying ? "pause.fill" : "play.fill") : "mic.slash")
                                            .foregroundStyle(recorded ? OT.labelPrimary : OT.labelTertiary)
                                            .frame(width: 36, height: 36).background(OT.accentSoft, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!recorded)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Line \(index + 1)").font(.otBody)
                                        Text(recorded ? "Recorded · \"\(line.text.prefix(40))\"" : "Not recorded yet").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                    Spacer()

                                    if recorded {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                if expandedLine == index {
                                                    expandedLine = nil
                                                } else {
                                                    expandedLine = index
                                                }
                                            }
                                        } label: {
                                            Image(systemName: expandedLine == index ? "chevron.up.circle.fill" : "slider.horizontal.3")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(expandedLine == index ? OT.accent : OT.labelTertiary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(expandedLine == index ? "Hide audio scrubber" : "Scrub audio")
                                    }

                                    Button {
                                        player.stop()
                                        playingLine = nil
                                        store.push(.recordReader(auditionID, sceneIndex: sceneIndex, initialLineIndex: index, readerCharacter: effectiveReaderName))
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: recorded ? "arrow.clockwise" : "mic.fill")
                                            Text(recorded ? "Retake" : "Record")
                                        }
                                        .font(.otCaption.weight(.semibold))
                                        .foregroundStyle(recorded ? OT.accent : OT.reader)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(OT.accentSoft, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if recorded {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if expandedLine == index {
                                                expandedLine = nil
                                            } else {
                                                expandedLine = index
                                            }
                                        }
                                    }
                                }

                                if recorded && (expandedLine == index || playingLine == index) {
                                    ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: index, compact: false)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                    Picker("\(effectiveReaderName)’s volume on the tape", selection: $volume) { ForEach(["Same as me", "Quieter", "Much quieter"], id: \.self) { Text($0) } }
                }
                Section {
                    Button { store.push(.recordReader(auditionID, sceneIndex: sceneIndex, readerCharacter: effectiveReaderName)) } label: { IconRow(symbol: "mic", title: "Record reader audio", detail: "Record each cue in your own voice") }
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
            Button("Continue") {
                if store.auditionsPath.contains(.noticeReview) {
                    store.auditionsPath = [.auditionDetail(auditionID)]
                    store.continueAfterAdd = auditionID
                    store.auditionDraft = .blank
                } else {
                    store.pop()
                }
            }
            .buttonStyle(.otPrimary)
            .padding(OT.gutter)
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
            !ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: $0)
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
    var initialLineIndex: Int? = nil
    var readerCharacter: String? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lineIndex = 0
    @State private var recording = false
    @State private var isProcessing = false
    @State private var microphoneAllowed = false
    @State private var recordingError: String?
    @State private var successBanner: String?
    @State private var recorder = ReaderLineRecorder()
    @State private var player = ReaderTrackPlayer()
    @State private var isPreviewPlaying = false
    @State private var playingReviewIndex: Int?
    @State private var expandedReviewIndex: Int?
    @State private var selectedReader: String? = nil

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let allUnowned = a.scenes[sceneIndex].lines.filter { !$0.isMine }
            let availableReaders: [String] = {
                var seen = Set<String>()
                var list: [String] = []
                for line in allUnowned {
                    let name = line.character.capitalized
                    if !seen.contains(name.lowercased()) {
                        seen.insert(name.lowercased())
                        list.append(name)
                    }
                }
                return list
            }()
            let readerName: String = {
                if let sel = selectedReader, availableReaders.contains(where: { $0.caseInsensitiveCompare(sel) == .orderedSame }) {
                    return sel.capitalized
                }
                if let rc = readerCharacter, availableReaders.contains(where: { $0.caseInsensitiveCompare(rc) == .orderedSame }) {
                    return rc.capitalized
                }
                return allUnowned.first?.character.capitalized ?? "Reader"
            }()
            let readerLines = allUnowned.filter { $0.character.caseInsensitiveCompare(readerName) == .orderedSame }
            let readerTrackVersion = store.readerTrackVersion

            VStack(alignment: .leading, spacing: 14) {
                InContentNavHeader(title: "Record \(readerName)", backLabel: "Back", onBack: {
                    player.stop()
                    recorder.cancel()
                    store.pop()
                }) {
                    Button {
                        player.stop()
                        recorder.cancel()
                        store.push(.sceneAudioFlow(auditionID, sceneIndex: sceneIndex))
                    } label: {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OT.labelPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scene audio flow")
                }
                .padding(.top, 4)

                if availableReaders.count > 1 {
                    HStack(spacing: 8) {
                        Text("Reader:").font(.otCaption).foregroundStyle(OT.labelTertiary)
                        ForEach(availableReaders, id: \.self) { char in
                            let isCurrent = char.caseInsensitiveCompare(readerName) == .orderedSame
                            Button {
                                guard !recording && !isProcessing else { return }
                                player.stop()
                                isPreviewPlaying = false
                                selectedReader = char
                                lineIndex = 0
                                recordingError = nil
                                Haptics.tick()
                            } label: {
                                Text(char)
                                    .font(.otCaption.weight(isCurrent ? .bold : .medium))
                                    .foregroundStyle(isCurrent ? OT.bgCanvas : OT.reader)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isCurrent ? OT.reader : OT.fillField, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Interactive Progress & Line Selector
                HStack(spacing: 4) {
                    ForEach(readerLines.indices, id: \.self) { i in
                        let isRec = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: i)
                        Button {
                            guard !recording && !isProcessing else { return }
                            player.stop()
                            isPreviewPlaying = false
                            playingReviewIndex = nil
                            lineIndex = i
                            recordingError = nil
                            Haptics.tick()
                        } label: {
                            Capsule()
                                .fill(i == lineIndex ? OT.accent : (isRec ? OT.reader : OT.fillQuiet))
                                .frame(height: i == lineIndex ? 6 : 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Line \(i + 1)")
                    }
                }

                // Prev / Next Line Stepper
                HStack {
                    Button {
                        guard lineIndex > 0, !recording, !isProcessing else { return }
                        player.stop()
                        isPreviewPlaying = false
                        playingReviewIndex = nil
                        lineIndex -= 1
                        recordingError = nil
                        Haptics.tick()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Prev line")
                        }
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(lineIndex > 0 ? OT.accent : OT.labelTertiary.opacity(0.4))
                    }
                    .disabled(lineIndex <= 0 || recording || isProcessing)

                    Spacer()

                    if lineIndex < readerLines.count {
                        Text("Line \(lineIndex + 1) of \(readerLines.count)")
                            .font(.otFootnote.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                    } else {
                        Text("Reviewing all \(readerLines.count) lines")
                            .font(.otFootnote.weight(.medium))
                            .foregroundStyle(OT.reader)
                    }

                    Spacer()

                    Button {
                        guard !recording, !isProcessing else { return }
                        player.stop()
                        isPreviewPlaying = false
                        playingReviewIndex = nil
                        if lineIndex < readerLines.count {
                            lineIndex += 1
                        }
                        recordingError = nil
                        Haptics.tick()
                    } label: {
                        HStack(spacing: 4) {
                            Text(lineIndex < readerLines.count - 1 ? "Next line" : (lineIndex == readerLines.count - 1 ? "Review" : ""))
                            if lineIndex < readerLines.count {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(lineIndex < readerLines.count ? OT.accent : Color.clear)
                    }
                    .disabled(lineIndex >= readerLines.count || recording || isProcessing)
                }

                if lineIndex < readerLines.count {
                    let line = readerLines[lineIndex]
                    let isCurrentRecorded = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)

                    HStack {
                        SectionLabel(text: "\(readerName) · line \(lineIndex + 1)")
                        Spacer()
                        if isCurrentRecorded {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Recorded")
                            }
                            .font(.otCaption.weight(.semibold))
                            .foregroundStyle(OT.reader)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "mic")
                                Text("Needs audio")
                            }
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelTertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(line.text)
                            .font(.system(size: 26, weight: .bold))
                            .lineSpacing(4)
                            .foregroundStyle(OT.labelPrimary)

                        if isCurrentRecorded {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Play & Scrub Recorded Audio")
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(OT.labelSecondary)

                                ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, compact: false)

                                Text("Tap Record below to retake this line")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelTertiary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .otCard(radius: 20)

                    if let recordingError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(OT.warning)
                            Text(recordingError)
                                .font(.otFootnote)
                                .foregroundStyle(OT.warning)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OT.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if let successBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OT.reader)
                            Text(successBanner)
                                .font(.otFootnote.weight(.medium))
                                .foregroundStyle(OT.reader)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OT.reader.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Spacer()

                    if recording {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text("Listening... Say the line clearly")
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.labelPrimary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(OT.fillField)
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(OT.accent)
                                        .frame(width: max(8, geo.size.width * CGFloat(recorder.liveAudioLevel)), height: 6)
                                        .animation(.easeOut(duration: 0.08), value: recorder.liveAudioLevel)
                                }
                            }
                            .frame(height: 6)
                            .padding(.horizontal, 40)
                            Text("Tap stop when finished")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelTertiary)
                        }
                    } else if isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Verifying speech...")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(isCurrentRecorded ? "Tap record to retake this line" : "Tap record when you're ready")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                            .frame(maxWidth: .infinity)
                    }

                    RecordButton(isRecording: recording) {
                        handleRecordTap(readerLines: readerLines, isCurrentRecorded: isCurrentRecorded)
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isProcessing)
                } else {
                    // All lines completed or Review Mode
                    VStack(alignment: .leading, spacing: 12) {
                        Text("All \(readerLines.count) lines done")
                            .font(.otLargeTitle)
                        Text("Review your recorded cues below, or retake any line if needed.")
                            .font(.otCallout)
                            .foregroundStyle(OT.labelSecondary)

                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(Array(readerLines.enumerated()), id: \.offset) { idx, line in
                                    let isRec = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: idx)
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 12) {
                                            Button {
                                                if isRec {
                                                    if player.isPlaying && playingReviewIndex == idx {
                                                        player.pause()
                                                    } else if !player.isPlaying && playingReviewIndex == idx {
                                                        player.resume()
                                                    } else {
                                                        player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: idx)
                                                        playingReviewIndex = idx
                                                        expandedReviewIndex = idx
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: isRec ? (player.isPlaying && playingReviewIndex == idx ? "pause.fill" : "play.fill") : "mic.slash")
                                                    .foregroundStyle(isRec ? OT.labelPrimary : OT.labelTertiary)
                                                    .frame(width: 36, height: 36)
                                                    .background(OT.accentSoft, in: Circle())
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!isRec)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Line \(idx + 1)")
                                                    .font(.otHeadline)
                                                Text(line.text)
                                                    .font(.otFootnote)
                                                    .foregroundStyle(OT.labelSecondary)
                                                    .lineLimit(2)
                                            }

                                            Spacer()

                                            if isRec {
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        if expandedReviewIndex == idx {
                                                            expandedReviewIndex = nil
                                                        } else {
                                                            expandedReviewIndex = idx
                                                        }
                                                    }
                                                } label: {
                                                    Image(systemName: expandedReviewIndex == idx ? "chevron.up.circle.fill" : "slider.horizontal.3")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundStyle(expandedReviewIndex == idx ? OT.accent : OT.labelTertiary)
                                                        .frame(width: 32, height: 32)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel(expandedReviewIndex == idx ? "Hide audio scrubber" : "Scrub audio")
                                            }

                                            Button {
                                                player.stop()
                                                isPreviewPlaying = false
                                                playingReviewIndex = nil
                                                lineIndex = idx
                                                recordingError = nil
                                                successBanner = nil
                                                Haptics.tick()
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: isRec ? "arrow.clockwise" : "mic.fill")
                                                    Text(isRec ? "Retake" : "Record")
                                                }
                                                .font(.otCaption.weight(.semibold))
                                                .foregroundStyle(isRec ? OT.accent : OT.reader)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(OT.accentSoft, in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if isRec {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    if expandedReviewIndex == idx {
                                                        expandedReviewIndex = nil
                                                    } else {
                                                        expandedReviewIndex = idx
                                                    }
                                                }
                                            }
                                        }

                                        if isRec && (expandedReviewIndex == idx || playingReviewIndex == idx) {
                                            ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: idx, compact: false)
                                                .padding(.top, 4)
                                        }
                                    }
                                    .padding(12)
                                    .otCard(radius: 14)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Spacer()

                        Button {
                            player.stop()
                            recorder.cancel()
                            store.push(.sceneAudioFlow(auditionID, sceneIndex: sceneIndex))
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                Text("Rehearse in Scene Audio Flow")
                            }
                            .font(.otSubhead.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Button("Save and finish") {
                            player.stop()
                            recorder.cancel()
                            store.pop()
                        }
                        .buttonStyle(.otPrimary)
                        .buttonStyle(.otPrimary)
                    }
                }
            }
            .padding(OT.gutter)
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .task {
                if #available(iOS 17.0, *) {
                    microphoneAllowed = await AVAudioApplication.requestRecordPermission()
                } else {
                    microphoneAllowed = await withCheckedContinuation { continuation in
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            continuation.resume(returning: granted)
                        }
                    }
                }
                if let audition = store.audition(auditionID), audition.scenes.indices.contains(sceneIndex) {
                    let scene = audition.scenes[sceneIndex]
                    let allUnowned = scene.lines.filter { !$0.isMine }
                    let available: [String] = {
                        var seen = Set<String>()
                        var list: [String] = []
                        for line in allUnowned {
                            let name = line.character.capitalized
                            if !seen.contains(name.lowercased()) {
                                seen.insert(name.lowercased())
                                list.append(name)
                            }
                        }
                        return list
                    }()
                    if let readerCharacter, available.contains(where: { $0.caseInsensitiveCompare(readerCharacter) == .orderedSame }) {
                        selectedReader = readerCharacter
                    }
                    let rName = selectedReader ?? readerCharacter ?? available.first ?? "Reader"
                    let rLines = allUnowned.filter { $0.character.caseInsensitiveCompare(rName) == .orderedSame }

                    if let initialLineIndex, rLines.indices.contains(initialLineIndex) {
                        lineIndex = initialLineIndex
                    } else {
                        // Open on the first unrecorded line; if all recorded, start on 0 so the user can review/retake
                        lineIndex = rLines.indices.first(where: {
                            !ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: $0)
                        }) ?? 0
                    }
                }
            }
            .onDisappear {
                player.stop()
                recorder.cancel()
            }
        }
    }

    private func handleRecordTap(readerLines: [ScriptLine], isCurrentRecorded: Bool) {
        if recording {
            recording = false
            isProcessing = true
            recordingError = nil
            let currentLineText = readerLines[lineIndex].text
            let recordedIndex = lineIndex

            Task {
                let result = await recorder.stop(expectedText: currentLineText)
                isProcessing = false
                switch result {
                case .success:
                    store.readerTracksDidChange()
                    Haptics.success()
                    successBanner = isCurrentRecorded ? "Retake saved for Line \(recordedIndex + 1)" : "Line \(recordedIndex + 1) recorded"
                    recordingError = nil

                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        if successBanner != nil { successBanner = nil }
                    }

                    if recordedIndex + 1 < readerLines.count {
                        lineIndex = recordedIndex + 1
                    } else {
                        lineIndex = readerLines.count // Go to Review mode
                    }

                case .tooShort(let duration):
                    Haptics.warning()
                    recordingError = "Recording was too short (\(String(format: "%.1f", duration))s). Please speak the line clearly before stopping."

                case .noSpeechDetected:
                    Haptics.warning()
                    recordingError = "No speech detected. Please speak the line clearly before tapping stop."

                case .recordingFailed(let message):
                    Haptics.warning()
                    recordingError = message
                }
            }
        } else if !microphoneAllowed {
            recordingError = "Allow microphone access in Settings to record reader lines."
            Haptics.warning()
        } else {
            player.stop()
            isPreviewPlaying = false
            recordingError = nil
            successBanner = nil
            if recorder.start(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex) {
                recording = true
            } else {
                recordingError = "Recording couldn't start. Check microphone access and try again."
                Haptics.warning()
            }
        }
    }
}

// MARK: - 14 Reader Audio Scrubber

/// Interactive audio scrubbing and playback component.
/// Allows actors to scrub to any timestamp (0.0s to duration), tap to seek, jump -5s/+5s, and play/pause/resume.
struct ReaderAudioScrubberView: View {
    @Bindable var player: ReaderTrackPlayer
    let auditionID: Audition.ID
    let sceneIndex: Int
    let lineIndex: Int
    var compact: Bool = false
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var isDragging: Bool = false
    @State private var dragPosition: Double = 0

    private var isThisLineActive: Bool {
        player.currentAuditionID == auditionID &&
        player.currentSceneIndex == sceneIndex &&
        player.currentLineIndex == lineIndex
    }

    private var isPlaying: Bool {
        isThisLineActive && player.isPlaying
    }

    private var duration: TimeInterval {
        if isThisLineActive && player.duration > 0 {
            return player.duration
        }
        return ReaderTrackPlayer.duration(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
    }

    private var currentTime: TimeInterval {
        if isDragging {
            return dragPosition
        }
        if isThisLineActive {
            return player.currentTime
        }
        return 0
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            expandedBody
        }
    }

    private var compactBody: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Play / Pause
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(OT.labelPrimary)
                        .frame(width: 28, height: 28)
                        .background(OT.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)

                // Scrubber Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(OT.fillField)
                            .frame(height: 6)

                        Capsule()
                            .fill(OT.reader)
                            .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 6)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .offset(x: max(0, min(geo.size.width * CGFloat(progress) - 7, geo.size.width - 14)))
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                                dragPosition = Double(fraction) * duration
                            }
                            .onEnded { value in
                                let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                                let targetTime = Double(fraction) * duration
                                isDragging = false
                                seek(to: targetTime)
                            }
                    )
                }
                .frame(height: 14)

                // Time label
                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(OT.labelTertiary)
            }
        }
    }

    private var expandedBody: some View {
        VStack(spacing: 12) {
            // Interactive Scrubber Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(OT.fillField)
                        .frame(height: 8)

                    // Progress track
                    Capsule()
                        .fill(LinearGradient(colors: [OT.reader, OT.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * CGFloat(progress)), height: 8)

                    // Scrubber thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .offset(x: max(0, min(geo.size.width * CGFloat(progress) - 10, geo.size.width - 20)))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                            dragPosition = Double(fraction) * duration
                        }
                        .onEnded { value in
                            let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                            let targetTime = Double(fraction) * duration
                            isDragging = false
                            seek(to: targetTime)
                        }
                )
            }
            .frame(height: 20)

            // Timestamps: Current time & remaining duration
            HStack {
                Text(formatDetailedTime(currentTime))
                    .font(.otCaption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OT.labelPrimary)

                Spacer()

                Text("-\(formatDetailedTime(max(0, duration - currentTime)))")
                    .font(.otCaption.weight(.medium).monospacedDigit())
                    .foregroundStyle(OT.labelTertiary)
            }

            // Scrub Controls Row: -5s, Play/Pause, +5s, Replay
            HStack(spacing: 24) {
                // Rewind 5s
                Button {
                    seekRelative(-5)
                } label: {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OT.labelSecondary)
                        .frame(width: 44, height: 44)
                        .background(OT.fillField, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rewind 5 seconds")

                // Main Play / Pause Button
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 52, height: 52)
                        .background(OT.accent, in: Circle())
                        .shadow(color: OT.accent.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                // Skip +5s
                Button {
                    seekRelative(5)
                } label: {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OT.labelSecondary)
                        .frame(width: 44, height: 44)
                        .background(OT.fillField, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip forward 5 seconds")

                // Replay from start
                Button {
                    seek(to: 0)
                    if !isPlaying {
                        player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: 0)
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OT.labelSecondary)
                        .frame(width: 44, height: 44)
                        .background(OT.fillField, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay from beginning")
            }
        }
        .padding(14)
        .background(OT.fillField.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func togglePlay() {
        if isPlaying {
            player.pause()
        } else if isThisLineActive && player.currentTime > 0 && player.currentTime < duration {
            player.resume()
        } else {
            player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: isThisLineActive ? player.currentTime : 0)
        }
        Haptics.tick()
    }

    private func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        if isThisLineActive {
            player.seek(to: clamped)
        } else {
            player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: clamped)
        }
        onSeek?(clamped)
        Haptics.tick()
    }

    private func seekRelative(_ delta: TimeInterval) {
        if isThisLineActive {
            player.seekRelative(delta)
        } else {
            let target = max(0, min(delta, duration))
            player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: target)
        }
        Haptics.tick()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatDetailedTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        let tenths = Int((clamped.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, tenths)
    }
}

// MARK: - 15 Scene Audio Flow & Walkthrough

/// Dedicated scene audio walkthrough allowing actors to see the full scene dialogue flow,
/// tap ANY line to jump playback immediately to that point, scrub between seconds,
/// and rehearse with continuous autoplay across cues.
struct SceneAudioFlowView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var player = ReaderTrackPlayer()
    @State private var activeLineIndex: Int? = nil
    @State private var isContinuousFlow: Bool = true
    @State private var waitingForActor: Bool = false
    @State private var actorCountdown: Int = 3
    @State private var countdownTimer: Timer? = nil

    private var audition: Audition? {
        store.audition(auditionID)
    }

    private var scene: ScriptScene? {
        guard let a = audition, a.scenes.indices.contains(sceneIndex) else { return nil }
        return a.scenes[sceneIndex]
    }

    private var myRole: String {
        audition?.role ?? "You"
    }

    private var allLines: [ScriptLine] {
        scene?.lines ?? []
    }

    var body: some View {
        let readerTrackVersion = store.readerTrackVersion
        VStack(spacing: 0) {
            InContentNavHeader(title: "Scene Audio Flow", backLabel: "Back", onBack: {
                stopAll()
                store.pop()
            })
            .padding(.horizontal, OT.gutter)
            .padding(.top, 4)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Overview Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Scene \(scene?.number ?? 1): Full Dialogue Flow", systemImage: "waveform.badge.magnifyingglass")
                                    .font(.otSubhead.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                                Spacer()
                                Toggle(isOn: $isContinuousFlow) {
                                    Text("Continuous")
                                        .font(.otCaption.weight(.semibold))
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                .toggleStyle(.button)
                                .tint(OT.accent)
                            }

                            Text("Tap ANY line below to start playback from that exact moment. Use the scrubber to play from between seconds.")
                                .font(.otCallout)
                                .foregroundStyle(OT.labelSecondary)

                            HStack(spacing: 12) {
                                Button {
                                    jumpToLine(0)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                        Text("Play scene from start")
                                    }
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.labelOnAccent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(OT.accent, in: Capsule())
                                }
                                .buttonStyle(.plain)

                                if activeLineIndex != nil {
                                    Button {
                                        stopAll()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "stop.fill")
                                            Text("Stop")
                                        }
                                        .font(.otFootnote.weight(.medium))
                                        .foregroundStyle(OT.labelSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(OT.fillField, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .otCard(radius: 18)

                        // Dialogue Lines List
                        ForEach(Array(allLines.enumerated()), id: \.offset) { index, line in
                            let isActive = activeLineIndex == index
                            let sameCharLines = allLines.filter { !$0.isMine && $0.character.caseInsensitiveCompare(line.character) == .orderedSame }
                            let cueIndex = sameCharLines.firstIndex(where: { $0.id == line.id }) ?? 0
                            let isRec = !line.isMine && readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: cueIndex)
                            let cueDuration = isRec ? ReaderTrackPlayer.duration(auditionID: auditionID, sceneIndex: sceneIndex, line: cueIndex) : 0

                            VStack(alignment: .leading, spacing: 8) {
                                // Header row
                                HStack(spacing: 8) {
                                    if line.isMine {
                                        Text("YOU (\(myRole.isEmpty ? "Your role" : myRole))")
                                            .font(.otCaption.weight(.bold))
                                            .foregroundStyle(OT.accent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(OT.accentSoft, in: Capsule())
                                    } else {
                                        Text(line.character.uppercased())
                                            .font(.otCaption.weight(.bold))
                                            .foregroundStyle(OT.reader)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(OT.reader.opacity(0.14), in: Capsule())

                                        if isRec {
                                            HStack(spacing: 4) {
                                                Image(systemName: isActive && player.isPlaying ? "waveform" : "checkmark.circle.fill")
                                                Text(formatTime(cueDuration))
                                            }
                                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(OT.reader)
                                        } else {
                                            HStack(spacing: 4) {
                                                Image(systemName: "mic.slash")
                                                Text("Needs audio")
                                            }
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(OT.labelTertiary)
                                        }
                                    }

                                    Spacer()

                                    Text("Line \(index + 1)")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelTertiary)
                                }

                                // Dialogue text
                                Text(line.text)
                                    .font(line.isMine ? .otHeadline : .otBody)
                                    .foregroundStyle(OT.labelPrimary)
                                    .lineSpacing(2)

                                // Active Line controls
                                if isActive {
                                    if line.isMine {
                                        if waitingForActor {
                                            HStack(spacing: 8) {
                                                Circle().fill(OT.accent).frame(width: 8, height: 8)
                                                Text("Your turn! Speak your line (\(actorCountdown)s)...")
                                                    .font(.otFootnote.weight(.semibold))
                                                    .foregroundStyle(OT.accent)
                                                Spacer()
                                                Button {
                                                    advanceAfterActorLine()
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text("Continue")
                                                        Image(systemName: "chevron.right")
                                                    }
                                                    .font(.otCaption.weight(.bold))
                                                    .foregroundStyle(OT.labelOnAccent)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(OT.accent, in: Capsule())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(10)
                                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                                        }
                                    } else if isRec {
                                        // Inline scrubber for recorded reader line
                                        ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: cueIndex, compact: false)
                                            .padding(.top, 4)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isActive ? (line.isMine ? OT.accentSoft.opacity(0.4) : OT.reader.opacity(0.12)) : OT.surfaceCard)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isActive ? (line.isMine ? OT.accent : OT.reader) : Color.clear, lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(isActive ? 0.08 : 0.03), radius: 6, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !line.isMine && !isRec {
                                    stopAll()
                                    store.push(.recordReader(auditionID, sceneIndex: sceneIndex, initialLineIndex: cueIndex, readerCharacter: line.character))
                                } else {
                                    jumpToLine(index)
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, OT.gutter)
                    .padding(.bottom, 120)
                }
                .onChange(of: activeLineIndex) { _, newIndex in
                    if let newIndex {
                        withAnimation {
                            scrollProxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            bottomDeck
        }
        .onAppear {
            player.onPlaybackFinished = {
                handlePlaybackFinished()
            }
        }
        .onDisappear {
            stopAll()
        }
    }

    private var bottomDeck: some View {
        HStack(spacing: 12) {
            // Prev Line
            Button {
                stepCue(forward: false)
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OT.labelPrimary)
                    .frame(width: 44, height: 44)
                    .background(OT.fillField, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(allLines.isEmpty)

            // Current line info
            VStack(alignment: .leading, spacing: 2) {
                if let idx = activeLineIndex, allLines.indices.contains(idx) {
                    let l = allLines[idx]
                    Text("Line \(idx + 1) · \(l.isMine ? "YOU" : l.character.capitalized)")
                        .font(.otSubhead.weight(.bold))
                        .foregroundStyle(OT.labelPrimary)
                    Text(l.text)
                        .font(.otCaption)
                        .foregroundStyle(OT.labelSecondary)
                        .lineLimit(1)
                } else {
                    Text("Tap any line to play")
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelSecondary)
                    Text("Walkthrough all scene cues")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)
                }
            }

            Spacer()

            // Play / Pause
            Button {
                if let idx = activeLineIndex {
                    let l = allLines[idx]
                    if l.isMine {
                        advanceAfterActorLine()
                    } else {
                        if player.isPlaying {
                            player.pause()
                        } else if player.currentTime > 0 {
                            player.resume()
                        } else {
                            jumpToLine(idx)
                        }
                    }
                } else {
                    jumpToLine(0)
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background(OT.accent, in: Circle())
            }
            .buttonStyle(.plain)

            // Next Line
            Button {
                stepCue(forward: true)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OT.labelPrimary)
                    .frame(width: 44, height: 44)
                    .background(OT.fillField, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(allLines.isEmpty)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: -2)
        .padding(.horizontal, OT.gutter)
        .padding(.bottom, 6)
    }

    private func jumpToLine(_ index: Int) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        waitingForActor = false
        guard allLines.indices.contains(index) else { return }
        activeLineIndex = index
        let line = allLines[index]

        if line.isMine {
            player.stop()
            if isContinuousFlow {
                waitingForActor = true
                actorCountdown = 3
                let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                    if actorCountdown > 1 {
                        actorCountdown -= 1
                    } else {
                        t.invalidate()
                        advanceAfterActorLine()
                    }
                }
                countdownTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            let sameCharLines = allLines.filter { !$0.isMine && $0.character.caseInsensitiveCompare(line.character) == .orderedSame }
            let cueIndex = sameCharLines.firstIndex(where: { $0.id == line.id }) ?? 0
            if ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: cueIndex) {
                player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: cueIndex, from: 0)
            } else if isContinuousFlow && index + 1 < allLines.count {
                jumpToLine(index + 1)
            }
        }
        Haptics.tick()
    }

    private func advanceAfterActorLine() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        waitingForActor = false
        guard let current = activeLineIndex, current + 1 < allLines.count else {
            activeLineIndex = nil
            return
        }
        jumpToLine(current + 1)
    }

    private func handlePlaybackFinished() {
        guard isContinuousFlow, let current = activeLineIndex, current + 1 < allLines.count else {
            activeLineIndex = nil
            return
        }
        jumpToLine(current + 1)
    }

    private func stepCue(forward: Bool) {
        guard !allLines.isEmpty else { return }
        let current = activeLineIndex ?? (forward ? -1 : allLines.count)
        let next = forward ? current + 1 : current - 1
        if allLines.indices.contains(next) {
            jumpToLine(next)
        } else if forward {
            jumpToLine(0)
        } else {
            jumpToLine(allLines.count - 1)
        }
    }

    private func stopAll() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        waitingForActor = false
        player.stop()
        activeLineIndex = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        return String(format: "%d:%02d", m, s)
    }
}
