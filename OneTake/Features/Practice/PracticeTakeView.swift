import SwiftUI
import AVKit
import OneTakeUI

struct PracticeTakeView: View {
    var pieceID: PracticePiece.ID? = nil
    var initialDisplayMode: StandaloneDisplay = .full
    var initialRecordMode: PracticeRecordMode = .camera

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = CameraController()
    @State private var recordedTakeURL: URL?
    @State private var recordedTakeDuration: Int = 0
    @State private var showPlayer = false
    @State private var activePieceID: PracticePiece.ID?
    @State private var lineIndex = 0
    @State private var follower = SpeechFollower()
    @State private var readerPlayer = ReaderTrackPlayer()
    @State private var displayMode: StandaloneDisplay = .full
    @State private var recordMode: PracticeRecordMode = .camera
    @State private var revealedLines: Set<ScriptLine.ID> = []
    @State private var onYourOwnLines: Set<ScriptLine.ID> = []
    @State private var hiddenGapWords: [ScriptLine.ID: Set<Int>] = [:]
    @State private var voiceReview: [VoiceLineReview] = []
    @State private var isAnalyzingVoice = false
    @State private var voiceReviewError: String?
    @State private var showVoiceReview = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var rehearsalFinished = false
    @State private var milestone: OTMilestoneBannerItem?
    @State private var breathePulse = false
    @AppStorage("prompter.size") private var prompterSize = 1
    @AppStorage("prompter.mirror") private var mirrorPrompter = false

    init(pieceID: PracticePiece.ID? = nil, initialDisplayMode: StandaloneDisplay = .full, initialRecordMode: PracticeRecordMode = .camera) {
        self.pieceID = pieceID
        self.initialDisplayMode = initialDisplayMode
        self.initialRecordMode = initialRecordMode
        _displayMode = State(initialValue: initialDisplayMode)
        _recordMode = State(initialValue: initialRecordMode)
    }

    private var piece: PracticePiece? {
        if let id = activePieceID ?? pieceID {
            return store.practice.first { $0.id == id }
        }
        return store.practice.first
    }

    private var sceneTitle: String {
        piece?.scene?.title ?? piece?.title ?? "Practice"
    }

    private var takeNumber: Int {
        (piece?.takesRecorded ?? 0) + 1
    }

    private var nextSceneAvailable: Bool {
        guard let p = piece else { return false }
        if let audID = p.auditionID, let sIdx = p.sceneIndex, let audition = store.audition(audID) {
            return sIdx + 1 < audition.scenes.count
        }
        if let idx = store.practice.firstIndex(where: { $0.id == p.id }) {
            return idx + 1 < store.practice.count
        }
        return false
    }

    private func advanceToNextScene() {
        guard let p = piece else { return }
        recordedTakeURL = nil
        lineIndex = 0
        onYourOwnLines.removeAll()
        revealedLines.removeAll()
        if let audID = p.auditionID, let sIdx = p.sceneIndex, let audition = store.audition(audID) {
            if sIdx + 1 < audition.scenes.count {
                let nextPiece = store.practicePiece(for: audID, sceneIndex: sIdx + 1)
                activePieceID = nextPiece.id
                store.promotePracticePiece(nextPiece.id)
                Haptics.tick()
                return
            }
        }
        if let idx = store.practice.firstIndex(where: { $0.id == p.id }), idx + 1 < store.practice.count {
            let nextPiece = store.practice[idx + 1]
            activePieceID = nextPiece.id
            store.promotePracticePiece(nextPiece.id)
            Haptics.tick()
        }
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        ZStack {
            if recordMode == .camera {
                CameraBackground(controller: camera)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.06, blue: 0.12), Color(red: 0.04, green: 0.03, blue: 0.06)], // ot-lint:allow
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay {
                    ZStack {
                        Circle()
                            .stroke(OT.reader.opacity(camera.state == .recording ? 0.25 : 0.08), lineWidth: 1)
                            .frame(width: 320, height: 320) // ot-lint:allow
                        Circle()
                            .stroke(OT.accent.opacity(camera.state == .recording ? 0.18 : 0.05), lineWidth: 1)
                            .frame(width: 480, height: 480) // ot-lint:allow
                    }
                    .allowsHitTesting(false)
                }
                .clipped()
                .ignoresSafeArea()
            }

            VStack {
                if camera.state == .recording || camera.state == .paused {
                    HStack(spacing: OTSpace.xs) {
                        Circle()
                            .fill(camera.state == .paused ? OT.due : OT.recRed)
                            .frame(width: 8, height: 8) // ot-lint:allow
                            .opacity(camera.state == .recording && breathePulse ? 0.4 : 1.0)
                        Text(camera.state == .paused ? "PAUSED · \(formatElapsed(camera.elapsed))" : formatElapsed(camera.elapsed))
                            .font(.otFootnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                        if recordMode == .voiceOnly {
                            Text("· VOICE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced)) // ot-lint:allow
                                .foregroundStyle(OT.prompterGold)
                        }
                    }
                    .padding(.horizontal, OTSpace.m)
                    .frame(height: 32) // ot-lint:allow
                    .background(OT.cameraBg.opacity(0.65), in: Capsule())
                    .padding(.top, OTSpace.s)
                } else {
                    HStack {
                        OTIconButton("xmark", accessibilityLabel: "Close") {
                            dismiss()
                        }

                        Spacer()

                        // Record Mode Switcher: Camera vs Voice only
                        HStack(spacing: 2) { // ot-lint:allow
                            Button {
                                withAnimation(OTMotion.snappy) { recordMode = .camera }
                                Haptics.tick()
                            } label: {
                                HStack(spacing: OTSpace.xs) {
                                    Image(systemName: "video.fill").font(.system(size: 11)) // ot-lint:allow
                                    Text("Camera").font(.otCaption.weight(.semibold))
                                }
                                .foregroundStyle(recordMode == .camera ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 10) // ot-lint:allow
                                .frame(height: 32) // ot-lint:allow
                                .background(recordMode == .camera ? Color.white.opacity(0.25) : Color.clear, in: Capsule()) // ot-lint:allow
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(OTMotion.snappy) { recordMode = .voiceOnly }
                                Haptics.tick()
                            } label: {
                                HStack(spacing: OTSpace.xs) {
                                    Image(systemName: "mic.fill").font(.system(size: 11)) // ot-lint:allow
                                    Text("Voice").font(.otCaption.weight(.semibold))
                                }
                                .foregroundStyle(recordMode == .voiceOnly ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 10) // ot-lint:allow
                                .frame(height: 32) // ot-lint:allow
                                .background(recordMode == .voiceOnly ? OT.reader : Color.clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(3) // ot-lint:allow
                        .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        // Practice Display Mode Menu
                        Menu {
                            Button { displayMode = .full; Haptics.tick() } label: {
                                Label("Full lines", systemImage: displayMode == .full ? "checkmark" : "")
                            }
                            Button { displayMode = .firstLetters; Haptics.tick() } label: {
                                Label("First letters", systemImage: displayMode == .firstLetters ? "checkmark" : "")
                            }
                            Button { displayMode = .gaps; Haptics.tick() } label: {
                                Label("Gaps", systemImage: displayMode == .gaps ? "checkmark" : "")
                            }
                            Button { displayMode = .hideMine; Haptics.tick() } label: {
                                Label("Hide my lines", systemImage: displayMode == .hideMine ? "checkmark" : "")
                            }
                        } label: {
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: displayMode == .firstLetters ? "character.textbox" : (displayMode == .hideMine ? "eye.slash" : (displayMode == .gaps ? "text.word.spacing" : "text.alignleft")))
                                    .font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                                Text(displayMode.title)
                                    .font(.otCaption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10) // ot-lint:allow
                            .frame(height: 36) // ot-lint:allow
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        // Text Size Menu
                        Menu {
                            Button {
                                withAnimation(OTMotion.snappy) { prompterSize = 0 }
                                Haptics.tick()
                            } label: {
                                Label("Regular text (18pt)", systemImage: prompterSize == 0 ? "checkmark" : "")
                            }
                            Button {
                                withAnimation(OTMotion.snappy) { prompterSize = 1 }
                                Haptics.tick()
                            } label: {
                                Label("Big text (26pt)", systemImage: prompterSize == 1 ? "checkmark" : "")
                            }
                            Button {
                                withAnimation(OTMotion.snappy) { prompterSize = 2 }
                                Haptics.tick()
                            } label: {
                                Label("Huge text (38pt)", systemImage: prompterSize == 2 ? "checkmark" : "")
                            }
                        } label: {
                            Image(systemName: "textformat.size")
                                .font(.system(size: 16, weight: .semibold)) // ot-lint:allow
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44) // ot-lint:allow
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.top, OTSpace.xs)
                }

                if camera.state == .recording && recordMode == .camera {
                    HStack(spacing: 5) { // ot-lint:allow
                        Capsule().fill(OT.prompterGold).frame(width: 3, height: 14) // ot-lint:allow
                        Text("LOOK AT LENS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced)) // ot-lint:allow
                            .foregroundStyle(OT.prompterGold)
                    }
                    .padding(.horizontal, 9) // ot-lint:allow
                    .frame(height: 22) // ot-lint:allow
                    .background(Color.black.opacity(0.65), in: Capsule()) // ot-lint:allow
                }

                if recordMode == .voiceOnly {
                    VStack(spacing: 6) { // ot-lint:allow
                        VoiceWaveformBars(isRecording: camera.state == .recording, level: camera.audioLevel)
                            .frame(height: 28) // ot-lint:allow

                        HStack(spacing: 6) { // ot-lint:allow
                            Circle()
                                .fill(camera.state == .recording ? Color.red : OT.reader)
                                .frame(width: 7, height: 7) // ot-lint:allow
                            Text(camera.state == .recording ? "RECORDING VOICE · LISTENING" : "VOICE REHEARSAL · NO CAMERA")
                                .font(.system(size: 11, weight: .bold, design: .monospaced)) // ot-lint:allow
                                .foregroundStyle(camera.state == .recording ? OT.prompterGold : Color.white.opacity(0.75)) // ot-lint:allow
                        }
                        .padding(.horizontal, 10) // ot-lint:allow
                        .padding(.vertical, OTSpace.xs)
                        .background(Color.black.opacity(0.45), in: Capsule()) // ot-lint:allow
                    }
                    .padding(.top, OTSpace.xs)
                }

                if let lines = piece?.scene?.lines, !lines.isEmpty {
                    if camera.state == .recording || camera.state == .paused || recordedTakeURL == nil {
                        SidesPrompterView(
                            lines: lines,
                            currentIndex: lineIndex,
                            spokenTranscript: follower.transcript,
                            prompterSize: prompterSize,
                            mirror: mirrorPrompter,
                            readerIsPlaying: readerPlayer.isPlaying,
                            readerAudioMissing: false,
                            displayMode: displayMode,
                            hiddenGapWords: hiddenGapWords,
                            revealedLines: revealedLines,
                            onAdvance: {
                                advanceRehearsalLine()
                            },
                            onPrevious: {
                                autoAdvanceTask?.cancel()
                                autoAdvanceTask = nil
                                rehearsalFinished = false
                                lineIndex = max(0, lineIndex - 1)
                                follower.reset()
                                Haptics.tick()
                                scheduleRehearsalAutoAdvance()
                            },
                            onToggleReveal: { id in
                                if revealedLines.contains(id) {
                                    revealedLines.remove(id)
                                } else {
                                    revealedLines.insert(id)
                                }
                                Haptics.tick()
                            },
                            onCycleSize: {
                                withAnimation(OTMotion.snappy) {
                                    prompterSize = (prompterSize + 1) % 3
                                }
                                Haptics.tick()
                            }
                        )
                        .padding(.top, 6) // ot-lint:allow
                    } else {
                        HStack(spacing: OTSpace.s) {
                            Text(lines.indices.contains(lineIndex) ? lines[lineIndex].text : sceneTitle)
                                .font(.otFootnote.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.85)) // ot-lint:allow
                                .lineLimit(1)
                            Spacer()
                            Text("\(lineIndex + 1) of \(lines.count) lines")
                                .font(.otCaption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(OT.prompterGold)
                        }
                        .padding(.horizontal, OTSpace.m)
                        .padding(.vertical, OTSpace.s)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)) // ot-lint:allow
                    }
                }

                Spacer()

                // Post-take review & next scene options
                if camera.state != .recording && camera.state != .paused, let _ = recordedTakeURL {
                    VStack(spacing: OTSpace.m) {
                        HStack(spacing: OTSpace.m) {
                            Image(systemName: recordMode == .voiceOnly ? "waveform.circle.fill" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(recordMode == .voiceOnly ? OT.reader : OT.success)

                            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                Text("\(recordMode == .voiceOnly ? "Voice take" : "Take") \(takeNumber - 1) saved")
                                    .font(.otHeadline)
                                    .foregroundStyle(.white)
                                Text("\(formatElapsed(Double(recordedTakeDuration))) · \(sceneTitle)")
                                    .font(.otFootnote)
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            Spacer()

                            Button {
                                showPlayer = true
                            } label: {
                                HStack(spacing: 5) { // ot-lint:allow
                                    Image(systemName: recordMode == .voiceOnly ? "waveform" : "play.fill")
                                        .font(.caption)
                                    Text(recordMode == .voiceOnly ? "Play voice" : "Watch take")
                                }
                            }
                            .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                        }

                        if recordMode == .voiceOnly {
                            Button { showVoiceReview = true } label: {
                                HStack(spacing: OTSpace.s) {
                                    Image(systemName: isAnalyzingVoice ? "hourglass" : "waveform.and.magnifyingglass")
                                    VStack(alignment: .leading, spacing: 1) { // ot-lint:allow
                                        Text(isAnalyzingVoice ? "Voice Checker · analyzing…" : "Voice Checker")
                                        Text("Check your recorded voice against the script")
                                            .font(.otCaption)
                                            .foregroundStyle(OT.cameraLabel2)
                                    }
                                    Spacer()
                                    if !isAnalyzingVoice, !voiceReview.isEmpty {
                                        Text("\(voiceReview.filter { $0.mark != .matched && !$0.dismissed }.count) notes")
                                            .font(.otCaption.weight(.semibold))
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                }
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(OTSpace.m)
                                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                            }
                            .buttonStyle(.plain)
                            .disabled(isAnalyzingVoice)
                        }

                        // Interactive prompt options card ("Full prompt used" -> switch modes or open all options)
                        let myScriptLines = piece?.scene?.lines.filter(\.isMine) ?? []
                        let myLines = max(myScriptLines.count, piece?.linesTotal ?? 0)
                        let rememberedCount = max(onYourOwnLines.count, displayMode == .full ? myLines : 0)
                        Menu {
                            ForEach(StandaloneDisplay.allCases) { modeOption in
                                Button {
                                    withAnimation(OTMotion.snappy) { displayMode = modeOption }
                                    Haptics.tick()
                                } label: {
                                    Label(modeOption.rawValue, systemImage: displayMode == modeOption ? "checkmark" : "")
                                }
                            }
                            if let audID = piece?.auditionID, let sIdx = piece?.sceneIndex {
                                Divider()
                                Button {
                                    dismiss()
                                    store.push(.practiceOptions(audID, sceneIndex: sIdx))
                                } label: {
                                    Label("More practice options…", systemImage: "slider.horizontal.3")
                                }
                            }
                        } label: {
                            HStack(spacing: OTSpace.s) {
                                Image(systemName: "brain.head.profile")
                                    .font(.subheadline)
                                    .foregroundStyle(OT.prompterGold)

                                VStack(alignment: .leading, spacing: 1) { // ot-lint:allow
                                    Text(displayMode == .full ? "Prompt: Full lines (\(myLines) lines)" : "Prompt: \(displayMode.title) · \(rememberedCount)/\(myLines)")
                                        .font(.otFootnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("Tap to switch prompt mode or drill options")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.cameraLabel2)
                                }

                                Spacer()

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(OT.prompterGold)
                            }
                            .padding(OTSpace.m)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                        }

                        // Individual line learned toggles + all-learned toggle
                        if let p = piece, !myScriptLines.isEmpty {
                            VStack(alignment: .leading, spacing: OTSpace.s) {
                                HStack {
                                    Text("Mark learned lines (\(p.linesLearned)/\(myLines))")
                                        .font(.otCaption.weight(.semibold))
                                        .foregroundStyle(OT.cameraLabel2)
                                    Spacer()
                                    let isAllLearned = p.linesLearned >= myLines && myLines > 0
                                    Button(isAllLearned ? "Reset all" : "Mark all") {
                                        store.markAllLinesLearned(pieceID: p.id, learned: !isAllLearned)
                                        if !isAllLearned {
                                            Haptics.celebrate()
                                            milestone = OTMilestoneBannerItem(title: "All \(myLines) lines learned!", subtitle: sceneTitle)
                                        } else {
                                            Haptics.tick()
                                        }
                                    }
                                    .font(.otCaption.weight(.bold))
                                    .foregroundStyle(OT.prompterGold)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: OTSpace.xs) {
                                        ForEach(Array(myScriptLines.enumerated()), id: \.element.id) { idx, line in
                                            Button {
                                                if let res = store.toggleLineLearned(pieceID: p.id, lineID: line.id) {
                                                    if res.allLearned {
                                                        Haptics.celebrate()
                                                        milestone = OTMilestoneBannerItem(title: "All \(myLines) lines learned!", subtitle: sceneTitle)
                                                    } else if res.nowLearned {
                                                        Haptics.stepDone()
                                                    } else {
                                                        Haptics.tick()
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: OTSpace.xs) {
                                                    Image(systemName: line.isLearned ? "checkmark.circle.fill" : "circle")
                                                    Text("Line \(idx + 1)")
                                                }
                                                .font(.otCaption.weight(.semibold))
                                                .foregroundStyle(line.isLearned ? OT.cameraBg : OT.cameraLabel)
                                                .padding(.horizontal, OTSpace.s)
                                                .padding(.vertical, OTSpace.xs)
                                                .background(
                                                    Capsule().fill(line.isLearned ? OT.success : OT.cameraGlass)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .animation(OTMotion.bouncy, value: line.isLearned)
                                        }
                                    }
                                }
                            }
                        }

                        HStack(spacing: 10) { // ot-lint:allow
                            if nextSceneAvailable {
                                Button {
                                    advanceToNextScene()
                                } label: {
                                    HStack(spacing: 5) { // ot-lint:allow
                                        Text("Next scene")
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .buttonStyle(.otPrimary)
                            }

                            Button("Done") {
                                dismiss()
                            }
                            .buttonStyle(.otSecondary)
                        }
                    }
                    .padding(OTSpace.m)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1) // ot-lint:allow
                    )
                    .padding(.bottom, 6) // ot-lint:allow
                }

                if let lines = piece?.scene?.lines, lines.indices.contains(lineIndex), camera.state == .recording {
                    let cur = lines[lineIndex]
                    VoiceFollowingPill(
                        isListening: follower.isListening,
                        isActorLine: cur.isMine,
                        characterName: cur.character,
                        isFollowingVoice: true,
                        isReaderPlaying: readerPlayer.isPlaying
                    )
                    .padding(.bottom, OTSpace.xxs)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                PracticeRecordingDock(
                    recordMode: recordMode,
                    cameraState: camera.state,
                    isExposureLocked: camera.isExposureLocked,
                    prompterSize: prompterSize,
                    hasLines: !(piece?.scene?.lines.isEmpty ?? true),
                    isAtLastLine: {
                        guard let lines = piece?.scene?.lines else { return false }
                        return lineIndex >= max(0, lines.count - 1)
                    }(),
                    rehearsalFinished: rehearsalFinished,
                    onPreviousLine: {
                        autoAdvanceTask?.cancel()
                        autoAdvanceTask = nil
                        readerPlayer.stop()
                        rehearsalFinished = false
                        lineIndex = max(0, lineIndex - 1)
                        follower.reset()
                        Haptics.tick()
                        scheduleRehearsalAutoAdvance()
                    },
                    onNextLine: {
                        advanceRehearsalLine()
                    },
                    onRestartLines: {
                        restartLines()
                    },
                    onCycleSize: {
                        withAnimation(OTMotion.snappy) { prompterSize = (prompterSize + 1) % 3 }
                        Haptics.tick()
                    },
                    onToggleAE: {
                        camera.toggleExposureLock()
                        Haptics.tick()
                    },
                    onStartRecording: {
                        startPracticeRecording()
                    },
                    onPauseResume: {
                        if camera.state == .paused {
                            camera.resumeRecording()
                            if !follower.isListening { follower.start() }
                        } else {
                            camera.pauseRecording()
                            autoAdvanceTask?.cancel()
                            readerPlayer.stop()
                        }
                    },
                    onStopRecording: {
                        Haptics.impact(.medium)
                        autoAdvanceTask?.cancel()
                        readerPlayer.stop()
                        camera.stopRecording()
                    }
                )
            }
            .padding(.horizontal, OTSpace.gutter)
        }
        .preferredColorScheme(.dark)
        .otSurface(.camera)
        .otMilestoneBanner($milestone)
        .keepScreenAwake()
        .task {
            if !reduceMotion {
                withAnimation(OTMotion.breathe) { breathePulse = true }
            }
            if await CameraController.requestAccess() {
                camera.configure()
            }
            if await SpeechFollower.requestAccess() {
                follower.start()
            }
            scheduleRehearsalAutoAdvance()
        }
        .task(id: displayMode) {
            guard displayMode == .gaps, let lines = piece?.scene?.lines else { return }
            var selections: [ScriptLine.ID: Set<Int>] = [:]
            for line in lines where line.isMine && !line.isSilentReactionCue {
                selections[line.id] = await RecallGapSelectionStore.hiddenWordIndices(for: line.text)
            }
            hiddenGapWords = selections
        }
        .onChange(of: follower.transcript) { _, transcript in
            guard !rehearsalFinished,
                  let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
            let line = lines[lineIndex]
            guard line.isMine else { return }
            if SpokenLineMatcher.isLineComplete(lineText: line.text, transcript: transcript) {
                if !revealedLines.contains(line.id) {
                    onYourOwnLines.insert(line.id)
                }
                advanceRehearsalLine()
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if (cmd?.word == "action" || cmd?.word == "now"), camera.state == .ready {
                startPracticeRecording()
            }
            if cmd?.word == "cut", camera.state == .recording || camera.state == .paused {
                Haptics.impact(.medium)
                autoAdvanceTask?.cancel()
                readerPlayer.stop()
                camera.stopRecording()
            }
        }
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            if camera.state == .recording || camera.state == .paused {
                Haptics.impact(.medium)
                autoAdvanceTask?.cancel()
                readerPlayer.stop()
                camera.stopRecording()
            } else {
                startPracticeRecording()
            }
        }
        .onChange(of: camera.state) { _, newState in
            guard newState == .ready, let url = camera.lastRecording, let p = piece else { return }
            autoAdvanceTask?.cancel()
            readerPlayer.stop()
            let number = p.takesRecorded + 1
            recordedTakeDuration = Int(camera.elapsed)
            if let saved = MediaStore.persist(url, as: "take-\(number)-\(UUID().uuidString).mov", in: "practice-\(p.id.uuidString)") {
                store.incrementPracticeTakes(for: p.id)
                let linesCount = p.scene?.lines.filter(\.isMine).count ?? p.linesTotal
                let learned = max(onYourOwnLines.count, (rehearsalFinished && displayMode == .full) ? linesCount : 0)
                if learned > 0 {
                    store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: learned)
                }
                recordedTakeURL = saved
                if recordMode == .voiceOnly, let lines = p.scene?.lines {
                    // Stop live SpeechFollower microphone tap before running Voice Checker on the saved take.
                    follower.stop()
                    isAnalyzingVoice = true
                    voiceReviewError = nil
                    voiceReview = []
                    Task { @MainActor in
                        defer { isAnalyzingVoice = false }
                        do {
                            voiceReview = try await VoicePracticeReviewAnalyzer.analyze(url: saved, lines: lines)
                        } catch {
                            voiceReviewError = "Speech recognition couldn't analyze this take automatically (\(error.localizedDescription)). You can still play and review your voice recording above."
                        }
                    }
                }
                Haptics.celebrate()
                milestone = OTMilestoneBannerItem(
                    title: recordMode == .voiceOnly ? "Voice take saved!" : "Practice take saved!",
                    subtitle: sceneTitle
                )
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = recordedTakeURL {
                PracticeVideoPlayerSheet(url: url, isVoiceTake: recordMode == .voiceOnly, sceneTitle: sceneTitle)
            }
        }
        .sheet(isPresented: $showVoiceReview) {
            VoicePracticeReviewView(recordingURL: recordedTakeURL, reviews: $voiceReview,
                                    isAnalyzing: isAnalyzingVoice, errorMessage: voiceReviewError)
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
            autoAdvanceTask = nil
            readerPlayer.stop()
            camera.stop()
            follower.stop()
        }
    }

    private func readerScope(for piece: PracticePiece) -> ReaderTrackScope {
        if let audID = piece.auditionID, let sIdx = piece.sceneIndex {
            return .audition(audID, sceneIndex: sIdx)
        }
        return .practice(piece.id)
    }

    private func startPracticeRecording() {
        Haptics.impact(.heavy)
        recordedTakeURL = nil
        rehearsalFinished = false
        lineIndex = 0
        onYourOwnLines.removeAll()
        if !follower.isListening { follower.start() }
        follower.reset()
        camera.startRecording()
        scheduleRehearsalAutoAdvance()
    }

    private func restartLines() {
        autoAdvanceTask?.cancel()
        readerPlayer.stop()
        rehearsalFinished = false
        lineIndex = 0
        follower.reset()
        if !follower.isListening { follower.start() }
        Haptics.tick()
        scheduleRehearsalAutoAdvance()
    }

    private func advanceRehearsalLine() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        readerPlayer.stop()
        follower.reset()
        guard let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
        if lineIndex + 1 < lines.count {
            withAnimation(OTMotion.smooth) {
                lineIndex += 1
            }
            Haptics.tick()
            scheduleRehearsalAutoAdvance()
        } else {
            withAnimation(OTMotion.bouncy) {
                rehearsalFinished = true
            }
            follower.stop()
            Haptics.celebrate()
            milestone = OTMilestoneBannerItem(
                title: "End of scene!",
                subtitle: (camera.state == .recording || camera.state == .paused)
                    ? "Tap Stop below to save your take"
                    : "Scene run complete"
            )
        }
    }

    private func scheduleRehearsalAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        guard !rehearsalFinished,
              let p = piece,
              let lines = p.scene?.lines, lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        let hasSpokenWords = !line.text.split(separator: " ").map({ SpokenLineMatcher.cleanWord($0) }).filter({ !$0.isEmpty }).isEmpty

        guard !line.isMine || !hasSpokenWords || line.isSilentReactionCue else { return }

        var delay: Double
        if !line.isMine && !line.isSilentReactionCue {
            let readerIndex = lines[..<lineIndex].filter { !$0.isMine }.count
            if readerPlayer.play(scope: readerScope(for: p), lineIndex: readerIndex) {
                delay = max(1.0, readerPlayer.duration + 0.45)
            } else {
                let wordCount = max(1, line.text.split(separator: " ").count)
                delay = max(2.0, Double(wordCount) * 0.38 + 0.8)
            }
        } else {
            delay = 1.6
        }

        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            advanceRehearsalLine()
        }
    }
}

