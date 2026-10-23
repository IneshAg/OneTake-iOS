import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Automated Tape Check: a real, on-device look at exactly the clips that will go on the tape
/// (`MediaExporter.clips`). Video frames are sampled and run through Vision face detection plus a
/// brightness measure; the audio track is read and its levels measured; and the package is checked
/// against what the notice asked for. Nothing leaves the iPhone. Findings are advisory — nothing
/// here blocks sending.
enum TapeAnalyzer {
    struct Report {
        var findings: [TapeFinding] = []
        var passed: [String] = []
        /// Clips that were actually analyzed (0 means nothing has been recorded yet).
        var clipCount = 0
        var checkCount: Int { findings.count + passed.count }
    }

    /// Off the main actor: frame sampling, Vision and audio decoding all take real time.
    static func analyze(_ audition: Audition, takes: [Take]) async -> Report {
        let clips = MediaExporter.clips(for: audition, takes: takes)
        var report = Report(clipCount: clips.count)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        var totalSeconds = 0.0
        var allLandscape = true
        var allHD = true
        var framingOK = true, lightOK = true, eyelineOK = true, audioOK = true

        for clip in clips {
            if Task.isCancelled { return report }
            let asset = AVURLAsset(url: clip.url)
            guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { continue }
            totalSeconds += duration

            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let loaded = try? await track.load(.naturalSize, .preferredTransform) {
                let (naturalSize, transform) = loaded
                let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
                let width = abs(oriented.width), height = abs(oriented.height)
                if width < height { allLandscape = false }
                if min(width, height) < 1080 { allHD = false }
            }

            let video = await videoFindings(for: clip, asset: asset, duration: duration, context: context)
            if video.contains(where: { $0.category == "Framing" }) { framingOK = false }
            if video.contains(where: { $0.category == "Light" }) { lightOK = false }
            if video.contains(where: { $0.category == "Eyeline" }) { eyelineOK = false }
            report.findings += video

            let audio = await audioFindings(for: clip, asset: asset)
            if !audio.isEmpty { audioOK = false }
            report.findings += audio
        }
        guard !clips.isEmpty else { return report }

        if framingOK { report.passed.append("Framing") }
        if lightOK { report.passed.append("Light") }
        if eyelineOK { report.passed.append("Facing camera") }
        if audioOK { report.passed.append("Sound level") }
        var passed = report.passed
        let package = packageFindings(audition, clips: clips, totalSeconds: totalSeconds,
                                      allLandscape: allLandscape, allHD: allHD, passed: &passed)
        report.passed = passed
        report.findings += package
        report.passed.append("File name")
        return report
    }

    // MARK: Video

    private struct FrameSample {
        var time: Double
        /// Largest face, in normalized image coordinates (origin bottom-left), if one was found.
        var face: CGRect?
        var yaw: Double?
        var frameLuma: Double
        var faceLuma: Double?
    }

    private static func videoFindings(for clip: MediaExporter.Clip, asset: AVURLAsset, duration: Double, context: CIContext) async -> [TapeFinding] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        // ~1 frame a second, capped so a long take still checks quickly; skip the first half second
        // (the actor is usually still settling after "Action").
        let count = max(3, min(20, Int(duration)))
        let start = min(0.5, duration / 4)
        let step = (duration - start) / Double(count)
        var samples: [FrameSample] = []
        for i in 0..<count {
            if Task.isCancelled { break }
            let t = start + step * Double(i)
            guard let cgImage = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { continue }
            samples.append(sample(cgImage, at: t, context: context))
        }
        guard !samples.isEmpty else { return [] }

        var findings: [TapeFinding] = []
        func add(_ category: String, _ title: String, at time: Double, _ advice: String) {
            findings.append(TapeFinding(category: category, title: title, where_: "\(clip.label) · \(timestamp(time))",
                                        advice: advice, clipURL: clip.url, seconds: time))
        }
        /// The first sample matching `condition`, when it holds for at least `share` of the clip.
        func persistent(_ share: Double, _ condition: (FrameSample) -> Bool) -> FrameSample? {
            let hits = samples.filter(condition)
            return Double(hits.count) / Double(samples.count) >= share ? hits.first : nil
        }

        let isFullLength = clip.kind == .fullLength
        if let s = persistent(0.3, { $0.face == nil }) {
            add("Framing", "Your face isn't in frame", at: s.time,
                "For long stretches the camera couldn't find your face. Check you're in the middle of the shot and facing the lens.")
        } else if !isFullLength {
            // Self-tape framing is a medium close-up: face roughly a fifth to a third of the frame
            // height, head near the top with a little room, roughly centred.
            if let s = persistent(0.5, { ($0.face?.height ?? 1) < 0.12 }) {
                add("Framing", "You're quite far from the camera", at: s.time,
                    "Casting wants a medium close-up — chest up. Move closer, or bring the phone closer.")
            }
            if let s = persistent(0.4, { ($0.face?.maxY ?? 0) > 0.97 }) {
                add("Framing", "The top of your head is cut off", at: s.time,
                    "Tilt the phone down or lower it a little so there's a sliver of space above your head.")
            } else if let s = persistent(0.5, { ($0.face?.maxY ?? 1) < 0.68 }) {
                add("Framing", "Lots of empty space above your head", at: s.time,
                    "Raise the phone or tilt it up so your eyes sit about a third of the way down the frame.")
            }
            if let s = persistent(0.5, { face in face.face.map { $0.midX < 0.3 || $0.midX > 0.7 } ?? false }) {
                add("Framing", "You're off to one side", at: s.time,
                    "Centre yourself in the shot — slide the phone, or step to your mark.")
            }
            // A big head turn reads as profile, not "just beside the lens" eyeline.
            if let s = persistent(0.25, { abs($0.yaw ?? 0) > 0.6 }) {
                add("Eyeline", "You're turned away from the camera", at: s.time,
                    "Keep your eyeline just beside the lens, on your reader — not off to the side.")
            }
        }

        let meanLuma = samples.map(\.frameLuma).reduce(0, +) / Double(samples.count)
        let darkest = samples.min { $0.frameLuma < $1.frameLuma }
        if meanLuma < 0.22, let s = darkest {
            add("Light", "It's too dark", at: s.time,
                "Face a window or add a lamp in front of you. Casting needs to see your eyes.")
        } else if meanLuma > 0.85, let s = samples.max(by: { $0.frameLuma < $1.frameLuma }) {
            add("Light", "The picture is overexposed", at: s.time,
                "Move away from direct sun or turn a light down — bright areas are washing out.")
        } else if let s = persistent(0.5, { s in s.faceLuma.map { $0 < s.frameLuma * 0.6 } ?? false }) {
            add("Light", "You're backlit", at: s.time,
                "The background is much brighter than your face. Put the light in front of you, not behind.")
        }
        return findings
    }

    private static func sample(_ cgImage: CGImage, at time: Double, context: CIContext) -> FrameSample {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let face = (request.results ?? []).max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }

        let image = CIImage(cgImage: cgImage)
        let frameLuma = averageLuma(image, in: image.extent, context: context)
        var faceLuma: Double?
        if let box = face?.boundingBox {
            let rect = VNImageRectForNormalizedRect(box, cgImage.width, cgImage.height)
            faceLuma = averageLuma(image, in: rect, context: context)
        }
        return FrameSample(time: time, face: face?.boundingBox, yaw: face?.yaw?.doubleValue, frameLuma: frameLuma, faceLuma: faceLuma)
    }

    /// Rec. 601 luma of the average colour over `rect`, 0…1.
    private static func averageLuma(_ image: CIImage, in rect: CGRect, context: CIContext) -> Double {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = rect
        guard let output = filter.outputImage else { return 0.5 }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
    }

    // MARK: Audio

    private static func audioFindings(for clip: MediaExporter.Clip, asset: AVURLAsset) async -> [TapeFinding] {
        // The full length is usually silent by design; only spoken clips are level-checked.
        guard clip.kind != .fullLength,
              let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let windows = audioWindows(asset, track: track), !windows.isEmpty else { return [] }

        var findings: [TapeFinding] = []
        func add(_ title: String, at time: Double, _ advice: String) {
            findings.append(TapeFinding(category: "Sound", title: title, where_: "\(clip.label) · \(timestamp(time))",
                                        advice: advice, clipURL: clip.url, seconds: time))
        }
        // Speaking level = the loud end of the clip (90th percentile), so pauses don't drag it down.
        let sorted = windows.map(\.db).sorted()
        let speaking = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
        if speaking < -55 {
            add("There's no sound", at: 0, "Nothing was picked up. Check the microphone isn't covered and AirPods are connected if you're using them.")
        } else if speaking < -32, let quietest = windows.first(where: { $0.db < -32 }) {
            add("Your voice is quiet", at: quietest.time, "Move the phone closer, speak up a little, or use a wired or AirPods mic.")
        }
        if let clipped = windows.first(where: { $0.clipped }) {
            add("The sound distorts", at: clipped.time, "Your voice is clipping. Step back from the phone a little or bring your level down on the loud moments.")
        }
        return findings
    }

    private struct AudioWindow { var time: Double; var db: Double; var clipped: Bool }

    /// Half-second RMS windows over the clip's audio, decoded to float PCM.
    private static func audioWindows(_ asset: AVURLAsset, track: AVAssetTrack) -> [AudioWindow]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var windows: [AudioWindow] = []
        var windowSamples = 0, samplesPerWindow = 0
        var sumSquares = 0.0, clippedSamples = 0
        func closeWindow() {
            guard windowSamples > 0 else { return }
            let rms = (sumSquares / Double(windowSamples)).squareRoot()
            windows.append(AudioWindow(time: Double(windows.count) * 0.5, db: rms > 0 ? 20 * log10(rms) : -120,
                                       clipped: Double(clippedSamples) / Double(windowSamples) > 0.001))
            windowSamples = 0; sumSquares = 0; clippedSamples = 0
        }

        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            if samplesPerWindow == 0, let format = CMSampleBufferGetFormatDescription(buffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                samplesPerWindow = max(1, Int(asbd.mSampleRate * 0.5) * Int(max(1, asbd.mChannelsPerFrame)))
            }
            guard samplesPerWindow > 0, let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = floats.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: floats.count * MemoryLayout<Float>.size, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            for sample in floats {
                let value = Double(sample)
                sumSquares += value * value
                if abs(value) >= 0.99 { clippedSamples += 1 }
                windowSamples += 1
                if windowSamples >= samplesPerWindow { closeWindow() }
            }
        }
        closeWindow()
        return windows
    }

    // MARK: Package

    private static func packageFindings(_ a: Audition, clips: [MediaExporter.Clip], totalSeconds: Double,
                                        allLandscape: Bool, allHD: Bool, passed: inout [String]) -> [TapeFinding] {
        var findings: [TapeFinding] = []
        func add(_ title: String, _ advice: String) {
            findings.append(TapeFinding(category: "Package", title: title, where_: a.project, advice: advice))
        }

        if clips.contains(where: { $0.kind == .slate }) { passed.append("Slate") }
        else { add("There's no slate yet", "Most casting offices want a slate first. Record one from the camera — it only takes 5 seconds.") }

        if a.asks.contains("Full length") {
            if clips.contains(where: { $0.kind == .fullLength }) { passed.append("Full length") }
            else { add("They asked for a full-length shot", "This notice asked for one. Add it from the camera — head to feet, a few seconds.") }
        }

        let shot = Set(clips.compactMap { clip -> Int? in if case .scene(let i) = clip.kind { return i } else { return nil } })
        let missing = a.scenes.indices.filter { !shot.contains($0) }
        if missing.isEmpty { if !a.scenes.isEmpty { passed.append("Every scene shot") } }
        else { add("\(missing.map { a.scenes[$0].title }.joined(separator: ", ")) not shot yet", "Every scene they sent goes on the tape. Record a take for it before sending.") }

        if a.asks.contains("Under 3 min") {
            if totalSeconds <= 180 { passed.append("Under 3 minutes") }
            else { add("The tape runs \(timestamp(totalSeconds))", "They asked for under 3 minutes. Pick shorter takes or trim the start and end.") }
        }
        if a.asks.contains("Landscape") {
            if allLandscape { passed.append("Landscape") }
            else { add("Some of it is portrait", "They asked for landscape. Turn the phone sideways and re-record the portrait clips.") }
        }
        if allHD { passed.append("1080p") }
        else { add("Lower than 1080p", "Casting sites expect 1080p. Re-record on this iPhone's camera rather than a screen recording or import.") }
        return findings
    }

    private static func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
