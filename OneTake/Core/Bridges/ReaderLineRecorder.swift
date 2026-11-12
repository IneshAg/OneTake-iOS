import Foundation
import AVFoundation
@preconcurrency import Speech

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
    private var cueDestination: URL?
    private var isFinishing = false
    private var meterTimer: Timer?
    var liveAudioLevel: Float = 0.0
    private var maxPeakPower: Float = -160.0
    private var speechFramesCount: Int = 0
    private var totalFramesCount: Int = 0
    private var startTime: Date = .now

    var lastAudioAnalysis: AudioAnalysisResult?
    var lastAudioIssues: [AudioQualityIssue] = []

    @MainActor
    @discardableResult
    func start(auditionID: Audition.ID, sceneIndex: Int, lineIndex: Int) -> Bool {
        guard cueDestination == nil else { return false }
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
        let destination = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reader-cue-\(UUID().uuidString).m4a")
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        self.recorder = recorder
        cueDestination = destination

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

    @MainActor
    func stop(expectedText: String? = nil) async -> ReaderRecordResult {
        guard !isFinishing, let recorder, let cueDestination else {
            return .recordingFailed("Recorder was not active.")
        }
        isFinishing = true
        meterTimer?.invalidate()
        meterTimer = nil
        liveAudioLevel = 0.0

        let url = recorder.url
        let duration = max(recorder.currentTime, Date().timeIntervalSince(startTime))
        recorder.stop()
        let fm = FileManager.default
        defer {
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: ReaderTrackPlayer.originalURL(for: url))
            if self.recorder === recorder {
                self.recorder = nil
                self.cueDestination = nil
                self.isFinishing = false
            }
        }
        guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: url.standardizedFileURL.path) else {
            return .recordingFailed("No audio file was created.")
        }

        // 1. Inspect actual audio file and perform noise/silence trimming
        let hasMeteredSpeech = (maxPeakPower > -38.0 && speechFramesCount >= 2) || maxPeakPower > -28.0
        let analysis = await Self.inspectAndTrim(url: url)

        // 2. Determine voice activity
        let hasAcousticSpeech = analysis?.hasSpeech == true

        var hasSpeech = hasAcousticSpeech || hasMeteredSpeech
        if !hasSpeech && duration >= 0.4 {
            // Check speech recognizer fallback for low-energy speech
            hasSpeech = await checkSpeechWords(in: url)
        }
        guard self.recorder === recorder else { return .recordingFailed("Recording was canceled.") }

        if hasSpeech {
            do {
                try Self.saveCue(from: url, to: cueDestination)
            } catch {
                return .recordingFailed("Couldn’t save the recording. Any previous cue is still available.")
            }
            // Speech detected! Accept it even if short (e.g. 0.25s-0.5s cue)
            let finalDuration = analysis?.trimmedDuration ?? duration
            self.lastAudioAnalysis = analysis
            self.lastAudioIssues = analysis?.issues ?? []
            return .success(duration: finalDuration)
        }

        // 3. No speech detected: audio is blank / quiet room noise
        self.lastAudioAnalysis = analysis
        self.lastAudioIssues = []
        // Blank threshold: if blank and shorter than 1.0s (increased from 0.3s/0.7s), flag as too short / blank tap
        if duration < 1.0 {
            return .tooShort(duration: duration)
        } else {
            return .noSpeechDetected
        }
    }

    static func saveCue(from staged: URL, to destination: URL) throws {
        let fm = FileManager.default
        let audio = try Data(contentsOf: staged, options: .mappedIfSafe)
        let backup = ReaderTrackPlayer.originalURL(for: destination)
        let stagedBackup = ReaderTrackPlayer.originalURL(for: staged)
        let previousBackup = backup.deletingLastPathComponent().appendingPathComponent(".reader-backup-\(UUID().uuidString)")
        let hadBackup = fm.fileExists(atPath: backup.path)
        if hadBackup { try fm.moveItem(at: backup, to: previousBackup) }
        do {
            if fm.fileExists(atPath: stagedBackup.path) {
                try Data(contentsOf: stagedBackup, options: .mappedIfSafe).write(to: backup, options: .atomic)
            }
            try audio.write(to: destination, options: .atomic)
        } catch {
            try? fm.removeItem(at: backup)
            if hadBackup { try? fm.moveItem(at: previousBackup, to: backup) }
            throw error
        }
        if hadBackup { try? fm.removeItem(at: previousBackup) }
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

        var savedDuration = originalDuration
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
                defer { try? FileManager.default.removeItem(at: tempURL) }
                do {
                    try await exporter.export(to: tempURL, as: .m4a)
                    try ReaderTrackPlayer.installEditedRecording(tempURL, at: url)
                    savedDuration = trimmedDuration
                } catch {
                    // The original is still playable when exporting or installing the trim fails.
                }
            }
        }

        return AudioAnalysisResult(
            hasSpeech: true,
            originalDuration: originalDuration,
            trimmedDuration: savedDuration,
            peakDB: peakDB,
            averageSpeechRMS: avgSpeechRMS,
            noiseFloorRMS: estimatedNoiseFloor,
            snrDB: snrDB,
            issues: issues,
            speechStart: startTime,
            speechEnd: endTime
        )
    }

    @MainActor
    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        if let recorder, !isFinishing {
            recorder.stop()
            try? FileManager.default.removeItem(at: recorder.url)
        }
        recorder = nil
        cueDestination = nil
        isFinishing = false
        liveAudioLevel = 0.0
    }

    private func checkSpeechWords(in url: URL) async -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            return false
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        return await withCheckedContinuation { continuation in
            let gate = RecognitionOnceGate()
            let task = recognizer.recognitionTask(with: request) { result, error in
                let text = result?.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                let heardSpeech = text?.isEmpty == false
                guard heardSpeech || result?.isFinal == true || error != nil else { return }
                guard gate.claim() else { return }
                continuation.resume(returning: heardSpeech)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                let timedOut = gate.claim()
                task.cancel()
                if timedOut { continuation.resume(returning: false) }
            }
        }
    }
}
