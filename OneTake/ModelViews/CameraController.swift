import AVFoundation
import SwiftUI
import UIKit
import Vision

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
    private(set) var openPalmDetected = false
    private(set) var isExposureLocked = false
    private(set) var zoomFactor: CGFloat = 1

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
    private(set) var face: FaceReading?
    /// On-device body-pose landmarks used only for the optional setup coach.
    struct BodyPoseReading: Equatable {
        var shoulderCenterX: CGFloat
        var shoulderTiltDegrees: Double
    }
    private(set) var bodyPose: BodyPoseReading?
    /// Average brightness of the frame, 0…1 (updates alongside `face`).
    private(set) var lightLevel: Double?
    @ObservationIgnored var wantsFaceGuidance = false
    @ObservationIgnored var wantsBodyPoseGuidance = false
    @ObservationIgnored var wantsHandGesture = false
    /// Pause detection (e.g. once recording starts) without tearing the output down.
    @ObservationIgnored var faceGuidanceActive = true
    @ObservationIgnored private let faceOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let faceQueue = DispatchQueue(label: "onetake.camera.face")
    @ObservationIgnored private var lastFaceCheck = Date.distantPast
    @ObservationIgnored private var faceBufferIsUpright = false
    @ObservationIgnored private var photoRequestID = 0

    func clearBodyPose() { bodyPose = nil }
    func clearHandGestureDetection() { openPalmDetected = false }

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "onetake.camera")
    private var timer: Timer?
    private var photoHandler: ((UIImage?) -> Void)?
    /// Called once the movie file is actually finalized on disk — `stopRecording()` returns before that.
    private var recordingFinishedHandler: ((URL?) -> Void)?
    private var isStopping = false
    private(set) var position: Position = .front

    /// Keeps recordings, photos and the preview upright however the phone is held. Without it every
    /// clip is written in the sensor's own orientation, so only one way of holding the phone came out
    /// the right way up.
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var videoDevice: AVCaptureDevice?

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

    func configure(position: Position = .front) {
        self.position = position
        isExposureLocked = false
        zoomFactor = 1
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .hd1920x1080
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

            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
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

            // Lock exposure once framed so the light doesn't pump mid-take ("Exposure locked" pill in the HUD).
            try? camera.lockForConfiguration()
            if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
            camera.unlockForConfiguration()

            session.commitConfiguration()
            session.startRunning()
            Task { @MainActor in
                self.videoDevice = camera
                self.updateRotationCoordinator()
                self.state = .ready
            }
        }
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
        queue.async { [weak self] in
            guard let self,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  device.isExposureModeSupported(.locked),
                  (try? device.lockForConfiguration()) != nil
            else { return }
            device.exposureMode = .locked
            device.unlockForConfiguration()
            // Only claim "Exposure locked" in the HUD once it really is.
            Task { @MainActor in self.isExposureLocked = true }
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        queue.async { [weak self] in
            guard let self,
                  let device = self.session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }),
                  (try? device.lockForConfiguration()) != nil
            else { return }
            let zoom = min(max(factor, 1), min(device.activeFormat.videoMaxZoomFactor, 5))
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
            Task { @MainActor in self.zoomFactor = zoom }
        }
    }

    func cycleZoom() {
        let next: CGFloat
        if zoomFactor < 1.25 { next = 1.5 }
        else if zoomFactor < 1.75 { next = 2 }
        else { next = 1 }
        setZoomFactor(next)
    }

    /// Flips between the front and back camera — never mid-take, which would end the recording.
    func switchCamera() {
        guard state == .ready else { return }
        configure(position: position == .front ? .back : .front)
    }

    /// Roughly how many minutes of 1080p30 video still fit on this iPhone (~120 MB a minute).
    static var recordingMinutesLeft: Int? {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int(bytes / 120_000_000)
    }

    func stop() {
        queue.async { [weak self] in self?.session.stopRunning() }
        timer?.invalidate()
    }

    // MARK: Recording

    func startRecording() {
        guard state == .ready else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("take-\(UUID().uuidString).mov")
        prepareOutput(movieOutput.connection(with: .video))
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
            UIColor(white: 0.25, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 210, y: 230, width: 300, height: 300))
            UIBezierPath(roundedRect: CGRect(x: 140, y: 560, width: 440, height: 460), cornerRadius: 120).fill()
        }
    }
    #endif
}

/// A main-actor-isolated weak handle lets AVFoundation's Sendable KVO callback hop back to the UI
/// actor without capturing the non-Sendable camera controller in that callback.
@MainActor
private final class WeakCameraControllerReference {
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
        Task { @MainActor in
            let url = finished ? outputFileURL : nil
            self.lastRecording = url
            self.state = .ready
            self.isStopping = false
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

// MARK: - Preview layer (UIKit)

/// Hosts `AVCaptureVideoPreviewLayer` — not available in SwiftUI — inside a `UIView`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    /// Hands the preview layer to whoever keeps it level (see `CameraController.attachPreview`).
    var onLayer: (@MainActor (AVCaptureVideoPreviewLayer) -> Void)? = nil

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = gravity
        onLayer?(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.videoGravity = gravity
    }
}

/// Camera background that falls back to a still in the Simulator (no camera there).
struct CameraBackground: View {
    let controller: CameraController
    var body: some View {
        ZStack {
            OT.cameraBg
            #if targetEnvironment(simulator)
            GeometryReader { geo in
                HeadshotImage()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.85)
            }
            #else
            CameraPreview(session: controller.session) { layer in controller.attachPreview(layer) }
            #endif
        }
        .ignoresSafeArea()
    }
}

// MARK: - Live face detection (headshot alignment)

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        let minimumInterval = wantsBodyPoseGuidance ? 0.25 : 0.15
        guard (faceGuidanceActive || wantsHandGesture), now.timeIntervalSince(lastFaceCheck) > minimumInterval,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFaceCheck = now
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let poseRequest = wantsBodyPoseGuidance ? VNDetectHumanBodyPoseRequest() : nil
        let handRequest = wantsHandGesture ? VNDetectHumanHandPoseRequest() : nil
        handRequest?.maximumHandCount = 1
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: faceBufferIsUpright ? .up : .right, options: [:])
        var requests: [VNRequest] = [request]
        if let poseRequest { requests.append(poseRequest) }
        if let handRequest { requests.append(handRequest) }
        try? handler.perform(requests)
        var results = request.results ?? []
        if results.isEmpty || (wantsBodyPoseGuidance && (poseRequest?.results?.isEmpty ?? true))
            || (wantsHandGesture && (handRequest?.results?.isEmpty ?? true)) {
            // Orientation fallback in case sensor orientation or device flip inverts the buffer
            let fallbackOrientation: CGImagePropertyOrientation = faceBufferIsUpright ? .down : .left
            let fallbackHandler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: fallbackOrientation, options: [:])
            try? fallbackHandler.perform(requests)
            results = request.results ?? []
        }
        let best = results.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
        let reading = best.map {
            FaceReading(centerX: $0.boundingBox.midX, centerY: 1 - $0.boundingBox.midY,
                        height: $0.boundingBox.height, yaw: $0.yaw?.doubleValue)
        }
        let pose = poseRequest?.results?.first.flatMap { observation -> BodyPoseReading? in
            guard let left = try? observation.recognizedPoint(.leftShoulder),
                  let right = try? observation.recognizedPoint(.rightShoulder),
                  left.confidence >= 0.3, right.confidence >= 0.3 else { return nil }
            let dx = Double(right.location.x - left.location.x)
            guard abs(dx) > 0.04 else { return nil }
            let dy = Double(right.location.y - left.location.y)
            return BodyPoseReading(shoulderCenterX: (left.location.x + right.location.x) / 2,
                                   shoulderTiltDegrees: atan2(dy, abs(dx)) * 180 / .pi)
        }
        let openPalm = handRequest?.results?.contains(where: Self.isOpenPalm) ?? false
        let luma = Self.averageLuma(buffer)
        Task { @MainActor in
            self.face = reading
            self.bodyPose = self.wantsBodyPoseGuidance ? pose : nil
            self.openPalmDetected = self.wantsHandGesture && openPalm
            self.lightLevel = luma
        }
    }

    private static func isOpenPalm(_ hand: VNHumanHandPoseObservation) -> Bool {
        guard let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence >= 0.3 else { return false }
        let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP), (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP)
        ]
        return fingers.allSatisfy { tipName, pipName in
            guard let tip = try? hand.recognizedPoint(tipName),
                  let pip = try? hand.recognizedPoint(pipName),
                  tip.confidence >= 0.25, pip.confidence >= 0.25 else { return false }
            let tipDistance = hypot(tip.location.x - wrist.location.x, tip.location.y - wrist.location.y)
            let pipDistance = hypot(pip.location.x - wrist.location.x, pip.location.y - wrist.location.y)
            return tipDistance > pipDistance * 1.18
        }
    }

    /// Mean brightness of the luma plane, sampled sparsely (cheap enough to run several times a second).
    private static func averageLuma(_ buffer: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPlaneCount(buffer) > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        var count = 0
        for y in Swift.stride(from: 0, to: height, by: 24) {
            for x in Swift.stride(from: 0, to: width, by: 24) {
                sum += Int(pixels[y * rowBytes + x])
                count += 1
            }
        }
        return count > 0 ? Double(sum) / Double(count) / 255 : nil
    }
}
