import Foundation
import SwiftUI
import AVFoundation
import AVKit
@preconcurrency import Speech

/// A line-level hint from aligning the recorded voice take with the actor's dialogue.
/// These are review suggestions, not a performance score.
struct VoiceLineReview: Identifiable {
    enum Mark: String, CaseIterable, Identifiable {
        case matched = "Looks okay"
        case skipped = "Skipped"
        case forgot = "Forgot"
        case hesitated = "Hesitated"
        case notInScript = "Not in Script"
        var id: String { rawValue }
    }

    let id: UUID
    let lineIndex: Int
    let text: String
    let timestamp: TimeInterval?
    let detail: String
    let suggestion: Mark
    var mark: Mark
    var dismissed = false
}

enum VoicePracticeReviewAnalyzer {
    private struct Word {
        var value: String
        var timestamp: TimeInterval
        var duration: TimeInterval
    }
    private struct ScriptWord {
        var value: String
        var line: Int
    }

    static func analyze(url: URL, lines: [ScriptLine]) async throws -> [VoiceLineReview] {
        let localeID = UserDefaults.standard.string(forKey: "speech.recognitionLocale") ?? SpeechFollower.defaultAccentIdentifier
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { throw ReviewError.unavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw ReviewError.onDeviceUnavailable }
        let audioURL = try await makeAudioFile(from: url)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let audioRequest = SFSpeechURLRecognitionRequest(url: audioURL)
        audioRequest.shouldReportPartialResults = false
        audioRequest.requiresOnDeviceRecognition = true
        let words = try await transcribe(audioRequest, recognizer: recognizer)
        guard !words.isEmpty else { throw ReviewError.noSpeech }
        return align(words: words, lines: lines)
    }

    private static func makeAudioFile(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else { throw ReviewError.noSpeech }
        let audioRange = try await audioTrack.load(.timeRange)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ReviewError.noSpeech
        }
        try track.insertTimeRange(audioRange, of: audioTrack, at: audioRange.start)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("voice-review-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ReviewError.noSpeech
        }
        guard exporter.supportedFileTypes.contains(.m4a) else { throw ReviewError.noSpeech }
        do {
            try await exporter.export(to: output, as: .m4a)
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func transcribe(_ request: SFSpeechURLRecognitionRequest, recognizer: SFSpeechRecognizer) async throws -> [Word] {
        try await withCheckedThrowingContinuation { continuation in
            let gate = RecognitionOnceGate()
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard result?.isFinal == true || error != nil else { return }
                guard gate.claim() else { return }
                if let result, result.isFinal {
                    let words = result.bestTranscription.segments.flatMap { segment in
                        let tokens = tokenize(segment.substring)
                        let duration = segment.duration / Double(max(1, tokens.count))
                        return tokens.enumerated().map { offset, token in
                            Word(value: token, timestamp: segment.timestamp + Double(offset) * duration, duration: duration)
                        }
                    }
                    continuation.resume(returning: words)
                } else if let error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func align(words: [Word], lines: [ScriptLine]) -> [VoiceLineReview] {
        let actorLines = lines.enumerated().filter { $0.element.isMine && !$0.element.isSilentReactionCue }
        let script = actorLines.flatMap { index, line in
            tokenize(line.text).map { ScriptWord(value: $0, line: index) }
        }
        guard !script.isEmpty else { return [] }

        // Global edit-distance alignment tolerates recognition substitutions and extra spoken words
        // while retaining the word timestamps returned by Apple Speech.
        let m = script.count, n = words.count, width = n + 1
        var cost = [Int](repeating: 0, count: (m + 1) * (n + 1))
        var step = [UInt8](repeating: 0, count: (m + 1) * (n + 1)) // 1 match/substitute, 2 skipped script, 3 extra speech
        if m > 0 { for i in 1...m { cost[i * width] = i * 2; step[i * width] = 2 } }
        if n > 0 { for j in 1...n { cost[j] = j * 2; step[j] = 3 } }
        if m > 0, n > 0 {
            for i in 1...m { for j in 1...n {
                let exact = script[i - 1].value == words[j - 1].value
                let substitution = exact ? 0 : (similar(script[i - 1].value, words[j - 1].value) ? 1 : 3)
                let diagonal = cost[(i - 1) * width + j - 1] + substitution
                let deletion = cost[(i - 1) * width + j] + 2
                let insertion = cost[i * width + j - 1] + 2
                let cell = i * width + j
                if diagonal <= deletion && diagonal <= insertion { cost[cell] = diagonal; step[cell] = 1 }
                else if deletion <= insertion { cost[cell] = deletion; step[cell] = 2 }
                else { cost[cell] = insertion; step[cell] = 3 }
            } }
        }

        var matchedByLine: [Int: [(script: Int, audio: Int)]] = [:]
        var missedByLine: [Int: [String]] = [:]
        var extraByLine: [Int: [String]] = [:]
        var i = m, j = n
        while i > 0 || j > 0 {
            let action = step[i * width + j]
            if i > 0, j > 0, action == 1 {
                if script[i - 1].value == words[j - 1].value || similar(script[i - 1].value, words[j - 1].value) {
                    matchedByLine[script[i - 1].line, default: []].append((i - 1, j - 1))
                } else {
                    missedByLine[script[i - 1].line, default: []].append(script[i - 1].value)
                    extraByLine[script[i - 1].line, default: []].append(words[j - 1].value)
                }
                i -= 1; j -= 1
            } else if i > 0, action == 2 {
                missedByLine[script[i - 1].line, default: []].append(script[i - 1].value)
                i -= 1
            } else if j > 0 {
                let line = i < m ? script[i].line : script[max(0, i - 1)].line
                extraByLine[line, default: []].append(words[j - 1].value)
                j -= 1
            } else { break }
        }

        return actorLines.map { lineIndex, line in
            let matched = (matchedByLine[lineIndex] ?? []).sorted { $0.audio < $1.audio }
            let missing = missedByLine[lineIndex] ?? []
            let extras = extraByLine[lineIndex] ?? []
            let longestPause = zip(matched, matched.dropFirst()).map { left, right in
                words[right.audio].timestamp - (words[left.audio].timestamp + words[left.audio].duration)
            }.max() ?? 0
            let suggestion: VoiceLineReview.Mark
            let detail: String
            if matched.isEmpty {
                suggestion = .skipped
                detail = "No clear match was found for this line. Check the audio; recognition can miss words."
            } else if longestPause >= 1.25 {
                suggestion = .hesitated
                detail = "A pause of about \(String(format: "%.1f", longestPause)) seconds was detected within this line."
            } else if !missing.isEmpty {
                suggestion = .forgot
                detail = "Possible missing words: \(missing.reversed().joined(separator: " "))."
            } else if !extras.isEmpty {
                suggestion = .notInScript
                detail = "Possible extra words: \(extras.reversed().joined(separator: " "))."
            } else {
                suggestion = .matched
                detail = "The recognized words follow this line."
            }
            return VoiceLineReview(id: line.id, lineIndex: lineIndex, text: line.text,
                                   timestamp: matched.first.map { words[$0.audio].timestamp },
                                   detail: detail, suggestion: suggestion, mark: suggestion)
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
            .map { String($0.filter { $0.isLetter || $0.isNumber }) }
            .filter { !$0.isEmpty }
    }
    private static func similar(_ lhs: String, _ rhs: String) -> Bool {
        guard min(lhs.count, rhs.count) >= 4 else { return false }
        let a = Array(lhs), b = Array(rhs)
        var previous = Array(0...b.count)
        for (i, charA) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, charB) in b.enumerated() {
                current[j + 1] = min(min(current[j] + 1, previous[j + 1] + 1), previous[j] + (charA == charB ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count] <= 1
    }
    private enum ReviewError: Error { case unavailable, onDeviceUnavailable, noSpeech }
}

final class RecognitionOnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}

struct VoicePracticeReviewView: View {
    let recordingURL: URL?
    @Binding var reviews: [VoiceLineReview]
    let isAnalyzing: Bool
    let errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Check the recording against your lines. The marks are suggestions; pauses can be intentional.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                    if let player {
                        VideoPlayer(player: player).frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if isAnalyzing {
                        Label("Listening for words and pauses…", systemImage: "waveform")
                            .font(.otBody).foregroundStyle(OT.accent)
                    } else if let errorMessage {
                        Text(errorMessage).font(.otCallout).foregroundStyle(OT.labelSecondary)
                    } else if reviews.isEmpty {
                        Text("No actor lines were available to review.").font(.otCallout).foregroundStyle(OT.labelSecondary)
                    } else {
                        ForEach(reviews.indices, id: \.self) { index in
                            let item = reviews[index]
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    Text("Line \(item.lineIndex + 1)").font(.otCaption.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                                    Spacer()
                                    if let time = item.timestamp {
                                        Button {
                                            player?.seek(to: CMTime(seconds: max(0, time - 0.7), preferredTimescale: 600))
                                            player?.play()
                                        } label: {
                                            Label(String(format: "%.1fs", time), systemImage: "play.fill")
                                                .font(.otCaption.monospacedDigit()).foregroundStyle(OT.accent)
                                        }
                                    }
                                }
                                Text(item.text).font(.otBody).foregroundStyle(OT.labelPrimary)
                                Text(item.detail).font(.otFootnote).foregroundStyle(OT.labelSecondary)
                                HStack {
                                    Menu {
                                        ForEach(VoiceLineReview.Mark.allCases) { mark in
                                            Button(mark.rawValue) { reviews[index].mark = mark }
                                        }
                                    } label: {
                                        Label(item.mark.rawValue, systemImage: item.mark == .matched ? "checkmark.circle" : "exclamationmark.circle")
                                            .font(.otFootnote.weight(.semibold))
                                            .foregroundStyle(item.mark == .matched ? OT.success : OT.warning)
                                    }
                                    Spacer()
                                    Button(item.dismissed ? "Restore mark" : "Dismiss") { reviews[index].dismissed.toggle() }
                                        .font(.otFootnote.weight(.medium)).foregroundStyle(OT.labelTertiary)
                                }
                            }
                            .padding(14).otCard(radius: 14)
                            .opacity(item.dismissed ? 0.55 : 1)
                        }
                    }
                }
                .padding(OT.gutter)
            }
            .background(OT.bgCanvas)
            .navigationTitle("Speech review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .onAppear { if let recordingURL { player = AVPlayer(url: recordingURL) } }
        .onDisappear { player?.pause() }
    }
}
