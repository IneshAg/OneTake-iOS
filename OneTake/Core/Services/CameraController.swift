import AVFoundation
import SwiftUI
import UIKit
import Vision

enum CameraResolution: String, CaseIterable, Identifiable {
    case hd720
    case hd1080
    case uhd4K

    var id: String { rawValue }
    var title: String {
        switch self {
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }
    var preset: AVCaptureSession.Preset {
        switch self {
        case .hd720: .hd1280x720
        case .hd1080: .hd1920x1080
        case .uhd4K: .hd4K3840x2160
        }
    }
}

/// AVFoundation capture pipeline for takes and headshots.
/// SwiftUI has no camera view, so this is the main place OneTake drops to UIKit/AVFoundation.
@Observable
final class CameraController: NSObject {
    enum Position { case front, back }
    enum State: Equatable { case idle, ready, recording, paused, failed(String) }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastRecording: URL?
    private(set) var audioLevel: Float = 0
    private(set) var audioMeterAvailable = false
    var openPalmDetected = false
    private(set) var isExposureLocked = false
    private(set) var zoomFactor: CGFloat = 1
    private(set) var currentResolution: CameraResolution = .hd1080
    private(set) var supportedResolutions: [CameraResolution] = CameraResolution.allCases

    struct InterruptionEvent: Equatable, Sendable {
        var url: URL?
        var duration: TimeInterval
        var hasSavedContent: Bool
        var reason: String
    }

    private(set) var lastInterruption: InterruptionEvent?
    func clearInterruption() { lastInterruption = nil }

    /// Where the face sits in the (upright, as-displayed) frame, all 0…1 with the origin top-left.
    struct FaceReading: Equatable {
        var centerX: CGFloat
        var centerY: CGFloat
        var height: CGFloat
        /// Head turn in radians (0 = facing the camera).
        var yaw: Double?
    }
    /// Live face position for headshot alignment. nil = no face found. Only updates when
    /// `wantsFaceGuidance` was set before `configure`.
    var face: FaceReading?
    /// On-device body-pose landmarks used only for the optional setup coach.
    struct BodyPoseReading: Equatable {
        var shoulderCenterX: CGFloat
        var shoulderTiltDegrees: Double
    }
    var bodyPose: BodyPoseReading?
    /// Average brightness of the frame, 0…1 (updates alongside `face`).
    var lightLevel: Double?
    @ObservationIgnored var wantsFaceGuidance = false
    @ObservationIgnored var wantsBodyPoseGuidance = false
    @ObservationIgnored var wantsHandGesture = false
    /// Pause detection (e.g. once recording starts) without tearing the output down.
    @ObservationIgnored var faceGuidanceActive = true
    @ObservationIgnored private let faceOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let faceQueue = DispatchQueue(label: "onetake.camera.face")
    @ObservationIgnored var lastFaceCheck = Date.distantPast
    @ObservationIgnored var faceBufferIsUpright = false
    @ObservationIgnored private var photoRequestID = 0

    func clearBodyPose() { bodyPose = nil }
    func clearHandGestureDetection() { openPalmDetected = false }

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "onetake.camera")
    private var timer: Timer?
    private var audioMeterTimer: Timer?
    private var audioMeterTimerTarget: CameraAudioMeterTimerTarget?
    private var photoHandler: ((UIImage?) -> Void)?
    /// Called once the movie file is actually finalized on disk — `stopRecording()` returns before that.
    private var recordingFinishedHandler: ((URL?) -> Void)?
    private var isStopping = false
    /// Accessed only from `queue`; it remembers a requested ramp before AVFoundation reports the
    /// new device factor, so repeated zoom taps progress 1× → 1.5× → 2× without getting stuck.
    private var requestedZoomFactor: CGFloat = 1
    private(set) var position: Position = .front

    /// Keeps recordings, photos and the preview upright however the phone is held. Without it every
    /// clip is written in the sensor's own orientation, so only one way of holding the phone came out
    /// the right way up.
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var videoDevice: AVCaptureDevice?
    @ObservationIgnored private var subjectAreaChangeObserver: Any?
    @ObservationIgnored private var interruptionObserver: Any?
    private var wasInterrupted = false

    deinit {
        if let obs = subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: Permissions

    /// Headshots only need the camera, not the microphone.
    static func requestVideoAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    static func requestAccess() async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        let audio = await AVCaptureDevice.requestAccess(for: .audio)
        return video && audio
    }

    // MARK: Session

    func configure(position: Position = .front, resolution: CameraResolution = .hd1080) {
        self.position = position
        isExposureLocked = false
        zoomFactor = 1
        #if targetEnvironment(simulator)
        currentResolution = resolution
        supportedResolutions = CameraResolution.allCases
        #endif
        queue.async { [weak self] in
            guard let self else { return }
            self.requestedZoomFactor = 1
            session.beginConfiguration()
            session.inputs.forEach { self.session.removeInput($0) }

            let devicePosition: AVCaptureDevice.Position = position == .front ? .front : .back
            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition),
                let videoInput = try? AVCaptureDeviceInput(device: camera),
                session.canAddInput(videoInput)
            else {
                session.commitConfiguration()
                Task { @MainActor in self.state = .failed("Camera unavailable") }
                return
            }
            session.addInput(videoInput)

            let supported = CameraResolution.allCases.filter { self.session.canSetSessionPreset($0.preset) }
            let selected = supported.contains(resolution) ? resolution : (supported.contains(.hd1080) ? .hd1080 : supported.first ?? .hd1080)
            if session.canSetSessionPreset(selected.preset) { session.sessionPreset = selected.preset }

            var hasAudioInput = false
            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
                hasAudioInput = true
            }
            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

            if wantsFaceGuidance {
                if !session.outputs.contains(faceOutput), session.canAddOutput(faceOutput) {
                    faceOutput.alwaysDiscardsLateVideoFrames = true
                    faceOutput.setSampleBufferDelegate(self, queue: faceQueue)
                    session.addOutput(faceOutput)
                }
                // Connections are rebuilt whenever the camera input changes, so set these every time.
                if let conn = faceOutput.connection(with: .video) {
                    let defaultAngle: CGFloat = (position == .front) ? 270 : 90
                    let uprightAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? defaultAngle
                    if conn.isVideoRotationAngleSupported(uprightAngle) {
                        conn.videoRotationAngle = uprightAngle
                        faceBufferIsUpright = true
                    } else if conn.isVideoRotationAngleSupported(90) {
                        conn.videoRotationAngle = 90
                        faceBufferIsUpright = true
                    }
                    if conn.isVideoMirroringSupported {
                        conn.automaticallyAdjustsVideoMirroring = false
                        conn.isVideoMirrored = (position == .front)   // match the mirrored selfie preview
                    }
                }
            }

            // Keep autofocus and autoexposure continuous and smooth so the actor is always sharp.
            try? camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isSmoothAutoFocusSupported {
                camera.isSmoothAutoFocusEnabled = true
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if camera.isSubjectAreaChangeMonitoringEnabled == false {
                camera.isSubjectAreaChangeMonitoringEnabled = true
            }
            camera.unlockForConfiguration()

            session.commitConfiguration()
            session.startRunning()
            let hasAudioMeterConnection = hasAudioInput
                && !(movieOutput.connection(with: .audio)?.audioChannels.isEmpty ?? true)

            Task { @MainActor in
                self.supportedResolutions = supported
                self.currentResolution = selected
                self.audioMeterAvailable = hasAudioMeterConnection
                if !hasAudioMeterConnection { self.audioLevel = 0 }
            }

            if self.subjectAreaChangeObserver == nil {
                self.subjectAreaChangeObserver = NotificationCenter.default.addObserver(
                    forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    self?.resetFocusToContinuous()
                }
            }
            if self.interruptionObserver == nil {
                self.interruptionObserver = NotificationCenter.default.addObserver(
                    forName: AVCaptureSession.wasInterruptedNotification,
                    object: self.session,
                    queue: nil
                ) { [weak self] note in
                    let reasonCode = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? 0
                    let reasonText: String
                    switch reasonCode {
                    case 1: reasonText = "Audio device in use by another app"
                    case 2: reasonText = "Video device in use by another app"
                    case 3: reasonText = "App in background"
                    default: reasonText = "Recording was interrupted"
                    }
                    Task { @MainActor in
                        self?.handleSessionInterruption(reason: reasonText)
                    }
                }
            }
            Task { @MainActor in
                self.videoDevice = camera
                self.updateRotationCoordinator()
                self.state = .ready
                self.startAudioMeterPolling()
            }
        }
    }

    func setResolution(_ resolution: CameraResolution) {
        #if targetEnvironment(simulator)
        // Simulator has no camera capture device. Keep the requested quality as a usable app
        // preference so the control remains testable, while making clear that it won't create media.
        currentResolution = resolution
        supportedResolutions = CameraResolution.allCases
        return
        #else
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            let canSet = session.canSetSessionPreset(resolution.preset)
            if canSet { session.sessionPreset = resolution.preset }
            session.commitConfiguration()
            Task { @MainActor in
                if canSet {
                    self.currentResolution = resolution
                } else {
                    self.supportedResolutions.removeAll { $0 == resolution }
                }
            }
        }
        #endif
    }

    // MARK: Orientation

    /// The on-screen preview registers itself so it can be kept level too.
    @MainActor
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        updateRotationCoordinator()
    }

    @MainActor
    private func updateRotationCoordinator() {
        rotationObservation = nil
        guard let videoDevice else { rotationCoordinator = nil; return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: videoDevice, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        applyFaceOutputRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        let controllerReference = WeakCameraControllerReference(self)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { _, change in
            guard let angle = change.newValue else { return }
            Task { @MainActor in
                controllerReference.value?.applyPreviewRotation(angle)
                if let captureAngle = controllerReference.value?.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture {
                    controllerReference.value?.applyFaceOutputRotation(captureAngle)
                }
            }
        }
    }

    private func applyFaceOutputRotation(_ angle: CGFloat) {
        guard let conn = faceOutput.connection(with: .video), conn.isVideoRotationAngleSupported(angle) else { return }
        conn.videoRotationAngle = angle
        faceBufferIsUpright = true
    }

    @MainActor
    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// Levels an output for how the phone is held right now. Recordings and photos are also never
    /// mirrored: the preview mirrors the front camera so it feels like a mirror, but casting should
    /// see the shot the right way round (a mirrored file flips any text or set dressing behind you).
    private func prepareOutput(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    func lockExposure() {
        lockExposure(at: nil)
    }

    func lockExposure(at viewPoint: CGPoint?) {
        let devicePoint: CGPoint
        if let viewPoint, let layer = previewLayer {
            devicePoint = layer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        } else {
            devicePoint = CGPoint(x: 0.5, y: 0.5)
        }
        let controllerReference = WeakCameraControllerReference(self)
        queue.async { [controllerReference] in
            guard let self = controllerReference.value,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  (try? device.lockForConfiguration()) != nil
            else { return }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint }
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
            device.unlockForConfiguration()
            Task { @MainActor in self.isExposureLocked = true }
        }
    }

    func unlockExposure() {
        let controllerReference = WeakCameraControllerReference(self)
        queue.async { [controllerReference] in
            guard let self = controllerReference.value,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  (try? device.lockForConfiguration()) != nil
            else { return }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
            Task { @MainActor in self.isExposureLocked = false }
        }
    }

    func toggleExposureLock() {
        if isExposureLocked {
            unlockExposure()
        } else {
            lockExposure()
        }
    }

    func resetFocusToContinuous() {
        queue.async { [weak self] in
            guard let self,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  (try? device.lockForConfiguration()) != nil
            else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    @MainActor
    func focusAndLockExposure(at viewPoint: CGPoint) {
        let devicePoint: CGPoint
        if let layer = previewLayer {
            devicePoint = layer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        } else {
            devicePoint = CGPoint(x: 0.5, y: 0.5)
        }

        let controllerReference = WeakCameraControllerReference(self)
        queue.async { [controllerReference] in
            guard let self = controllerReference.value,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  (try? device.lockForConfiguration()) != nil
            else { return }

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                } else if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                } else if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
            }
            device.unlockForConfiguration()
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        queue.async { [weak self] in
            guard let self,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  (try? device.lockForConfiguration()) != nil
            else { return }
            let zoom = min(max(factor, 1), min(device.activeFormat.videoMaxZoomFactor, 5))
            self.requestedZoomFactor = zoom
            // Ramping feels natural on a live preview. Cancelling an in-flight ramp also means a
            // quick series of taps always lands on the last requested zoom level.
            if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
            device.ramp(toVideoZoomFactor: zoom, withRate: 3.5)
            device.unlockForConfiguration()
            Task { @MainActor in self.zoomFactor = zoom }
        }
    }

    func cycleZoom() {
        // Calculate from the capture device on its own serial queue. The former version used the
        // asynchronously updated UI value, so fast taps could repeatedly request 1.5×.
        queue.async { [weak self] in
            guard let self,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  (try? device.lockForConfiguration()) != nil
            else { return }
            let current = self.requestedZoomFactor
            let next: CGFloat = current < 1.25 ? 1.5 : current < 1.75 ? 2 : 1
            self.requestedZoomFactor = next
            if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
            device.ramp(toVideoZoomFactor: next, withRate: 3.5)
            device.unlockForConfiguration()
            Task { @MainActor in self.zoomFactor = next }
        }
    }

    /// Flips between the front and back camera — never mid-take, which would end the recording.
    func switchCamera() {
        guard state == .ready else { return }
        configure(position: position == .front ? .back : .front, resolution: currentResolution)
    }

    func stop() {
        queue.async { [weak self] in self?.session.stopRunning() }
        timer?.invalidate()
        audioMeterTimer?.invalidate()
        audioMeterTimer = nil
        audioMeterTimerTarget = nil
        audioLevel = 0
    }

    @MainActor
    private func startAudioMeterPolling() {
        audioMeterTimer?.invalidate()
        let target = CameraAudioMeterTimerTarget(controller: self)
        audioMeterTimerTarget = target
        audioMeterTimer = Timer.scheduledTimer(
            timeInterval: 0.12,
            target: target,
            selector: #selector(CameraAudioMeterTimerTarget.poll(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @MainActor
    fileprivate func pollAudioMeter() {
        guard audioMeterAvailable,
              let channel = movieOutput.connection(with: .audio)?.audioChannels.first else {
            audioLevel = 0
            return
        }
        // AVFoundation reports dBFS (typically -60...0); expose a smoothed 0...1 value to UI.
        let db = max(-60, min(0, channel.averagePowerLevel))
        let level = Float(pow(10, db / 20))
        audioLevel = audioLevel * 0.55 + level * 0.45
    }

    // MARK: Recording

    func startRecording() {
        guard state == .ready else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("take-\(UUID().uuidString).mov")
        prepareOutput(movieOutput.connection(with: .video))
        lockExposure()
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recording
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.state == .recording else { return }
            self.elapsed += 0.1
        }
        Haptics.impact(.rigid)
    }

    /// Stopping is asynchronous: the file isn't written until AVFoundation calls back, so callers that
    /// need the recording must use `completion` rather than reading `lastRecording` straight away.
    /// A second stop while one is already finishing (say, hold-to-stop plus a spoken "Cut") is
    /// ignored rather than reported as a failed recording — the first stop's completion still fires.
    func stopRecording(_ completion: ((URL?) -> Void)? = nil) {
        guard state == .recording || state == .paused, !isStopping else { return }
        isStopping = true
        recordingFinishedHandler = completion
        movieOutput.stopRecording()
        timer?.invalidate()
        Haptics.success()
    }

    func pauseRecording() {
        guard state == .recording, movieOutput.isRecording else { return }
        movieOutput.pauseRecording()
        timer?.invalidate()
        timer = nil
        state = .paused
        Haptics.tick()
    }

    func resumeRecording() {
        guard state == .paused, movieOutput.isRecording else { return }
        movieOutput.resumeRecording()
        state = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.state == .recording else { return }
            self.elapsed += 0.1
        }
        Haptics.tick()
    }

    private func handleSessionInterruption(reason: String) {
        guard state == .recording || state == .paused else { return }
        wasInterrupted = true
        timer?.invalidate()
        movieOutput.stopRecording()
    }

    // MARK: Photo (headshots)

    /// Reports nil when nothing was captured (camera not ready, capture failed) — callers must not
    /// save anything in that case.
    func capturePhoto(_ completion: @escaping (UIImage?) -> Void) {
        #if targetEnvironment(simulator)
        // No camera in the Simulator: a plain silhouette lets the flow be exercised there.
        Haptics.impact(.medium)
        completion(Self.simulatorPlaceholder)
        #else
        guard state == .ready, session.isRunning, let connection = photoOutput.connection(with: .video) else {
            completion(nil)
            return
        }
        prepareOutput(connection)
        photoHandler = completion
        photoRequestID += 1
        let requestID = photoRequestID
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        Haptics.impact(.medium)
        // If AVFoundation never calls back, don't leave the shutter stuck.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.photoRequestID == requestID, let handler = self.photoHandler else { return }
            self.photoHandler = nil
            handler(nil)
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private static var simulatorPlaceholder: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 720, height: 960)).image { context in
            UIColor(white: 0.12, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 720, height: 960))
            // Body silhouette
            UIColor(white: 0.25, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 140, y: 560, width: 440, height: 460), cornerRadius: 120).fill() // ot-lint:allow
            // Head silhouette
            context.cgContext.fillEllipse(in: CGRect(x: 210, y: 230, width: 300, height: 300))
            // Facial features for Vision face detection in simulator
            UIColor(white: 0.08, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 280, y: 330, width: 35, height: 20))
            context.cgContext.fillEllipse(in: CGRect(x: 405, y: 330, width: 35, height: 20))
            context.cgContext.fillEllipse(in: CGRect(x: 350, y: 375, width: 20, height: 30))
            UIBezierPath(roundedRect: CGRect(x: 310, y: 440, width: 100, height: 22), cornerRadius: 10).fill() // ot-lint:allow
        }
    }
    #endif
}

/// Timer target keeps only a weak controller reference and avoids capturing the non-Sendable
/// AVFoundation controller in Timer's @Sendable closure.
private final class CameraAudioMeterTimerTarget: NSObject {
    weak var controller: CameraController?

    init(controller: CameraController) {
        self.controller = controller
    }

    @MainActor @objc func poll(_ timer: Timer) {
        controller?.pollAudioMeter()
    }
}

/// Weak sendable handle used to access the controller from AVFoundation's queue callbacks.
/// Camera session work remains serialized on the controller's capture queue.
private final class WeakCameraControllerReference: @unchecked Sendable {
    weak var value: CameraController?
    init(_ value: CameraController) { self.value = value }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // AVFoundation can report an error (e.g. disk nearly full) even though the file was finalized
        // and is playable — that case is flagged with AVErrorRecordingSuccessfullyFinishedKey.
        let finished = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let hasSavedContent = fileSize > 1024
        let hadInterruption = wasInterrupted || (!finished && error != nil)

        Task { @MainActor in
            let url = finished ? outputFileURL : (hasSavedContent ? outputFileURL : nil)
            self.lastRecording = finished ? outputFileURL : nil
            self.state = .ready
            self.isStopping = false

            if hadInterruption {
                let reason = self.wasInterrupted ? "Recording interrupted by system" : (error?.localizedDescription ?? "Recording interrupted")
                self.lastInterruption = InterruptionEvent(
                    url: hasSavedContent ? outputFileURL : nil,
                    duration: self.elapsed,
                    hasSavedContent: hasSavedContent,
                    reason: reason
                )
                self.wasInterrupted = false
            }

            let handler = self.recordingFinishedHandler
            self.recordingFinishedHandler = nil
            handler?(url)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        Task { @MainActor in self.photoHandler?(image); self.photoHandler = nil }
    }
}
