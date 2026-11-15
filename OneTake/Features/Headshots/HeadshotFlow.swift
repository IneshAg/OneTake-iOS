import SwiftUI
import AVKit
import OneTakeUI

struct HeadshotFlow: View {
    enum Angle: String, CaseIterable { case front = "Front", left = "Left", right = "Right" }

    var auditionID: Audition.ID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var camera = CameraController()
    @State private var follower = SpeechFollower()
    @State private var cameraSpeaker = CameraGuidanceSpeaker()
    @State private var voiceAllowed = false
    @State private var voiceGuidanceEnabled = true
    @State private var showMatchGuide = false
    @State private var showGhostOverlay = true
    @State private var angle: Angle = .front
    @State private var justCaptured = false
    @State private var captureFailed = false
    @State private var comparisonPhotos: [UIImage] = []
    @State private var selectedComparisonPhoto = 1
    @State private var showingComparison = false
    @State private var milestone: OTMilestoneBannerItem?

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)

            // Alignment overlay — ghost outline to position against, shifted per angle.
            if showGhostOverlay {
                ghostAlignmentOverlay
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle()) // ot-lint:allow
                    }
                    .accessibilityLabel("Close")

                    Spacer()

                    Picker("Angle", selection: $angle) {
                        ForEach(Angle.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220) // ot-lint:allow

                    Spacer()

                    // Reference model button
                    referenceThumbnail
                }
                .frame(height: 44) // ot-lint:allow
                .padding(.top, OTSpace.s)

                Spacer()

                // Live status chips (lighting & angle)
                statusChips
                    .padding(.bottom, OTSpace.xs)

                Text(comparisonPhotos.isEmpty ? guide.message : "Take another photo to compare")
                    .font(.otHeadline).foregroundStyle(guide.aligned ? OT.success : .white)
                Text(follower.isListening ? "Tap, or say “Now”" : "Voice is off — tap the shutter")
                    .font(.otFootnote).foregroundStyle(.white.opacity(0.7)) // ot-lint:allow

                ZStack {
                    Button { capture() } label: {
                        Circle().fill(.white).frame(width: 66, height: 66).overlay(Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)) // ot-lint:allow
                    }
                    .scaleEffect(justCaptured ? 0.88 : 1)
                    .animation(OTMotion.bouncy, value: justCaptured)
                    .accessibilityLabel("Take photo")

                    HStack {
                        // Voice guidance speaker toggle
                        Button {
                            voiceGuidanceEnabled.toggle()
                            Haptics.tick()
                            if voiceGuidanceEnabled {
                                cameraSpeaker.speak("Voice guidance on", minInterval: 0.1)
                            } else {
                                cameraSpeaker.stop()
                            }
                        } label: {
                            Image(systemName: voiceGuidanceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .foregroundStyle(voiceGuidanceEnabled ? OT.due : .white.opacity(0.7)) // ot-lint:allow
                                .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle()) // ot-lint:allow
                        }
                        .accessibilityLabel(voiceGuidanceEnabled ? "Mute voice guidance" : "Turn on voice guidance")

                        Spacer()

                        Button {
                            camera.switchCamera()
                            Haptics.tick()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle()) // ot-lint:allow
                        }
                        .disabled(camera.state != .ready)
                        .accessibilityLabel("Switch camera")
                    }
                }
                .padding(.bottom, OTSpace.m)
            }
            .padding(.horizontal, OTSpace.gutter)

            if showingComparison {
                HeadshotComparisonView(
                    title: angle.rawValue,
                    photos: comparisonPhotos,
                    selectedIndex: $selectedComparisonPhoto,
                    onKeep: keepSelectedComparisonPhoto,
                    onRetry: retryComparisonPhoto,
                    onTakeAnother: takeAnotherToCompare
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
        .otSurface(.camera)
        .otMilestoneBanner($milestone)
        .sheet(isPresented: $showMatchGuide) {
            HeadshotReferenceGuideSheet(
                angle: angle,
                auditionID: auditionID,
                showGhostOverlay: $showGhostOverlay,
                voiceGuidanceEnabled: $voiceGuidanceEnabled
            )
        }
        .task {
            camera.wantsFaceGuidance = true
            if await CameraController.requestVideoAccess() { camera.configure(position: .front) }
            voiceAllowed = await SpeechFollower.requestAccess()
            if voiceAllowed { follower.start() }
            if voiceGuidanceEnabled {
                let initialPrompt: String
                switch angle {
                case .front: initialPrompt = "Front headshot. Look straight at the camera."
                case .left:  initialPrompt = "Left profile. Turn your head to your left."
                case .right: initialPrompt = "Right profile. Turn your head to your right."
                }
                cameraSpeaker.speak(initialPrompt, minInterval: 0.8)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                if Self.shouldSpeakGuidance(
                    voiceGuidanceEnabled: voiceGuidanceEnabled,
                    cameraReady: camera.state == .ready,
                    showingComparison: showingComparison,
                    showMatchGuide: showMatchGuide,
                    justCaptured: justCaptured
                ) {
                    speakCurrentGuidance()
                }
            }
        }
        .onChange(of: camera.state) { _, state in
            if state == .ready, voiceAllowed, !follower.isListening, !showingComparison { follower.start() }
        }
        .onChange(of: guide.message) { _, _ in
            guard !isGuidancePaused else { return }
            speakCurrentGuidance()
        }
        .onChange(of: showingComparison) { _, _ in
            syncGuidanceActiveState()
        }
        .onChange(of: showMatchGuide) { _, _ in
            syncGuidanceActiveState()
        }
        .onChange(of: justCaptured) { _, _ in
            syncGuidanceActiveState()
        }
        .onChange(of: angle) { _, newAngle in
            follower.reset()
            guard !isGuidancePaused else { return }
            if voiceGuidanceEnabled {
                let prompt: String
                switch newAngle {
                case .front: prompt = "Front headshot. Look straight at the camera."
                case .left:  prompt = "Left profile. Turn your head to your left."
                case .right: prompt = "Right profile. Turn your head to your right."
                }
                cameraSpeaker.speak(prompt, minInterval: 0.1)
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if cmd?.word == "now" || cmd?.word == "action" { capture() }
        }
        .onCameraCaptureEvent { event in
            if event.phase == .ended { capture() }
        }
        .onDisappear {
            cameraSpeaker.stop()
            camera.stop()
            follower.stop()
            store.syncHeadshotPieces()
        }
        .alert("Couldn’t take that photo", isPresented: $captureFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage)
        }
    }

    private var ghostAlignmentOverlay: some View {
        ZStack {
            Ellipse()
                .stroke(guide.aligned ? OT.success : OT.due, lineWidth: guide.aligned ? 3 : 1.5) // ot-lint:allow
                .frame(width: 200, height: 270) // ot-lint:allow
                .rotation3DEffect(.degrees(angle == .front ? 0 : (angle == .left ? -14 : 14)), axis: (x: 0, y: 1, z: 0))

            HStack {
                if angle == .left && !guide.aligned {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.otTitle)
                        .foregroundStyle(OT.prompterGold)
                }
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2) // ot-lint:allow
                Spacer()
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2) // ot-lint:allow
                if angle == .right && !guide.aligned {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.otTitle)
                        .foregroundStyle(OT.prompterGold)
                }
            }
            .frame(width: 190) // ot-lint:allow
            .offset(y: -24) // ot-lint:allow
        }
        .offset(x: angle == .left ? -14 : angle == .right ? 14 : 0, y: -20) // ot-lint:allow
        .animation(OTMotion.snappy, value: guide.aligned)
        .animation(OTMotion.smooth, value: angle)
    }

    private var statusChips: some View {
        HStack(spacing: OTSpace.s) {
            HStack(spacing: OTSpace.xxs) {
                Circle()
                    .fill(lightColor)
                    .frame(width: 6, height: 6) // ot-lint:allow
                Text(lightText)
                    .font(.otCaptionStrong)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, OTSpace.s)
            .frame(height: 24) // ot-lint:allow
            .background(.black.opacity(0.55), in: Capsule()) // ot-lint:allow

            HStack(spacing: OTSpace.xxs) {
                Circle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 6, height: 6) // ot-lint:allow
                Text(angleStatusText)
                    .font(.otCaptionStrong)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, OTSpace.s)
            .frame(height: 24) // ot-lint:allow
            .background(.black.opacity(0.55), in: Capsule()) // ot-lint:allow

            if let pose = camera.face?.predictedPose {
                let deg = Int((camera.face?.predictedYawDegrees ?? 0).rounded())
                Text("\(poseChipLabel(pose)) \(deg > 0 ? "+\(deg)" : "\(deg)")°")
                    .font(.otCaptionStrong.monospacedDigit())
                    .foregroundStyle(guide.aligned ? OT.success : OT.prompterGold)
                    .padding(.horizontal, OTSpace.s)
                    .frame(height: 24) // ot-lint:allow
                    .background(.black.opacity(0.55), in: Capsule()) // ot-lint:allow
            }
        }
    }

    private func poseChipLabel(_ pose: HeadshotPoseLabel) -> String {
        switch pose {
        case .front: "Front"
        case .leftProfile: "Left"
        case .rightProfile: "Right"
        }
    }

    private var lightColor: Color {
        guard let luma = camera.lightLevel else { return OT.success }
        return (luma < 0.22 || luma > 0.85) ? OT.due : OT.success
    }

    private var lightText: String {
        guard let luma = camera.lightLevel else { return "Light: Good" }
        if luma < 0.22 { return "Low light" }
        if luma > 0.85 { return "Direct glare" }
        return "Light: Soft & even"
    }

    private var angleStatusText: String {
        switch angle {
        case .front: return guide.aligned ? "Angle: Square" : "Face forward"
        case .left:  return guide.aligned ? "Angle: 90° profile" : "Turn left"
        case .right: return guide.aligned ? "Angle: 90° profile" : "Turn right"
        }
    }

    private var isGuidancePaused: Bool {
        showingComparison || showMatchGuide || justCaptured
    }

    private func syncGuidanceActiveState() {
        let active = !isGuidancePaused
        camera.faceGuidanceActive = active
        if !active {
            cameraSpeaker.stop()
        }
    }

    static func shouldSpeakGuidance(
        voiceGuidanceEnabled: Bool,
        cameraReady: Bool,
        showingComparison: Bool,
        showMatchGuide: Bool,
        justCaptured: Bool
    ) -> Bool {
        voiceGuidanceEnabled && cameraReady && !showingComparison && !showMatchGuide && !justCaptured
    }

    private func speakCurrentGuidance(immediate: Bool = false) {
        guard Self.shouldSpeakGuidance(
            voiceGuidanceEnabled: voiceGuidanceEnabled,
            cameraReady: camera.state == .ready,
            showingComparison: showingComparison,
            showMatchGuide: showMatchGuide,
            justCaptured: justCaptured
        ) else { return }
        cameraSpeaker.speak(guide.spoken, minInterval: immediate ? 0.2 : 2.0, repeatInterval: 4.5)
    }

    private var failureMessage: String {
        switch camera.state {
        case .failed(let reason): reason
        case .idle: "The camera hasn’t started. Check Settings › OneTake › Camera is on, then reopen this screen."
        default: "The camera wasn’t ready. Give it a second, then try again."
        }
    }

    private var guide: (message: String, spoken: String, aligned: Bool) {
        Self.evaluatePoseGuide(face: camera.face, angle: angle)
    }

    /// Combines CoreML `HeadshotPoseClassifier` predictions (`Front 0°`, `Left +90°`, `Right -90°`)
    /// with Vision bounding-box framing & signed yaw to give unambiguous directional guidance.
    static func evaluatePoseGuide(
        face: CameraController.FaceReading?,
        angle: Angle
    ) -> (message: String, spoken: String, aligned: Bool) {
        guard let f = face else {
            return ("Show your face to the camera", "Step into the frame so your face is visible", false)
        }
        if f.height < 0.20 {
            return ("Move closer", "Move closer to the camera", false)
        }
        if f.height > 0.52 {
            return ("Move back a little", "Move back a little", false)
        }
        if f.centerX < 0.38 {
            return ("Too far left — move right", "Move to your right", false)
        }
        if f.centerX > 0.62 {
            return ("Too far right — move left", "Move to your left", false)
        }
        if f.centerY < 0.28 {
            return ("Tilt the phone up a little", "Tilt the phone up a little", false)
        }
        if f.centerY > 0.58 {
            return ("Tilt the phone down a little", "Tilt the phone down a little", false)
        }

        let yawDegrees = f.predictedYawDegrees ?? (f.yaw.map { $0 * 180.0 / .pi } ?? 0)
        switch angle {
        case .front:
            if (f.predictedPose == .leftProfile || f.predictedPose == .rightProfile) && f.poseConfidence >= 0.65 {
                return ("Look straight at the camera", "Look straight at the camera", false)
            }
            if abs(yawDegrees) > 15 {
                return ("Look straight at the camera", "Look straight at the camera", false)
            }
        case .left:
            if (f.predictedPose == .rightProfile && f.poseConfidence >= 0.55) || yawDegrees < -15 {
                return ("Wrong side — turn your head LEFT", "Wrong side, turn your head to your left", false)
            }
            let isLeftAligned = (f.predictedPose == .leftProfile && f.poseConfidence >= 0.55) || yawDegrees >= 25
            if !isLeftAligned {
                return ("Turn your head to your LEFT", "Turn your head to your left", false)
            }
            if abs(yawDegrees) > 105 {
                return ("Turn back a little", "Turn back slightly toward the camera", false)
            }
        case .right:
            if (f.predictedPose == .leftProfile && f.poseConfidence >= 0.55) || yawDegrees > 15 {
                return ("Wrong side — turn your head RIGHT", "Wrong side, turn your head to your right", false)
            }
            let isRightAligned = (f.predictedPose == .rightProfile && f.poseConfidence >= 0.55) || yawDegrees <= -25
            if !isRightAligned {
                return ("Turn your head to your RIGHT", "Turn your head to your right", false)
            }
            if abs(yawDegrees) > 105 {
                return ("Turn back a little", "Turn back slightly toward the camera", false)
            }
        }
        return ("Hold still — that's it", "Hold still, say Now to shoot", true)
    }

    private var referenceThumbnail: some View {
        Button {
            showMatchGuide = true
            Haptics.tick()
        } label: {
            VStack(spacing: 3) { // ot-lint:allow
                ZStack {
                    RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                        .fill(.white.opacity(0.14)) // ot-lint:allow
                        .overlay(
                            RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                .stroke(showMatchGuide ? OT.due : .white.opacity(0.28), lineWidth: 1.5) // ot-lint:allow
                        )

                    if let img = thumbnailImageForCurrentOrPriorAngle() {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44) // ot-lint:allow
                            .clipShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                    } else {
                        Image(systemName: referenceSymbol)
                            .font(.system(size: 20)) // ot-lint:allow
                            .foregroundStyle(.white.opacity(0.9)) // ot-lint:allow
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11, weight: .bold)) // ot-lint:allow
                                .foregroundStyle(OT.due)
                                .background(Circle().fill(.black.opacity(0.7))) // ot-lint:allow
                                .offset(x: 3, y: 3) // ot-lint:allow
                        }
                    }
                    .frame(width: 44, height: 44) // ot-lint:allow
                }
                .frame(width: 44, height: 44) // ot-lint:allow

                HStack(spacing: 2) { // ot-lint:allow
                    Text("Match this")
                        .font(.system(size: 9.5, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(.white.opacity(0.7)) // ot-lint:allow
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Match this reference guide for \(angle.rawValue)")
    }

    private func thumbnailImageForCurrentOrPriorAngle() -> UIImage? {
        if let current = HeadshotStore.load(key: angle.rawValue, auditionID: auditionID) {
            return current
        }
        if angle == .left, let front = HeadshotStore.load(key: "Front", auditionID: auditionID) {
            return front
        }
        if angle == .right {
            return HeadshotStore.load(key: "Left", auditionID: auditionID) ?? HeadshotStore.load(key: "Front", auditionID: auditionID)
        }
        return nil
    }

    private var referenceSymbol: String {
        switch angle {
        case .front: "person.crop.circle"
        case .left:  "person.crop.circle.badge.checkmark"
        case .right: "person.crop.circle.badge.checkmark"
        }
    }

    private func capture() {
        guard !justCaptured, !showingComparison else { return }
        justCaptured = true
        camera.faceGuidanceActive = false
        cameraSpeaker.stop()
        camera.capturePhoto { image in
            justCaptured = false
            guard let image else {
                syncGuidanceActiveState()
                captureFailed = true
                Haptics.warning()
                return
            }
            Haptics.success()
            if comparisonPhotos.isEmpty, let prior = HeadshotStore.load(key: angle.rawValue, auditionID: auditionID) {
                comparisonPhotos = [prior, image]
                selectedComparisonPhoto = 1
            } else {
                comparisonPhotos.append(image)
                selectedComparisonPhoto = comparisonPhotos.count - 1
            }
            showingComparison = true
            syncGuidanceActiveState()
        }
    }

    private func keepSelectedComparisonPhoto() {
        guard comparisonPhotos.indices.contains(selectedComparisonPhoto) else { return }
        HeadshotStore.save(comparisonPhotos[selectedComparisonPhoto], key: angle.rawValue, auditionID: auditionID)
        store.headshotVersion += 1
        store.syncHeadshotPieces()
        comparisonPhotos.removeAll()
        if let next = Angle.allCases.drop(while: { $0 != angle }).dropFirst().first {
            let saved = angle.rawValue
            showingComparison = false
            syncGuidanceActiveState()
            angle = next
            follower.reset()
            Haptics.stepDone()
            milestone = OTMilestoneBannerItem(
                title: "\(saved) headshot saved!",
                subtitle: "Next: \(next.rawValue) angle"
            )
            if voiceGuidanceEnabled {
                let prompt = next == .left ? "\(saved) photo saved. Now turn to your left profile." : "\(saved) photo saved. Now turn to your right profile."
                cameraSpeaker.speak(prompt, minInterval: 0.1)
            }
        } else {
            // Stop all capture, voice guidance, and speech recognition immediately before leaving.
            voiceGuidanceEnabled = false
            camera.faceGuidanceActive = false
            cameraSpeaker.stop()
            camera.stop()
            follower.stop()
            showingComparison = false
            Haptics.celebrate()
            dismiss()
        }
    }

    private func retryComparisonPhoto() {
        comparisonPhotos.removeAll()
        selectedComparisonPhoto = 0
        showingComparison = false
        Haptics.tick()
    }

    private func takeAnotherToCompare() {
        showingComparison = false
        if voiceGuidanceEnabled {
            cameraSpeaker.speak("Take another photo to compare.", minInterval: 0.1)
        }
        Haptics.tick()
    }
}

private struct HeadshotComparisonView: View {
    let title: String
    let photos: [UIImage]
    @Binding var selectedIndex: Int
    let onKeep: () -> Void
    let onRetry: () -> Void
    var onTakeAnother: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onRetry) {
                    Image(systemName: "xmark")
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                        .frame(width: OT.minTap, height: OT.minTap) // ot-lint:allow
                        .background(OT.fillField, in: Circle()) // ot-lint:allow
                }
                .accessibilityLabel("Return to camera")
                Spacer()
                Text("\(title) · \(photos.count == 1 ? "1 shot" : "\(photos.count) shots")")
                    .font(.otHeadline).foregroundStyle(OT.labelPrimary)
                Spacer()
                Color.clear.frame(width: OT.minTap, height: OT.minTap) // ot-lint:allow
            }
            .padding(.horizontal, OTSpace.gutter).padding(.top, OTSpace.s)

            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text(photos.count > 1 ? "Keep the better one" : "Review your shot")
                    .font(.otTitle)
                    .foregroundStyle(OT.labelPrimary)
                Text(photos.count > 1 ? "Compare the headshots side by side" : "Keep this photo, or take another if you want to compare.")
                    .font(.otCallout)
                    .foregroundStyle(OT.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OTSpace.gutter).padding(.top, OTSpace.m).padding(.bottom, OTSpace.m)

            if photos.count > 1 {
                HStack(alignment: .top, spacing: OTSpace.s) {
                    ForEach(photos.indices, id: \.self) { index in
                        Button { selectedIndex = index } label: {
                            VStack(spacing: OTSpace.xs) {
                                Image(uiImage: photos[index])
                                    .resizable().scaledToFill()
                                    .frame(maxWidth: .infinity).frame(height: 219) // ot-lint:allow
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: selectedIndex == index ? "checkmark.circle.fill" : "circle")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(selectedIndex == index ? OT.accent : OT.labelTertiary)
                                            .padding(OTSpace.s)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                            .strokeBorder(selectedIndex == index ? OT.accent : Color.clear, lineWidth: 2)
                                    )
                                Text("Take \(index + 1)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select take \(index + 1)")
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
            } else if let single = photos.first {
                Image(uiImage: single)
                    .resizable().scaledToFill()
                    .frame(height: 260) // ot-lint:allow
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                    .padding(.horizontal, OTSpace.gutter)
            }

            VStack(alignment: .leading, spacing: OTSpace.xs) {
                comparisonNote("sun.max", "Check for soft, even light")
                comparisonNote("viewfinder", "Check that your face is centred")
                comparisonNote("exclamationmark.circle", "Look for a plain background and eye-level camera")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OTSpace.gutter).padding(.top, OTSpace.m)

            Spacer(minLength: OTSpace.m)
            VStack(spacing: OTSpace.s) {
                Button(photos.count > 1 ? "Keep take \(selectedIndex + 1)" : "Keep photo", action: onKeep)
                    .buttonStyle(.otPrimary)

                if photos.count == 1, let onTakeAnother {
                    Button("Take another to compare", action: onTakeAnother)
                        .buttonStyle(.otSecondary)
                }

                Button(photos.count > 1 ? "Try again" : "Retake", action: onRetry)
                    .buttonStyle(.ot(.secondary, size: .medium))
            }
            .padding(.horizontal, OTSpace.gutter).padding(.bottom, OTSpace.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .otSurface(.standard)
    }

    private func comparisonNote(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: OTSpace.s) {
            Image(systemName: symbol).font(.otFootnote.weight(.semibold))
                .foregroundStyle(symbol == "exclamationmark.circle" ? OT.due : OT.success)
            Text(text).font(.otFootnote).foregroundStyle(OT.labelSecondary)
        }
    }
}

struct HeadshotReferenceGuideSheet: View {
    let angle: HeadshotFlow.Angle
    var auditionID: Audition.ID? = nil
    @Binding var showGhostOverlay: Bool
    @Binding var voiceGuidanceEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OTSpace.l) {
                    VStack(spacing: OTSpace.s) {
                        ZStack {
                            RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                                .fill(Color.white.opacity(0.06)) // ot-lint:allow
                                .frame(height: 200) // ot-lint:allow

                            if let saved = HeadshotStore.load(key: angle.rawValue, auditionID: auditionID) {
                                Image(uiImage: saved)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 180) // ot-lint:allow
                                    .clipShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                            } else {
                                referencePoseIllustration
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1) // ot-lint:allow
                        )

                        Text(angleTitle)
                            .font(.system(size: 20, weight: .bold)) // ot-lint:allow
                            .foregroundStyle(.white)

                        Text(angleSummary)
                            .font(.otSubhead)
                            .foregroundStyle(OT.labelSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, OTSpace.s)
                    }
                    .padding(.top, OTSpace.s)

                    // Casting Standards Checklist
                    VStack(alignment: .leading, spacing: OTSpace.m) {
                        Text("Casting Standards")
                            .font(.otHeadline)
                            .foregroundStyle(.white)

                        guideRow(icon: "eye.fill", title: "Eye-line Alignment", desc: "Align eyes level with the horizontal guide notches. Look straight at the camera lens.")
                        guideRow(icon: "arrow.triangle.2.circlepath", title: "Head Angle", desc: angleAngleDesc)
                        guideRow(icon: "sun.max.fill", title: "Soft & Even Lighting", desc: "Face a window or soft key light. Avoid harsh backlights, hard shadows, or overhead glare.")
                        guideRow(icon: "viewfinder", title: "Framing & Distance", desc: "Hold phone 2–3 feet away at chin level. Head and shoulders should fill the frame with 1–2 inches headroom.")
                    }
                    .padding(OTSpace.m)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)) // ot-lint:allow

                    VStack(spacing: OTSpace.s) {
                        Toggle(isOn: $showGhostOverlay) {
                            Label("Show Alignment Overlay", systemImage: "viewfinder")
                                .font(.otSubhead.weight(.medium))
                        }
                        .tint(OT.due)

                        Divider().overlay(Color.white.opacity(0.1)) // ot-lint:allow

                        Toggle(isOn: $voiceGuidanceEnabled) {
                            Label("Spoken Voice Guidance", systemImage: "speaker.wave.2.fill")
                                .font(.otSubhead.weight(.medium))
                        }
                        .tint(OT.due)
                    }
                    .padding(OTSpace.m)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)) // ot-lint:allow

                    Button {
                        dismiss()
                    } label: {
                        Text("Got it — Start Matching")
                            .font(.otHeadline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52) // ot-lint:allow
                            .background(OT.due, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                    }
                    .padding(.top, OTSpace.xs)
                }
                .padding(OTSpace.gutter)
            }
            .background(Color(white: 0.08).ignoresSafeArea()) // ot-lint:allow
            .navigationTitle("Match Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var angleTitle: String {
        switch angle {
        case .front: "Front Headshot"
        case .left:  "Left 90° Profile"
        case .right: "Right 90° Profile"
        }
    }

    private var angleSummary: String {
        switch angle {
        case .front: "Direct front-facing portrait. Shoulders square, eyes looking straight at the camera with chin level."
        case .left:  "Full 90-degree turn to your left. Your left ear, nose profile, and jawline should be clearly defined."
        case .right: "Full 90-degree turn to your right. Your right ear, nose profile, and jawline should be clearly defined."
        }
    }

    private var angleAngleDesc: String {
        switch angle {
        case .front: "Face the lens squarely. Keep head level without tilting left or right."
        case .left:  "Turn head 90° to your left until only your left profile is visible. Keep chin parallel to ground."
        case .right: "Turn head 90° to your right until only your right profile is visible. Keep chin parallel to ground."
        }
    }

    private func guideRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: OTSpace.s) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold)) // ot-lint:allow
                .foregroundStyle(OT.due)
                .frame(width: 24, height: 24) // ot-lint:allow
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var referencePoseIllustration: some View {
        VStack(spacing: OTSpace.xs) {
            ZStack {
                Circle()
                    .stroke(OT.due.opacity(0.4), lineWidth: 2) // ot-lint:allow
                    .frame(width: 90, height: 90) // ot-lint:allow

                Image(systemName: angle == .front ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48)) // ot-lint:allow
                    .foregroundStyle(OT.due)
                    .scaleEffect(x: angle == .left ? -1 : 1, y: 1)
            }
            Text("Reference Pose Guide")
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(OT.labelTertiary)
        }
        .frame(height: 180) // ot-lint:allow
    }
}
