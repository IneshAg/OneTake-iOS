import Foundation
import AVFoundation
@preconcurrency import Speech

// MARK: - Speech follower (prompter follows your voice, "Action" / "Cut")

@Observable
final class SpeechFollower {
    struct AccentOption: Identifiable, Hashable {
        let id: String
        let title: String
    }

    static let availableEnglishAccents: [AccentOption] = {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map {
            $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        })
        let options = [
            AccentOption(id: "en-US", title: "US English"),
            AccentOption(id: "en-IN", title: "Indian English"),
            AccentOption(id: "en-GB", title: "UK English"),
            AccentOption(id: "en-AU", title: "Australian English"),
            AccentOption(id: "en-CA", title: "Canadian English"),
            AccentOption(id: "en-NZ", title: "New Zealand English"),
            AccentOption(id: "en-ZA", title: "South African English"),
            AccentOption(id: "en-IE", title: "Irish English")
        ]
        let available = options.filter { supported.contains($0.id.lowercased()) }
        return available.isEmpty ? [AccentOption(id: "en-US", title: "US English")] : available
    }()

    static var defaultAccentIdentifier: String {
        let current = Locale.current.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return availableEnglishAccents.first(where: { $0.id.lowercased() == current })?.id
            ?? availableEnglishAccents.first(where: { $0.id == "en-US" })?.id
            ?? availableEnglishAccents[0].id
    }

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

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// The recognizer keeps transcribing one continuous session, so its word count never goes back
    /// to zero. `reset()` records where the current line starts instead.
    private var totalWords = 0
    private var wordOffset = 0
    private var contextualStrings: [String] = []

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
        case "action", "roll", "rolling", "start", "begin", "go":
            return "action"
        case "cut", "stop", "finish", "done":
            return "cut"
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

    init() {
        let stored = UserDefaults.standard.string(forKey: "speech.recognitionLocale")
        let selected = Self.availableEnglishAccents.first(where: { $0.id == stored })?.id ?? Self.defaultAccentIdentifier
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: selected))
            ?? SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Adds short script-specific words and names to Speech's vocabulary for the current line.
    @MainActor
    func setContextualStrings(_ strings: [String]) {
        var seen = Set<String>()
        let cleaned = Array(strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(100))
        guard cleaned != contextualStrings else { return }
        contextualStrings = cleaned
        guard isListening else { return }

        // A fresh request is needed for Speech to use the new context. Keep the audio engine and
        // microphone tap running so this only happens at a line or scene boundary.
        generation += 1
        request?.endAudio()
        task?.cancel()
        totalWords = 0
        wordOffset = 0
        transcript = ""
        spokenWordCount = 0
        lastFiredIndex = -1
        pendingWord = nil
        pendingIndex = -1
        pendingTask?.cancel()
        pendingTask = nil
        beginRecognition()
    }

    func start() {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        // The input node only has a usable format once the audio session allows recording. On a
        // fresh session (Run Lines, drills — no camera has configured it) installing the tap with
        // that empty format raises an exception.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
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
        request.contextualStrings = contextualStrings
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
        if words.count < totalWords || wordOffset >= words.count {
            wordOffset = 0
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
            // Give Speech a little longer to settle on the final word. Shorter pauses made a
            // command disappear when recognition appended a correction immediately afterward.
            try? await Task.sleep(for: .milliseconds(400))
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
        wordOffset = totalWords
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
