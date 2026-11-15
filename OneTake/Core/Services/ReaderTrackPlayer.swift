import Foundation
import AVFoundation

// MARK: - Reader track playback (your own recorded voice only)

enum ReaderTrackScope: Hashable, Sendable {
    case audition(Audition.ID, sceneIndex: Int)
    case practice(PracticePiece.ID)

    var storageFolder: String {
        switch self {
        case .audition(let id, let sceneIndex):
            "\(ReaderTrackPlayer.folder)/\(id.uuidString)/scene-\(sceneIndex)"
        case .practice(let id):
            "\(ReaderTrackPlayer.folder)/practice-\(id.uuidString)"
        }
    }

    var primaryID: UUID {
        switch self {
        case .audition(let id, _): id
        case .practice(let id): id
        }
    }

    var sceneIndex: Int {
        switch self {
        case .audition(_, let idx): idx
        case .practice: -1
        }
    }
}

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

    /// One file per reader line, scoped to an audition scene or standalone practice piece.
    static func url(scope: ReaderTrackScope, line index: Int) -> URL {
        MediaStore.directory(scope.storageFolder)
            .appendingPathComponent("line-\(index).m4a")
    }

    /// One file per reader line, scoped to the audition and scene it was recorded for — so one
    /// audition's reader never plays (or overwrites) another's.
    static func url(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> URL {
        url(scope: .audition(auditionID, sceneIndex: sceneIndex), line: index)
    }

    static func hasRecording(scope: ReaderTrackScope, line index: Int) -> Bool {
        let url = self.url(scope: scope, line: index)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 1 > 0
        }
        if fm.fileExists(atPath: url.standardizedFileURL.path) {
            return (try? url.standardizedFileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 1 > 0
        }
        return false
    }

    private static let audioSessionQueue = DispatchQueue(label: "onetake.reader.audiosession", qos: .userInitiated)

    @discardableResult
    func play(scope: ReaderTrackScope, lineIndex: Int, from time: TimeInterval? = nil, volume: Float = 1) -> Bool {
        let url = Self.url(scope: scope, line: lineIndex)
        guard Self.hasRecording(scope: scope, line: lineIndex) else { return false }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            Self.audioSessionQueue.async {
                try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            }
        }

        if let existing = player, currentAuditionID == scope.primaryID, currentSceneIndex == scope.sceneIndex, currentLineIndex == lineIndex {
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
        self.currentAuditionID = scope.primaryID
        self.currentSceneIndex = scope.sceneIndex
        self.currentLineIndex = lineIndex

        if newPlayer.play() {
            isPlaying = true
            currentTime = newPlayer.currentTime
            startTimer()
            return true
        }
        return false
    }

    nonisolated static func originalURL(for recordingURL: URL) -> URL {
        recordingURL.deletingPathExtension().appendingPathExtension("original.m4a")
    }

    static func hasOriginal(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> Bool {
        FileManager.default.fileExists(atPath: originalURL(for: url(auditionID: auditionID, sceneIndex: sceneIndex, line: index)).path)
    }

    /// Replaces the playable cue with an edited copy while keeping the first untouched recording for Restore.
    nonisolated static func installEditedRecording(_ editedURL: URL, at recordingURL: URL) throws {
        let fm = FileManager.default
        let backup = originalURL(for: recordingURL)
        defer { try? fm.removeItem(at: editedURL) }
        let editedAudio = try Data(contentsOf: editedURL, options: .mappedIfSafe)
        if !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: recordingURL, to: backup)
        }
        try editedAudio.write(to: recordingURL, options: .atomic)
    }

    static func restoreOriginalRecording(at recordingURL: URL) throws {
        let fm = FileManager.default
        let backup = originalURL(for: recordingURL)
        guard fm.fileExists(atPath: backup.path) else { return }
        let originalAudio = try Data(contentsOf: backup, options: .mappedIfSafe)
        try originalAudio.write(to: recordingURL, options: .atomic)
    }

    /// Checks if a valid recording exists for this reader cue.
    static func hasRecording(auditionID: Audition.ID, sceneIndex: Int, line index: Int) -> Bool {
        hasRecording(scope: .audition(auditionID, sceneIndex: sceneIndex), line: index)
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
        play(scope: .audition(auditionID, sceneIndex: sceneIndex), lineIndex: lineIndex, from: time, volume: volume)
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
