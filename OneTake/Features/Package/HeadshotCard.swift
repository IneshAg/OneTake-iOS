import AVFoundation
import UIKit

/// The audition headshots as the tape's opening card: the front shot for 3 s, then the left and right
/// profiles for 1.5 s each when they've been taken. Rendered once into a short silent video at the
/// tape's frame size, so it joins the composition like any other clip; re-rendered only when a
/// headshot is retaken.
enum HeadshotCard {
    private static let shots: [(key: String, seconds: Double)] = [("front", 3), ("left", 1.5), ("right", 1.5)]

    static func video(size: CGSize) async -> URL? {
        let images = shots.compactMap { shot in HeadshotStore.load(key: shot.key).map { (image: $0, seconds: shot.seconds) } }
        // No front headshot, no card — the tape just starts on the slate.
        guard HeadshotStore.exists(key: "front"), !images.isEmpty else { return nil }

        let width = Int(size.width) / 2 * 2, height = Int(size.height) / 2 * 2
        let fingerprint = shots.map { shot -> String in
            let url = MediaStore.directory("headshots").appendingPathComponent("\(shot.key).jpg")
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
            return "\(Int(modified))"
        }.joined(separator: "-")
        let url = MediaStore.directory("Exports").appendingPathComponent("headshot-card-\(width)x\(height)-\(fingerprint).mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        // Older cards (a retaken headshot, a different frame size) are no longer used.
        if let old = try? FileManager.default.contentsOfDirectory(at: MediaStore.directory("Exports"), includingPropertiesForKeys: nil) {
            for file in old where file.lastPathComponent.hasPrefix("headshot-card-") { try? FileManager.default.removeItem(at: file) }
        }
        return await render(images, width: width, height: height, to: url) ? url : nil
    }

    private static func render(_ images: [(image: UIImage, seconds: Double)], width: Int, height: Int, to url: URL) async -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        // A still only needs one frame per shot: each holds until the next one starts.
        var time = 0.0
        for shot in images {
            guard let buffer = pixelBuffer(for: shot.image, width: width, height: height) else { continue }
            while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(10)) }
            adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
            time += shot.seconds
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        await writer.finishWriting()
        if writer.status != .completed { try? FileManager.default.removeItem(at: url) }
        return writer.status == .completed
    }

    /// The photo, upright and aspect-filled to the tape's frame (centred crop, like the camera saw it).
    private static func pixelBuffer(for image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
        guard let cgImage = upright.cgImage else { return nil }

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB,
                            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                            &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
