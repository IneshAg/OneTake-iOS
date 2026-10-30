import AVFoundation

/// Finds long silent edges and exports a padded suggestion. It never changes the source recording.
enum SilenceTrimmer {
    struct Suggestion {
        let start: Double
        let end: Double
        let removedLeading: Double
        let removedTrailing: Double
    }

    static func suggest(for url: URL) -> Suggestion? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384),
              let channels = buffer.floatChannelData else { return nil }

        let windowFrames = max(1, Int(sampleRate * 0.05))
        var energies: [Double] = []
        var totalFrames = 0
        var sum: Double = 0
        var count = 0
        while true {
            do { try file.read(into: buffer) } catch { return nil }
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            for frame in 0..<frames {
                var sampleEnergy: Double = 0
                for channel in 0..<Int(format.channelCount) {
                    let value = Double(channels[channel][frame])
                    sampleEnergy += value * value
                }
                sum += sampleEnergy / Double(max(1, format.channelCount))
                count += 1
                totalFrames += 1
                if count == windowFrames {
                    energies.append(sqrt(sum / Double(count)))
                    sum = 0; count = 0
                }
            }
        }
        if count > 0 { energies.append(sqrt(sum / Double(count))) }
        guard energies.count >= 10 else { return nil }

        let duration = Double(totalFrames) / sampleRate
        let peak = energies.max() ?? 0
        let threshold = max(0.003, peak * 0.035)
        let active = energies.map { $0 >= threshold }
        guard let firstActive = active.indices.dropLast().first(where: { active[$0] && active[$0 + 1] }),
              let lastActive = active.indices.dropLast().reversed().first(where: { active[$0] && active[$0 + 1] }) else { return nil }
        let leadingSilence = Double(firstActive) * 0.05
        let trailingSilence = duration - Double(lastActive + 2) * 0.05
        guard leadingSilence >= 0.45 || trailingSilence >= 0.60 else { return nil }

        let padding = 0.22
        let start = max(0, leadingSilence - padding)
        let end = min(duration, duration - trailingSilence + padding)
        guard end - start >= 1.0, end - start < duration - 0.3 else { return nil }
        return Suggestion(start: start, end: end, removedLeading: start, removedTrailing: duration - end)
    }

    static func export(_ suggestion: Suggestion, from source: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("slate-trim-\(UUID().uuidString).mov")
        exporter.outputURL = output
        exporter.outputFileType = .mov
        exporter.timeRange = CMTimeRange(start: CMTime(seconds: suggestion.start, preferredTimescale: 600),
                                         duration: CMTime(seconds: suggestion.end - suggestion.start, preferredTimescale: 600))
        return await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume(returning: exporter.status == .completed ? output : nil)
            }
        }
    }
}
