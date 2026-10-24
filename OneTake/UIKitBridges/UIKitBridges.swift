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

// MARK: - Clipboard (UIPasteboard) — "On your clipboard" card in Add audition

enum Clipboard {
    static var castingNotice: String? {
        guard UIPasteboard.general.hasStrings, let text = UIPasteboard.general.string else { return nil }
        let lower = text.lowercased()
        return (lower.contains("tape") || lower.contains("audition") || lower.contains("sides")) ? text : nil
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

    /// What you've said since the last `reset()`, word by word (lowercased, no punctuation) — what
    /// `otMatch` lines up against the script.
    private(set) var heardWords: [String] = []
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
        heardWords = []
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
        heardWords = Array(words.dropFirst(wordOffset))
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
        heardWords = []
        lastWordAt = .distantPast
        firedThroughWord = 0
        pendingCommand?.cancel()
        pendingCommand = nil
    }

    func reset() {
        wordOffset = totalWords
        heardWords = []
        lastCommand = nil
        pendingCommand?.cancel()
        pendingCommand = nil
    }
}

// MARK: - Reader track playback (your own recorded voice; a built-in voice fills gaps in rehearsal)

/// Plays the reader lines the actor recorded in "Record Maya". One file per line, saved by RecordReaderView.
/// For rehearsal only, a line that hasn't been recorded can be read in a built-in voice instead
/// (`readToEnd`); takes only ever play your recordings (`playToEnd`).
@Observable
final class ReaderTrackPlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private var player: AVAudioPlayer?
    /// Whoever is waiting in `playToEnd` / `readToEnd` for the current line to finish.
    @ObservationIgnored private var finished: CheckedContinuation<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var utterance: AVSpeechUtterance?

    /// UserDefaults key: read unrecorded reader lines in a built-in voice while rehearsing (on unless
    /// switched off on the Reader screen).
    static let builtInVoiceKey = "reader.builtInVoice"
    static var usesBuiltInVoice: Bool { UserDefaults.standard.object(forKey: builtInVoiceKey) as? Bool ?? true }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Root folder for every reader recording, so size and delete-all can treat it as one unit.
    static let folder = "reader"

    /// One file per reader line, scoped to the audition and scene it was recorded for — so one
    /// audition's reader never plays (or overwrites) another's.
    static func url(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> URL {
        MediaStore.directory("\(folder)/\(auditionID.uuidString)/scene-\(sceneIndex)")
            .appendingPathComponent("line-\(index).m4a")
    }

    static func isRecorded(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> Bool {
        FileManager.default.fileExists(atPath: url(auditionID: auditionID, sceneIndex: sceneIndex, line: index).path)
    }

    /// Plays one recorded reader line. Returns false when that line hasn't been recorded.
    @discardableResult
    func play(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int, volume: Float = 1) -> Bool {
        stop()
        let url = Self.url(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }  // not recorded yet → silent cue
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.volume = volume
        return player?.play() ?? false
    }

    /// Plays one recorded line and returns once it has finished (or been stopped), so whatever comes
    /// next waits for the whole line however long it was read. False straight away when the line
    /// hasn't been recorded.
    @MainActor
    func playToEnd(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int, volume: Float = 1) async -> Bool {
        guard play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, volume: volume) else { return false }
        await withCheckedContinuation { finished = $0 }
        return true
    }

    /// Rehearsal: your recording when there is one, otherwise `text` in the built-in voice (if that's
    /// on). Returns once it's done; false when there was nothing to hear.
    @MainActor
    func readToEnd(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int, text: String) async -> Bool {
        if await playToEnd(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex) { return true }
        guard Self.usesBuiltInVoice else { return false }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        self.utterance = utterance
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        synthesizer.speak(utterance)
        await withCheckedContinuation { finished = $0 }
        return true
    }

    /// The best installed English voice — premium, then enhanced, then the default — preferring the
    /// iPhone's own English (en-GB, en-IN…). Better ones download free in Settings › Accessibility.
    private static let voice: AVSpeechSynthesisVoice? = {
        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.language == current ? 0 : 1) < ($1.language == current ? 0 : 1) }
        return english.first { $0.quality == .premium } ?? english.first { $0.quality == .enhanced }
            ?? english.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    func stop() {
        player?.stop()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        utterance = nil
        resumeFinished()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { spoke(utterance) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { spoke(utterance) }

    private func spoke(_ spoken: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            // A stopped line's callback can land after the next one has started; only the current one counts.
            guard let self, spoken === self.utterance else { return }
            self.utterance = nil
            self.resumeFinished()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, player === self.player else { return }
            self.resumeFinished()
        }
    }

    private func resumeFinished() {
        finished?.resume()
        finished = nil
    }
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
