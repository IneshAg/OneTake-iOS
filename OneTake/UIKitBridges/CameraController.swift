import AVFoundation
import SwiftUI
import UIKit

/// AVFoundation capture pipeline for takes and headshots.
/// SwiftUI has no camera view, so this is the main place OneTake drops to UIKit/AVFoundation.
@Observable
final class CameraController: NSObject {
    enum Position { case front, back }
    enum State: Equatable { case idle, ready, recording, failed(String) }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastRecording: URL?
    private(set) var audioLevel: Float = 0

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "onetake.camera")
    private var timer: Timer?
    private var photoHandler: ((UIImage?) -> Void)?
    /// Called once the movie file is actually finalized on disk — `stopRecording()` returns before that.
    private var recordingFinishedHandler: ((URL?) -> Void)?
    private var isStopping = false
    private var position: Position = .front

    // MARK: Permissions

    static func requestAccess() async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        let audio = await AVCaptureDevice.requestAccess(for: .audio)
        return video && audio
    }

    // MARK: Session

    func configure(position: Position = .front) {
        self.position = position
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

            // Lock exposure once framed so the light doesn't pump mid-take ("Exposure locked" pill in the HUD).
            try? camera.lockForConfiguration()
            if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
            camera.unlockForConfiguration()

            session.commitConfiguration()
            session.startRunning()
            Task { @MainActor in self.state = .ready }
        }
    }

    func lockExposure() {
        queue.async { [weak self] in
            guard let device = (self?.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            device.unlockForConfiguration()
        }
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
        if let connection = movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = position == .front
        }
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recording
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.elapsed += 0.1
        }
        Haptics.impact(.rigid)
    }

    /// Stopping is asynchronous: the file isn't written until AVFoundation calls back, so callers that
    /// need the recording must use `completion` rather than reading `lastRecording` straight away.
    /// A second stop while one is already finishing (say, hold-to-stop plus a spoken "Cut") is
    /// ignored rather than reported as a failed recording — the first stop's completion still fires.
    func stopRecording(_ completion: ((URL?) -> Void)? = nil) {
        guard state == .recording, !isStopping else { return }
        isStopping = true
        recordingFinishedHandler = completion
        movieOutput.stopRecording()
        timer?.invalidate()
        Haptics.success()
    }

    // MARK: Photo (headshots)

    func capturePhoto(fallbackName: String = "Headshot", _ completion: @escaping (UIImage?) -> Void) {
        #if targetEnvironment(simulator)
        Haptics.impact(.medium)
        completion(UIImage(named: fallbackName) ?? UIImage(named: "Headshot"))
        #else
        guard state == .ready, session.isRunning, photoOutput.connection(with: .video) != nil else {
            completion(UIImage(named: fallbackName) ?? UIImage(named: "Headshot"))
            return
        }
        photoHandler = completion
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        Haptics.impact(.medium)
        #endif
    }
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
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in self.photoHandler?(image); self.photoHandler = nil }
    }
}

// MARK: - Preview layer (UIKit)

/// Hosts `AVCaptureVideoPreviewLayer` — not available in SwiftUI — inside a `UIView`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = gravity
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
            CameraPreview(session: controller.session)
            #endif
        }
        .ignoresSafeArea()
    }
}
