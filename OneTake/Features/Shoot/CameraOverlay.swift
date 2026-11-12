import SwiftUI
import OneTakeUI

// MARK: - Camera Overlay, HUD & Stage Presentation

extension ShootFlow {
    // MARK: Bars

    var topBar: some View {
        HStack {
            if camera.state == .recording {
                Color.clear.frame(width: 44, height: 44) // ot-lint:allow
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(Color.white) // ot-lint:allow
                        .frame(width: 44, height: 44) // ot-lint:allow
                        .background(OT.cameraGlass, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            Spacer()
            HStack(spacing: OTSpace.xs) {
                if camera.state == .recording {
                    Circle().fill(OT.recRed).frame(width: 8, height: 8) // ot-lint:allow
                }
                Text(pillText)
                    .font(.otFootnote.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.white) // ot-lint:allow
            .padding(.horizontal, OTSpace.m)
            .frame(height: 32) // ot-lint:allow
            .background(OT.cameraGlass, in: Capsule())

            Spacer()

            if camera.state == .recording {
                Color.clear.frame(width: 44, height: 44) // ot-lint:allow
            } else {
                if stage == .check {
                    HStack(spacing: 5) { // ot-lint:allow
                        timerMenu
                        handsFreeControlsMenu
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
                                .font(.system(size: 14, weight: .semibold)) // ot-lint:allow
                                .foregroundStyle(Color.white) // ot-lint:allow
                                .frame(width: 38, height: 38) // ot-lint:allow
                                .background(OT.cameraGlass, in: Circle())
                        }
                        .accessibilityLabel(voiceGuidanceEnabled ? "Mute voice guidance" : "Turn on voice guidance")
                        topBarTrailing
                    }
                } else {
                    topBarTrailing
                }
            }
        }
    }

    var timerMenu: some View {
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
            HStack(spacing: 3) { // ot-lint:allow
                Image(systemName: "timer")
                if timerSeconds > 0 {
                    Text("\(timerSeconds)s").font(.system(size: 11, weight: .bold)) // ot-lint:allow
                }
            }
            .font(.system(size: 14, weight: .semibold)) // ot-lint:allow
            .foregroundStyle(timerSeconds > 0 ? OT.prompterGold : Color.white) // ot-lint:allow
            .frame(width: 44, height: 44) // ot-lint:allow
            .background(OT.cameraGlass, in: Circle())
            .contentShape(Circle())
        }
        .disabled(camera.state == .recording || countdown != nil)
        .accessibilityLabel(timerSeconds == 0 ? "Set recording countdown" : "Recording countdown, \(timerSeconds) seconds")
    }

    @ViewBuilder
    var topBarTrailing: some View {
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
                .foregroundStyle(Color.white) // ot-lint:allow
                .padding(.horizontal, OTSpace.m)
                .frame(height: 36) // ot-lint:allow
                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
        } else if hasTapeCheck {
            Button("Tape check") { finish(goTo: .tapeCheck(auditionID)) }
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(Color.white) // ot-lint:allow
                .padding(.horizontal, OTSpace.m)
                .frame(height: 36) // ot-lint:allow
                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
        } else {
            switch stage {
            case .slate:
                Button("Skip") { advancePastCameraPiece(.slate, skipped: true) }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .padding(.horizontal, OTSpace.m)
                    .frame(height: 36) // ot-lint:allow
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
            case .fullLength:
                Button("Skip") { advancePastCameraPiece(.fullLength, skipped: true) }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .padding(.horizontal, OTSpace.m)
                    .frame(height: 36) // ot-lint:allow
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
            case .scene:
                let sceneTakes = store.takes.filter { $0.auditionID == auditionID && ($0.sceneIndex ?? 0) == sceneIndex }
                if !sceneTakes.isEmpty {
                    Button("Takes (\(sceneTakes.count))") {
                        finish(goTo: .takes(auditionID, sceneIndex: sceneIndex))
                    }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .padding(.horizontal, OTSpace.m)
                    .frame(height: 36) // ot-lint:allow
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                } else if let a = store.audition(auditionID) {
                    Button("Skip") { skipCurrentScene(in: a) }
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(Color.white) // ot-lint:allow
                        .padding(.horizontal, OTSpace.m)
                        .frame(height: 36) // ot-lint:allow
                        .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                } else {
                    Color.clear.frame(width: 44, height: 44) // ot-lint:allow
                }
            default:
                Color.clear.frame(width: 44, height: 44) // ot-lint:allow
            }
        }
    }

    var pillText: String {
        let t = Int(camera.elapsed)
        let time = String(format: "%02d:%02d", t / 60, t % 60)
        if camera.state == .paused { return "Paused  \(time)" }
        switch stage {
        case .check: return "Camera check"
        case .slate, .slateDone: return "Slate  \(time)"
        case .fullLength: return "Full-body shot  \(time)"
        case .scene: return "SC \(sceneIndex + 1) · TK \(store.nextTakeNumber(auditionID: auditionID, sceneIndex: sceneIndex))  \(time)"
        case .saved: return "SC \(sceneIndex + 1) · TK \(takeNumber)  \(time)"
        }
    }

    @ViewBuilder
    func overlay(for a: Audition) -> some View {
        switch stage {
        case .check:
            VStack(spacing: OTSpace.s) {
                Text(firstStage == .slate ? "Ready to record your slate" : firstStage == .fullLength ? "Ready for your full-body shot" : "Ready for \(sceneTitle(in: a))")
                    .font(.otHeadline)
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(firstStage == .slate
                     ? (a.asks.contains("Full-body shot with slate")
                        ? "Step back so your head and feet fit in frame, then say your name, height, and city."
                        : "Keep your face centered and say your name, height, and city.")
                     : firstStage == .fullLength
                        ? "Step back until your head and feet are in frame. Hold still for a few seconds."
                        : "Keep your eyeline near the lens. Your scene and reader cues are ready below.")
                    .font(.otFootnote)
                    .foregroundStyle(Color.white.opacity(0.76)) // ot-lint:allow
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Label("Pose guide", systemImage: "figure.stand")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(Color.white) // ot-lint:allow
                    Spacer()
                    Button {
                        poseGuideEnabled.toggle()
                        Haptics.tick()
                    } label: {
                        Text(poseGuideEnabled ? "On" : "Off")
                            .font(.otCaption.weight(.bold))
                            .foregroundStyle(Color.white) // ot-lint:allow
                            .padding(.horizontal, OTSpace.m)
                            .frame(height: 30) // ot-lint:allow
                            .background(poseGuideEnabled ? AnyShapeStyle(OT.accent.opacity(0.85)) : AnyShapeStyle(OT.cameraGlass), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                    }
                    .accessibilityLabel("Pose guide \(poseGuideEnabled ? "on" : "off")")
                }
                .padding(.horizontal, OTSpace.m)
                .frame(height: 34) // ot-lint:allow
                .background(Color.black.opacity(0.55), in: Capsule()) // ot-lint:allow

                ForEach(Array(liveChecks.enumerated()), id: \.offset) { _, row in
                    liveCheckRow(row.text, ok: row.ok)
                }
                if poseGuideEnabled { poseCoachRow }
            }
            scenePicker(a)
        case .slate:
            let asksForFullBodyWithSlate = a.asks.contains("Full-body shot with slate")
            promptCard(
                eyebrow: asksForFullBodyWithSlate ? "Slate + full-body shot · ≈ 5 s" : "Slate · say it to the lens · ≈ 5 s",
                text: asksForFullBodyWithSlate ? "\(store.slate.spoken) Keep your head and feet in frame." : store.slate.spoken
            )
        case .slateDone:
            slateDoneOverlay(for: a)
        case .fullLength:
            promptCard(eyebrow: "Requested · after the slate", text: "Head to feet, hold still")
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

    var liveChecks: [(text: String, ok: Bool)] {
        if case .failed = camera.state {
            #if targetEnvironment(simulator)
            return [("Camera unavailable in Simulator · recording works on iPhone", false)]
            #else
            return [("Camera unavailable · check camera permission and try again", false)]
            #endif
        }
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

    @ViewBuilder
    var poseCoachRow: some View {
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

    var cameraGuidanceKey: String? {
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

    func liveCheckRow(_ text: String, ok: Bool) -> some View {
        HStack(spacing: OTSpace.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? OT.success : OT.due)
            Text(text)
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(Color.white) // ot-lint:allow
            Spacer()
        }
        .padding(.horizontal, OTSpace.m)
        .frame(height: 32) // ot-lint:allow
        .background(Color.black.opacity(0.55), in: Capsule()) // ot-lint:allow
    }

    @ViewBuilder
    var voiceStatusPill: some View {
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
            .padding(.bottom, OTSpace.xxs)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder
    var voiceCommandStatus: some View {
        if voiceCommandsEnabled, [.slate, .fullLength, .scene].contains(stage), camera.state == .ready {
            Label(
                follower.isListening ? "Say Action to start · Cut to stop" : (voiceAllowed ? "Voice commands unavailable" : "Allow speech and microphone access"),
                systemImage: follower.isListening ? "waveform" : "mic.slash"
            )
            .font(.system(size: 12, weight: .semibold)) // ot-lint:allow
            .foregroundStyle(follower.isListening ? OT.success : OT.due)
            .padding(.horizontal, OTSpace.m)
            .frame(height: 30) // ot-lint:allow
            .background(Color.black.opacity(0.58), in: Capsule()) // ot-lint:allow
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    var handsFreeControlsMenu: some View {
        Menu {
            Toggle(isOn: $voiceCommandsEnabled) {
                Label("Voice commands · Action / Cut", systemImage: "waveform")
            }
            Toggle(isOn: $gesturesEnabled) {
                Label("Hand gestures · open palm", systemImage: "hand.raised")
            }
            Text("Turn on either control or both.")
        } label: {
            Image(systemName: "hand.raised.fingers.spread")
                .font(.system(size: 14, weight: .semibold)) // ot-lint:allow
                .foregroundStyle(voiceCommandsEnabled || gesturesEnabled ? OT.accent : Color.white) // ot-lint:allow
                .frame(width: 38, height: 38) // ot-lint:allow
                .background(OT.cameraGlass, in: Circle())
        }
        .accessibilityLabel("Hands-free controls")
    }

    var hud: some View {
        VStack(spacing: 7) { // ot-lint:allow
            if let requested = requestedVideoOrientation, orientationMismatch(for: requested),
               [.check, .slate, .fullLength, .scene].contains(stage) {
                let direction = requested == "Landscape" ? "sideways" : "upright"
                Label("Casting requested \(requested) · Turn phone \(direction)", systemImage: "rotate.3d")
                    .font(.system(size: 11, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.prompterGold)
                    .padding(.horizontal, 11) // ot-lint:allow
                    .frame(height: 28) // ot-lint:allow
                    .background(OT.cameraGlass, in: Capsule())
                    .accessibilityLabel("Casting requested \(requested). Turn the phone \(direction) before recording.")
            }
            HStack(spacing: 6) { // ot-lint:allow
                if camera.audioMeterAvailable, [.check, .slate, .fullLength, .scene].contains(stage) {
                    HStack(spacing: 6) { // ot-lint:allow
                        Image(systemName: "mic.fill").font(.system(size: 10, weight: .semibold)) // ot-lint:allow
                        HStack(alignment: .center, spacing: 2) {
                            ForEach(0..<8, id: \.self) { index in
                                Capsule().fill(meterColor(for: index))
                                    .frame(width: 3, height: CGFloat(4 + (index % 3) * 2)) // ot-lint:allow
                                    .opacity(CGFloat(index) / 8 < CGFloat(camera.audioLevel) ? 1 : 0.28) // ot-lint:allow
                            }
                        }
                        .frame(height: 16) // ot-lint:allow
                        Text(camera.audioLevel > 0.02 ? "Mic" : "Speak to test")
                            .font(.system(size: 10, weight: .semibold)) // ot-lint:allow
                    }
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .padding(.horizontal, 9) // ot-lint:allow
                    .frame(height: 26) // ot-lint:allow
                    .background(Color.black.opacity(0.55), in: Capsule()) // ot-lint:allow
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(camera.audioLevel > 0.02 ? "Microphone input detected" : "Microphone ready. Speak to test input")
                }
                if stage == .check {
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
                            Text("\(camera.currentResolution.title) · 30 fps").font(.otCaption.weight(.semibold))
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) // ot-lint:allow
                        }
                        .foregroundStyle(Color.white) // ot-lint:allow
                        .padding(.horizontal, 9) // ot-lint:allow
                        .frame(height: 26) // ot-lint:allow
                        .background(Color.black.opacity(0.55), in: Capsule()) // ot-lint:allow
                    }
                    .disabled(camera.state == .recording || countdown != nil)
                    .accessibilityLabel("Recording resolution, \(camera.currentResolution.title)")
                }

                if gesturesEnabled && [.slate, .fullLength, .scene].contains(stage) {
                    chip("hand.raised.fill", camera.state == .recording ? "Palm: pause" : "Palm: start / resume")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(stage == .saved || stage == .slateDone ? 0 : 1)
    }

    var requestedVideoOrientation: String? {
        guard let a = store.audition(auditionID) else { return nil }
        if let value = a.submissionInstructions?.videoOrientation?.lowercased() {
            if value.contains("landscape") { return "Landscape" }
            if value.contains("portrait") { return "Portrait" }
        }
        if a.asks.contains(where: { $0.localizedCaseInsensitiveContains("landscape") }) { return "Landscape" }
        if a.asks.contains(where: { $0.localizedCaseInsensitiveContains("portrait") }) { return "Portrait" }
        return nil
    }

    func orientationMismatch(for requested: String) -> Bool {
        switch deviceOrientation {
        case .portrait, .portraitUpsideDown:
            return requested == "Landscape"
        case .landscapeLeft, .landscapeRight:
            return requested == "Portrait"
        default:
            return false
        }
    }

    func meterColor(for index: Int) -> Color {
        if index >= 6 { return .red }
        if index >= 4 { return .yellow }
        return .green
    }

    @ViewBuilder
    var sceneActionBar: some View {
        if stage == .scene, let lines = sceneLines, !lines.isEmpty {
            HStack(spacing: OTSpace.s) {
                Button {
                    advanceLine()
                    Haptics.tick()
                } label: {
                    HStack(spacing: 5) { // ot-lint:allow
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)) // ot-lint:allow
                        Text("Next line").font(.otFootnote.weight(.semibold))
                    }
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .padding(.horizontal, OTSpace.m)
                    .frame(height: 36) // ot-lint:allow
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
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
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .padding(.horizontal, OTSpace.s)
                    .frame(height: 36) // ot-lint:allow
                    .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                }
            }
        }
    }

    var bottomControls: some View {
        ZStack(alignment: .center) {
            // Symmetrical secondary controls layer: 44x44 circular buttons on each side
            if stage == .check {
                HStack(alignment: .center) {
                    Button {
                        camera.cycleZoom()
                    } label: {
                        Text(zoomLabel)
                            .font(.system(size: 14, weight: .bold)) // ot-lint:allow
                            .foregroundStyle(Color.white) // ot-lint:allow
                            .frame(width: 44, height: 44) // ot-lint:allow
                            .background(OT.cameraGlass, in: Circle())
                    }
                    .disabled(camera.state != .ready || countdown != nil)
                    .accessibilityLabel("Zoom \(zoomLabel)")

                    Spacer()

                    Button {
                        camera.switchCamera()
                        if stage != .check { camera.lockExposure() }
                        Haptics.tick()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 16, weight: .semibold)) // ot-lint:allow
                            .foregroundStyle(Color.white) // ot-lint:allow
                            .frame(width: 44, height: 44) // ot-lint:allow
                            .background(OT.cameraGlass, in: Circle())
                    }
                    .disabled(camera.state != .ready || countdown != nil)
                    .opacity(camera.state == .recording ? 0 : 1)
                    .accessibilityLabel("Switch camera")
                }
            } else {
                Color.clear.frame(height: 44) // ot-lint:allow
            }

            // Primary action: RecordButton or Go to your mark
            switch stage {
            case .check:
                VStack(spacing: OTSpace.s) {
                    Button(firstStage == .slate ? "Record your slate" : firstStage == .fullLength ? "Record full-body shot" : "Go to your mark") {
                        start(at: firstStage)
                    }
                    .buttonStyle(.otPrimary)
                    .frame(width: 200) // ot-lint:allow

                    if firstStage == .scene {
                        HStack(spacing: OTSpace.s) {
                            cameraChoice(store.audition(auditionID)?.slateVideoURL != nil ? "Redo slate" : "Record slate") {
                                start(at: .slate)
                            }
                            if let audition = store.audition(auditionID),
                               requiresSeparateFullBodyShot(audition) || audition.fullLengthVideoURL != nil {
                                cameraChoice(audition.fullLengthVideoURL != nil ? "Redo full-body shot" : "Add full-body shot") {
                                    start(at: .fullLength)
                                }
                            }
                        }
                    }
                }
            case .slateDone, .saved:
                Color.clear.frame(height: 78) // ot-lint:allow
            default:
                VStack(spacing: OTSpace.s) {
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
        .padding(.bottom, OTSpace.s)
    }

    var zoomLabel: String {
        camera.zoomFactor == 1 ? "1×" : String(format: "%.1f×", camera.zoomFactor)
    }

    var firstStage: Stage {
        guard let audition = store.audition(auditionID) else { return .scene }
        switch audition.nextPiece?.kind {
        case .slate: return .slate
        case .fullLength: return .fullLength
        default: return .scene
        }
    }

    func sceneTitle(in audition: Audition) -> String {
        guard audition.scenes.indices.contains(sceneIndex) else { return "Scene \(sceneIndex + 1)" }
        return audition.scenes[sceneIndex].title
    }

    @ViewBuilder
    func scenePicker(_ a: Audition) -> some View {
        if a.scenes.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { // ot-lint:allow
                    ForEach(a.scenes.indices, id: \.self) { i in
                        let shot = store.takes.contains { $0.auditionID == auditionID && $0.sceneIndex == i }
                        Button { pickScene(i) } label: {
                            HStack(spacing: 4) {
                                if shot { Image(systemName: "checkmark").font(.caption2) }
                                Text(a.scenes[i].title).font(.otCaption.weight(.semibold))
                            }
                            .foregroundStyle(i == sceneIndex ? OT.labelOnAccent : Color.white) // ot-lint:allow
                            .padding(.horizontal, 10) // ot-lint:allow
                            .frame(height: 30) // ot-lint:allow
                            .background(i == sceneIndex ? AnyShapeStyle(OT.accent) : AnyShapeStyle(Color.black.opacity(0.55)), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)) // ot-lint:allow
                        }
                        .accessibilityLabel("\(a.scenes[i].title)\(shot ? ", has a take" : "")")
                        .accessibilityAddTraits(i == sceneIndex ? .isSelected : [])
                    }
                }
            }
        }
    }
}
