import SwiftUI

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
// Solo-only for MVP: the solo/multi-device picker and the whole pairing flow (connect, reconnect,
// disconnect) are cut. The framing-check job they partly existed for is covered by voice commands
// ("How do I look?"), and the prompter job is already covered by the solo flow's own prompter below.

struct ShootSetupView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var silenced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before you roll").font(.otLargeTitle)
                Text("Simple · one iPhone").font(.otCallout).foregroundStyle(OT.labelSecondary)
                Text("\(silenced ? 4 : 3) of 4 set").font(.otTitle)
                check("Camera", "Back camera · sharper", "Screen faces away — we talk you through it", ok: true)
                check("Hands-free", "Your voice + AirPods click", "“Action”, “Cut”, “Line?” · volume buttons on", ok: true)
                check("Microphone", "Kabir’s AirPods Pro", "Good level from your mark", ok: true)
                VStack(alignment: .leading, spacing: 8) {
                    check("Interruptions", "Calls and alerts can cut in", "A notification mid-scene throws Maya’s timing", ok: silenced)
                    if !silenced {
                        Button { silenced = true; Haptics.success() } label: { Label("Silence for this shoot", systemImage: "moon.fill") }
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
            VStack(spacing: 4) {
                Button { store.camera = .shoot(auditionID) } label: { Label("Set up by voice", systemImage: "waveform") }.buttonStyle(.otPrimary)
                Button("Start without voice") { store.camera = .shoot(auditionID) }
                    .font(.otHeadline).foregroundStyle(OT.labelPrimary).frame(maxWidth: .infinity, minHeight: 48)
            }
            .padding(.horizontal, OT.gutter).padding(.top, 8)
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
            if cmd == "action", camera.state == .ready { roll() }
            if cmd == "cut", camera.state == .recording { cut() }
        }
        .onDisappear { camera.stop(); follower.stop() }
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
        case .scene, .saved: return "SC 1 · TK \(takeNumber)  \(time)"
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
                       primary: ("Next: full length", { stage = .fullLength; store.markDone(.slate, in: a.id) }),
                       secondary: ("Redo", { stage = .slate }))
        case .fullLength:
            promptCard(eyebrow: "After the slate", text: "Head to feet, hold still")
        case .scene:
            let lines = a.scenes.first?.lines ?? []
            if lines.indices.contains(lineIndex) {
                promptCard(eyebrow: lines[lineIndex].isMine ? "\(lines[lineIndex].character) · you" : lines[lineIndex].character,
                           text: lines[lineIndex].text, mine: lines[lineIndex].isMine)
                    .onTapGesture { lineIndex = min(lineIndex + 1, lines.count - 1) }
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
            chip(nil, "4K · 30"); chip(nil, "1/60"); chip("lock.fill", "Exposure locked"); chip("internaldrive", "38 min")
        }
        .opacity(stage == .saved || stage == .slateDone ? 0 : 1)
    }

    private var bottomControls: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer()
            switch stage {
            case .check:
                Button("Go to your mark") { stage = .slate; camera.lockExposure() }.buttonStyle(.otPrimary).frame(width: 200)
            case .slateDone, .saved:
                Color.clear.frame(height: 78)
            default:
                RecordButton(isRecording: camera.state == .recording, holdToStop: stage == .scene) {
                    camera.state == .recording ? cut() : roll()
                }
            }
            Spacer()
            Button { } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundStyle(.white).frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle()) }
                .accessibilityLabel("Switch camera")
        }
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private func roll() {
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
        switch cutStage {
        case .slate:
            if let url = MediaStore.persist(recording, as: "slate.mov", in: folder) {
                store.setSlateVideo(url, for: auditionID)
            }
            stage = .slateDone
        case .fullLength:
            if let url = MediaStore.persist(recording, as: "fulllength.mov", in: folder) {
                store.setFullLengthVideo(url, for: auditionID)
            }
            store.markDone(.fullLength, in: auditionID)
            stage = .scene
        case .scene:
            let number = store.nextTakeNumber(auditionID: auditionID, sceneIndex: sceneIndex)
            if let url = MediaStore.persist(recording, as: "take-\(number).mov", in: "\(folder)/scene-\(sceneIndex)") {
                let take = Take(number: number, duration: camera.elapsed, recordedAt: .now, isCircled: false, notes: [],
                                 fileURL: url, auditionID: auditionID, sceneIndex: sceneIndex)
                store.addTake(take)
                takeNumber = number
            }
            stage = .saved
        default: break
        }
    }

    private func finish(goTo route: Route?) {
        store.markDone(.scene, in: auditionID)
        dismiss()
        if let route { store.push(route) } else { store.push(.auditionDetail(auditionID)) }
    }

    // MARK: Pieces

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
