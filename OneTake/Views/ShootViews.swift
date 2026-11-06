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
        .onTapGesture {
            if !(isRecording && holdToStop) {
                if isRecording {
                    Haptics.impact(.medium)
                } else {
                    Haptics.impact(.heavy)
                }
                action()
            }
        }
        .onLongPressGesture(minimumDuration: 0.8, perform: {
            if isRecording && holdToStop {
                holdProgress = 0
                Haptics.impact(.medium)
                action()
            }
        }, onPressingChanged: { pressing in
            guard isRecording && holdToStop else { return }
            if pressing { Haptics.tick() }
            withAnimation(pressing ? .linear(duration: 0.8) : .easeOut(duration: 0.2)) { holdProgress = pressing ? 1 : 0 }
        })
        .accessibilityLabel(isRecording ? (holdToStop ? "Stop recording, press and hold" : "Stop recording") : "Record")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Dedicated "Following your voice" Floating Glass Pill (Figma y: 668)

struct VoiceFollowingPill: View {
    var isListening: Bool
    var isActorLine: Bool
    var characterName: String
    var isFollowingVoice: Bool
    var isReaderPlaying: Bool
    @State private var waveAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            if isActorLine {
                if isFollowingVoice {
                    // Audio waveform visualization
                    HStack(spacing: 2.5) {
                        ForEach(0..<4) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(isListening ? OT.prompterGold : Color.white.opacity(0.4))
                                .frame(width: 2.5, height: barHeight(for: index))
                        }
                    }
                    .frame(width: 16, height: 16)

                    Text(isListening ? "Following your voice" : "Voice follower paused")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isListening ? OT.prompterGold : Color.white.opacity(0.8))
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Timed auto-advance")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else {
                Image(systemName: isReaderPlaying ? "speaker.wave.2.fill" : "speaker.wave.1")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OT.reader)
                Text(characterName.isEmpty ? "Reader speaking" : "\(characterName) speaking")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OT.reader)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isActorLine && isFollowingVoice && isListening
                                ? OT.prompterGold.opacity(0.35)
                                : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                waveAnimating = true
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isListening else { return 4 }
        let heights: [(CGFloat, CGFloat)] = [
            (5, 13),
            (11, 6),
            (15, 8),
            (7, 14)
        ]
        let (minH, maxH) = heights[index % heights.count]
        return waveAnimating ? maxH : minH
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
    @AppStorage("speech.recognitionLocale") private var speechRecognitionLocale = SpeechFollower.defaultAccentIdentifier

    private var shootScene: Int { scene ?? store.sceneToShoot(auditionID) }
    /// Focus/Do Not Disturb can't be read or set by an app, so this one is the actor's own tick.
    @State private var silenced = false

    private struct Check { var eyebrow: String; var title: String; var detail: String; var ok: Bool }

    /// Every row reflects the real state of this iPhone right now — nothing is assumed.
    private var checks: [Check] {
        var checks: [Check] = []

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

        _ = store.readerTrackVersion
        if let a = store.audition(auditionID), a.scenes.indices.contains(shootScene) {
            let readerLines = a.scenes[shootScene].lines.filter { !$0.isMine }
            let readerName = readerLines.first?.character.capitalized ?? "Reader"
            let specificReaderLines = readerLines.filter { $0.character.caseInsensitiveCompare(readerName) == .orderedSame }
            let recorded = specificReaderLines.indices.filter {
                ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: shootScene, line: $0)
            }.count
            if !specificReaderLines.isEmpty {
                checks.append(Check(eyebrow: "Reader", title: "\(recorded) of \(specificReaderLines.count) reader lines recorded",
                                    detail: recorded == specificReaderLines.count ? "" : "Record the missing lines for playback.",
                                    ok: recorded == specificReaderLines.count))
            }
        }

        checks.append(Check(eyebrow: "Interruptions", title: silenced ? "Silenced for this shoot" : "Calls and alerts can cut in",
                            detail: silenced ? "" : "Turn on Do Not Disturb in Control Centre.", ok: silenced))
        return checks
    }

    var body: some View {
        let rows = checks
        let audition = store.audition(auditionID)
        let sceneTitle = audition.flatMap {
            $0.scenes.indices.contains(shootScene) ? $0.scenes[shootScene].title : nil
        } ?? "Scene \(shootScene + 1)"
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(title: "Scene setup", backLabel: "Back", onBack: { store.pop() })
                    .padding(.top, 4)

                Text(sceneTitle).font(.otLargeTitle)
                Text("Check your reader and microphone before recording this scene.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Speech accent")
                        .font(.otFootnote.weight(.medium)).foregroundStyle(OT.labelSecondary)
                    Picker("Speech accent", selection: $speechRecognitionLocale) {
                        ForEach(SpeechFollower.availableEnglishAccents) { accent in
                            Text(accent.title).tag(accent.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Choose the English accent closest to your pronunciation.")
                        .font(.otCaption).foregroundStyle(OT.labelTertiary)
                }
                .padding(14)
                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                ForEach(rows, id: \.eyebrow) { c in
                    check(c.eyebrow, c.title, c.detail, ok: c.ok)
                    if c.eyebrow == "Reader", !c.ok {
                        Button { store.push(.recordReader(auditionID, sceneIndex: shootScene)) } label: { Label("Record the reader", systemImage: "mic") }
                            .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 12))
                    }
                    if c.eyebrow == "Interruptions", !silenced {
                        Button { silenced = true; Haptics.success() } label: { Label("I've turned on Do Not Disturb", systemImage: "moon.fill") }
                            .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 12))
                    }
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 160)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !SpeechFollower.availableEnglishAccents.contains(where: { $0.id == speechRecognitionLocale }) {
                speechRecognitionLocale = SpeechFollower.defaultAccentIdentifier
            }
        }
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
    @State private var timerSeconds = 3
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
    @AppStorage("camera.voiceGuidanceEnabled") private var voiceGuidanceEnabled = true
    @AppStorage("camera.poseGuideEnabled") private var poseGuideEnabled = true
    @AppStorage("camera.gesturesEnabled") private var gesturesEnabled = false
    @AppStorage("camera.gestureHoldDuration") private var gestureHoldDuration = 1.2
    @State private var gestureHoldTask: Task<Void, Never>?
    @State private var lastGestureAction = Date.distantPast
    @AppStorage("camera.recordingResolution") private var recordingResolution = CameraResolution.hd1080.rawValue
    @State private var advanceAfterSceneSave = false

    var body: some View {
        let a = store.audition(auditionID)
        ZStack {
            CameraBackground(controller: camera)
                .ignoresSafeArea()
            if camera.state == .recording { RoundedRectangle(cornerRadius: 55).stroke(OT.recRed, lineWidth: 6).ignoresSafeArea() }

            VStack(spacing: 12) {
                topBar
                if camera.isExposureLocked && camera.state == .ready {
                    Label("AE/AF LOCKED · Tap to unlock", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OT.prompterGold)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(OT.cameraGlass, in: Capsule())
                }
                if camera.state == .recording {
                    HStack(spacing: 5) {
                        Capsule().fill(OT.prompterGold).frame(width: 3, height: 14)
                        Text("LOOK AT LENS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(OT.prompterGold)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Color.black.opacity(0.65), in: Capsule())
                }
                if let a { overlay(for: a) }
                Spacer()
                if let countdown {
                    Text("\(countdown)").font(.system(size: 160, weight: .bold)).foregroundStyle(.white)
                        .transition(.scale(scale: 1.3).combined(with: .opacity)).id(countdown)
                    Spacer()
                }
                voiceStatusPill
                voiceCommandStatus
                sceneActionBar
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
            follower.setContextualStrings(speechContext(for: 0))
            camera.wantsFaceGuidance = true   // live framing + light check on the "Camera check" screen
            camera.wantsBodyPoseGuidance = poseGuideEnabled
            camera.wantsHandGesture = gesturesEnabled && stage != .check
            if await CameraController.requestAccess() {
                let resolution = CameraResolution(rawValue: recordingResolution) ?? .hd1080
                camera.configure(position: .front, resolution: resolution)
            }
            voiceAllowed = await SpeechFollower.requestAccess()
            if voiceAllowed { follower.start() }
        }
        // The camera session reconfigures the shared audio session when it starts or flips; make sure
        // the listener is running again afterwards.
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
            if (cmd?.word == "action" || cmd?.word == "now"), camera.state == .ready,
               [.slate, .fullLength, .scene].contains(stage) { roll() }
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
                  lines.indices.contains(lineIndex) else { return }
            let line = lines[lineIndex]
            if line.isMine || readerAudioMissing {
                let required = SpokenLineMatcher.requiredMatches(for: line.text)
                if required > 0 && SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: transcript).count >= required {
                    interpretTalkback(line)
                }
            }
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
            if camera.state == .recording {
                Color.clear.frame(width: 44, height: 44)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            Spacer()
            HStack(spacing: 6) {
                if camera.state == .recording { Circle().fill(OT.recRed).frame(width: 8, height: 8) }
                Text(pillText).font(.otFootnote.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32).background(OT.cameraGlass, in: Capsule())
            Spacer()
            if camera.state == .recording {
                Color.clear.frame(width: 44, height: 44)
            } else {
                HStack(spacing: 5) {
                    timerMenu
                    Button {
                        voiceGuidanceEnabled.toggle()
                        Haptics.tick()
                        if voiceGuidanceEnabled {
                            cameraSpeaker.speak("Voice guidance on", minInterval: 0.1)
                        } else {
                            cameraSpeaker.stop()
                        }
                    } label: {
                        Image(systemName: voiceGuidanceEnabled ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(OT.cameraGlass, in: Circle())
                    }
                    .accessibilityLabel(voiceGuidanceEnabled ? "Mute voice guidance" : "Turn on voice guidance")
                    topBarTrailing
                }
            }
        }
    }

    private var timerMenu: some View {
        Menu {
            ForEach([0, 3, 5, 10], id: \.self) { seconds in
                Button {
                    timerSeconds = seconds
                    Haptics.tick()
                } label: {
                    if timerSeconds == seconds {
                        Label(seconds == 0 ? "Timer off" : "\(seconds) seconds", systemImage: "checkmark")
                    } else {
                        Text(seconds == 0 ? "Timer off" : "\(seconds) seconds")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                if timerSeconds > 0 { Text("\(timerSeconds)s").font(.system(size: 11, weight: .bold)) }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(timerSeconds > 0 ? OT.prompterGold : .white)
            .frame(width: 44, height: 44)
            .background(OT.cameraGlass, in: Circle())
            .contentShape(Circle())
        }
        .disabled(camera.state == .recording || countdown != nil)
        .accessibilityLabel(timerSeconds == 0 ? "Set recording countdown" : "Recording countdown, \(timerSeconds) seconds")
    }

    @ViewBuilder
    private var topBarTrailing: some View {
        let hasPreview = store.currentPath.contains(where: {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        })
        let hasTapeCheck = store.currentPath.contains(where: {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        })

        if hasPreview {
            Button("Preview") { finish(goTo: .preview(auditionID)) }
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if hasTapeCheck {
            Button("Tape check") { finish(goTo: .tapeCheck(auditionID)) }
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            switch stage {
            case .slate:
                Button("Skip") {
                    let a = store.audition(auditionID)
                    stage = a?.asks.contains("Full length") == true ? .fullLength : .scene
                }
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .fullLength:
                Button("Skip") { stage = .scene }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .scene:
                let sceneTakes = store.takes.filter { $0.auditionID == auditionID && ($0.sceneIndex ?? 0) == sceneIndex }
                if !sceneTakes.isEmpty {
                    Button("Takes (\(sceneTakes.count))") {
                        finish(goTo: .takes(auditionID, sceneIndex: sceneIndex))
                    }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let a = store.audition(auditionID), let next = nextUnshotScene(in: a) {
                    Button("Skip") { moveToScene(next) }
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            default:
                Color.clear.frame(width: 44, height: 44)
            }
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
                Text(firstStage == .slate ? "Ready to record your slate" : "Ready for \(sceneTitle(in: a))")
                    .font(.otHeadline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(firstStage == .slate
                     ? "Keep your face centered and say your name, height, and city."
                     : "Keep your eyeline near the lens. Your scene and reader cues are ready below.")
                    .font(.otFootnote).foregroundStyle(.white.opacity(0.76))
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .background(poseGuideEnabled ? AnyShapeStyle(OT.accent.opacity(0.85)) : AnyShapeStyle(OT.cameraGlass), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            slateDoneOverlay(for: a)
        case .fullLength:
            promptCard(eyebrow: "Optional · after the slate", text: "Head to feet, hold still")
        case .scene:
            if camera.state != .recording { scenePicker(a) }
            let lines = sceneLines ?? []
            if !lines.isEmpty {
                SidesPrompterView(
                    lines: lines,
                    currentIndex: lineIndex,
                    spokenTranscript: follower.transcript,
                    prompterSize: prompterSize,
                    mirror: mirrorPrompter,
                    readerIsPlaying: reader.isPlaying,
                    readerAudioMissing: readerAudioMissing,
                    onAdvance: { advanceLine() },
                    onPrevious: {
                        stopReader()
                        lineIndex = max(0, lineIndex - 1)
                        follower.reset()
                    },
                    onCycleSize: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            prompterSize = (prompterSize + 1) % 3
                        }
                        Haptics.tick()
                    }
                )
            }
        case .saved:
            savedOverlay(for: a)
        }
    }

    @ViewBuilder
    private func slateDoneOverlay(for a: Audition) -> some View {
        if isAnalyzingSlate {
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Checking for long silent edges…").font(.otCallout).foregroundStyle(.white)
            }.padding(18).background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 20))
        } else {
            let hasPreview = store.currentPath.contains {
                if case .preview(let id) = $0, id == auditionID { return true }
                return false
            }
            resultCard(title: "Slate’s done.", detail: "\(Int(camera.elapsed)) s · saved · opens every scene in \(a.project)",
                       primary: slateDonePrimaryAction(for: a),
                       secondary: ("Redo slate", { stage = .slate }),
                       more: hasPreview ? [("Check the tape", { finish(goTo: .tapeCheck(a.id)) })] : [])
        }
    }

    private func slateDonePrimaryAction(for a: Audition) -> (String, () -> Void) {
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasPreview {
            return ("Back to preview", { finish(goTo: .preview(a.id)) })
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasTapeCheck {
            return ("Back to tape check", { finish(goTo: .tapeCheck(a.id)) })
        }
        if a.asks.contains("Full length") && store.audition(auditionID)?.fullLengthVideoURL == nil {
            return ("Next: full length", { stage = .fullLength })
        }
        if let unshot = nextUnshotScene(in: a) {
            return ("Next: \(a.scenes[unshot].title)", { moveToScene(unshot) })
        }
        return ("Check the tape", { finish(goTo: .tapeCheck(a.id)) })
    }

    private func isSceneOptional(title: String, in a: Audition) -> Bool {
        for piece in a.pieces {
            if piece.kind == .scene && piece.title == title {
                return piece.isOptional
            }
        }
        return false
    }

    private func savedPrimaryAction(for a: Audition) -> (String, () -> Void) {
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasPreview {
            return ("Back to preview", { finish(goTo: .preview(a.id)) })
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasTapeCheck {
            return ("Back to tape check", { finish(goTo: .tapeCheck(a.id)) })
        }
        return ("Review takes", { finish(goTo: .takes(a.id, sceneIndex: sceneIndex)) })
    }

    @ViewBuilder
    private func savedOverlay(for a: Audition) -> some View {
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }

        if let next = nextUnshotScene(in: a) {
            let nextTitle = a.scenes[next].title
            let isOpt = isSceneOptional(title: nextTitle, in: a)
            let primaryTitle = isOpt ? "Next: \(nextTitle) (Optional)" : "Next: \(nextTitle)"
            let moreActions: [(String, () -> Void)] = [
                ("Watch take \(takeNumber)", { finish(goTo: .takes(a.id, sceneIndex: sceneIndex)) }),
                hasPreview ? ("Back to preview", { finish(goTo: .preview(a.id)) }) : nil,
                hasTapeCheck ? ("Back to tape check", { finish(goTo: .tapeCheck(a.id)) }) : nil,
                ("Done for now", { finish(goTo: nil) })
            ].compactMap { $0 }

            resultCard(title: "Take \(takeNumber), in the can.", detail: "\(Int(camera.elapsed)) s · \(nextTitle) is still to shoot",
                       primary: (primaryTitle, { moveToScene(next) }),
                       secondary: ("Go again", { lineIndex = 0; stage = .scene }),
                       more: moreActions)
        } else {
            resultCard(title: "Take \(takeNumber), in the can.", detail: "\(Int(camera.elapsed)) s · saved on this iPhone",
                       primary: savedPrimaryAction(for: a),
                       secondary: ("Go again", { lineIndex = 0; stage = .scene }),
                       more: [
                        ("Check the tape", { finish(goTo: .tapeCheck(a.id)) }),
                        ("Done for now", { finish(goTo: nil) })
                       ])
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

    @ViewBuilder
    private var voiceStatusPill: some View {
        if stage == .scene, camera.state == .recording,
           let lines = sceneLines, lines.indices.contains(lineIndex) {
            let cur = lines[lineIndex]
            VoiceFollowingPill(
                isListening: follower.isListening,
                isActorLine: cur.isMine,
                characterName: cur.character,
                isFollowingVoice: followVoice,
                isReaderPlaying: reader.isPlaying
            )
            .padding(.bottom, 2)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder private var voiceCommandStatus: some View {
        if [.slate, .fullLength, .scene].contains(stage), camera.state == .ready {
            Label(
                follower.isListening ? "Say Action to start · Cut to stop" : (voiceAllowed ? "Voice commands unavailable" : "Allow speech and microphone access"),
                systemImage: follower.isListening ? "waveform" : "mic.slash"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(follower.isListening ? OT.success : OT.due)
            .padding(.horizontal, 12).frame(height: 30)
            .background(.black.opacity(0.58), in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var hud: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(camera.supportedResolutions) { resolution in
                    Button {
                        recordingResolution = resolution.rawValue
                        camera.setResolution(resolution)
                        Haptics.tick()
                    } label: {
                        if camera.currentResolution == resolution {
                            Label(resolution.title, systemImage: "checkmark")
                        } else {
                            Text(resolution.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "video").font(.caption2)
                    Text("\(camera.currentResolution.title) · 30").font(.otCaption.weight(.semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9).frame(height: 26).background(.black.opacity(0.55), in: Capsule())
            }
            .disabled(camera.state != .ready || countdown != nil)
            .accessibilityLabel("Recording resolution, \(camera.currentResolution.title)")

            if gesturesEnabled && [.slate, .fullLength, .scene].contains(stage) {
                chip("hand.raised.fill", camera.state == .recording ? "Palm: pause" : "Palm: start / resume")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(stage == .saved || stage == .slateDone ? 0 : 1)
    }

    @ViewBuilder
    private var sceneActionBar: some View {
        if stage == .scene, let lines = sceneLines, !lines.isEmpty {
            HStack(spacing: 8) {
                Button {
                    advanceLine()
                    Haptics.tick()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                        Text("Next line").font(.otFootnote.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        prompterSize = (prompterSize + 1) % 3
                    }
                    Haptics.tick()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size").font(.caption)
                        Text(["Regular", "Big", "Huge"][prompterSize]).font(.otCaption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var bottomControls: some View {
        ZStack(alignment: .center) {
            // Symmetrical secondary controls layer: 44x44 circular buttons on each side
            HStack(alignment: .center) {
                Button {
                    camera.cycleZoom()
                } label: {
                    Text(zoomLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(OT.cameraGlass, in: Circle())
                }
                .disabled(camera.state != .ready || countdown != nil)
                .accessibilityLabel("Zoom \(zoomLabel)")

                Spacer()

                Button {
                    camera.switchCamera()
                    // Exposure was locked on the old camera; lock the new one too once you're past the check.
                    if stage != .check { camera.lockExposure() }
                    Haptics.tick()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(OT.cameraGlass, in: Circle())
                }
                .disabled(camera.state != .ready || countdown != nil)
                .opacity(camera.state == .recording ? 0 : 1)
                .accessibilityLabel("Switch camera")
            }

            // Primary action: RecordButton or Go to your mark — guaranteed horizontally centered!
            switch stage {
            case .check:
                VStack(spacing: 10) {
                    Button("Go to your mark") { start(at: firstStage) }
                        .buttonStyle(.otPrimary)
                        .frame(width: 200)
                    // Once the slate is in, the default skips to the scene — these keep the slate and
                    // the optional full length reachable without making them part of every reopen.
                    if firstStage == .scene {
                        HStack(spacing: 8) {
                            cameraChoice(store.audition(auditionID)?.slateVideoURL != nil ? "Redo slate" : "Record slate") { start(at: .slate) }
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
                        cameraChoice(camera.state == .paused ? "Resume" : "Pause") {
                            camera.state == .paused ? camera.resumeRecording() : camera.pauseRecording()
                        }
                        .disabled(countdown != nil)
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
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var zoomLabel: String {
        camera.zoomFactor == 1 ? "1×" : String(format: "%.1f×", camera.zoomFactor)
    }

    /// Picks up where this audition left off: once the slate is in, or if slate is optional,
    /// "Go to your mark" goes straight to the scene rather than forcing the actor into the slate camera.
    private var firstStage: Stage {
        let slatePiece = store.audition(auditionID)?.pieces.first(where: { $0.kind == .slate })
        let slateDone = slatePiece?.isDone ?? false
        let slateRequired = !(slatePiece?.isOptional ?? true)
        if slateRequired && !slateDone {
            return .slate
        }
        return .scene
    }

    private func sceneTitle(in audition: Audition) -> String {
        guard audition.scenes.indices.contains(sceneIndex) else { return "Scene \(sceneIndex + 1)" }
        return audition.scenes[sceneIndex].title
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
                            .background(i == sceneIndex ? AnyShapeStyle(OT.accent) : AnyShapeStyle(Color.black.opacity(0.55)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        follower.setContextualStrings(speechContext(for: 0))
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
        follower.setContextualStrings(speechContext(for: 0))
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
        advanceAfterSceneSave = false
        follower.reset()
        follower.setContextualStrings(speechContext(for: 0))
        speakIfReader()
        scheduleTimedAdvance()
    }

    private func handleCameraStateChange(_ newState: CameraController.State) {
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

    private func advanceLine() {
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

    /// Speech gets the current and adjacent script wording as vocabulary hints, which helps it
    /// recognize character names and less common dialogue across different English accents.
    private func speechContext(for index: Int) -> [String] {
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

    private func interpretTalkback(_ line: ScriptLine) {
        talkbackTask?.cancel()
        talkbackTask = Task { @MainActor in
            // Natural 300ms pause after speaking before advancing to next line
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, camera.state == .recording, stage == .scene,
                  sceneLines?.indices.contains(lineIndex) == true,
                  SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: follower.transcript).count >= SpokenLineMatcher.requiredMatches(for: line.text) else { return }
            timedAdvance?.cancel()
            timedAdvance = nil
            advanceLine()
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
        let delay = reader.duration + 0.45
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

    /// Schedules automatic line advance:
    /// - In timed mode: advances every line based on word length.
    /// - In voice-following mode: automatically advances reader lines that have no recorded audio,
    ///   or lines without spoken words (silent reactions, punctuation like "?"), so the prompter rolls naturally.
    private func scheduleTimedAdvance() {
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

    private func start(at first: Stage) {
        stage = first
        camera.lockExposure()
    }

    private func roll() {
        // A tap or "Action" during the countdown must not start a second, overlapping one.
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

    private func cut() {
        Haptics.impact(.medium)
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
            guard let url = MediaStore.persist(recording, as: "slate-original.mov", in: folder) else {
                saveError = failed
                Haptics.warning()
                return
            }
            store.keepOriginalSlate(url, for: auditionID)
            // Done as soon as it's on disk, so closing the camera here doesn't lose the progress.
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
            stage = .scene
        case .scene:
            let number = store.nextTakeNumber(auditionID: auditionID, sceneIndex: sceneIndex)
            let takeID = UUID()
            // The take's own ID in the file name means a new take can never replace another's file.
            guard let url = MediaStore.persist(recording, as: "take-\(number)-\(takeID.uuidString).mov", in: "\(folder)/scene-\(sceneIndex)") else {
                saveError = failed
                Haptics.warning()
                return
            }
            let take = Take(id: takeID, number: number, duration: camera.elapsed, recordedAt: .now, isCircled: false, notes: [],
                             fileURL: url, auditionID: auditionID, sceneIndex: sceneIndex)
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

    private func finish(goTo route: Route?) {
        markSceneDone()
        store.camera = nil
        dismiss()
        if let route {
            store.popTo(route)
        }
    }

    // MARK: Pieces

    private func cameraChoice(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.otFootnote.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 36).background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chip(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text).font(.otCaption.weight(.semibold))
        }
        .foregroundStyle(text == "Exposure locked" ? OT.due : .white)
        .padding(.horizontal, 9).frame(height: 26).background(.black.opacity(0.55), in: Capsule())
    }

    @ViewBuilder
    private func promptCard(eyebrow: String, text: String, mine: Bool = true) -> some View {
        let spokenWords = mine ? SpokenLineMatcher.matchedWordIndices(in: text, transcript: follower.transcript) : []
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(mine ? OT.prompterGold : OT.reader)
            highlightedPrompterText(text, matchedWords: spokenWords, mine: mine)
                .font(.system(size: [16, 19, 23][min(max(prompterSize, 0), 2)], weight: .semibold))
                .scaleEffect(x: mirrorPrompter ? -1 : 1, y: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    /// Spoken words turn to prompter gold (#FFCC00) as speech recognition hears them (matching Figma).
    private func highlightedPrompterText(_ text: String, matchedWords: Set<Int>, mine: Bool) -> Text {
        let words = text.split(separator: " ")
        var result = Text("")
        for (index, word) in words.enumerated() {
            let piece = Text(String(word) + (index < words.count - 1 ? " " : ""))
            if mine && matchedWords.contains(index) {
                result = result + piece.foregroundColor(OT.prompterGold)
            } else if mine {
                result = result + piece.foregroundColor(.white)
            } else {
                result = result + piece.foregroundColor(Color.white.opacity(0.8))
            }
        }
        return result
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button("Use original", action: keepOriginal)
                    .font(.otHeadline)
                    .foregroundStyle(OT.accent)
            }
            .padding(.top, 16)

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
        .padding(.horizontal, OT.gutter)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}

// MARK: - Sides Teleprompter (mirrors Figma 17_Recording.html / 17.2_RecYourLine.html / 24e_PracticeRecording.html)

struct SidesPrompterView: View {
    let lines: [ScriptLine]
    let currentIndex: Int
    var spokenTranscript: String = ""
    var prompterSize: Int = 1 // 0: Regular, 1: Big, 2: Huge
    var mirror: Bool = false
    var readerIsPlaying: Bool = false
    var readerAudioMissing: Bool = false
    var displayMode: StandaloneDisplay = .full
    var revealedLines: Set<ScriptLine.ID> = []
    var onAdvance: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onToggleReveal: ((ScriptLine.ID) -> Void)? = nil
    var onCycleSize: (() -> Void)? = nil

    private var currentLine: ScriptLine? {
        lines.indices.contains(currentIndex) ? lines[currentIndex] : nil
    }

    private var prevLine: ScriptLine? {
        currentIndex > 0 && lines.indices.contains(currentIndex - 1) ? lines[currentIndex - 1] : nil
    }

    private var nextLine: ScriptLine? {
        currentIndex + 1 < lines.count ? lines[currentIndex + 1] : nil
    }

    private var fontSize: CGFloat {
        switch prompterSize {
        case 0: return 18  // Regular: compact, clean & focused
        case 2: return 38  // Huge: massive font for tripod / distance reading
        default: return 26 // Big: standard comfortable prompter
        }
    }

    private var prompterMaxHeight: CGFloat {
        switch prompterSize {
        case 0: return 118  // Regular: ultra-compact, leaves camera framing completely clear
        case 2: return 280  // Huge: spacious box to fit large 38pt text without cramping
        default: return 195 // Big: standard height
        }
    }

    private var progress: Double {
        guard !lines.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(lines.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: prompterSize == 0 ? 6 : 10) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: prompterSize == 0 ? 6 : 12) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            let isCurrent = (index == currentIndex)
                            let isPast = (index < currentIndex)

                            VStack(alignment: .leading, spacing: prompterSize == 0 ? 3 : 6) {
                                // Header tag
                                HStack(spacing: 8) {
                                    Text(line.isMine ? "\(line.character.uppercased()) · YOU" : line.character.uppercased())
                                        .font(.system(size: isCurrent ? (prompterSize == 0 ? 12 : 13) : 11, weight: .bold, design: .monospaced))
                                        .tracking(0.8)
                                        .foregroundStyle(isCurrent ? (line.isMine ? OT.prompterGold : OT.reader) : Color.white.opacity(0.40))

                                    if isCurrent {
                                        if !line.isMine {
                                            if readerIsPlaying {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "waveform")
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Text("Reading")
                                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                }
                                                .foregroundStyle(OT.reader)
                                            } else if readerAudioMissing {
                                                Text("No audio · auto-playing")
                                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                    .foregroundStyle(OT.due)
                                            }
                                        }
                                    }

                                    Spacer()

                                    if isCurrent {
                                        // Clickable prompter size badge right on the prompter line header
                                        if let onCycleSize {
                                            Button {
                                                onCycleSize()
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "textformat.size")
                                                        .font(.system(size: 9, weight: .bold))
                                                    Text(["Regular", "Big", "Huge"][min(max(prompterSize, 0), 2)])
                                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                }
                                                .foregroundStyle(Color.white.opacity(0.88))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(Color.white.opacity(0.16), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        Text("\(index + 1) of \(lines.count)")
                                            .font(.system(size: prompterSize == 0 ? 11 : 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(0.50))
                                    }
                                }

                                // Dialogue content
                                if isCurrent {
                                    if line.isMine {
                                        let matchedIndices = SpokenLineMatcher.matchedWordIndices(in: line.text, transcript: spokenTranscript)
                                        let isRev = revealedLines.contains(line.id)
                                        if line.isSilentReactionCue {
                                            SilentReactionCue()
                                        } else {
                                            attributedPromptText(line.text, matchedIndices: matchedIndices, displayMode: displayMode, isRevealed: isRev)
                                                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                                .shadow(
                                                    color: matchedIndices.isEmpty ? .clear : OT.prompterGold.opacity(0.65),
                                                    radius: matchedIndices.isEmpty ? 0 : 7
                                                )
                                                .scaleEffect(x: mirror ? -1 : 1, y: 1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        if displayMode != .full && !line.isSilentReactionCue {
                                            Button {
                                                onToggleReveal?(line.id)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: isRev ? "eye.slash" : "eye")
                                                    Text(isRev ? "Hide hint" : displayMode == .firstLetters ? "Show full line hint" : "Reveal line hint")
                                                }
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(OT.prompterGold)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 4)
                                                .background(Color.white.opacity(0.14), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.top, 2)
                                        }
                                    } else {
                                        Text(line.text)
                                            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                                            .italic()
                                            .foregroundStyle(Color.white.opacity(0.88))
                                            .scaleEffect(x: mirror ? -1 : 1, y: 1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else if isPast {
                                    Text(line.isSilentReactionCue ? "Silent reaction" : line.text)
                                        .font(.system(size: prompterSize == 0 ? 11 : 12, weight: .regular, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.25))
                                        .lineLimit(1)
                                } else {
                                    // Upcoming lines left below the active line (compact peek)
                                    let isImmediateNext = (index == currentIndex + 1)
                                    let nextLimit = isImmediateNext ? (prompterSize == 0 ? 1 : 2) : 1
                                    let nextOpacity = isImmediateNext ? 0.55 : 0.20
                                    if line.isMine && displayMode == .firstLetters {
                                        Text(promptFirstLettersString(line.text))
                                            .font(.system(size: prompterSize == 0 ? 12 : 13, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(nextOpacity))
                                            .lineLimit(nextLimit)
                                    } else if line.isMine && displayMode == .hideMine && !revealedLines.contains(line.id) {
                                        Text(String(repeating: "• ", count: min(line.text.split(separator: " ").count, 8)))
                                            .font(.system(size: prompterSize == 0 ? 12 : 13, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(nextOpacity))
                                            .lineLimit(1)
                                    } else {
                                        Text(line.isSilentReactionCue ? "Silent reaction" : line.text)
                                            .font(.system(size: prompterSize == 0 ? 12 : 13, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(nextOpacity))
                                            .lineLimit(nextLimit)
                                    }
                                }
                            }
                            .id("prompter_line_\(index)")
                            .padding(.vertical, isCurrent ? (prompterSize == 0 ? 2 : 4) : 1)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, prompterMaxHeight * 0.85)
                }
                .frame(maxHeight: prompterMaxHeight)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.02),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: currentIndex) { _, newIndex in
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
                        proxy.scrollTo("prompter_line_\(newIndex)", anchor: .top)
                    }
                }
                .onAppear {
                    proxy.scrollTo("prompter_line_\(currentIndex)", anchor: .top)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 3)
                    Capsule().fill(Color.white)
                        .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 3)
                }
            }
            .frame(height: 3)
            .padding(.top, 6)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onAdvance() }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width > 60 { onPrevious() }
                else if value.translation.width < -60 { onAdvance() }
            }
        )
    }

    private func promptFirstLettersString(_ text: String) -> String {
        text.split(separator: " ").map { w in
            guard let f = w.first else { return "" }
            let punct = w.filter { $0.isPunctuation }
            return String(f) + "—" + (punct.isEmpty ? "" : String(punct))
        }.joined(separator: " ")
    }

    private func attributedPromptText(_ text: String, matchedIndices: Set<Int>, displayMode: StandaloneDisplay = .full, isRevealed: Bool = false) -> Text {
        let words = text.split(separator: " ").map(String.init)
        var result = Text("")
        for (idx, word) in words.enumerated() {
            let isMatched = matchedIndices.contains(idx)
            let displayText: String
            switch displayMode {
            case .full:
                displayText = word
            case .firstLetters:
                if isRevealed {
                    displayText = word
                } else {
                    let first = word.first.map(String.init) ?? ""
                    let punct = word.filter { $0.isPunctuation }
                    displayText = first + "—" + (punct.isEmpty ? "" : String(punct))
                }
            case .hideMine:
                if isRevealed || isMatched {
                    displayText = word
                } else {
                    let punct = word.filter { $0.isPunctuation }
                    let dots = String(repeating: "•", count: max(2, min(word.count, 5)))
                    displayText = dots + (punct.isEmpty ? "" : String(punct))
                }
            }
            let space = (idx < words.count - 1 ? " " : "")
            let wordText = Text(displayText + space)
            if isMatched {
                result = result + wordText.foregroundColor(OT.prompterGold).fontWeight(.heavy)
            } else {
                result = result + wordText.foregroundColor(.white.opacity(displayMode == .hideMine && !isRevealed ? 0.55 : 1.0))
            }
        }
        return result
    }
}
