import SwiftUI
import AVKit

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

                Text(comparisonPhotos.isEmpty ? guide.message : "Take one more to compare")
                    .font(.otHeadline).foregroundStyle(guide.aligned ? OT.success : .white)
                Text(follower.isListening ? "Tap, or say “Now”" : "Voice is off — tap the shutter")
                    .font(.otFootnote).foregroundStyle(.white.opacity(0.7)) // ot-lint:allow

                ZStack {
                    Button { capture() } label: {
                        Circle().fill(.white).frame(width: 66, height: 66).overlay(Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)) // ot-lint:allow
                    }
                    .scaleEffect(justCaptured ? 0.88 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: justCaptured)
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
                    onRetry: retryComparisonPhoto
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
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
                if voiceGuidanceEnabled, camera.state == .ready {
                    speakCurrentGuidance()
                }
            }
        }
        .onChange(of: camera.state) { _, state in
            if state == .ready, voiceAllowed, !follower.isListening { follower.start() }
        }
        .onChange(of: guide.message) { _, _ in
            speakCurrentGuidance()
        }
        .onChange(of: angle) { _, newAngle in
            follower.reset()
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
                .rotation3DEffect(.degrees(angle == .front ? 0 : 8), axis: (x: 0, y: 1, z: 0))

            HStack {
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2) // ot-lint:allow
                Spacer()
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2) // ot-lint:allow
            }
            .frame(width: 170) // ot-lint:allow
            .offset(y: -24) // ot-lint:allow
        }
        .offset(x: angle == .left ? -14 : angle == .right ? 14 : 0, y: -20) // ot-lint:allow
        .animation(.easeOut(duration: 0.15), value: guide.aligned)
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

    private func speakCurrentGuidance(immediate: Bool = false) {
        guard voiceGuidanceEnabled, camera.state == .ready else { return }
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
        guard let f = camera.face else {
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
        let yaw = f.yaw ?? 0
        switch angle {
        case .front:
            if abs(yaw) > 0.25 {
                return ("Look straight at the camera", "Look straight at the camera", false)
            }
        case .left:
            if f.yaw != nil && abs(yaw) < 0.25 {
                return ("Turn your head to your left", "Turn your head to your left", false)
            }
            if abs(yaw) > 1.15 {
                return ("Turn back a little", "Turn back a little", false)
            }
        case .right:
            if f.yaw != nil && abs(yaw) < 0.25 {
                return ("Turn your head to your right", "Turn your head to your right", false)
            }
            if abs(yaw) > 1.15 {
                return ("Turn back a little", "Turn back a little", false)
            }
        }
        return ("Hold still — that’s it", "Hold still — say Now to shoot", true)
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
        cameraSpeaker.stop()
        camera.capturePhoto { image in
            justCaptured = false
            guard let image else { captureFailed = true; Haptics.warning(); return }
            Haptics.success()
            if comparisonPhotos.isEmpty, let prior = HeadshotStore.load(key: angle.rawValue, auditionID: auditionID) {
                comparisonPhotos = [prior, image]
                selectedComparisonPhoto = 1
                showingComparison = true
            } else {
                comparisonPhotos.append(image)
                if comparisonPhotos.count >= 2 {
                    selectedComparisonPhoto = comparisonPhotos.count - 1
                    showingComparison = true
                } else if voiceGuidanceEnabled {
                    cameraSpeaker.speak("Good. Take one more so you can compare.", minInterval: 0.1)
                }
            }
        }
    }

    private func keepSelectedComparisonPhoto() {
        guard comparisonPhotos.indices.contains(selectedComparisonPhoto) else { return }
        HeadshotStore.save(comparisonPhotos[selectedComparisonPhoto], key: angle.rawValue, auditionID: auditionID)
        store.headshotVersion += 1
        store.syncHeadshotPieces()
        comparisonPhotos.removeAll()
        showingComparison = false
        Haptics.success()
        if let next = Angle.allCases.drop(while: { $0 != angle }).dropFirst().first {
            let saved = angle.rawValue
            angle = next
            follower.reset()
            if voiceGuidanceEnabled {
                let prompt = next == .left ? "\(saved) photo saved. Now turn to your left profile." : "\(saved) photo saved. Now turn to your right profile."
                cameraSpeaker.speak(prompt, minInterval: 0.1)
            }
        } else {
            if voiceGuidanceEnabled { cameraSpeaker.speak("All headshots saved!", minInterval: 0.1) }
            dismiss()
        }
    }

    private func retryComparisonPhoto() {
        if comparisonPhotos.count > 1 { comparisonPhotos = [comparisonPhotos[selectedComparisonPhoto]] }
        selectedComparisonPhoto = 0
        showingComparison = false
        Haptics.tick()
    }
}

private struct HeadshotComparisonView: View {
    let title: String
    let photos: [UIImage]
    @Binding var selectedIndex: Int
    let onKeep: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onRetry) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(OT.cameraLabel)
                        .frame(width: 44, height: 44) // ot-lint:allow
                        .background(.white.opacity(0.85), in: Circle()) // ot-lint:allow
                }
                .accessibilityLabel("Return to camera")
                Spacer()
                Text("\(title) · \(photos.count) shots")
                    .font(.otHeadline).foregroundStyle(OT.cameraLabel)
                Spacer()
                Color.clear.frame(width: 44, height: 44) // ot-lint:allow
            }
            .padding(.horizontal, OTSpace.gutter).padding(.top, OTSpace.s)

            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text("Keep the better one").font(.system(size: 22, weight: .semibold)).foregroundStyle(OT.cameraLabel) // ot-lint:allow
                Text("Compare the headshots side by side").font(.otCallout).foregroundStyle(OT.cameraLabel2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OTSpace.gutter).padding(.top, OTSpace.m).padding(.bottom, OTSpace.m)

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
                                        .foregroundStyle(selectedIndex == index ? Color(red: 0.56, green: 0.38, blue: 0.06) : OT.cameraLabel2) // ot-lint:allow
                                        .padding(OTSpace.s)
                                }
                                .overlay(RoundedRectangle(cornerRadius: OTRadius.m).strokeBorder(selectedIndex == index ? Color(red: 0.56, green: 0.38, blue: 0.06) : Color.clear, lineWidth: 2)) // ot-lint:allow
                            Text("Take \(index + 1)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.cameraLabel)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select take \(index + 1)")
                }
            }
            .padding(.horizontal, OTSpace.gutter)

            VStack(alignment: .leading, spacing: OTSpace.xs) {
                comparisonNote("sun.max", "Compare for soft, even light")
                comparisonNote("viewfinder", "Check that your face is centred")
                comparisonNote("exclamationmark.circle", "Look for a plain background and eye-level camera")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OTSpace.gutter).padding(.top, OTSpace.m)

            Spacer(minLength: OTSpace.m)
            VStack(spacing: OTSpace.s) {
                Button("Keep take \(selectedIndex + 1)", action: onKeep)
                    .buttonStyle(.otPrimary)
                Button("Try again", action: onRetry)
                    .font(.otHeadline).foregroundStyle(OT.accent)
                    .frame(maxWidth: .infinity).frame(height: 52) // ot-lint:allow
                    .background(Color(red: 0.91, green: 0.85, blue: 0.95), in: Capsule()) // ot-lint:allow
            }
            .padding(.horizontal, OTSpace.gutter).padding(.bottom, OTSpace.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.965, green: 0.957, blue: 0.972).ignoresSafeArea()) // ot-lint:allow
    }

    private func comparisonNote(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: OTSpace.s) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                .foregroundStyle(symbol == "exclamationmark.circle" ? OT.due : OT.success)
            Text(text).font(.otFootnote).foregroundStyle(OT.cameraLabel2)
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
