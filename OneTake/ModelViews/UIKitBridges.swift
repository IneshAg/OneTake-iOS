import SwiftUI
import AVKit
import UIKit
import VisionKit
@preconcurrency import Speech
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
    var subject: String? = nil
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let subject, !subject.isEmpty {
            vc.setValue(subject, forKey: "subject")
        }
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete?(completed) }
        return vc
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Video trim editor

/// A compact editor with its close control at the top and the save action safely at the bottom.
/// It exports a new file so callers can keep the source clip and offer an undo path.
struct VideoTrimmer: View {
    let url: URL
    var onFinish: (URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var exportError = false
    @State private var exportSession: AVAssetExportSession?

    static func canTrim(_ url: URL) -> Bool { url.isFileURL && FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(OT.fillField, in: Circle())
                }
                .accessibilityLabel("Close video editor")
                Spacer()
                Text("Edit video").font(.otHeadline)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black)
                            .frame(height: 250)
                            .overlay(ProgressView().tint(.white))
                    }

                    if duration > 0.5 {
                        HStack {
                            Button {
                                if isPlaying { player?.pause(); isPlaying = false }
                                else {
                                    if playhead < trimStart || playhead >= trimEnd {
                                        playhead = trimStart
                                        seek(to: trimStart)
                                    }
                                    player?.play()
                                    isPlaying = true
                                }
                            } label: {
                                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.otFootnote.weight(.semibold))
                            }
                            Spacer()
                            Text("\(timeLabel(playhead)) / \(timeLabel(duration))")
                                .font(.otCaption.monospacedDigit()).foregroundStyle(OT.labelSecondary)
                        }

                        Slider(value: $playhead, in: 0...duration) { editing in
                            if !editing { seek(to: playhead) }
                        }
                        .tint(OT.accent)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Trim range").font(.otHeadline)
                            VStack(spacing: 4) {
                                HStack {
                                    Text("Start").foregroundStyle(OT.labelSecondary)
                                    Spacer()
                                    Text(timeLabel(trimStart)).monospacedDigit()
                                }
                                Slider(value: $trimStart, in: 0...max(0, trimEnd - 0.5))
                                HStack {
                                    Text("End").foregroundStyle(OT.labelSecondary)
                                    Spacer()
                                    Text(timeLabel(trimEnd)).monospacedDigit()
                                }
                                Slider(value: $trimEnd, in: min(duration, trimStart + 0.5)...duration)
                            }
                            .font(.otFootnote)
                            .tint(OT.accent)
                        }
                        .padding(14)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Text("Your original recording will remain available so you can restore it later.")
                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                    }
                }
                .padding(OT.gutter)
            }
        }
        .background(OT.bgCanvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: exportTrim) {
                HStack(spacing: 8) {
                    if isExporting { ProgressView().tint(.white) }
                    Text(isExporting ? "Saving edited clip…" : "Save trimmed clip")
                }
            }
            .buttonStyle(.otPrimary)
            .disabled(duration <= 0.5 || trimEnd - trimStart < 0.5 || isExporting)
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .alert("Couldn't save the edit", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The original clip is still safe. Please try saving the edit again.")
        }
        .task(id: url) {
            let asset = AVURLAsset(url: url)
            do {
                let loadedDuration = try await asset.load(.duration).seconds
                guard loadedDuration.isFinite, loadedDuration > 0 else { return }
                duration = loadedDuration
                trimEnd = loadedDuration
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } catch {
                exportError = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func cancel() {
        exportSession?.cancelExport()
        player?.pause()
        onFinish(nil)
        dismiss()
    }

    private func exportTrim() {
        guard duration > 0.5,
              let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetHighestQuality) else {
            exportError = true
            return
        }
        player?.pause()
        isPlaying = false
        isExporting = true
        exportSession = session
        let outputType: AVFileType = session.supportedFileTypes.contains(.mov) ? .mov : .mp4
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetake-edit-\(UUID().uuidString).\(outputType == .mov ? "mov" : "mp4")")
        session.outputURL = output
        session.outputFileType = outputType
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            duration: CMTime(seconds: trimEnd - trimStart, preferredTimescale: 600)
        )
        Task {
            do {
                try await session.export(to: output, as: outputType)
                isExporting = false
                onFinish(output)
                dismiss()
            } catch {
                try? FileManager.default.removeItem(at: output)
                isExporting = false
                exportError = true
            }
        }
    }
}

/// Trims one recorded reader cue to a new M4A file; the caller decides when to replace the playable cue.
struct ReaderAudioTrimmer: View {
    let url: URL
    var onFinish: (URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var duration: Double = 0
    @State private var playhead: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var showExportError = false

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Trim reader audio", backLabel: "Cancel", onDark: false, onBack: cancel)
                .padding(.horizontal, OT.gutter)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(OT.reader)
                            .frame(width: 54, height: 54)
                            .background(OT.reader.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Keep the part you want")
                                .font(.otHeadline)
                            Text("The original recording stays available to restore.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                    }

                    VStack(spacing: 14) {
                        Button(action: togglePlayback) {
                            Label(isPlaying ? "Pause preview" : "Play preview", systemImage: isPlaying ? "pause.fill" : "play.fill")
                                .font(.otSubhead.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.otSecondary)

                        Slider(value: $playhead, in: 0...max(duration, 0.01)) { editing in
                            if !editing { seek(to: playhead) }
                        }
                        .tint(OT.reader)

                        HStack {
                            Text(timeLabel(playhead))
                            Spacer()
                            Text("\(timeLabel(trimEnd - trimStart)) kept")
                            Spacer()
                            Text(timeLabel(duration))
                        }
                        .font(.otCaption.monospacedDigit())
                        .foregroundStyle(OT.labelSecondary)

                        VStack(spacing: 10) {
                            HStack {
                                Text("Start")
                                Spacer()
                                Text(timeLabel(trimStart)).monospacedDigit()
                            }
                            Slider(value: $trimStart, in: 0...max(0, trimEnd - 0.5))
                            HStack {
                                Text("End")
                                Spacer()
                                Text(timeLabel(trimEnd)).monospacedDigit()
                            }
                            Slider(value: $trimEnd, in: min(duration, trimStart + 0.5)...max(min(duration, trimStart + 0.5), duration))
                        }
                        .font(.otFootnote.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                        .tint(OT.accent)
                        .padding(16)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Label("Trimming cuts off unwanted audio at the start or end. It doesn’t remove background noise between words.", systemImage: "info.circle")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(OT.gutter)
            }
        }
        .background(OT.bgCanvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: exportTrim) {
                HStack(spacing: 8) {
                    if isExporting { ProgressView().tint(.white) }
                    Text(isExporting ? "Saving trimmed audio…" : "Save trimmed audio")
                }
            }
            .buttonStyle(.otPrimary)
            .disabled(duration <= 0.5 || trimEnd - trimStart < 0.5 || isExporting)
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .alert("Couldn’t save the trim", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your reader recording is unchanged. Try saving again.")
        }
        .task(id: url) { await loadAudio() }
        .onDisappear { stopPreview() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func loadAudio() async {
        do {
            let asset = AVURLAsset(url: url)
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
            duration = seconds
            trimEnd = seconds
            let preview = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = preview
            timeObserver = preview.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { time in
                let current = time.seconds
                guard current.isFinite else { return }
                playhead = current
                if isPlaying && current >= trimEnd {
                    preview.pause()
                    preview.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
                    isPlaying = false
                }
            }
        } catch {
            showExportError = true
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead < trimStart || playhead >= trimEnd {
                playhead = trimStart
                seek(to: trimStart)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func stopPreview() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        isPlaying = false
    }

    private func cancel() {
        stopPreview()
        onFinish(nil)
        dismiss()
    }

    private func exportTrim() {
        guard trimEnd - trimStart >= 0.5,
              let exporter = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetAppleM4A),
              exporter.supportedFileTypes.contains(.m4a) else {
            showExportError = true
            return
        }
        stopPreview()
        isExporting = true
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("reader-trim-\(UUID().uuidString).m4a")
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 44100),
            duration: CMTime(seconds: trimEnd - trimStart, preferredTimescale: 44100)
        )
        Task {
            do {
                try await exporter.export(to: output, as: .m4a)
                isExporting = false
                onFinish(output)
                dismiss()
            } catch {
                try? FileManager.default.removeItem(at: output)
                isExporting = false
                showExportError = true
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
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

        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
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
            DispatchQueue.main.async { [weak self] in
                self?.onFinish([])
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
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

@Observable
final class CameraGuidanceSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenAt = Date.distantPast
    private var lastMessage = ""

    /// Use the system's familiar default English voice. Selecting the highest downloaded voice
    /// quality often picked an unexpectedly emphatic premium voice.
    private var preferredVoice: AVSpeechSynthesisVoice? { AVSpeechSynthesisVoice(language: "en-US") }

    func speak(_ message: String, minInterval: TimeInterval = 2.0, repeatInterval: TimeInterval = 4.5) {
        guard !message.isEmpty else { return }
        // Camera guidance changes as the actor moves. Let the current short prompt finish instead
        // of cutting it off and restarting with each new face-detection update.
        guard !synthesizer.isSpeaking else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpokenAt)
        if message == lastMessage {
            guard elapsed >= repeatInterval else { return }
        } else {
            guard elapsed >= minInterval else { return }
        }
        lastMessage = message
        lastSpokenAt = now
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.34
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
final class ReaderTrackPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var displayTimer: Timer?

    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentAuditionID: Audition.ID?
    var currentSceneIndex: Int?
    var currentLineIndex: Int?
    var onPlaybackFinished: (() -> Void)?

    func isPlaying(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int) -> Bool {
        return isPlaying && currentAuditionID == auditionID && currentSceneIndex == sceneIndex && currentLineIndex == lineIndex
    }

    /// Root folder for every reader recording, so size and delete-all can treat it as one unit.
    static let folder = "reader"

    /// One file per reader line, scoped to the audition and scene it was recorded for — so one
    /// audition's reader never plays (or overwrites) another's.
    static func url(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> URL {
        MediaStore.directory("\(folder)/\(auditionID.uuidString)/scene-\(sceneIndex)")
            .appendingPathComponent("line-\(index).m4a")
    }

    nonisolated static func originalURL(for recordingURL: URL) -> URL {
        recordingURL.deletingPathExtension().appendingPathExtension("original.m4a")
    }

    static func hasOriginal(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> Bool {
        FileManager.default.fileExists(atPath: originalURL(for: url(auditionID: auditionID, sceneIndex: sceneIndex, line: index)).path)
    }

    /// Replaces the playable cue with an edited copy while keeping the first untouched recording for Restore.
    static func installEditedRecording(_ editedURL: URL, at recordingURL: URL) throws {
        let fm = FileManager.default
        let backup = originalURL(for: recordingURL)
        if !fm.fileExists(atPath: backup.path), fm.fileExists(atPath: recordingURL.path) {
            try fm.copyItem(at: recordingURL, to: backup)
        }
        try? fm.removeItem(at: recordingURL)
        try fm.moveItem(at: editedURL, to: recordingURL)
    }

    static func restoreOriginalRecording(at recordingURL: URL) throws {
        let fm = FileManager.default
        let backup = originalURL(for: recordingURL)
        guard fm.fileExists(atPath: backup.path) else { return }
        try? fm.removeItem(at: recordingURL)
        try fm.copyItem(at: backup, to: recordingURL)
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

    /// Returns the duration of a recorded reader cue in seconds.
    static func duration(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> TimeInterval {
        let url = self.url(auditionID: auditionID, sceneIndex: sceneIndex, line: index)
        guard hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: index) else { return 0 }
        if let p = try? AVAudioPlayer(contentsOf: url) {
            return p.duration
        }
        return 0
    }

    /// Plays one recorded reader line from the beginning or a specific start offset.
    @discardableResult
    func play(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int, from time: TimeInterval? = nil, volume: Float = 1) -> Bool {
        let url = Self.url(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
        guard Self.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex) else { return false }
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])

        // Resume or seek within existing player instance if already loaded
        if let existing = player, currentAuditionID == auditionID, currentSceneIndex == sceneIndex, currentLineIndex == lineIndex {
            if let startTime = time {
                existing.currentTime = max(0, min(startTime, existing.duration))
            }
            existing.volume = volume
            if existing.play() {
                isPlaying = true
                currentTime = existing.currentTime
                duration = existing.duration
                startTimer()
                return true
            }
        }

        stop()
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return false }
        newPlayer.delegate = self
        newPlayer.volume = volume
        if let startTime = time {
            newPlayer.currentTime = max(0, min(startTime, newPlayer.duration))
        }
        self.player = newPlayer
        self.duration = newPlayer.duration
        self.currentAuditionID = auditionID
        self.currentSceneIndex = sceneIndex
        self.currentLineIndex = lineIndex

        if newPlayer.play() {
            isPlaying = true
            currentTime = newPlayer.currentTime
            startTimer()
            return true
        }
        return false
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        if let p = player {
            currentTime = p.currentTime
        }
    }

    func resume() {
        guard let p = player else { return }
        if p.play() {
            isPlaying = true
            currentTime = p.currentTime
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        guard let p = player else { return }
        let clamped = max(0, min(time, p.duration))
        p.currentTime = clamped
        currentTime = clamped
    }

    func seekRelative(_ delta: TimeInterval) {
        guard let p = player else { return }
        seek(to: p.currentTime + delta)
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentLineIndex = nil
        currentAuditionID = nil
        currentSceneIndex = nil
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, p.isPlaying else { return }
            self.currentTime = p.currentTime
        }
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        stopTimer()
        onPlaybackFinished?()
    }
}

enum ReaderRecordResult: Equatable {
    case success(duration: TimeInterval)
    case tooShort(duration: TimeInterval)
    case noSpeechDetected
    case recordingFailed(String)
}

enum AudioQualityIssue: String, CaseIterable, Identifiable, Sendable {
    case clipped = "Audio was slightly distorted / clipped"
    case tooQuiet = "Voice was quiet — speak closer to mic"
    case noisyBackground = "Background room noise detected"
    case cutOffAtEnd = "Line may have cut off at end"

    var id: String { rawValue }

    var userAdvice: String {
        switch self {
        case .clipped:
            return "Audio was loud or distorted. Consider speaking slightly further from the microphone."
        case .tooQuiet:
            return "Volume was quiet. Consider speaking louder or moving closer to the phone."
        case .noisyBackground:
            return "Noticeable background noise detected. Consider recording in a quieter room."
        case .cutOffAtEnd:
            return "Speech was still active when recording stopped. Pause briefly after speaking before tapping stop."
        }
    }
}

/// Records one reader line to disk with speech verification, acoustic voice activity detection,
/// automatic leading/trailing noise trimming, and audio quality analysis.
@Observable
final class ReaderLineRecorder {
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    var liveAudioLevel: Float = 0.0
    private var maxPeakPower: Float = -160.0
    private var speechFramesCount: Int = 0
    private var totalFramesCount: Int = 0
    private var startTime: Date = .now

    var lastAudioAnalysis: AudioAnalysisResult?
    var lastAudioIssues: [AudioQualityIssue] = []

    @discardableResult
    func start(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int) -> Bool {
        let session = AVAudioSession.sharedInstance()
        #if !targetEnvironment(simulator)
        if #available(iOS 17.0, *) {
            guard AVAudioApplication.shared.recordPermission == .granted else { return false }
        } else {
            guard session.recordPermission == .granted else { return false }
        }
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
        try? FileManager.default.removeItem(at: ReaderTrackPlayer.originalURL(for: url))
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        self.recorder = recorder
        guard recorder.record() else { self.recorder = nil; return false }

        startTime = Date()
        maxPeakPower = -160.0
        speechFramesCount = 0
        totalFramesCount = 0
        liveAudioLevel = 0.0
        lastAudioAnalysis = nil
        lastAudioIssues = []

        meterTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder, rec.isRecording else { return }
            rec.updateMeters()
            let peak = rec.peakPower(forChannel: 0)
            let avg = rec.averagePower(forChannel: 0)
            if peak > self.maxPeakPower { self.maxPeakPower = peak }
            self.totalFramesCount += 1
            if peak > -38.0 && avg > -55.0 {
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

        // 1. Inspect actual audio file and perform noise/silence trimming
        let analysis = await Self.inspectAndTrim(url: url)

        // 2. Determine voice activity
        let hasAcousticSpeech = analysis?.hasSpeech == true
        let hasMeteredSpeech = (maxPeakPower > -38.0 && speechFramesCount >= 2) || maxPeakPower > -28.0

        var hasSpeech = hasAcousticSpeech || hasMeteredSpeech
        if !hasSpeech && duration >= 0.4 {
            // Check speech recognizer fallback for low-energy speech
            hasSpeech = await checkSpeechWords(in: url)
        }

        if hasSpeech {
            // Speech detected! Accept it even if short (e.g. 0.25s-0.5s cue)
            let finalDuration = analysis?.trimmedDuration ?? duration
            self.lastAudioAnalysis = analysis
            self.lastAudioIssues = analysis?.issues ?? []
            return .success(duration: finalDuration)
        }

        // 3. No speech detected: audio is blank / quiet room noise
        try? fm.removeItem(at: url)
        self.lastAudioAnalysis = analysis
        self.lastAudioIssues = []
        // Blank threshold: if blank and shorter than 1.0s (increased from 0.3s/0.7s), flag as too short / blank tap
        if duration < 1.0 {
            return .tooShort(duration: duration)
        } else {
            return .noSpeechDetected
        }
    }

    struct AudioAnalysisResult: Sendable {
        var hasSpeech: Bool
        var originalDuration: Double
        var trimmedDuration: Double
        var peakDB: Float
        var averageSpeechRMS: Float
        var noiseFloorRMS: Float
        var snrDB: Float
        var issues: [AudioQualityIssue]
        var speechStart: Double
        var speechEnd: Double
    }

    /// Inspects recorded PCM samples, checks acoustic speech energy against room noise,
    /// catches quality issues (clipping, quiet, noisy, cut off), and trims leading/trailing silence and background noise.
    static func inspectAndTrim(url: URL) async -> AudioAnalysisResult? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }
        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let originalDuration = Double(frameCount) / sampleRate

        // 10ms analysis windows (100 windows per second)
        let windowFrames = max(1, Int(sampleRate * 0.010))
        var windowRMS: [Float] = []
        var windowPeak: [Float] = []
        var maxPeak: Float = 0.0

        var offset = 0
        while offset < frameCount {
            let nextLimit = min(offset + windowFrames, frameCount)
            let count = nextLimit - offset
            var sumSquares: Float = 0.0
            var wPeak: Float = 0.0
            for f in offset..<nextLimit {
                for c in 0..<channelCount {
                    let val = abs(channels[c][f])
                    if val > maxPeak { maxPeak = val }
                    if val > wPeak { wPeak = val }
                    sumSquares += val * val
                }
            }
            let rms = sqrt(sumSquares / Float(max(1, count * channelCount)))
            windowRMS.append(rms)
            windowPeak.append(wPeak)
            offset = nextLimit
        }

        let peakDB = maxPeak > 0 ? 20 * log10(maxPeak) : -160.0

        // Estimate background noise floor without being skewed by clips where the speaker starts immediately
        let sortedRMS = windowRMS.sorted()
        let estimatedNoiseFloor: Float
        if originalDuration <= 0.9 {
            // For short recordings (e.g. 0.3s-0.9s), the entire clip might be speech.
            // Natural room noise baseline is ~0.001 - 0.0035 (-60 to -49 dBFS).
            estimatedNoiseFloor = min(0.0035, sortedRMS.first ?? 0.002)
        } else {
            let p15Index = max(0, min(sortedRMS.count - 1, Int(Double(sortedRMS.count) * 0.15)))
            estimatedNoiseFloor = min(0.015, sortedRMS[p15Index])
        }

        // Speech detection threshold:
        // Spoken vocalization reaches at least 0.005 RMS or 0.02 peak.
        let speechThresholdRMS = max(estimatedNoiseFloor * 2.2, 0.005)
        var speechWindows: [Int] = []
        for (idx, energy) in windowRMS.enumerated() {
            let p = windowPeak[idx]
            if energy >= speechThresholdRMS || (p >= 0.022 && energy >= 0.003) {
                speechWindows.append(idx)
            }
        }

        // Voice presence check:
        // At least 2 active windows (>= 20ms) with peak > -38 dB, or a strong vocal peak > -28 dB
        let hasSpeech = (speechWindows.count >= 2 && peakDB > -38.0) || peakDB > -28.0

        var issues: [AudioQualityIssue] = []

        if !hasSpeech {
            return AudioAnalysisResult(
                hasSpeech: false,
                originalDuration: originalDuration,
                trimmedDuration: originalDuration,
                peakDB: peakDB,
                averageSpeechRMS: 0.0,
                noiseFloorRMS: estimatedNoiseFloor,
                snrDB: 0.0,
                issues: [],
                speechStart: 0.0,
                speechEnd: originalDuration
            )
        }

        // Detect Issues:
        // 1. Clipping (too loud / distorted)
        if maxPeak >= 0.95 || peakDB >= -0.45 {
            issues.append(.clipped)
        }

        // Compute average speech RMS
        var speechRMSSum: Float = 0.0
        for idx in speechWindows {
            speechRMSSum += windowRMS[idx]
        }
        let avgSpeechRMS = speechRMSSum / Float(max(1, speechWindows.count))

        // 2. Too quiet
        if peakDB < -25.0 || avgSpeechRMS < 0.010 {
            issues.append(.tooQuiet)
        }

        // 3. Background noise / low SNR
        let snrDB = 20 * log10(max(1e-5, avgSpeechRMS) / max(1e-5, estimatedNoiseFloor))
        if estimatedNoiseFloor > 0.022 || (snrDB < 11.0 && avgSpeechRMS > 0.018) {
            issues.append(.noisyBackground)
        }

        // 4. Cut off at end: speaker was still vocalizing when stop was tapped
        if windowRMS.count >= 3 {
            let last3RMS = Array(windowRMS.suffix(3))
            let allActive = last3RMS.allSatisfy { $0 >= max(estimatedNoiseFloor * 2.5, 0.010) }
            if allActive {
                issues.append(.cutOffAtEnd)
            }
        }

        guard let firstWindow = speechWindows.first, let lastWindow = speechWindows.last else {
            return AudioAnalysisResult(
                hasSpeech: true,
                originalDuration: originalDuration,
                trimmedDuration: originalDuration,
                peakDB: peakDB,
                averageSpeechRMS: avgSpeechRMS,
                noiseFloorRMS: estimatedNoiseFloor,
                snrDB: snrDB,
                issues: issues,
                speechStart: 0.0,
                speechEnd: originalDuration
            )
        }

        // Padding: 60ms before speech, 80ms after speech
        let prePadding = 0.06
        let postPadding = 0.08
        let startTime = max(0.0, Double(firstWindow * windowFrames) / sampleRate - prePadding)
        let endTime = min(originalDuration, Double(min(frameCount, (lastWindow + 1) * windowFrames)) / sampleRate + postPadding)
        let trimmedDuration = max(0.18, endTime - startTime)

        // Trim leading and trailing dead air/noise if more than 35ms of silence exists at an edge
        let shouldTrim = (startTime >= 0.035 || (originalDuration - endTime) >= 0.040) && trimmedDuration < (originalDuration - 0.02)

        if shouldTrim {
            let asset = AVURLAsset(url: url)
            if let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("reader-trim-\(UUID().uuidString).m4a")
                exporter.outputURL = tempURL
                exporter.outputFileType = .m4a
                exporter.timeRange = CMTimeRange(
                    start: CMTime(seconds: startTime, preferredTimescale: 44100),
                    duration: CMTime(seconds: trimmedDuration, preferredTimescale: 44100)
                )
                let success: Bool
                do {
                    try await exporter.export(to: tempURL, as: .m4a)
                    success = true
                } catch {
                    success = false
                }
                if success {
                    let backupURL = ReaderTrackPlayer.originalURL(for: url)
                    if !FileManager.default.fileExists(atPath: backupURL.path) {
                        try? FileManager.default.copyItem(at: url, to: backupURL)
                    }
                    _ = try? FileManager.default.removeItem(at: url)
                    try? FileManager.default.moveItem(at: tempURL, to: url)
                } else {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }

        return AudioAnalysisResult(
            hasSpeech: true,
            originalDuration: originalDuration,
            trimmedDuration: trimmedDuration,
            peakDB: peakDB,
            averageSpeechRMS: avgSpeechRMS,
            noiseFloorRMS: estimatedNoiseFloor,
            snrDB: snrDB,
            issues: issues,
            speechStart: startTime,
            speechEnd: endTime
        )
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        liveAudioLevel = 0.0
    }

    private func checkSpeechWords(in url: URL) async -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            return false
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
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
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                        if !hasResumed {
                            hasResumed = true
                            task.cancel()
                            continuation.resume(returning: false)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Enable swipe back when navigation bar is hidden

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - ScriptTextEditor (Stable, flicker-free text editor that doesn't blank out on view updates)

struct ScriptTextEditor: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = .monospacedSystemFont(ofSize: 15, weight: .regular)
    var isEditable: Bool = true

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0xF3/255.0, green: 0xEE/255.0, blue: 0xF5/255.0, alpha: 1.0)
                : UIColor(red: 0x1E/255.0, green: 0x1A/255.0, blue: 0x22/255.0, alpha: 1.0)
        }
        textView.tintColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0xC8/255.0, green: 0xA8/255.0, blue: 0xE0/255.0, alpha: 1.0)
                : UIColor(red: 0x5B/255.0, green: 0x3E/255.0, blue: 0x73/255.0, alpha: 1.0)
        }
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        textView.isScrollEnabled = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.isEditable = isEditable
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        updateTextView(uiView)
    }

    func updateTextView(_ uiView: UITextView) {
        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            if selectedRange.location + selectedRange.length <= text.utf16.count {
                uiView.selectedRange = selectedRange
            }
        }
        uiView.font = font
        uiView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScriptTextEditor

        init(_ parent: ScriptTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
        }
    }
}
