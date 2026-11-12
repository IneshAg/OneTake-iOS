import SwiftUI
import AVKit

struct PracticeTakeView: View {
    var pieceID: PracticePiece.ID? = nil
    var initialDisplayMode: StandaloneDisplay = .full
    var initialRecordMode: PracticeRecordMode = .camera

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var recordedTakeURL: URL?
    @State private var recordedTakeDuration: Int = 0
    @State private var showPlayer = false
    @State private var activePieceID: PracticePiece.ID?
    @State private var lineIndex = 0
    @State private var follower = SpeechFollower()
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
                if camera.state == .recording {
                    HStack(spacing: 6) { // ot-lint:allow
                        Circle().fill(Color.red).frame(width: 8, height: 8) // ot-lint:allow
                        Text(formatElapsed(camera.elapsed))
                            .font(.otFootnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                        if recordMode == .voiceOnly {
                            Text("· VOICE ONLY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced)) // ot-lint:allow
                                .foregroundStyle(OT.prompterGold)
                        }
                    }
                    .padding(.horizontal, OTSpace.m)
                    .frame(height: 32) // ot-lint:allow
                    .background(.black.opacity(0.6), in: Capsule())
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
                                withAnimation(.easeInOut(duration: 0.2)) { recordMode = .camera }
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
                                withAnimation(.easeInOut(duration: 0.2)) { recordMode = .voiceOnly }
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
                            Button { displayMode = .hideMine; Haptics.tick() } label: {
                                Label("Hide my lines", systemImage: displayMode == .hideMine ? "checkmark" : "")
                            }
                        } label: {
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: displayMode == .firstLetters ? "character.textbox" : (displayMode == .hideMine ? "eye.slash" : "text.alignleft"))
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
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    prompterSize = 0
                                }
                                Haptics.tick()
                            } label: {
                                Label("Regular text (18pt)", systemImage: prompterSize == 0 ? "checkmark" : "")
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    prompterSize = 1
                                }
                                Haptics.tick()
                            } label: {
                                Label("Big text (26pt)", systemImage: prompterSize == 1 ? "checkmark" : "")
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    prompterSize = 2
                                }
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
                    if camera.state == .recording || recordedTakeURL == nil {
                        SidesPrompterView(
                            lines: lines,
                            currentIndex: lineIndex,
                            spokenTranscript: follower.transcript,
                            prompterSize: prompterSize,
                            mirror: mirrorPrompter,
                            readerIsPlaying: false,
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
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
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
                if camera.state != .recording, let _ = recordedTakeURL {
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
                                    Image(systemName: isAnalyzingVoice ? "hourglass" : "text.alignleft")
                                    Text(isAnalyzingVoice ? "Checking your lines…" : "Review speech against script")
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

                        // Memory & lines learned evaluation
                        let myLines = piece?.scene?.lines.filter(\.isMine).count ?? piece?.linesTotal ?? 0
                        let rememberedCount = max(onYourOwnLines.count, displayMode == .full ? myLines : 0)
                        HStack(spacing: OTSpace.s) {
                            Image(systemName: "brain.head.profile")
                                .font(.subheadline)
                                .foregroundStyle(OT.prompterGold)

                            VStack(alignment: .leading, spacing: 1) { // ot-lint:allow
                                Text(displayMode == .full ? "Full prompt used (\(myLines) lines)" : "\(rememberedCount) of \(myLines) lines from memory")
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(displayMode == .full ? "Try 'First letters' or 'Hide mine' to test recall" : (rememberedCount == myLines ? "Perfect memory on this run!" : "Good practice! Re-run to lock lines in"))
                                    .font(.system(size: 11)) // ot-lint:allow
                                    .foregroundStyle(Color.white.opacity(0.65)) // ot-lint:allow
                            }

                            Spacer()

                            if displayMode != .full && myLines > 0 {
                                let pct = Int((Double(rememberedCount) / Double(myLines)) * 100)
                                Text("\(pct)%")
                                    .font(.otFootnote.monospacedDigit().weight(.bold))
                                    .foregroundStyle(pct >= 80 ? OT.accent : OT.prompterGold)
                                    .padding(.horizontal, OTSpace.s)
                                    .padding(.vertical, OTSpace.xs)
                                    .background(Color.white.opacity(0.12), in: Capsule()) // ot-lint:allow
                            }
                        }
                        .padding(10) // ot-lint:allow
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: OTRadius.m)) // ot-lint:allow

                        // Explicit lines learned toggle
                        let isAllLearned = (piece?.linesLearned ?? 0) >= myLines && myLines > 0
                        HStack {
                            Button {
                                if let p = piece {
                                    let nextLearned = isAllLearned ? 0 : myLines
                                    store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: nextLearned)
                                    Haptics.success()
                                }
                            } label: {
                                HStack(spacing: 6) { // ot-lint:allow
                                    Image(systemName: isAllLearned ? "checkmark.circle.fill" : "circle")
                                        .font(.subheadline.weight(.semibold))
                                    Text(isAllLearned ? "Lines learned (\(myLines)/\(myLines))" : "Mark lines learned (\(myLines) lines)")
                                        .font(.otFootnote.weight(.semibold))
                                }
                                .foregroundStyle(isAllLearned ? OT.accent : .white)
                                .padding(.horizontal, 12) // ot-lint:allow
                                .padding(.vertical, 7) // ot-lint:allow
                                .background(isAllLearned ? AnyShapeStyle(OT.accentSoft) : AnyShapeStyle(Color.white.opacity(0.12)), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)) // ot-lint:allow
                            }
                            .buttonStyle(.plain)

                            Spacer()
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
                        isReaderPlaying: false
                    )
                    .padding(.bottom, 2) // ot-lint:allow
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                if let lines = piece?.scene?.lines, !lines.isEmpty, camera.state == .recording {
                    HStack(spacing: OTSpace.s) {
                        Button {
                            if lineIndex + 1 < lines.count { lineIndex += 1; Haptics.tick() }
                        } label: {
                            HStack(spacing: 5) { // ot-lint:allow
                                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)) // ot-lint:allow
                                Text("Next line").font(.otFootnote.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, OTSpace.m)
                            .frame(height: 36) // ot-lint:allow
                            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                prompterSize = (prompterSize + 1) % 3
                            }
                            Haptics.tick()
                        } label: {
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: "textformat.size").font(.caption)
                                Text(["Regular", "Big", "Huge"][prompterSize]).font(.otCaption.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10) // ot-lint:allow
                            .frame(height: 36) // ot-lint:allow
                            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if recordMode == .camera {
                            Button {
                                camera.toggleExposureLock()
                                Haptics.tick()
                            } label: {
                                HStack(spacing: OTSpace.xs) {
                                    Image(systemName: camera.isExposureLocked ? "lock.fill" : "lock.open")
                                        .font(.caption2)
                                    Text(camera.isExposureLocked ? "Locked" : "AE")
                                        .font(.otCaption.weight(.bold))
                                }
                                .foregroundStyle(camera.isExposureLocked ? OT.prompterGold : .white)
                                .padding(.horizontal, 10) // ot-lint:allow
                                .frame(height: 36) // ot-lint:allow
                                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, OTSpace.xs)
                }

                if recordMode == .voiceOnly {
                    HStack {
                        Spacer()
                        Button {
                            if camera.state == .recording {
                                Haptics.impact(.medium)
                                camera.stopRecording()
                            } else {
                                Haptics.impact(.heavy)
                                recordedTakeURL = nil
                                onYourOwnLines.removeAll()
                                camera.startRecording()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(camera.state == .recording ? Color.red.opacity(0.25) : Color.white.opacity(0.12)) // ot-lint:allow
                                    .frame(width: 78, height: 78) // ot-lint:allow
                                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 2)) // ot-lint:allow

                                if camera.state == .recording {
                                    RoundedRectangle(cornerRadius: 6) // ot-lint:allow
                                        .fill(Color.red)
                                        .frame(width: 28, height: 28) // ot-lint:allow
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 28, weight: .semibold)) // ot-lint:allow
                                        .foregroundStyle(Color.red)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.bottom, 6) // ot-lint:allow

                    HStack(spacing: 6) { // ot-lint:allow
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                        Text("Voice rehearsal · records voice only, no camera")
                            .font(.otCaption.weight(.medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.6)) // ot-lint:allow
                    .padding(.bottom, OTSpace.s)
                } else {
                    RecordButton(isRecording: camera.state == .recording) {
                        if camera.state == .recording {
                            Haptics.impact(.medium)
                            camera.stopRecording()
                        } else {
                            Haptics.impact(.heavy)
                            recordedTakeURL = nil
                            onYourOwnLines.removeAll()
                            camera.startRecording()
                        }
                    }
                    .padding(.bottom, OTSpace.m)
                }
            }
            .padding(.horizontal, OTSpace.gutter)
        }
        .preferredColorScheme(.dark)
        .keepScreenAwake()
        .task {
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
            guard let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
            let line = lines[lineIndex]
            let required = SpokenLineMatcher.requiredMatches(for: line.text)
            if required > 0 && SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: transcript).count >= required {
                let curID = line.id
                if line.isMine && !revealedLines.contains(curID) {
                    onYourOwnLines.insert(curID)
                }
                advanceRehearsalLine()
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if (cmd?.word == "action" || cmd?.word == "now"), camera.state == .ready {
                Haptics.impact(.heavy)
                recordedTakeURL = nil
                onYourOwnLines.removeAll()
                camera.startRecording()
                scheduleRehearsalAutoAdvance()
            }
            if cmd?.word == "cut", camera.state == .recording {
                Haptics.impact(.medium)
                camera.stopRecording()
            }
        }
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            if camera.state == .recording {
                Haptics.impact(.medium)
                camera.stopRecording()
            } else {
                Haptics.impact(.heavy)
                recordedTakeURL = nil
                onYourOwnLines.removeAll()
                camera.startRecording()
                scheduleRehearsalAutoAdvance()
            }
        }
        .onChange(of: camera.state) { _, newState in
            guard newState == .ready, let url = camera.lastRecording, let p = piece else { return }
            let number = p.takesRecorded + 1
            recordedTakeDuration = Int(camera.elapsed)
            if let saved = MediaStore.persist(url, as: "take-\(number)-\(UUID().uuidString).mov", in: "practice-\(p.id.uuidString)") {
                store.incrementPracticeTakes(for: p.id)
                let linesCount = p.scene?.lines.filter(\.isMine).count ?? p.linesTotal
                let learned = max(onYourOwnLines.count, (lineIndex + 1 >= (p.scene?.lines.count ?? 0) && displayMode == .full) ? linesCount : 0)
                if learned > 0 {
                    store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: learned)
                }
                recordedTakeURL = saved
                if recordMode == .voiceOnly, let lines = p.scene?.lines {
                    isAnalyzingVoice = true
                    voiceReviewError = nil
                    voiceReview = []
                    Task { @MainActor in
                        defer { isAnalyzingVoice = false }
                        do {
                            voiceReview = try await VoicePracticeReviewAnalyzer.analyze(url: saved, lines: lines)
                        } catch {
                            voiceReviewError = "On-device speech recognition wasn't available or couldn't detect enough speech. Your recording stays on this iPhone; play it and review the lines yourself."
                        }
                    }
                }
                Haptics.success()
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
            camera.stop()
            follower.stop()
        }
    }

    private func advanceRehearsalLine() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        follower.reset()
        guard let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
        if lineIndex + 1 < lines.count {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                lineIndex += 1
            }
            Haptics.tick()
            scheduleRehearsalAutoAdvance()
        }
    }

    private func scheduleRehearsalAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        guard let lines = piece?.scene?.lines, lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        let hasSpokenWords = !line.text.split(separator: " ").map({ SpokenLineMatcher.cleanWord($0) }).filter({ !$0.isEmpty }).isEmpty

        guard !line.isMine || !hasSpokenWords || line.isSilentReactionCue else { return }

        let wordCount = max(1, line.text.split(separator: " ").count)
        let delay: Double = (!hasSpokenWords || line.isSilentReactionCue) ? 1.6 : max(2.0, Double(wordCount) * 0.38 + 0.8)

        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            advanceRehearsalLine()
        }
    }
}

