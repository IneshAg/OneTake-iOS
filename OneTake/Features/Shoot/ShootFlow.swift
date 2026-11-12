import SwiftUI
import OneTakeUI
import AVKit
import Speech

// MARK: - Camera flow: camera check → slate → requested full-body shot → scenes → take saved

struct ShootFlow: View {
    enum Stage { case check, slate, slateDone, fullLength, scene, saved }

    let auditionID: Audition.ID
    /// Which scene to open on; nil picks the next one still to shoot.
    var initialScene: Int? = nil
    var initialStage: CameraFlow.ShootStart = .check
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    @State var camera = CameraController()
    @State var follower = SpeechFollower()
    @State var cameraSpeaker = CameraGuidanceSpeaker()
    @State var voiceAllowed = false
    @State var stage: Stage = .check
    /// The scene being shot. Takes, reader lines and the checklist piece all follow it.
    @State var sceneIndex = 0
    /// Scenes skipped during this camera session are excluded from the wraparound search so Skip
    /// cannot cycle back to a scene the actor already passed.
    @State var skippedSceneIndices: Set<Int> = []
    @State var skippedCameraPieces: Set<PieceKind> = []
    @State var countdown: Int?
    @State var timerSeconds = 3
    @State var pinchStartZoom: CGFloat?
    @State var lineIndex = 0
    @State var takeNumber = 1
    @State var saveError: String?
    @State var isAnalyzingSlate = false
    @State var slateTrimReview: SlateTrimReview?
    /// Your own recorded reader lines, played during a take so they land under your voice.
    @State var reader = ReaderTrackPlayer()
    @State var readerAdvance: Task<Void, Never>?
    @State var timedAdvance: Task<Void, Never>?
    @State var readerAudioMissing = false
    @State var talkbackTask: Task<Void, Never>?
    @AppStorage("readerVolume") var readerVolume = "Quieter"
    // Teleprompter settings from Prepare — applied to the in-camera prompter.
    @AppStorage("prompter.size") var prompterSize = 1
    @AppStorage("prompter.followVoice") var followVoice = true
    @AppStorage("prompter.mirror") var mirrorPrompter = false
    @AppStorage("camera.voiceGuidanceEnabled") var voiceGuidanceEnabled = true
    @AppStorage("camera.voiceCommandsEnabled") var voiceCommandsEnabled = true
    @AppStorage("camera.poseGuideEnabled") var poseGuideEnabled = true
    @AppStorage("camera.gesturesEnabled") var gesturesEnabled = false
    @AppStorage("camera.gestureHoldDuration") var gestureHoldDuration = 1.2
    @State var gestureHoldTask: Task<Void, Never>?
    @State var lastGestureAction = Date.distantPast
    @AppStorage("camera.recordingResolution") var recordingResolution = CameraResolution.hd1080.rawValue
    @State var advanceAfterSceneSave = false
    @State var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation

    var body: some View {
        let a = store.audition(auditionID)
        ZStack {
            CameraBackground(controller: camera)
                .ignoresSafeArea()
            if camera.state == .recording {
                RoundedRectangle(cornerRadius: 55) // ot-lint:allow
                    .stroke(OT.recRed, lineWidth: 6) // ot-lint:allow
                    .ignoresSafeArea()
            }

            VStack(spacing: OTSpace.m) {
                topBar
                if camera.isExposureLocked && camera.state == .ready {
                    Label("AE/AF LOCKED · Tap to unlock", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(OT.prompterGold)
                        .padding(.horizontal, OTSpace.s)
                        .frame(height: 28) // ot-lint:allow
                        .background(OT.cameraGlass, in: Capsule())
                }
                if camera.state == .recording {
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
                if let a { overlay(for: a) }
                Spacer()
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 160, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(Color.white) // ot-lint:allow
                        .transition(.scale(scale: 1.3).combined(with: .opacity))
                        .id(countdown)
                    Spacer()
                }
                voiceStatusPill
                voiceCommandStatus
                sceneActionBar
                hud
                bottomControls
            }
            .padding(.horizontal, OTSpace.gutter)
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard stage == .check else { return }
                    let start = pinchStartZoom ?? camera.zoomFactor
                    pinchStartZoom = start
                    camera.setZoomFactor(start * value)
                }
                .onEnded { _ in pinchStartZoom = nil }
        )
        .otSurface(.camera)
        .preferredColorScheme(.dark)
        .statusBarHidden(camera.state == .recording)
        .keepScreenAwake()
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            let orientation = UIDevice.current.orientation
            if orientation.isValidInterfaceOrientation { deviceOrientation = orientation }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            if orientation.isValidInterfaceOrientation { deviceOrientation = orientation }
        }
        .task {
            sceneIndex = initialScene ?? store.sceneToShoot(auditionID)
            stage = initialStage == .slate ? .slate : initialStage == .fullLength ? .fullLength : .check
            follower.setContextualStrings(speechContext(for: 0))
            camera.wantsFaceGuidance = true
            camera.wantsBodyPoseGuidance = poseGuideEnabled
            camera.wantsHandGesture = gesturesEnabled && stage != .check
            if await CameraController.requestAccess() {
                let resolution = CameraResolution(rawValue: recordingResolution) ?? .hd1080
                camera.configure(position: .front, resolution: resolution)
            }
            voiceAllowed = await SpeechFollower.requestAccess()
            if voiceAllowed { follower.start() }
        }
        .onChange(of: camera.state) { _, state in
            if state == .ready, voiceAllowed, !follower.isListening { follower.start() }
        }
        .onChange(of: cameraGuidanceKey) { _, key in
            guard voiceGuidanceEnabled, stage == .check, camera.state == .ready, let key else { return }
            Task { @MainActor in
                let spoken = await OnDeviceIntelligence.cameraGuidance(fact: key) ?? key
                guard voiceGuidanceEnabled, stage == .check, camera.state == .ready else { return }
                cameraSpeaker.speak(spoken)
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            guard voiceCommandsEnabled else { return }
            if (cmd?.word == "action" || cmd?.word == "now"), camera.state == .ready,
               [.slate, .fullLength, .scene].contains(stage) { roll() }
            if cmd?.word == "cut", camera.state == .recording { cut() }
        }
        .onChange(of: follower.transcript) { _, transcript in
            guard followVoice, stage == .scene, camera.state == .recording, let lines = sceneLines,
                  lines.indices.contains(lineIndex) else { return }
            let line = lines[lineIndex]
            guard line.isMine else { return }
            let matches = SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: transcript)
            let required = SpokenLineMatcher.requiredMatches(for: line.text)
            if matches.count >= required {
                interpretTalkback(line)
            }
        }
        .onChange(of: stage) { _, newStage in
            camera.wantsHandGesture = gesturesEnabled && [.slate, .fullLength, .scene].contains(newStage)
            camera.clearHandGestureDetection()
        }
        .onChange(of: gesturesEnabled) { _, enabled in
            camera.wantsHandGesture = enabled && [.slate, .fullLength, .scene].contains(stage)
            if !enabled { gestureHoldTask?.cancel(); camera.clearHandGestureDetection() }
        }
        .onChange(of: camera.openPalmDetected) { _, detected in
            guard detected, gesturesEnabled, [.slate, .fullLength, .scene].contains(stage) else {
                gestureHoldTask?.cancel()
                return
            }
            gestureHoldTask?.cancel()
            gestureHoldTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(gestureHoldDuration))
                guard !Task.isCancelled, camera.openPalmDetected,
                      Date().timeIntervalSince(lastGestureAction) > 2 else { return }
                lastGestureAction = .now
                switch camera.state {
                case .ready: roll()
                case .recording: camera.pauseRecording()
                case .paused: camera.resumeRecording()
                default: break
                }
            }
        }
        .onChange(of: poseGuideEnabled) { _, enabled in
            camera.wantsBodyPoseGuidance = enabled
            if !enabled { camera.clearBodyPose() }
        }
        .onChange(of: camera.state) { _, newState in handleCameraStateChange(newState) }
        .onChange(of: followVoice) { _, followsVoice in
            if followsVoice { timedAdvance?.cancel() }
            else { scheduleTimedAdvance() }
        }
        .onDisappear {
            gestureHoldTask?.cancel()
            talkbackTask?.cancel()
            timedAdvance?.cancel()
            cameraSpeaker.stop()
            camera.stop()
            follower.stop()
            stopReader()
        }
        .alert("Couldn’t save that recording", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .sheet(item: $slateTrimReview) { review in
            SlateTrimReviewView(
                original: review.original,
                trimmed: review.trimmed,
                removedLeading: review.suggestion.removedLeading,
                removedTrailing: review.suggestion.removedTrailing,
                keepTrimmed: {
                    store.acceptSlateTrim(review.trimmed, for: auditionID)
                    slateTrimReview = nil
                },
                keepOriginal: {
                    try? FileManager.default.removeItem(at: review.trimmed)
                    slateTrimReview = nil
                }
            )
        }
    }

    // MARK: Actions

    var sceneLines: [ScriptLine]? {
        guard let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return nil }
        return scenes[sceneIndex].lines
    }

    func pickScene(_ i: Int) {
        guard camera.state != .recording, countdown == nil else { return }
        stopReader()
        sceneIndex = i
        lineIndex = 0
        follower.reset()
        follower.setContextualStrings(speechContext(for: 0))
        Haptics.tick()
    }

    func nextUnshotScene(in a: Audition) -> Int? {
        let order = a.scenes.indices.filter { $0 > sceneIndex } + a.scenes.indices.filter { $0 < sceneIndex }
        return order.first { i in
            !skippedSceneIndices.contains(i)
                && !store.takes.contains { $0.auditionID == auditionID && $0.sceneIndex == i }
        }
    }

    func skipCurrentScene(in audition: Audition) {
        skippedSceneIndices.insert(sceneIndex)
        if audition.scenes.indices.contains(sceneIndex) {
            let title = audition.scenes[sceneIndex].title
            if let optionalPiece = audition.pieces.first(where: { $0.kind == .scene && $0.title == title && $0.isOptional }) {
                store.markPieceDone(auditionID, pieceID: optionalPiece.id)
            }
        }
        reader.stop()
        readerAdvance?.cancel()
        timedAdvance?.cancel()
        if let next = nextUnshotScene(in: audition) {
            moveToScene(next)
        } else {
            finish(goTo: nil)
        }
    }

    func advancePastCameraPiece(_ kind: PieceKind, skipped: Bool = false) {
        guard let audition = store.audition(auditionID) else {
            finish(goTo: nil)
            return
        }
        if skipped {
            skippedCameraPieces.insert(kind)
            if let piece = audition.pieces.first(where: { $0.kind == kind && $0.isOptional }) {
                store.markPieceDone(auditionID, pieceID: piece.id)
            }
        }
        guard let updated = store.audition(auditionID), let next = nextCameraFlowPiece(in: updated) else {
            finish(goTo: nil)
            return
        }
        switch next.kind {
        case .slate: stage = .slate
        case .fullLength: stage = .fullLength
        case .scene:
            if let index = updated.scenes.firstIndex(where: { $0.title == next.title }) {
                moveToScene(index)
            } else {
                finish(goTo: nil)
            }
        case .headshot: finish(goTo: .headshots(for: auditionID))
        }
    }

    func nextCameraFlowPiece(in audition: Audition) -> Piece? {
        guard !audition.isPackageReady else { return nil }
        return audition.pieces.first { piece in
            guard !piece.isDone, !skippedCameraPieces.contains(piece.kind) else { return false }
            guard piece.kind == .scene else { return true }
            guard let index = audition.scenes.firstIndex(where: { $0.title == piece.title }) else { return false }
            return !skippedSceneIndices.contains(index)
        }
    }

    func moveToScene(_ next: Int) {
        markSceneDone()
        sceneIndex = next
        lineIndex = 0
        follower.reset()
        follower.setContextualStrings(speechContext(for: 0))
        stage = .scene
    }

    func markSceneDone() {
        guard store.takes.contains(where: { $0.auditionID == auditionID && $0.sceneIndex == sceneIndex }),
              let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return }
        store.markDone(.scene, in: auditionID, title: scenes[sceneIndex].title)
    }

    var readerGain: Float {
        switch readerVolume {
        case "Same as me": 1
        case "Much quieter": 0.35
        default: 0.6
        }
    }

    func startScene() {
        lineIndex = 0
        advanceAfterSceneSave = false
        follower.reset()
        follower.setContextualStrings(speechContext(for: 0))
        speakIfReader()
        scheduleTimedAdvance()
    }

    func handleCameraStateChange(_ newState: CameraController.State) {
        if newState == .recording {
            if stage == .scene {
                if camera.elapsed == 0 { startScene() } else { speakIfReader(); scheduleTimedAdvance() }
            }
        } else {
            stopReader()
            timedAdvance?.cancel()
            timedAdvance = nil
        }
    }

    func advanceLine() {
        Haptics.tick()
        stopReader()
        timedAdvance?.cancel()
        timedAdvance = nil
        readerAudioMissing = false
        follower.reset()
        guard let lines = sceneLines, lines.indices.contains(lineIndex) else { return }
        guard lineIndex + 1 < lines.count else {
            guard camera.state == .recording else { return }
            advanceAfterSceneSave = true
            cut()
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            lineIndex += 1
        }
        follower.setContextualStrings(speechContext(for: lineIndex))
        speakIfReader()
        scheduleTimedAdvance()
    }

    func speechContext(for index: Int) -> [String] {
        guard let lines = sceneLines, !lines.isEmpty else { return [] }
        let lower = max(0, index - 1)
        let upper = min(lines.count - 1, index + 1)
        let words = lines[lower...upper].flatMap { line in
            line.text.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 1 }
        }
        var hints = words
        if words.count > 1 {
            hints.append(contentsOf: zip(words, words.dropFirst()).map { "\($0) \($1)" })
        }
        return Array(hints.prefix(100))
    }

    func interpretTalkback(_ line: ScriptLine) {
        talkbackTask?.cancel()
        talkbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, camera.state == .recording, stage == .scene,
                  sceneLines?.indices.contains(lineIndex) == true,
                  SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: follower.transcript).count >= SpokenLineMatcher.requiredMatches(for: line.text) else { return }
            timedAdvance?.cancel()
            timedAdvance = nil
            advanceLine()
        }
    }

    func replayReaderBeforeCurrent() {
        guard let lines = sceneLines else { return }
        let previousReaderCount = lines[..<lineIndex].filter { !$0.isMine }.count
        guard previousReaderCount > 0 else { return }
        reader.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: previousReaderCount - 1, volume: readerGain)
    }

    func speakIfReader() {
        guard camera.state == .recording, let lines = sceneLines, lines.indices.contains(lineIndex), !lines[lineIndex].isMine else { return }
        readerAdvance?.cancel()
        readerAdvance = nil
        readerAudioMissing = false
        if lines[lineIndex].isSilentReactionCue {
            scheduleTimedAdvance()
            return
        }
        let readerIndex = lines[..<lineIndex].filter { !$0.isMine }.count
        guard reader.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerIndex, volume: readerGain) else {
            readerAudioMissing = true
            scheduleTimedAdvance()
            return
        }
        let delay = reader.duration + 0.45
        readerAdvance = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            advanceLine()
        }
    }

    func stopReader() {
        readerAdvance?.cancel()
        readerAdvance = nil
        reader.stop()
    }

    func scheduleTimedAdvance() {
        timedAdvance?.cancel()
        timedAdvance = nil
        guard camera.state == .recording, stage == .scene,
              let lines = sceneLines, lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        let hasSpokenWords = !line.text.split(separator: " ").map({ SpokenLineMatcher.cleanWord($0) }).filter({ !$0.isEmpty }).isEmpty
        if followVoice && line.isMine && hasSpokenWords { return }
        if followVoice && !line.isMine && !readerAudioMissing { return }

        let wordCount = max(1, line.text.split(separator: " ").count)
        let delay: Double
        if !hasSpokenWords || line.isSilentReactionCue {
            delay = 1.6
        } else if !line.isMine {
            delay = max(2.0, Double(wordCount) * 0.38 + 0.8)
        } else {
            delay = max(2.2, Double(wordCount) * 0.45 + 1.2)
        }
        timedAdvance = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, camera.state == .recording else { return }
            advanceLine()
        }
    }

    func start(at first: Stage) {
        stage = first
        camera.lockExposure()
    }

    func roll() {
        guard countdown == nil else { return }
        Task {
            if timerSeconds > 0 {
                for n in stride(from: timerSeconds, through: 1, by: -1) {
                    withAnimation(.easeOut(duration: 0.3)) { countdown = n }
                    Haptics.tick()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            withAnimation { countdown = nil }
            Haptics.impact(.heavy)
            camera.startRecording()
        }
    }

    func cut() {
        Haptics.impact(.medium)
        let cutStage = stage
        camera.stopRecording { url in saveRecording(url, from: cutStage) }
    }

    func saveRecording(_ recording: URL?, from cutStage: Stage) {
        let folder = "audition-\(auditionID.uuidString)"
        let failed = "Nothing was written to this iPhone. Record it again."
        switch cutStage {
        case .slate:
            guard let url = MediaStore.persist(recording, as: "slate-original.mov", in: folder) else {
                saveError = failed
                Haptics.warning()
                return
            }
            store.keepOriginalSlate(url, for: auditionID)
            store.markDone(.slate, in: auditionID)
            Haptics.success()
            stage = .slateDone
            isAnalyzingSlate = true
            Task {
                defer { isAnalyzingSlate = false }
                guard let suggestion = SilenceTrimmer.suggest(for: url),
                      let trimmed = await SilenceTrimmer.export(suggestion, from: url) else { return }
                slateTrimReview = SlateTrimReview(original: url, trimmed: trimmed, suggestion: suggestion)
            }
        case .fullLength:
            guard let url = MediaStore.persist(recording, as: "fulllength.mov", in: folder) else {
                saveError = failed
                Haptics.warning()
                return
            }
            store.setFullLengthVideo(url, for: auditionID)
            store.markDone(.fullLength, in: auditionID)
            Haptics.success()
            advancePastCameraPiece(.fullLength)
        case .scene:
            let number = store.nextTakeNumber(auditionID: auditionID, sceneIndex: sceneIndex)
            let takeID = UUID()
            guard let url = MediaStore.persist(recording, as: "take-\(number)-\(takeID.uuidString).mov", in: "\(folder)/scene-\(sceneIndex)") else {
                saveError = failed
                Haptics.warning()
                return
            }
            let take = Take(
                id: takeID,
                number: number,
                duration: camera.elapsed,
                recordedAt: .now,
                isCircled: false,
                notes: [],
                fileURL: url,
                auditionID: auditionID,
                sceneIndex: sceneIndex
            )
            store.addTake(take)
            takeNumber = number
            Haptics.success()
            if advanceAfterSceneSave, let audition = store.audition(auditionID),
               let next = nextUnshotScene(in: audition) {
                advanceAfterSceneSave = false
                moveToScene(next)
                return
            }
            advanceAfterSceneSave = false
            stage = .saved
        default: break
        }
    }

    func finish(goTo route: Route?) {
        markSceneDone()
        store.camera = nil
        dismiss()
        if let route {
            store.popTo(route)
        }
    }
}
