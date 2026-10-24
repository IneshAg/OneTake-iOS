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

/// "Scan the pages" for printed sides. Returns recognised page images.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
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

    /// Command words also turn up in dialogue ("…I said cut", "Now listen"). A word only counts as a
    /// command when it's said on its own: a pause before it and no more speech straight after.
    private static let commandWords: Set<String> = ["action", "cut", "line", "now"]
    private static let commandPause: TimeInterval = 0.5
    private var latestWords: [String] = []
    private var lastWordAt = Date.distantPast
    /// Word count up to which a command has already fired, so re-sent partial results can't repeat it.
    private var firedThroughWord = 0
    private var pendingCommand: Task<Void, Never>?

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
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
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
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
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
                Task { @MainActor in await self.restartRecognition(from: generation) }
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
        latestWords = []
        firedThroughWord = 0
        pendingCommand?.cancel()
        pendingCommand = nil
        // Brief pause so an immediately-failing recognizer can't spin.
        try? await Task.sleep(for: .milliseconds(300))
        guard isListening else { return }
        beginRecognition()
    }

    @MainActor
    private func handle(_ words: [String]) {
        let now = Date()
        if words.count > totalWords {
            let silenceBefore = now.timeIntervalSince(lastWordAt)
            // Any new speech means a pending command wasn't said on its own.
            pendingCommand?.cancel()
            pendingCommand = nil
            if words.count == totalWords + 1, words.count > firedThroughWord,
               let last = words.last, Self.commandWords.contains(last), silenceBefore >= Self.commandPause {
                let count = words.count
                pendingCommand = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Self.commandPause))
                    guard let self, !Task.isCancelled, self.latestWords.count == count, self.latestWords.last == last else { return }
                    self.firedThroughWord = count
                    self.lastCommand = Command(word: last)
                }
            }
            lastWordAt = now
        }
        latestWords = words
        totalWords = words.count
        spokenWordCount = max(0, words.count - wordOffset)
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
        latestWords = []
        lastWordAt = .distantPast
        firedThroughWord = 0
        pendingCommand?.cancel()
        pendingCommand = nil
    }

    func reset() {
        wordOffset = totalWords
        spokenWordCount = 0
        lastCommand = nil
        pendingCommand?.cancel()
        pendingCommand = nil
    }
}

// MARK: - Reader track playback (your own recorded voice only)

/// Plays the reader lines the actor recorded in "Record Maya". One file per line, saved by RecordReaderView.
@Observable
final class ReaderTrackPlayer {
    private var player: AVAudioPlayer?

    /// Root folder for every reader recording, so size and delete-all can treat it as one unit.
    static let folder = "reader"

    /// One file per reader line, scoped to the audition and scene it was recorded for — so one
    /// audition's reader never plays (or overwrites) another's.
    static func url(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> URL {
        MediaStore.directory("\(folder)/\(auditionID.uuidString)/scene-\(sceneIndex)")
            .appendingPathComponent("line-\(index).m4a")
    }

    /// Plays one recorded reader line. Returns false when that line hasn't been recorded.
    @discardableResult
    func play(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int, volume: Float = 1) -> Bool {
        let url = Self.url(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }  // not recorded yet → silent cue
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = volume
        return player?.play() ?? false
    }

    func stop() { player?.stop() }
}

/// Records one reader line to disk.
@Observable
final class ReaderLineRecorder {
    private var recorder: AVAudioRecorder?

    func start(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]
        recorder = try? AVAudioRecorder(url: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex), settings: settings)
        recorder?.record()
    }

    func stop() { recorder?.stop() }
}
