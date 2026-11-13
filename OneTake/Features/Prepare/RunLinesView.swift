import SwiftUI
import OneTakeUI

// MARK: - 11.3–11.6 Run lines

struct RunLinesView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var finished = false
    /// What this run actually showed: your lines said out loud without a prompt. Skipped lines
    /// count as neither.
    @State private var onYourOwn: Set<Int> = []
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
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // progress
                HStack(spacing: OTSpace.xxs) {
                    ForEach(lines.indices, id: \.self) { i in
                        Capsule()
                            .fill(i < index ? (lines[i].isMine ? OT.accent : OT.reader) : (i == index ? OT.labelPrimary : OT.fillQuiet))
                            .frame(height: 4) // ot-lint:allow
                    }
                }
                Text("Line \(index + 1) of \(lines.count)")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelTertiary)

                if finished {
                    RunFinishedView(
                        lines: lines,
                        onYourOwn: onYourOwn,
                        reachedEnd: reachedEnd,
                        heardYou: follower.isListening
                    ) {
                        index = 0
                        finished = false
                        reachedEnd = false
                        onYourOwn = []
                        follower.reset()
                        speakIfReader(lines)
                    } onClose: {
                        store.pop()
                    }
                } else {
                    if index > 0 {
                        OTSectionLabel(lines[index - 1].isMine ? "You said" : "\(lines[index - 1].character.capitalized) said")
                        if lines[index - 1].isSilentReactionCue {
                            SilentReactionCue(cueText: lines[index - 1].text, isMine: lines[index - 1].isMine, inPrompter: false)
                        } else {
                            Text(lines[index - 1].text)
                                .font(.otCallout)
                                .foregroundStyle(OT.labelTertiary)
                        }
                    }
                    let line = lines[index]
                    if line.isSilentReactionCue {
                        SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: false)
                    } else if line.isMine {
                        Label("Your line · listening", systemImage: "waveform")
                            .font(.otCaption.weight(.semibold))
                            .foregroundStyle(OT.reader)
                        Text(highlighted(line.text))
                            .font(.system(size: 30, weight: .bold)) // ot-lint:allow
                            .foregroundStyle(OT.labelPrimary)
                        Label("The highlight follows your voice", systemImage: "line.3.horizontal")
                            .font(.otFootnote)
                            .foregroundStyle(OT.accent)
                    } else {
                        Label(
                            readerAudioMissing ? "\(line.character.capitalized) · no recording" : "\(line.character.capitalized) · your recording",
                            systemImage: readerAudioMissing ? "mic.slash" : "waveform"
                        )
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.reader)

                        Text(line.text)
                            .font(.system(size: 30, weight: .bold)) // ot-lint:allow
                    }

                    Spacer()

                    HStack(spacing: OTSpace.m) {
                        OTIconButton("pause.fill", accessibilityLabel: "Pause") {
                            stopReader()
                            finished = true
                        }

                        if line.isSilentReactionCue {
                            Button("Done reacting") {
                                advance(lines)
                            }
                            .buttonStyle(.otPrimary)
                        } else if line.isMine {
                            Spacer(minLength: 0)
                        } else if readerAudioMissing {
                            Button("Continue") {
                                advance(lines)
                            }
                            .buttonStyle(.otPrimary)
                        } else {
                            Label("Reader audio", systemImage: "waveform")
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(OT.labelSecondary)
                                .frame(maxWidth: .infinity)
                        }

                        OTIconButton("forward.fill", accessibilityLabel: "Skip line") {
                            advance(lines)
                        }
                    }
                    .foregroundStyle(OT.labelPrimary)
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .otCanvas()
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { speakIfReader(lines) }
            .onChange(of: follower.transcript) { _, transcript in
                guard !finished, lines[index].isMine,
                      SpokenLineMatcher.matchedWordIndices(in: lines[index].text, transcript: transcript).count >= SpokenLineMatcher.requiredMatches(for: lines[index].text) else { return }
                onYourOwn.insert(index)
                advance(lines)
            }
            .task {
                if await SpeechFollower.requestAccess() {
                    follower.start()
                }
            }
            .onDisappear {
                follower.stop()
                stopReader()
            }
        }
    }

    private func advance(_ lines: [ScriptLine]) {
        stopReader()
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
        if lines[index].isSilentReactionCue {
            // Non-verbal reader beat: hold natural pause and advance
            readerAdvance = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                advance(lines)
            }
            return
        }
        let readerLineIndex = lines[..<index].filter { !$0.isMine }.count
        guard readerPlayer.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerLineIndex) else {
            readerAudioMissing = true
            return
        }
        let delay = readerPlayer.duration + 0.45
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

    private func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString()
        let matched = SpokenLineMatcher.matchedWordIndices(in: text, transcript: follower.transcript)
        for (i, w) in text.split(separator: " ").enumerated() {
            var part = AttributedString(String(w) + " ")
            if matched.contains(i) {
                part.foregroundColor = OT.prompterGold
            } else {
                part.foregroundColor = OT.labelPrimary.opacity(0.85)
            }
            out += part
        }
        return out
    }
}

struct RunFinishedView: View {
    let lines: [ScriptLine]
    /// Indices into `lines`.
    let onYourOwn: Set<Int>
    /// False when the run was paused before the last line.
    let reachedEnd: Bool
    /// Whether speech recognition was listening; without it nothing can count as said on your own.
    let heardYou: Bool
    var onAgain: () -> Void
    var onClose: () -> Void

    private var summary: String {
        guard heardYou else {
            return "on your own. Voice listening was off, so lines you skipped past can't count — turn on Speech Recognition for OneTake in Settings."
        }
        return reachedEnd ? "Lines you said without a prompt." : "Lines you said without a prompt before you paused."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            OTSectionLabel("This run")
            HStack(alignment: .firstTextBaseline) {
                Text("\(onYourOwn.count)").font(.system(size: 64, weight: .bold)) // ot-lint:allow
                Text("of \(lines.filter(\.isMine).count)").font(.otTitle).foregroundStyle(OT.labelSecondary)
            }
            Text(summary).font(.otCallout).foregroundStyle(OT.labelSecondary)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                HStack(alignment: .top) {
                    Image(systemName: symbol(i, l)).foregroundStyle(onYourOwn.contains(i) ? OT.accent : OT.labelTertiary)
                    if l.isSilentReactionCue {
                        SilentReactionCue(cueText: l.text, isMine: l.isMine, inPrompter: false)
                    } else {
                        Text(l.text).font(l.isMine ? .otHeadline : .otCallout).foregroundStyle(l.isMine ? OT.labelPrimary : OT.labelTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(l.isMine ? "\(onYourOwn.contains(i) ? "Said on your own" : "Not said"): \(l.text)" : "Reader: \(l.text)")
            }
            Spacer()
            Button("Run again", action: onAgain).buttonStyle(.otPrimary)
            Button("Done", action: onClose).buttonStyle(.otSecondary)
        }
    }

    private func symbol(_ i: Int, _ line: ScriptLine) -> String {
        guard line.isMine else { return "text.bubble" }
        if onYourOwn.contains(i) { return "checkmark.square.fill" }
        return "square"
    }
}
