import SwiftUI
import AVKit
import Speech

// MARK: - Record button (v2/Record Button · Ready / Rolling-hold)

/// Tap to start. While rolling it becomes hold-to-stop (0.8 s) so a stray tap can't end a take.
struct RecordButton: View {
    var isRecording: Bool
    var holdToStop: Bool = false
    var action: () -> Void
    @State private var holdProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
            if isRecording && holdToStop {
                Circle().trim(from: 0, to: holdProgress)
                    .stroke(OT.recRed, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 78, height: 78)
            }
            RoundedRectangle(cornerRadius: isRecording ? 8 : 32, style: .continuous)
                .fill(OT.recRed)
                .frame(width: isRecording ? 30 : 64, height: isRecording ? 30 : 64)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isRecording)
        .contentShape(Circle())
        .onTapGesture { if !(isRecording && holdToStop) { action() } }
        .onLongPressGesture(minimumDuration: 0.8, perform: {
            if isRecording && holdToStop { holdProgress = 0; action() }
        }, onPressingChanged: { pressing in
            guard isRecording && holdToStop else { return }
            withAnimation(pressing ? .linear(duration: 0.8) : .easeOut(duration: 0.2)) { holdProgress = pressing ? 1 : 0 }
        })
        .accessibilityLabel(isRecording ? (holdToStop ? "Stop recording, press and hold" : "Stop recording") : "Record")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 13c Before you roll
// Solo-only for MVP: the solo/multi-device picker and the whole pairing flow are cut. Framing is
// checked after the fact by Tape Check, and the prompter is the solo flow's own, below.

struct ShootSetupView: View {
    let auditionID: Audition.ID
    /// The scene to shoot, when the actor came from a particular one; otherwise the next one due.
    var scene: Int? = nil
    @Environment(AppStore.self) private var store

    private var shootScene: Int { scene ?? store.sceneToShoot(auditionID) }
    /// Focus/Do Not Disturb can't be read or set by an app, so this one is the actor's own tick.
    @State private var silenced = false

    private struct Check { var eyebrow: String; var title: String; var detail: String; var ok: Bool }

    /// Every row reflects the real state of this iPhone right now — nothing is assumed.
    private var checks: [Check] {
        var checks: [Check] = []
        checks.append(Check(eyebrow: "Camera", title: "Front camera ready",
                            detail: "", ok: true))

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            checks.append(Check(eyebrow: "Hands-free", title: "Say “Action” and “Cut”",
                                detail: "Or press a volume button, Camera Control, or your AirPods stem.", ok: true))
        case .notDetermined:
            checks.append(Check(eyebrow: "Hands-free", title: "Voice commands prompt at start",
                                detail: "", ok: true))
        default:
            checks.append(Check(eyebrow: "Hands-free", title: "Voice commands are off",
                                detail: "Enable Speech Recognition in Settings.", ok: false))
        }

        if AVAudioApplication.shared.recordPermission == .denied {
            checks.append(Check(eyebrow: "Microphone", title: "Microphone access is off",
                                detail: "Enable it in Settings.", ok: false))
        } else {
            let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
            let isHeadset = input.map { [.bluetoothHFP, .headsetMic].contains($0.portType) } ?? false
            checks.append(Check(eyebrow: "Microphone", title: input?.portName ?? "iPhone microphone",
                                detail: isHeadset ? "" : "Stay near the phone.", ok: true))
        }

        if let a = store.audition(auditionID), a.scenes.indices.contains(shootScene) {
            let readerLines = a.scenes[shootScene].lines.filter { !$0.isMine }
            let recorded = readerLines.indices.filter {
                FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: shootScene, line: $0).path)
            }.count
            if !readerLines.isEmpty {
                checks.append(Check(eyebrow: "Reader", title: "\(recorded) of \(readerLines.count) reader lines recorded",
                                    detail: recorded == readerLines.count ? "" : "Record the missing lines for playback.",
                                    ok: recorded == readerLines.count))
            }
        }

        if let minutes = CameraController.recordingMinutesLeft {
            checks.append(Check(eyebrow: "Storage", title: "About \(minutes) minutes of video free",
                                detail: minutes < 10 ? "Free up space before shooting." : "", ok: minutes >= 10))
        }

        checks.append(Check(eyebrow: "Interruptions", title: silenced ? "Silenced for this shoot" : "Calls and alerts can cut in",
                            detail: silenced ? "" : "Turn on Do Not Disturb in Control Centre.", ok: silenced))
        return checks
    }

    var body: some View {
        let rows = checks
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(title: "Shoot setup", backLabel: "Back", onBack: { store.pop() })
                    .padding(.top, 4)

                Text("Before you roll").font(.otLargeTitle)
                ForEach(rows, id: \.eyebrow) { c in
                    check(c.eyebrow, c.title, c.detail, ok: c.ok)
                    if c.eyebrow == "Reader", !c.ok {
                        Button { store.push(.recordReader(auditionID, sceneIndex: shootScene)) } label: { Label("Record the reader", systemImage: "mic") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    if c.eyebrow == "Interruptions", !silenced {
                        Button { silenced = true; Haptics.success() } label: { Label("I've turned on Do Not Disturb", systemImage: "moon.fill") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 160)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button { store.camera = .shoot(auditionID, scene: shootScene) } label: { Label("Open the camera", systemImage: "camera.fill") }
                .buttonStyle(.otPrimary)
                .padding(.horizontal, OT.gutter).padding(.vertical, 8)
                .background(OT.bgCanvas)
        }
    }

    private func check(_ eyebrow: String, _ title: String, _ detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(ok ? OT.accent : OT.warning).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                Text(title).font(.otHeadline)
                if !ok && !detail.isEmpty {
                    Text(detail).font(.otFootnote).foregroundStyle(OT.warning)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Camera flow: 15 check → 16 slate → 16c full length → 17 scene → 17.5 take saved

struct ShootFlow: View {
    enum Stage { case check, slate, slateDone, fullLength, scene, saved }

    let auditionID: Audition.ID
    /// Which scene to open on; nil picks the next one still to shoot.
    var initialScene: Int? = nil
    var initialStage: CameraFlow.ShootStart = .check
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var follower = SpeechFollower()
    @State private var cameraSpeaker = CameraGuidanceSpeaker()
    @State private var voiceAllowed = false
    @State private var stage: Stage = .check
    /// The scene being shot. Takes, reader lines and the checklist piece all follow it.
    @State private var sceneIndex = 0
    @State private var countdown: Int?
    @State private var timerEnabled = true
    @State private var pinchStartZoom: CGFloat?
    @State private var lineIndex = 0
    @State private var takeNumber = 1
    @State private var saveError: String?
    @State private var isAnalyzingSlate = false
    @State private var slateTrimReview: SlateTrimReview?
    /// Your own recorded reader lines, played during a take so they land under your voice.
    @State private var reader = ReaderTrackPlayer()
    @State private var readerAdvance: Task<Void, Never>?
    @State private var timedAdvance: Task<Void, Never>?
    @State private var readerAudioMissing = false
    @State private var talkbackTask: Task<Void, Never>?
    @AppStorage("readerVolume") private var readerVolume = "Quieter"
    // Teleprompter settings from Prepare — applied to the in-camera prompter.
    @AppStorage("prompter.size") private var prompterSize = 1
    @AppStorage("prompter.followVoice") private var followVoice = true
    @AppStorage("prompter.mirror") private var mirrorPrompter = false
    @AppStorage("camera.poseGuideEnabled") private var poseGuideEnabled = true
    @AppStorage("camera.gesturesEnabled") private var gesturesEnabled = false
    @AppStorage("camera.gestureHoldDuration") private var gestureHoldDuration = 1.2
    @State private var gestureHoldTask: Task<Void, Never>?
    @State private var lastGestureAction = Date.distantPast

    var body: some View {
        let a = store.audition(auditionID)
        ZStack {
            CameraBackground(controller: camera)
            if camera.state == .recording { RoundedRectangle(cornerRadius: 55).stroke(OT.recRed, lineWidth: 6).ignoresSafeArea() }

            VStack(spacing: 12) {
                topBar
                if let a { overlay(for: a) }
                Spacer()
                if let countdown {
                    Text("\(countdown)").font(.system(size: 160, weight: .bold)).foregroundStyle(.white)
                        .transition(.scale(scale: 1.3).combined(with: .opacity)).id(countdown)
                    Spacer()
                }
                hud
                bottomControls
            }
            .padding(.horizontal, OT.gutter)
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let start = pinchStartZoom ?? camera.zoomFactor
                    pinchStartZoom = start
                    camera.setZoomFactor(start * value)
                }
                .onEnded { _ in pinchStartZoom = nil }
        )
        .preferredColorScheme(.dark)
        .statusBarHidden(camera.state == .recording)
        .keepScreenAwake()
        .task {
            sceneIndex = initialScene ?? store.sceneToShoot(auditionID)
            stage = initialStage == .slate ? .slate : initialStage == .fullLength ? .fullLength : .check
            camera.wantsFaceGuidance = true   // live framing + light check on the "Camera check" screen
            camera.wantsBodyPoseGuidance = poseGuideEnabled
            camera.wantsHandGesture = gesturesEnabled && stage != .check
            if await CameraController.requestAccess() { camera.configure(position: .front) }
            voiceAllowed = await SpeechFollower.requestAccess()
            if voiceAllowed { follower.start() }
        }
        // The camera session reconfigures the shared audio session when it starts or flips; make sure
        // the listener is running again afterwards.
        .onChange(of: camera.state) { _, state in
            if state == .ready, voiceAllowed, !follower.isListening { follower.start() }
        }
        .onChange(of: cameraGuidanceKey) { _, key in
            guard stage == .check, camera.state == .ready, let key else { return }
            Task { @MainActor in
                let spoken = await OnDeviceIntelligence.cameraGuidance(fact: key) ?? key
                guard stage == .check, camera.state == .ready else { return }
                cameraSpeaker.speak(spoken)
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if (cmd?.word == "action" || cmd?.word == "now"), camera.state == .ready { roll() }
            if cmd?.word == "cut", camera.state == .recording { cut() }
        }
        // Volume buttons, Camera Control, and AirPods stem presses (camera remote) start and stop a
        // take, so the actor never has to walk back to the phone.
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            if camera.state == .recording { cut() }
            else if camera.state == .ready, [.slate, .fullLength, .scene].contains(stage) { roll() }
        }
        // The prompter follows your voice: once you've said your line, it moves on to the next one.
        .onChange(of: follower.transcript) { _, transcript in
            guard followVoice, stage == .scene, camera.state == .recording, let lines = sceneLines,
                  lines.indices.contains(lineIndex), lines[lineIndex].isMine,
                  SpokenLineMatcher.matchedWordIndices(in: lines[lineIndex].text, transcript: transcript).count >= SpokenLineMatcher.requiredMatches(for: lines[lineIndex].text) else { return }
            interpretTalkback(lines[lineIndex])
        }
        // Face detection is only for the pre-shoot check; don't spend CPU on it while filming.
        .onChange(of: stage) { _, newStage in camera.faceGuidanceActive = (newStage == .check) }
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
        .onDisappear { gestureHoldTask?.cancel(); talkbackTask?.cancel(); timedAdvance?.cancel(); cameraSpeaker.stop(); camera.stop(); follower.stop(); stopReader() }
        .alert("Couldn’t save that recording", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .sheet(item: $slateTrimReview) { review in
            SlateTrimReviewView(original: review.original, trimmed: review.trimmed,
                                removedLeading: review.suggestion.removedLeading,
                                removedTrailing: review.suggestion.removedTrailing,
                                keepTrimmed: {
                                    store.acceptSlateTrim(review.trimmed, for: auditionID)
                                    slateTrimReview = nil
                                }, keepOriginal: {
                                    try? FileManager.default.removeItem(at: review.trimmed)
                                    slateTrimReview = nil
                                })
        }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            HStack(spacing: 6) {
                if camera.state == .recording { Circle().fill(OT.recRed).frame(width: 8, height: 8) }
                Text(pillText).font(.otFootnote.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32).background(OT.cameraGlass, in: Capsule())
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var pillText: String {
        let t = Int(camera.elapsed)
        let time = String(format: "%02d:%02d", t / 60, t % 60)
        if camera.state == .paused { return "Paused  \(time)" }
        switch stage {
        case .check: return "Camera check"
        case .slate, .slateDone: return "Slate  \(time)"
        case .fullLength: return "Full length  \(time)"
        case .scene: return "SC \(sceneIndex + 1) · TK \(store.nextTakeNumber(auditionID: auditionID, sceneIndex: sceneIndex))  \(time)"
        case .saved: return "SC \(sceneIndex + 1) · TK \(takeNumber)  \(time)"
        }
    }

    @ViewBuilder private func overlay(for a: Audition) -> some View {
        switch stage {
        case .check:
            VStack(spacing: 8) {
                HStack {
                    Label("Pose guide", systemImage: "figure.stand").font(.otCaption.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Button {
                        poseGuideEnabled.toggle()
                        Haptics.tick()
                    } label: {
                        Text(poseGuideEnabled ? "On" : "Off")
                            .font(.otCaption.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(poseGuideEnabled ? OT.accent.opacity(0.85) : OT.cameraGlass, in: Capsule())
                    }
                    .accessibilityLabel("Pose guide \(poseGuideEnabled ? "on" : "off")")
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(.black.opacity(0.55), in: Capsule())
                ForEach(Array(liveChecks.enumerated()), id: \.offset) { _, row in
                    liveCheckRow(row.text, ok: row.ok)
                }
                if poseGuideEnabled { poseCoachRow }
            }
            scenePicker(a)
        case .slate:
            promptCard(eyebrow: "Slate · say it to the lens · ≈ 5 s", text: store.slate.spoken)
        case .slateDone:
            if isAnalyzingSlate {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Checking for long silent edges…").font(.otCallout).foregroundStyle(.white)
                }.padding(18).background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 20))
            } else {
                resultCard(title: "Slate’s done.", detail: "\(Int(camera.elapsed)) s · saved · opens every scene in \(a.project)",
                           primary: ("Next: full length", { stage = .fullLength }),
                           secondary: ("Redo", { stage = .slate }),
                           more: [("Skip full length — it’s optional", { stage = .scene })])
            }
        case .fullLength:
            promptCard(eyebrow: "Optional · after the slate", text: "Head to feet, hold still")
            if camera.state != .recording {
                Button("Skip full length") { stage = .scene }
                    .font(.otHeadline).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 44).background(OT.cameraGlass, in: Capsule())
            }
        case .scene:
            if camera.state != .recording { scenePicker(a) }
            let lines = sceneLines ?? []
            if lines.indices.contains(lineIndex) {
                let line = lines[lineIndex]
                let eyebrow: String = if line.isMine {
                    "\(line.character) · you"
                } else if readerAudioMissing {
                    "\(line.character) · no recording · tap to continue"
                } else {
                    line.character
                }
                promptCard(eyebrow: eyebrow, text: line.text, mine: line.isMine)
                    // Tap to move on early; swipe right to go back a line.
                    .onTapGesture { advanceLine() }
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width > 60 { stopReader(); lineIndex = max(0, lineIndex - 1); follower.reset() }
                        else if value.translation.width < -60 { advanceLine() }
                    })
            }
        case .saved:
            if let next = nextUnshotScene(in: a) {
                resultCard(title: "Take \(takeNumber), in the can.", detail: "\(Int(camera.elapsed)) s · \(a.scenes[next].title) is still to shoot",
                           primary: ("Next: \(a.scenes[next].title)", { moveToScene(next) }),
                           secondary: ("Go again", { lineIndex = 0; stage = .scene }),
                           more: [("Watch take \(takeNumber)", { finish(goTo: .takes(a.id)) }), ("Done for now", { finish(goTo: nil) })])
            } else {
                resultCard(title: "Take \(takeNumber), in the can.", detail: "\(Int(camera.elapsed)) s · saved on this iPhone",
                           primary: ("Watch take \(takeNumber)", { finish(goTo: .takes(a.id)) }),
                           secondary: ("Go again", { lineIndex = 0; stage = .scene }),
                           more: [("Done for now", { finish(goTo: nil) })])
            }
        }
    }

    /// Live pre-shoot check from the camera itself: face found, framing, distance and light.
    private var liveChecks: [(text: String, ok: Bool)] {
        guard camera.state == .ready else { return [("Starting the camera…", false)] }
        var rows: [(text: String, ok: Bool)] = []
        if let f = camera.face {
            rows.append(("Face in frame", true))
            if f.centerX < 0.4 { rows.append(("Off to the left — move right", false)) }
            else if f.centerX > 0.6 { rows.append(("Off to the right — move left", false)) }
            else { rows.append(("Centred", true)) }
            if f.centerY < 0.2 { rows.append(("Too much floor — tilt the phone up", false)) }
            else if f.centerY > 0.5 { rows.append(("Not enough headroom — tilt the phone down", false)) }
            else { rows.append(("Headroom looks right", true)) }
            if f.height < 0.1 { rows.append(("Too far away — move closer", false)) }
            else if f.height > 0.4 { rows.append(("Too close — step back", false)) }
            else { rows.append(("Good distance", true)) }
        } else {
            rows.append(("Can’t see your face — step into the frame", false))
        }

        if let light = camera.lightLevel {
            if light < 0.22 { rows.append(("Too dark — face a window or a lamp", false)) }
            else if light > 0.85 { rows.append(("Too bright — move away from direct light", false)) }
            else { rows.append(("Light is fine", true)) }
        }
        return rows
    }

    @ViewBuilder private var poseCoachRow: some View {
        if let pose = camera.bodyPose {
            if pose.shoulderCenterX < 0.42 {
                liveCheckRow("Move slightly right to center your shoulders", ok: false)
            } else if pose.shoulderCenterX > 0.58 {
                liveCheckRow("Move slightly left to center your shoulders", ok: false)
            } else if abs(pose.shoulderTiltDegrees) > 8 {
                liveCheckRow("Level your shoulders", ok: false)
            } else {
                liveCheckRow("Upper body centered · shoulders level", ok: true)
            }
        } else if camera.face != nil {
            liveCheckRow("Step back so both shoulders are visible", ok: false)
        } else {
            liveCheckRow("Pose guide is looking for your shoulders", ok: false)
        }
    }

    private var cameraGuidanceKey: String? {
        guard camera.state == .ready else { return nil }
        if camera.face == nil { return "Step into the frame so your face is visible." }
        if let face = camera.face {
            if face.centerX < 0.4 { return "Move a little to your right." }
            if face.centerX > 0.6 { return "Move a little to your left." }
            if face.centerY < 0.2 { return "Tilt the phone slightly down." }
            if face.centerY > 0.5 { return "Tilt the phone slightly up." }
            if face.height < 0.1 { return "Move closer to the phone." }
            if face.height > 0.4 { return "Step back from the phone." }
        }
        if let light = camera.lightLevel {
            if light < 0.22 { return "Face a window or a brighter light." }
            if light > 0.85 { return "Move away from the direct light." }
        }
        return nil
    }

    private func liveCheckRow(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? OT.success : OT.due)
            Text(text).font(.otCaption.weight(.semibold)).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var hud: some View {
        HStack(spacing: 6) {
            // Real values only: the session preset, whether exposure is actually locked, free space.
            chip(nil, "1080p · 30")
            chip(follower.isListening ? "mic.fill" : "mic.slash", follower.isListening ? "Listening" : "Voice off")
            if camera.isExposureLocked { chip("lock.fill", "Exposure locked") }
            if let minutes = CameraController.recordingMinutesLeft { chip("internaldrive", "\(minutes) min") }
            if gesturesEnabled && [.slate, .fullLength, .scene].contains(stage) {
                chip("hand.raised.fill", camera.state == .recording ? "Palm: pause" : "Palm: start / resume")
            }
        }
        .opacity(stage == .saved || stage == .slateDone ? 0 : 1)
    }

    private var bottomControls: some View {
        HStack {
            HStack(spacing: 8) {
                cameraChoice("\(zoomLabel)") { camera.cycleZoom() }
                    .disabled(camera.state != .ready || countdown != nil)
                cameraChoice(timerEnabled ? "Timer 3s" : "Timer off") { timerEnabled.toggle(); Haptics.tick() }
                    .disabled(camera.state == .recording || countdown != nil)
            }
            Spacer()
            switch stage {
            case .check:
                VStack(spacing: 10) {
                    Button("Go to your mark") { start(at: firstStage) }.buttonStyle(.otPrimary).frame(width: 200)
                    // Once the slate is in, the default skips to the scene — these keep the slate and
                    // the optional full length reachable without making them part of every reopen.
                    if firstStage == .scene {
                        HStack(spacing: 8) {
                            cameraChoice("Redo slate") { start(at: .slate) }
                            cameraChoice(store.audition(auditionID)?.fullLengthVideoURL != nil ? "Redo full length" : "Add full length") {
                                start(at: .fullLength)
                            }
                        }
                    }
                }
            case .slateDone, .saved:
                Color.clear.frame(height: 78)
            default:
                VStack(spacing: 8) {
                    if camera.state == .recording || camera.state == .paused {
                        HStack(spacing: 6) {
                            cameraChoice(camera.state == .paused ? "Resume" : "Pause") {
                                camera.state == .paused ? camera.resumeRecording() : camera.pauseRecording()
                            }
                            .disabled(countdown != nil)
                            cameraChoice("Finish") { cut() }
                        }
                    }
                    RecordButton(isRecording: camera.state == .recording, holdToStop: false) {
                        switch camera.state {
                        case .recording: cut()
                        case .paused: camera.resumeRecording()
                        default: roll()
                        }
                    }
                }
            }
            Spacer()
            Button {
                camera.switchCamera()
                // Exposure was locked on the old camera; lock the new one too once you're past the check.
                if stage != .check { camera.lockExposure() }
                Haptics.tick()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundStyle(.white).frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
            }
            .disabled(camera.state != .ready || countdown != nil)
            .opacity(camera.state == .recording ? 0 : 1)
            .accessibilityLabel("Switch camera")
        }
        .padding(.bottom, 8)
    }

    private var zoomLabel: String {
        camera.zoomFactor == 1 ? "1×" : String(format: "%.1f×", camera.zoomFactor)
    }

    /// Picks up where this audition left off: once the slate is in, "Next" goes straight to the scene
    /// rather than making the actor re-shoot the slate.
    private var firstStage: Stage {
        let slateDone = store.audition(auditionID)?.pieces.first(where: { $0.kind == .slate })?.isDone ?? false
        return slateDone ? .scene : .slate
    }

    // MARK: Actions

    private var sceneLines: [ScriptLine]? {
        guard let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return nil }
        return scenes[sceneIndex].lines
    }

    /// Scene chips, shown only when the sides have more than one scene and nothing is rolling.
    @ViewBuilder private func scenePicker(_ a: Audition) -> some View {
        if a.scenes.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(a.scenes.indices, id: \.self) { i in
                        let shot = store.takes.contains { $0.auditionID == auditionID && $0.sceneIndex == i }
                        Button { pickScene(i) } label: {
                            HStack(spacing: 4) {
                                if shot { Image(systemName: "checkmark").font(.caption2) }
                                Text(a.scenes[i].title).font(.otCaption.weight(.semibold))
                            }
                            .foregroundStyle(i == sceneIndex ? OT.labelOnAccent : .white)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(i == sceneIndex ? AnyShapeStyle(OT.accent) : AnyShapeStyle(Color.black.opacity(0.55)), in: Capsule())
                        }
                        .accessibilityLabel("\(a.scenes[i].title)\(shot ? ", has a take" : "")")
                        .accessibilityAddTraits(i == sceneIndex ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func pickScene(_ i: Int) {
        guard camera.state != .recording, countdown == nil else { return }
        stopReader()
        sceneIndex = i
        lineIndex = 0
        follower.reset()
        Haptics.tick()
    }

    /// The next scene (after this one, wrapping round) that has no take yet.
    private func nextUnshotScene(in a: Audition) -> Int? {
        let order = a.scenes.indices.filter { $0 > sceneIndex } + a.scenes.indices.filter { $0 < sceneIndex }
        return order.first { i in !store.takes.contains { $0.auditionID == auditionID && $0.sceneIndex == i } }
    }

    /// On to another scene: this one is ticked off (it has a take), the prompter starts from the top.
    private func moveToScene(_ next: Int) {
        markSceneDone()
        sceneIndex = next
        lineIndex = 0
        follower.reset()
        stage = .scene
    }

    private func markSceneDone() {
        // Only tick the scene off when a take for it actually exists.
        guard store.takes.contains(where: { $0.auditionID == auditionID && $0.sceneIndex == sceneIndex }),
              let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return }
        store.markDone(.scene, in: auditionID, title: scenes[sceneIndex].title)
    }

    private var readerGain: Float {
        switch readerVolume {
        case "Same as me": 1
        case "Much quieter": 0.35
        default: 0.6
        }
    }

    /// Rolling on a scene: start from the top, and if the scene opens on the reader, play them in.
    private func startScene() {
        lineIndex = 0
        follower.reset()
        speakIfReader()
        scheduleTimedAdvance()
    }

    private func handleCameraStateChange(_ newState: CameraController.State) {
        if newState == .recording {
            if stage == .scene {
                if camera.elapsed == 0 { startScene() } else { speakIfReader() }
            }
        } else {
            stopReader()
        }
    }

    private func advanceLine() {
        stopReader()
        timedAdvance?.cancel()
        timedAdvance = nil
        readerAudioMissing = false
        follower.reset()
        guard let lines = sceneLines, lineIndex + 1 < lines.count else { return }
        lineIndex += 1
        speakIfReader()
        scheduleTimedAdvance()
    }

    private func interpretTalkback(_ line: ScriptLine) {
        let spoken = follower.transcript
        talkbackTask?.cancel()
        talkbackTask = Task { @MainActor in
            // Let a short pause settle the transcript before spending time on an on-device model
            // request. Continuous speech updates cancel this task, coalescing them into one query.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let intent = await OnDeviceIntelligence.talkbackIntent(spoken: spoken, expectedLine: line.text)
            guard !Task.isCancelled, camera.state == .recording, sceneLines?.indices.contains(lineIndex) == true,
                  SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: follower.transcript).count >= SpokenLineMatcher.requiredMatches(for: line.text) else { return }
            switch intent {
            case .lineComplete, .nextLine:
                advanceLine()
            case .repeatLine:
                replayReaderBeforeCurrent()
            case .pause:
                break
            case .unknown:
                advanceLine()
            }
        }
    }

    private func replayReaderBeforeCurrent() {
        guard let lines = sceneLines else { return }
        let previousReaderCount = lines[..<lineIndex].filter { !$0.isMine }.count
        guard previousReaderCount > 0 else { return }
        reader.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: previousReaderCount - 1, volume: readerGain)
    }

    /// Plays your recorded reader line at the chosen volume, then moves on to your next line once it
    /// has had time to land (the same pacing as Run Lines).
    private func speakIfReader() {
        guard camera.state == .recording, let lines = sceneLines, lines.indices.contains(lineIndex), !lines[lineIndex].isMine else { return }
        let readerIndex = lines[..<lineIndex].filter { !$0.isMine }.count
        readerAdvance?.cancel()
        readerAdvance = nil
        readerAudioMissing = false
        guard reader.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerIndex, volume: readerGain) else {
            readerAudioMissing = true
            scheduleTimedAdvance()
            return
        }
        let delay = (reader.duration ?? (Double(lines[lineIndex].text.count) * 0.06)) + 0.45
        readerAdvance = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            advanceLine()
        }
    }

    private func stopReader() {
        readerAdvance?.cancel()
        readerAdvance = nil
        reader.stop()
    }

    /// Timed mode is deliberately simple: it advances only while filming, leaves enough time to
    /// read each line, and can still be overridden by a tap or swipe. Reader recordings use their
    /// actual duration; absent reader audio receives the same timed allowance.
    private func scheduleTimedAdvance() {
        timedAdvance?.cancel()
        timedAdvance = nil
        guard !followVoice, camera.state == .recording, stage == .scene,
              let lines = sceneLines, lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        if !line.isMine, !readerAudioMissing { return }
        let delay = max(2.2, Double(line.text.count) * 0.075 + 1.1)
        timedAdvance = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, !followVoice, camera.state == .recording else { return }
            advanceLine()
        }
    }

    private func start(at first: Stage) {
        stage = first
        camera.lockExposure()
    }

    private func roll() {
        // A tap or "Action" during the countdown must not start a second, overlapping one.
        guard countdown == nil else { return }
        Task {
            if timerEnabled {
                for n in [3, 2, 1] {
                    withAnimation(.easeOut(duration: 0.3)) { countdown = n }
                    Haptics.tick()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            withAnimation { countdown = nil }
            camera.startRecording()
        }
    }

    private func cut() {
        let cutStage = stage
        // Wait for the file to be finalized — reading `lastRecording` right after stopping would pick
        // up nothing (first clip) or the previous clip.
        camera.stopRecording { url in saveRecording(url, from: cutStage) }
    }

    private func saveRecording(_ recording: URL?, from cutStage: Stage) {
        let folder = "audition-\(auditionID.uuidString)"
        // A piece only moves forward (and is only ticked off) once its file is really on disk; on a
        // failed save the actor stays on the same stage to record it again.
        let failed = "Nothing was written to this iPhone. Record it again."
        switch cutStage {
        case .slate:
            guard let url = MediaStore.persist(recording, as: "slate-original.mov", in: folder) else { saveError = failed; return }
            store.keepOriginalSlate(url, for: auditionID)
            // Done as soon as it's on disk, so closing the camera here doesn't lose the progress.
            store.markDone(.slate, in: auditionID)
            stage = .slateDone
            isAnalyzingSlate = true
            Task {
                defer { isAnalyzingSlate = false }
                guard let suggestion = SilenceTrimmer.suggest(for: url),
                      let trimmed = await SilenceTrimmer.export(suggestion, from: url) else { return }
                slateTrimReview = SlateTrimReview(original: url, trimmed: trimmed, suggestion: suggestion)
            }
        case .fullLength:
            guard let url = MediaStore.persist(recording, as: "fulllength.mov", in: folder) else { saveError = failed; return }
            store.setFullLengthVideo(url, for: auditionID)
            store.markDone(.fullLength, in: auditionID)
            stage = .scene
        case .scene:
            let number = store.nextTakeNumber(auditionID: auditionID, sceneIndex: sceneIndex)
            let takeID = UUID()
            // The take's own ID in the file name means a new take can never replace another's file.
            guard let url = MediaStore.persist(recording, as: "take-\(number)-\(takeID.uuidString).mov", in: "\(folder)/scene-\(sceneIndex)") else {
                saveError = failed; return
            }
            let take = Take(id: takeID, number: number, duration: camera.elapsed, recordedAt: .now, isCircled: false, notes: [],
                             fileURL: url, auditionID: auditionID, sceneIndex: sceneIndex)
            store.addTake(take)
            takeNumber = number
            stage = .saved
        default: break
        }
    }

    private func finish(goTo route: Route?) {
        markSceneDone()
        dismiss()
        if let route { store.push(route) } else { store.push(.auditionDetail(auditionID)) }
    }

    // MARK: Pieces

    private func cameraChoice(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.otFootnote.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 36).background(OT.cameraGlass, in: Capsule())
    }

    private func chip(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text).font(.otCaption.weight(.semibold))
        }
        .foregroundStyle(text == "Exposure locked" ? OT.due : .white)
        .padding(.horizontal, 9).frame(height: 26).background(.black.opacity(0.55), in: Capsule())
    }

    private func promptCard(eyebrow: String, text: String, mine: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased()).font(.otCaption.weight(.semibold)).foregroundStyle(mine ? OT.cameraLabel2 : OT.reader)
            Text(text).font(.system(size: [20, 26, 34][min(max(prompterSize, 0), 2)], weight: .bold))
                .foregroundStyle(mine ? Color.white : Color.white.opacity(0.7))
                .scaleEffect(x: mirrorPrompter ? -1 : 1, y: 1)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func resultCard(title: String, detail: String, primary: (String, () -> Void), secondary: (String, () -> Void), more: [(String, () -> Void)] = []) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.otTitle).foregroundStyle(OT.labelPrimary)
            Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
            HStack {
                Button(secondary.0, action: secondary.1).buttonStyle(.otSecondary)
                Button(primary.0, action: primary.1).buttonStyle(.otPrimary)
            }
            ForEach(Array(more.enumerated()), id: \.offset) { _, item in
                Button(item.0, action: item.1).font(.otHeadline).foregroundStyle(OT.accent)
            }
        }
        .padding(18)
        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 140)
    }
}

private struct SlateTrimReview: Identifiable {
    let id = UUID()
    let original: URL
    let trimmed: URL
    let suggestion: SilenceTrimmer.Suggestion
}

private struct SlateTrimReviewView: View {
    let original: URL
    let trimmed: URL
    let removedLeading: Double
    let removedTrailing: Double
    let keepTrimmed: () -> Void
    let keepOriginal: () -> Void
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review slate trim").font(.otLargeTitle)
                Text("Long silent edges were trimmed with a short pause kept before and after. Your original is saved and can be restored from Package.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)
                VideoPlayer(player: AVPlayer(url: trimmed))
                    .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 18))
                Text("Removed about \(removedLeading, specifier: "%.1f") s at the start and \(removedTrailing, specifier: "%.1f") s at the end.")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                Button("Keep trimmed slate", action: keepTrimmed).buttonStyle(.otPrimary)
                Button("Use original slate", action: keepOriginal).buttonStyle(.otSecondary)
                Spacer(minLength: 0)
            }
            .padding(OT.gutter)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Use original") { keepOriginal() } } }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}
