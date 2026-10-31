import SwiftUI
import UIKit
import VisionKit
import Speech
import AVFoundation

// MARK: - Haptics (UIKit feedback generators)

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Share sheet (UIActivityViewController)

/// "More ways to share" on the package screen — AirDrop, Mail, Messages, Files, or the casting
/// site's own app/upload if it's installed. `onComplete` reports whether the person actually
/// finished a share action (vs. dismissing), which is what "sent" should mean with no real backend.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete?(completed) }
        return vc
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Trim (UIVideoEditorController, UIKit-only)

/// The system trimmer: drag the ends, tap Save. Reports the trimmed file (in a temporary location),
/// or nil if the person cancelled or it failed.
struct VideoTrimmer: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (URL?) -> Void

    static func canTrim(_ url: URL) -> Bool { UIVideoEditorController.canEditVideo(atPath: url.path) }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIVideoEditorController {
        let editor = UIVideoEditorController()
        editor.videoPath = url.path
        editor.videoQuality = .typeHigh
        editor.delegate = context.coordinator
        return editor
    }
    func updateUIViewController(_ editor: UIVideoEditorController, context: Context) {}

    final class Coordinator: NSObject, UIVideoEditorControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        /// UIVideoEditorController can call its save callback twice; only the first counts.
        private var finished = false
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        private func finish(_ url: URL?) {
            guard !finished else { return }
            finished = true
            onFinish(url)
        }
        func videoEditorController(_ editor: UIVideoEditorController, didSaveEditedVideoToPath editedVideoPath: String) {
            finish(URL(fileURLWithPath: editedVideoPath))
        }
        func videoEditorControllerDidCancel(_ editor: UIVideoEditorController) { finish(nil) }
        func videoEditorController(_ editor: UIVideoEditorController, didFailWithError error: Error) { finish(nil) }
    }
}

// MARK: - Document scanner (VisionKit, UIKit-only)

/// Helper view added to VisionKit's document camera hierarchy to monitor layout passes
/// and ensure the Save/Checkmark tick button stays positioned at the bottom right.
final class DocumentScannerLayoutHelperView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

enum DocumentScannerCustomizer {
    static func findView(in root: UIView, className: String) -> UIView? {
        if String(describing: type(of: root)).contains(className) { return root }
        for sub in root.subviews {
            if let found = findView(in: sub, className: className) { return found }
        }
        return nil
    }

    /// Recursively searches a view controller and its child hierarchy for the VisionKit Save/Checkmark button.
    static func findSaveButton(in vc: UIViewController) -> UIButton? {
        _ = vc.view
        if let btn = findView(in: vc.view, className: "SaveButton") as? UIButton {
            return btn
        }
        for child in vc.children {
            _ = child.view
            if let btn = findView(in: child.view, className: "SaveButton") as? UIButton {
                return btn
            }
            if let nav = child as? UINavigationController {
                for childVC in nav.viewControllers {
                    _ = childVC.view
                    if let btn = findView(in: childVC.view, className: "SaveButton") as? UIButton {
                        return btn
                    }
                }
            }
        }
        return nil
    }

    /// Positions the Save / Checkmark tick button at the bottom-right corner of the camera viewport
    /// for convenient one-handed thumb reach, aligned horizontally with the shutter and thumbnail.
    static func reposition(saveButton: UIButton, in sv: UIView) {
        guard sv.bounds.height > 0, sv.bounds.width > 0, sv.bounds.height > sv.bounds.width else { return } // portrait only
        guard saveButton.superview === sv else { return }

        let thumb = findView(in: sv, className: "Thumbnail")
        let shutter = findView(in: sv, className: "ShutterButton")

        let thumbLeading = thumb?.frame.origin.x ?? 28.0
        let margin: CGFloat = (thumbLeading > 0 && thumbLeading < 100) ? thumbLeading : 28.0

        let halfH = sv.bounds.height / 2.0
        let shutterY = (shutter != nil && shutter!.frame.origin.y > halfH) ? shutter!.center.y : 0
        let thumbY = (thumb != nil && thumb!.frame.origin.y > halfH) ? thumb!.center.y : 0
        let fallbackY = sv.bounds.height - max(sv.safeAreaInsets.bottom, 20.0) - 45.0
        let centerY = shutterY > 0 ? shutterY : (thumbY > 0 ? thumbY : fallbackY)

        let w = saveButton.bounds.width > 0 ? saveButton.bounds.width : 54.0
        let h = saveButton.bounds.height > 0 ? saveButton.bounds.height : 54.0

        let newX = sv.bounds.width - margin - w
        let newY = centerY - (h / 2.0)
        let targetFrame = CGRect(x: newX, y: newY, width: w, height: h)

        if saveButton.frame != targetFrame {
            saveButton.frame = targetFrame
        }
        if saveButton.superview === sv {
            sv.bringSubviewToFront(saveButton)
        }
    }
}

/// "Scan the pages" for printed sides. Returns recognised page images.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        context.coordinator.attachCustomizer(to: vc)
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {
        context.coordinator.attachCustomizer(to: vc)
    }
    static func dismantleUIViewController(_ uiViewController: VNDocumentCameraViewController, coordinator: Coordinator) {
        coordinator.detachCustomizer()
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        private var frameObservation: NSKeyValueObservation?
        private var hiddenObservation: NSKeyValueObservation?
        private var boundsObservation: NSKeyValueObservation?
        private var isRepositioning = false
        private var isFinished = false
        private weak var helperView: DocumentScannerLayoutHelperView?

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        deinit {
            detachCustomizer()
        }

        func detachCustomizer() {
            guard !isFinished else { return }
            isFinished = true
            boundsObservation?.invalidate()
            boundsObservation = nil
            frameObservation?.invalidate()
            frameObservation = nil
            hiddenObservation?.invalidate()
            hiddenObservation = nil
            helperView?.onLayout = nil
            helperView?.removeFromSuperview()
            helperView = nil
        }

        func attachCustomizer(to vc: VNDocumentCameraViewController) {
            guard !isFinished else { return }
            guard let saveBtn = DocumentScannerCustomizer.findSaveButton(in: vc),
                  let root = saveBtn.superview else {
                return
            }

            // Layout helper to react to parent layoutSubviews
            if let existingHelper = root.subviews.first(where: { $0 is DocumentScannerLayoutHelperView }) as? DocumentScannerLayoutHelperView {
                self.helperView = existingHelper
            } else {
                let helper = DocumentScannerLayoutHelperView()
                helper.isUserInteractionEnabled = false
                helper.isHidden = false
                helper.frame = root.bounds
                helper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                helper.onLayout = { [weak self, weak root, weak saveBtn] in
                    guard let self, let root, let saveBtn else { return }
                    self.performReposition(saveButton: saveBtn, in: root)
                }
                root.addSubview(helper)
                self.helperView = helper
            }

            // KVO on bounds to react to screen rotation or resizing
            boundsObservation = root.observe(\.bounds, options: [.new]) { [weak self, weak saveBtn] sv, _ in
                guard let self, let saveBtn else { return }
                self.performReposition(saveButton: saveBtn, in: sv)
            }

            // KVO on frame
            frameObservation = saveBtn.observe(\.frame, options: [.new]) { [weak self, weak root] btn, _ in
                guard let self, let root else { return }
                self.performReposition(saveButton: btn, in: root)
            }

            // KVO on isHidden
            hiddenObservation = saveBtn.observe(\.isHidden, options: [.new]) { [weak self, weak root] btn, _ in
                guard let self, let root else { return }
                self.performReposition(saveButton: btn, in: root)
            }

            performReposition(saveButton: saveBtn, in: root)
        }

        private func performReposition(saveButton: UIButton, in sv: UIView) {
            guard !isFinished, !isRepositioning else { return }
            guard saveButton.superview === sv else { return }
            isRepositioning = true
            defer { isRepositioning = false }
            DocumentScannerCustomizer.reposition(saveButton: saveButton, in: sv)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard !isFinished else { return }
            detachCustomizer()
            let count = scan.pageCount
            var pages: [UIImage] = []
            pages.reserveCapacity(count)
            for i in 0..<count {
                pages.append(scan.imageOfPage(at: i))
            }
            DispatchQueue.main.async { [weak self] in
                self?.onFinish(pages)
            }
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            guard !isFinished else { return }
            detachCustomizer()
            DispatchQueue.main.async { [weak self] in
                self?.onFinish([])
            }
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            guard !isFinished else { return }
            detachCustomizer()
            DispatchQueue.main.async { [weak self] in
                self?.onFinish([])
            }
        }
    }
}

// MARK: - Idle timer (keep the screen awake while filming)

struct KeepScreenAwake: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View { func keepScreenAwake() -> some View { modifier(KeepScreenAwake()) } }

// MARK: - Speech follower (prompter follows your voice, "Action" / "Cut")

@Observable
final class SpeechFollower {
    /// A spoken command. Each one is distinct (even the same word twice) so `onChange` fires every time.
    struct Command: Equatable {
        let word: String
        private let id = UUID()
        init(word: String) { self.word = word }
    }

    private(set) var spokenWordCount = 0
    private(set) var transcript = ""
    private(set) var lastCommand: Command?
    private(set) var isListening = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// The recognizer keeps transcribing one continuous session, so its word count never goes back
    /// to zero. `reset()` records where the current line starts instead.
    private var totalWords = 0
    private var wordOffset = 0

    /// Command words and natural synonyms. A word triggers as a command when followed by a brief
    /// pause or the end of the utterance so dialogue words ("Now listen...") don't misfire.
    private var pendingWord: String?
    private var pendingIndex: Int = -1
    private var lastFiredIndex: Int = -1
    private var pendingTask: Task<Void, Never>?

    static func canonicalCommand(for raw: String) -> String? {
        let word = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
        switch word {
        case "now", "capture", "shoot", "snap", "cheese", "click", "photo", "picture", "take":
            return "now"
        case "action", "roll", "rolling":
            return "action"
        case "cut", "stop":
            return "cut"
        case "line":
            return "line"
        default:
            return nil
        }
    }

    /// Speech recognition *and* the microphone — the follower can't hear anything without both.
    static func requestAccess() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Bumped on every restart/stop, so a callback from a recognition task that was replaced (its
    /// cancellation reports an error) can't trigger yet another restart.
    private var generation = 0
    private var configurationObserver: NSObjectProtocol?

    func start() {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        // The input node only has a usable format once the audio session allows recording. On a
        // fresh session (Run Lines, drills — no camera has configured it) installing the tap with
        // that empty format raises an exception.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch { return }
        guard startEngine() else { return }
        isListening = true

        // The camera reconfiguring the shared audio session stops the engine; pick it back up.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isListening else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            _ = self.startEngine()
        }
        beginRecognition()
    }

    private func startEngine() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
    }

    private func beginRecognition() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        let generation = self.generation

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let words = result.bestTranscription.segments.map {
                    $0.substring.lowercased().trimmingCharacters(in: .punctuationCharacters)
                }
                Task { @MainActor in self.handle(words) }
            }
            // Recognition ends on its own — a final result, a long silence, the system's time limit.
            // While still meant to be listening, start a fresh one so commands keep working all shoot.
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.finishCurrentUtterance()
                    await self.restartRecognition(from: generation)
                }
            }
        }
    }

    @MainActor
    private func restartRecognition(from ended: Int) async {
        guard isListening, ended == generation else { return }
        generation += 1
        request?.endAudio()
        task?.cancel()
        // A new recognition counts words from zero again.
        totalWords = 0
        wordOffset = 0
        lastFiredIndex = -1
        pendingWord = nil
        pendingIndex = -1
        pendingTask?.cancel()
        pendingTask = nil
        // Brief pause so an immediately-failing recognizer can't spin.
        try? await Task.sleep(for: .milliseconds(300))
        guard isListening else { return }
        beginRecognition()
    }

    @MainActor
    func fireCommand(_ word: String, at index: Int) {
        guard index > lastFiredIndex else { return }
        lastFiredIndex = index
        pendingWord = nil
        pendingIndex = -1
        pendingTask?.cancel()
        pendingTask = nil
        lastCommand = Command(word: word)
    }

    @MainActor
    func finishCurrentUtterance() {
        if let word = pendingWord, pendingIndex > lastFiredIndex {
            fireCommand(word, at: pendingIndex)
        }
    }

    @MainActor
    func handle(_ words: [String]) {
        if words.count < totalWords {
            lastFiredIndex = -1
            pendingWord = nil
            pendingIndex = -1
            pendingTask?.cancel()
            pendingTask = nil
        }
        totalWords = words.count
        let currentLineWords = words.dropFirst(min(wordOffset, words.count))
        transcript = currentLineWords.joined(separator: " ")
        spokenWordCount = currentLineWords.count

        let currentIndex = words.count - 1
        guard currentIndex >= 0, currentIndex > lastFiredIndex else { return }
        let last = words[currentIndex]

        guard let cmd = Self.canonicalCommand(for: last) else {
            // New speech arrived and it's not a command: cancel any pending command
            if pendingWord != nil {
                pendingTask?.cancel()
                pendingTask = nil
                pendingWord = nil
                pendingIndex = -1
            }
            return
        }

        // A command word was spoken. Schedule it to fire if no speech continues.
        pendingWord = cmd
        pendingIndex = currentIndex
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.fireCommand(cmd, at: currentIndex)
        }
    }

    func stop() {
        // Before cancelling, so the cancelled task's callback doesn't restart recognition.
        isListening = false
        generation += 1
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        totalWords = 0
        wordOffset = 0
        lastFiredIndex = -1
        pendingWord = nil
        pendingIndex = -1
        pendingTask?.cancel()
        pendingTask = nil
    }

    func reset() {
        totalWords = 0
        wordOffset = 0
        spokenWordCount = 0
        transcript = ""
        lastCommand = nil
        pendingWord = nil
        pendingIndex = -1
        pendingTask?.cancel()
        pendingTask = nil
        lastFiredIndex = -1
    }
}

@Observable
final class CameraGuidanceSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenAt = Date.distantPast
    private var lastMessage = ""

    /// Prefer the clearest installed US English system voice. Enhanced and Premium voices are
    /// downloaded through iOS settings; use the built-in voice if neither is installed.
    private var preferredVoice: AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: 2
            case .enhanced: 1
            default: 0
            }
        }
        return voices.max { qualityRank($0) < qualityRank($1) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func speak(_ message: String, minInterval: TimeInterval = 2.0, repeatInterval: TimeInterval = 4.5) {
        guard !message.isEmpty else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpokenAt)
        if message == lastMessage {
            guard elapsed >= repeatInterval else { return }
        } else {
            guard elapsed >= minInterval else { return }
        }
        lastMessage = message
        lastSpokenAt = now
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.43
        utterance.pitchMultiplier = 0.98
        utterance.volume = 0.88
        utterance.voice = preferredVoice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lastMessage = ""
    }
}

// MARK: - Reader track playback (your own recorded voice only)

/// Plays the reader lines the actor recorded in "Record Maya". One file per line, saved by RecordReaderView.
@Observable
final class ReaderTrackPlayer {
    private var player: AVAudioPlayer?
    var duration: TimeInterval? { player?.duration }

    /// Root folder for every reader recording, so size and delete-all can treat it as one unit.
    static let folder = "reader"

    /// One file per reader line, scoped to the audition and scene it was recorded for — so one
    /// audition's reader never plays (or overwrites) another's.
    static func url(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> URL {
        MediaStore.directory("\(folder)/\(auditionID.uuidString)/scene-\(sceneIndex)")
            .appendingPathComponent("line-\(index).m4a")
    }

    /// Checks if a valid recording exists for this reader cue.
    static func hasRecording(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> Bool {
        let url = self.url(auditionID: auditionID, sceneIndex: sceneIndex, line: index)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 1 > 0
        }
        if fm.fileExists(atPath: url.standardizedFileURL.path) {
            return (try? url.standardizedFileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 1 > 0
        }
        return false
    }

    /// Plays one recorded reader line. Returns false when that line hasn't been recorded.
    @discardableResult
    func play(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int, volume: Float = 1) -> Bool {
        let url = Self.url(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
        guard Self.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex) else { return false }  // not recorded yet → silent cue
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = volume
        return player?.play() ?? false
    }

    func stop() { player?.stop() }
}

enum ReaderRecordResult {
    case success(duration: TimeInterval)
    case tooShort(duration: TimeInterval)
    case noSpeechDetected
    case recordingFailed(String)
}

/// Records one reader line to disk with speech verification and acoustic voice activity detection.
@Observable
final class ReaderLineRecorder {
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    var liveAudioLevel: Float = 0.0
    private var maxPeakPower: Float = -160.0
    private var speechFramesCount: Int = 0
    private var totalFramesCount: Int = 0
    private var startTime: Date = .now

    @discardableResult
    func start(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int) -> Bool {
        let session = AVAudioSession.sharedInstance()
        #if !targetEnvironment(simulator)
        guard session.recordPermission == .granted else { return false }
        #endif
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch { return false }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let url = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.isMeteringEnabled = true
        self.recorder = recorder
        guard recorder.record() else { self.recorder = nil; return false }

        startTime = Date()
        maxPeakPower = -160.0
        speechFramesCount = 0
        totalFramesCount = 0
        liveAudioLevel = 0.0

        meterTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder, rec.isRecording else { return }
            rec.updateMeters()
            let peak = rec.peakPower(forChannel: 0)
            let avg = rec.averagePower(forChannel: 0)
            if peak > self.maxPeakPower { self.maxPeakPower = peak }
            self.totalFramesCount += 1
            if peak > -24.0 && avg > -40.0 {
                self.speechFramesCount += 1
            }
            let clamped = max(-60.0, min(0.0, peak))
            let linear = pow(10.0, clamped / 30.0)
            Task { @MainActor in
                self.liveAudioLevel = max(0.0, min(1.0, linear))
            }
        }
        meterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    func stop(expectedText: String? = nil) async -> ReaderRecordResult {
        meterTimer?.invalidate()
        meterTimer = nil
        await MainActor.run { self.liveAudioLevel = 0.0 }

        guard let recorder else { return .recordingFailed("Recorder was not active.") }
        let url = recorder.url
        let duration = max(recorder.currentTime, Date().timeIntervalSince(startTime))
        recorder.stop()
        self.recorder = nil

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: url.standardizedFileURL.path) else {
            return .recordingFailed("No audio file was created.")
        }

        // Accidental quick click and stop: less than 1.0 second cannot be a valid spoken dialogue cue
        if duration < 1.0 {
            try? fm.removeItem(at: url)
            return .tooShort(duration: duration)
        }

        // Check 1: Speech recognition verification (transcribed words)
        let recognizedSpeech = await checkSpeechWords(in: url)
        if recognizedSpeech {
            return .success(duration: duration)
        }

        // Check 2: Acoustic Voice Activity Detection (VAD)
        let hasAcousticVoice = (maxPeakPower > -24.0 && speechFramesCount >= 4) || (maxPeakPower > -18.0 && speechFramesCount >= 2)
        if hasAcousticVoice {
            return .success(duration: duration)
        }

        // Neither words nor acoustic vocal energy detected: quiet or empty tap
        try? fm.removeItem(at: url)
        return .noSpeechDetected
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        liveAudioLevel = 0.0
    }

    private func checkSpeechWords(in url: URL) async -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            return false
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    var hasResumed = false
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        guard !hasResumed else { return }
                        if let result {
                            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                hasResumed = true
                                continuation.resume(returning: true)
                            } else if result.isFinal {
                                hasResumed = true
                                continuation.resume(returning: false)
                            }
                        } else if error != nil {
                            hasResumed = true
                            continuation.resume(returning: false)
                        }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                        if !hasResumed {
                            hasResumed = true
                            task.cancel()
                            continuation.resume(returning: false)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Enable swipe back when navigation bar is hidden

extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
