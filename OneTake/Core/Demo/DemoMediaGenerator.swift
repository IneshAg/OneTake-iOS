import AVFoundation
import CoreGraphics
import CoreMedia
import CoreText
import Foundation
import UIKit

/// Synthesizes lightweight, genuinely playable on-disk assets (H.264 MP4 clips, AAC M4A reader cues,
/// and JPEG studio placeholder headshots) for Demo Mode so preview, playback, audio walk, tape check,
/// and export workflows work offline without bundled large binaries.
enum DemoMediaGenerator {
    struct VideoClipSpec: Sendable {
        let destinationURL: URL
        let headline: String
        let subheadline: String
        let badge: String
        let accentRGB: (CGFloat, CGFloat, CGFloat)
        let durationSeconds: Double
    }

    struct AudioCueSpec: Sendable {
        let destinationURL: URL
        let frequencyHz: Double
        let durationSeconds: Double
    }

    // MARK: - Studio Placeholder Headshots

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
    }

    static func renderHeadshotImage(angle: String) -> UIImage {
        let size = CGSize(width: 800, height: 1000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                srgb(0.14, 0.16, 0.21),
                srgb(0.08, 0.09, 0.12)
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.36),
                    startRadius: 40,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.45),
                    endRadius: 560,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // Minimal studio silhouette shifted slightly for left/right profile angles.
            let xOffset: CGFloat
            switch angle.lowercased() {
            case "left":  xOffset = -32
            case "right": xOffset = 32
            default:      xOffset = 0
            }

            cg.setFillColor(srgb(1.0, 1.0, 1.0, 0.18))
            let headRect = CGRect(x: 270 + xOffset, y: 215, width: 260, height: 300)
            cg.fillEllipse(in: headRect)

            let shoulders = CGMutablePath()
            shoulders.move(to: CGPoint(x: 110, y: 1000))
            shoulders.addQuadCurve(
                to: CGPoint(x: 690, y: 1000),
                control: CGPoint(x: 400 + xOffset * 0.5, y: 495)
            )
            shoulders.closeSubpath()
            cg.addPath(shoulders)
            cg.fillPath()

            // Subtle framing reticle & studio angle badge.
            cg.setStrokeColor(srgb(1.0, 1.0, 1.0, 0.28))
            cg.setLineWidth(3)
            cg.stroke(CGRect(x: 52, y: 52, width: size.width - 104, height: size.height - 104), width: 2)

            let badge = "DEMO · \(angle.uppercased())"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor(cgColor: srgb(1.0, 1.0, 1.0, 0.72))
            ]
            let attrStr = NSAttributedString(string: badge, attributes: attrs)
            let textSize = attrStr.size()
            attrStr.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: size.height - 120))
        }
    }

    // MARK: - Playable H.264 + AAC Clips

    @discardableResult
    static func writeVideoClip(_ spec: VideoClipSpec) async -> Bool {
        await Task.detached(priority: .utility) {
            generateVideoSync(spec)
        }.value
    }

    @discardableResult
    static func writeAudioCue(_ spec: AudioCueSpec) async -> Bool {
        await Task.detached(priority: .utility) {
            generateAudioCueSync(spec)
        }.value
    }

    private static func generateVideoSync(_ spec: VideoClipSpec) -> Bool {
        let fm = FileManager.default
        let dir = spec.destinationURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.removeItem(at: spec.destinationURL)

        let width = 640
        let height = 360
        let fps: Int32 = 24
        let totalFrames = max(24, Int(spec.durationSeconds * Double(fps)))

        guard let writer = try? AVAssetWriter(outputURL: spec.destinationURL, fileType: .mp4) else {
            return false
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 420_000,
                AVVideoMaxKeyFrameIntervalKey: 24
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: bufferAttrs
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { return false }
        writer.add(videoInput)
        writer.add(audioInput)

        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()

        group.enter()
        let videoQueue = DispatchQueue(label: "onetake.demo.video")
        var frameIndex = 0
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {
                if frameIndex >= totalFrames {
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                let progress = Double(frameIndex) / Double(max(1, totalFrames - 1))
                if let buffer = makeVideoFrameBuffer(
                    pool: adaptor.pixelBufferPool,
                    width: width,
                    height: height,
                    spec: spec,
                    progress: progress
                ) {
                    adaptor.append(buffer, withPresentationTime: time)
                }
                frameIndex += 1
            }
        }

        group.enter()
        let audioQueue = DispatchQueue(label: "onetake.demo.audio")
        let sampleRate = 44_100
        let totalSamples = Int(spec.durationSeconds * Double(sampleRate))
        let chunkFrames = 4_096
        var writtenSamples = 0
        audioInput.requestMediaDataWhenReady(on: audioQueue) {
            while audioInput.isReadyForMoreMediaData {
                if writtenSamples >= totalSamples {
                    audioInput.markAsFinished()
                    group.leave()
                    return
                }
                let count = min(chunkFrames, totalSamples - writtenSamples)
                if let sb = makeAudioSampleBuffer(
                    sampleOffset: writtenSamples,
                    frameCount: count,
                    sampleRate: sampleRate,
                    toneHz: 330.0,
                    toneAmplitude: writtenSamples < sampleRate / 6 ? 0.06 : 0.004
                ) {
                    audioInput.append(sb)
                }
                writtenSamples += count
            }
        }

        group.wait()

        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var succeeded = false
        writer.finishWriting {
            succeeded = writer.status == .completed
            sem.signal()
        }
        sem.wait()
        return succeeded && fm.fileExists(atPath: spec.destinationURL.path)
    }

    private static func generateAudioCueSync(_ spec: AudioCueSpec) -> Bool {
        let fm = FileManager.default
        let dir = spec.destinationURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.removeItem(at: spec.destinationURL)

        guard let writer = try? AVAssetWriter(outputURL: spec.destinationURL, fileType: .m4a) else {
            return false
        }
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else { return false }
        writer.add(audioInput)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        group.enter()
        let queue = DispatchQueue(label: "onetake.demo.audiocue")
        let sampleRate = 44_100
        let totalSamples = max(sampleRate / 2, Int(spec.durationSeconds * Double(sampleRate)))
        let chunkFrames = 4_096
        var writtenSamples = 0
        audioInput.requestMediaDataWhenReady(on: queue) {
            while audioInput.isReadyForMoreMediaData {
                if writtenSamples >= totalSamples {
                    audioInput.markAsFinished()
                    group.leave()
                    return
                }
                let count = min(chunkFrames, totalSamples - writtenSamples)
                let inChime = writtenSamples < Int(Double(sampleRate) * 0.25)
                if let sb = makeAudioSampleBuffer(
                    sampleOffset: writtenSamples,
                    frameCount: count,
                    sampleRate: sampleRate,
                    toneHz: spec.frequencyHz,
                    toneAmplitude: inChime ? 0.08 : 0.002
                ) {
                    audioInput.append(sb)
                }
                writtenSamples += count
            }
        }
        group.wait()

        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var succeeded = false
        writer.finishWriting {
            succeeded = writer.status == .completed
            sem.signal()
        }
        sem.wait()
        return succeeded && fm.fileExists(atPath: spec.destinationURL.path)
    }

    private static func makeVideoFrameBuffer(
        pool: CVPixelBufferPool?,
        width: Int,
        height: Int,
        spec: VideoClipSpec,
        progress: Double
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        }
        guard let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cg = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        // Background studio dark slate.
        cg.setFillColor(srgb(0.07, 0.08, 0.11))
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Top accent bar + soft framing border.
        let (r, g, b) = spec.accentRGB
        cg.setFillColor(srgb(r, g, b, 0.92))
        cg.fill(CGRect(x: 0, y: height - 8, width: width, height: 8))

        cg.setStrokeColor(srgb(1, 1, 1, 0.18))
        cg.setLineWidth(2)
        cg.stroke(CGRect(x: 28, y: 28, width: width - 56, height: height - 56))

        // Subtle animated playback progress bar at the bottom so scrubbing feels alive.
        cg.setFillColor(srgb(1, 1, 1, 0.12))
        cg.fill(CGRect(x: 44, y: 46, width: width - 88, height: 4))
        cg.setFillColor(srgb(r, g, b, 1.0))
        cg.fill(CGRect(x: 44, y: 46, width: max(8, CGFloat(width - 88) * progress), height: 4))

        drawCTLine(cg, text: spec.badge.uppercased(), x: 48, y: CGFloat(height) - 72, size: 14, bold: true, alpha: 0.72)
        drawCTLine(cg, text: spec.headline, x: 48, y: CGFloat(height) * 0.53, size: 28, bold: true, alpha: 0.96)
        drawCTLine(cg, text: spec.subheadline, x: 48, y: CGFloat(height) * 0.40, size: 18, bold: false, alpha: 0.76)

        return pb
    }

    private static func drawCTLine(
        _ cg: CGContext,
        text: String,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        bold: Bool,
        alpha: CGFloat
    ) {
        let fontName: CFString = (bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString
        let font = CTFontCreateWithName(fontName, size, nil)
        let color = srgb(1, 1, 1, alpha)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        cg.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, cg)
    }

    private static func makeAudioSampleBuffer(
        sampleOffset: Int,
        frameCount: Int,
        sampleRate: Int,
        toneHz: Double,
        toneAmplitude: Double
    ) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDesc: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        ) == noErr, let formatDesc else {
            return nil
        }

        let byteCount = frameCount * 2
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else {
            return nil
        }
        guard CMBlockBufferAssureBlockMemory(blockBuffer) == noErr else { return nil }

        var samples = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let t = Double(sampleOffset + i) / Double(sampleRate)
            let envelope = min(1.0, max(0.0, 1.0 - t * 3.2))
            let val = sin(2.0 * .pi * toneHz * t) * toneAmplitude * envelope
            samples[i] = Int16(max(-1.0, min(1.0, val)) * 32767.0)
        }
        let copyStatus = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard copyStatus == noErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(value: CMTimeValue(sampleOffset), timescale: CMTimeScale(sampleRate)),
            decodeTimeStamp: .invalid
        )
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        return status == noErr ? sampleBuffer : nil
    }
}
