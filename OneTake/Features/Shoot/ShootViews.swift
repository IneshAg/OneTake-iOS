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
    @Environment(AppStore.self) private var store
    /// Focus/Do Not Disturb can't be read or set by an app, so this one is the actor's own tick.
    @State private var silenced = false

    private struct Check { var eyebrow: String; var title: String; var detail: String; var ok: Bool }

    /// Every row reflects the real state of this iPhone right now — nothing is assumed.
    private var checks: [Check] {
        var checks: [Check] = []
        checks.append(Check(eyebrow: "Camera", title: "Front camera · you can watch yourself",
                            detail: "Switch to the back camera in the shot if you'd rather — it's sharper.", ok: true))

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            checks.append(Check(eyebrow: "Hands-free", title: "Say “Action” and “Cut”",
                                detail: "Or press a volume button, Camera Control, or your AirPods stem.", ok: true))
        case .notDetermined:
            checks.append(Check(eyebrow: "Hands-free", title: "Voice commands ask permission when you start",
                                detail: "Volume buttons, Camera Control and AirPods work either way.", ok: true))
        default:
            checks.append(Check(eyebrow: "Hands-free", title: "Voice commands are off",
                                detail: "Turn on Speech Recognition for OneTake in Settings — volume buttons still work.", ok: false))
        }

        if AVAudioApplication.shared.recordPermission == .denied {
            checks.append(Check(eyebrow: "Microphone", title: "Microphone access is off",
                                detail: "Turn it on for OneTake in Settings, or the tape will be silent.", ok: false))
        } else {
            let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
            let isHeadset = input.map { [.bluetoothHFP, .headsetMic].contains($0.portType) } ?? false
            checks.append(Check(eyebrow: "Microphone", title: input?.portName ?? "iPhone microphone",
                                detail: isHeadset ? "Close to your mouth — good for sound." : "Stay within an arm's length or two of the phone.", ok: true))
        }

        if let a = store.audition(auditionID), let scene = a.scenes.first {
            let readerLines = scene.lines.filter { !$0.isMine }
            let recorded = readerLines.indices.filter {
                FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: $0).path)
            }.count
            if !readerLines.isEmpty {
                checks.append(Check(eyebrow: "Reader", title: "\(recorded) of \(readerLines.count) reader lines recorded",
                                    detail: recorded == readerLines.count ? "They play under your takes." : "Unrecorded lines stay silent — you'll get a pause instead.",
                                    ok: recorded == readerLines.count))
            }
        }

        if let minutes = CameraController.recordingMinutesLeft {
            checks.append(Check(eyebrow: "Storage", title: "About \(minutes) minutes of video free",
                                detail: minutes < 10 ? "Free up space before you shoot." : "Plenty for a few takes.", ok: minutes >= 10))
        }

        checks.append(Check(eyebrow: "Interruptions", title: silenced ? "Silenced for this shoot" : "Calls and alerts can cut in",
                            detail: silenced ? "Do Not Disturb is on." : "Turn on Do Not Disturb from Control Centre.", ok: silenced))
        return checks
    }

    var body: some View {
        let rows = checks
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before you roll").font(.otLargeTitle)
                Text("Simple · one iPhone").font(.otCallout).foregroundStyle(OT.labelSecondary)
                Text("\(rows.filter(\.ok).count) of \(rows.count) set").font(.otTitle)
                ForEach(rows, id: \.eyebrow) { c in
                    check(c.eyebrow, c.title, c.detail, ok: c.ok)
                    if c.eyebrow == "Reader", !c.ok {
                        Button { store.push(.recordReader(auditionID)) } label: { Label("Record the reader", systemImage: "mic") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    if c.eyebrow == "Interruptions", !silenced {
                        Button { silenced = true; Haptics.success() } label: { Label("I've turned on Do Not Disturb", systemImage: "moon.fill") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                }
                Label("Every take saves while you record — even if a call gets through.", systemImage: "checkmark.shield")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 160)
        }
        .otCanvas()
        .safeAreaInset(edge: .bottom) {
            Button { store.camera = .shoot(auditionID) } label: { Label("Open the camera", systemImage: "camera.fill") }
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
                Text(detail).font(.otFootnote).foregroundStyle(ok ? OT.labelSecondary : OT.warning)
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
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var follower = SpeechFollower()
    @State private var stage: Stage = .check
    @State private var countdown: Int?
    @State private var lineIndex = 0
    @State private var takeNumber = 1
    @State private var saveError: String?
    /// Your own recorded reader lines, played during a take so they land under your voice.
    @State private var reader = ReaderTrackPlayer()
    @State private var readerAdvance: Task<Void, Never>?
    @AppStorage("readerVolume") private var readerVolume = "Quieter"

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
        .preferredColorScheme(.dark)
        .statusBarHidden(camera.state == .recording)
        .keepScreenAwake()
        .task {
            if await CameraController.requestAccess() { camera.configure(position: .front) }
            if await SpeechFollower.requestAccess() { follower.start() }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if cmd?.word == "action", camera.state == .ready { roll() }
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
        .onChange(of: follower.spokenWordCount) { _, count in
            guard stage == .scene, camera.state == .recording, let lines = sceneLines, lines.indices.contains(lineIndex),
                  lines[lineIndex].isMine, count >= lines[lineIndex].text.split(separator: " ").count else { return }
            advanceLine()
        }
        .onChange(of: camera.state) { _, state in
            if state == .recording, stage == .scene { startScene() } else if state != .recording { stopReader() }
        }
        .onDisappear { camera.stop(); follower.stop(); stopReader() }
        .alert("Couldn’t save that recording", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
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
            HStack(spacing: 6) { ForEach(["Framing", "Eyeline", "Light", "Sound"], id: \.self) { chip("checkmark", $0) } }
        case .slate:
            promptCard(eyebrow: "Slate · say it to the lens · ≈ 5 s", text: store.slate.spoken)
        case .slateDone:
            resultCard(title: "Slate’s done.", detail: "0:05 · saved · opens every scene in \(a.project)",
                       primary: ("Next: full length", { stage = .fullLength }),
                       secondary: ("Redo", { stage = .slate }),
                       tertiary: ("Skip full length — it’s optional", { stage = .scene }))
        case .fullLength:
            promptCard(eyebrow: "Optional · after the slate", text: "Head to feet, hold still")
            if camera.state != .recording {
                Button("Skip full length") { stage = .scene }
                    .font(.otHeadline).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 44).background(OT.cameraGlass, in: Capsule())
            }
        case .scene:
            let lines = a.scenes.first?.lines ?? []
            if lines.indices.contains(lineIndex) {
                promptCard(eyebrow: lines[lineIndex].isMine ? "\(lines[lineIndex].character) · you" : lines[lineIndex].character,
                           text: lines[lineIndex].text, mine: lines[lineIndex].isMine)
                    // Tap to move on early; swipe right to go back a line.
                    .onTapGesture { advanceLine() }
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width > 60 { stopReader(); lineIndex = max(0, lineIndex - 1); follower.reset() }
                        else if value.translation.width < -60 { advanceLine() }
                    })
            }
        case .saved:
            resultCard(title: "Take \(takeNumber), in the can.", detail: "\(Int(camera.elapsed)) s · reader track under your voice",
                       primary: ("Watch take \(takeNumber)", { finish(goTo: .takes(a.id)) }),
                       secondary: ("Go again", { lineIndex = 0; stage = .scene }),
                       tertiary: ("Done for now", { finish(goTo: nil) }))
        }
    }

    private var hud: some View {
        HStack(spacing: 6) {
            // Real values only: the session preset, whether exposure is actually locked, free space.
            chip(nil, "1080p · 30")
            if camera.isExposureLocked { chip("lock.fill", "Exposure locked") }
            if let minutes = CameraController.recordingMinutesLeft { chip("internaldrive", "\(minutes) min") }
        }
        .opacity(stage == .saved || stage == .slateDone ? 0 : 1)
    }

    private var bottomControls: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
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
                RecordButton(isRecording: camera.state == .recording, holdToStop: stage == .scene) {
                    camera.state == .recording ? cut() : roll()
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

    /// Picks up where this audition left off: once the slate is in, "Next" goes straight to the scene
    /// rather than making the actor re-shoot the slate.
    private var firstStage: Stage {
        let slateDone = store.audition(auditionID)?.pieces.first(where: { $0.kind == .slate })?.isDone ?? false
        return slateDone ? .scene : .slate
    }

    // MARK: Actions

    private var sceneLines: [ScriptLine]? { store.audition(auditionID)?.scenes.first?.lines }

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
    }

    private func advanceLine() {
        stopReader()
        follower.reset()
        guard let lines = sceneLines, lineIndex + 1 < lines.count else { return }
        lineIndex += 1
        speakIfReader()
    }

    /// Plays your recorded reader line at the chosen volume, then moves on to your next line once it
    /// has had time to land (the same pacing as Run Lines).
    private func speakIfReader() {
        guard camera.state == .recording, let lines = sceneLines, lines.indices.contains(lineIndex), !lines[lineIndex].isMine else { return }
        let readerIndex = lines[..<lineIndex].filter { !$0.isMine }.count
        reader.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerIndex, volume: readerGain)
        let delay = Double(lines[lineIndex].text.count) * 0.06 + 0.8
        readerAdvance?.cancel()
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

    private func start(at first: Stage) {
        stage = first
        camera.lockExposure()
    }

    private func roll() {
        // A tap or "Action" during the countdown must not start a second, overlapping one.
        guard countdown == nil else { return }
        Task {
            for n in [3, 2, 1] { withAnimation(.easeOut(duration: 0.3)) { countdown = n }; Haptics.tick(); try? await Task.sleep(for: .seconds(1)) }
            withAnimation { countdown = nil }
            camera.startRecording()
        }
    }

    /// Note: recording currently always targets scene 0 — there's no scene picker ahead of "Before
    /// you roll" yet, so a second scene can't be shot independently through this flow. Flagged as a
    /// known gap rather than silently dropping extra scenes' takes into the same bucket.
    private let sceneIndex = 0

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
            guard let url = MediaStore.persist(recording, as: "slate.mov", in: folder) else { saveError = failed; return }
            store.setSlateVideo(url, for: auditionID)
            // Done as soon as it's on disk, so closing the camera here doesn't lose the progress.
            store.markDone(.slate, in: auditionID)
            stage = .slateDone
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
        // Only tick the scene off when a take for it actually exists.
        if store.takes.contains(where: { $0.auditionID == auditionID && $0.sceneIndex == sceneIndex }) {
            let title = store.audition(auditionID)?.scenes.indices.contains(sceneIndex) == true
                ? store.audition(auditionID)?.scenes[sceneIndex].title : nil
            store.markDone(.scene, in: auditionID, title: title)
        }
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
            Text(text).font(.system(size: 24, weight: .bold)).foregroundStyle(mine ? Color.white : Color.white.opacity(0.7))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func resultCard(title: String, detail: String, primary: (String, () -> Void), secondary: (String, () -> Void), tertiary: (String, () -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.otTitle).foregroundStyle(OT.labelPrimary)
            Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
            HStack {
                Button(secondary.0, action: secondary.1).buttonStyle(.otSecondary)
                Button(primary.0, action: primary.1).buttonStyle(.otPrimary)
            }
            if let tertiary { Button(tertiary.0, action: tertiary.1).font(.otHeadline).foregroundStyle(OT.accent) }
        }
        .padding(18)
        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 140)
    }
}
