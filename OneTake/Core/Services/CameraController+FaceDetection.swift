import AVFoundation
import CoreImage
import Foundation
import UIKit
import Vision

// MARK: - Live face detection (headshot alignment)

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        let minimumInterval = wantsBodyPoseGuidance ? 0.25 : 0.15
        guard (faceGuidanceActive || wantsHandGesture), now.timeIntervalSince(lastFaceCheck) > minimumInterval,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFaceCheck = now
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let poseRequest = wantsBodyPoseGuidance ? VNDetectHumanBodyPoseRequest() : nil
        let handRequest = wantsHandGesture ? VNDetectHumanHandPoseRequest() : nil
        handRequest?.maximumHandCount = 1
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: faceBufferIsUpright ? .up : .right, options: [:])
        var requests: [VNRequest] = [request]
        if let poseRequest { requests.append(poseRequest) }
        if let handRequest { requests.append(handRequest) }
        try? handler.perform(requests)
        var results = request.results ?? []
        if results.isEmpty || (wantsBodyPoseGuidance && (poseRequest?.results?.isEmpty ?? true))
            || (wantsHandGesture && (handRequest?.results?.isEmpty ?? true)) {
            // Orientation fallback in case sensor orientation or device flip inverts the buffer
            let fallbackOrientation: CGImagePropertyOrientation = faceBufferIsUpright ? .down : .left
            let fallbackHandler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: fallbackOrientation, options: [:])
            try? fallbackHandler.perform(requests)
            results = request.results ?? []
        }
        let best = results.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
        let reading = best.map {
            FaceReading(centerX: $0.boundingBox.midX, centerY: 1 - $0.boundingBox.midY,
                        height: $0.boundingBox.height, yaw: $0.yaw?.doubleValue)
        }
        let pose = poseRequest?.results?.first.flatMap { observation -> BodyPoseReading? in
            guard let left = try? observation.recognizedPoint(.leftShoulder),
                  let right = try? observation.recognizedPoint(.rightShoulder),
                  left.confidence >= 0.3, right.confidence >= 0.3 else { return nil }
            let dx = Double(right.location.x - left.location.x)
            guard abs(dx) > 0.04 else { return nil }
            let dy = Double(right.location.y - left.location.y)
            return BodyPoseReading(shoulderCenterX: (left.location.x + right.location.x) / 2,
                                   shoulderTiltDegrees: atan2(dy, abs(dx)) * 180 / .pi)
        }
        let openPalm = handRequest?.results?.contains(where: Self.isOpenPalm) ?? false
        let luma = Self.averageLuma(buffer)
        Task { @MainActor in
            self.face = reading
            self.bodyPose = self.wantsBodyPoseGuidance ? pose : nil
            self.openPalmDetected = self.wantsHandGesture && openPalm
            self.lightLevel = luma
        }
    }

    private static func isOpenPalm(_ hand: VNHumanHandPoseObservation) -> Bool {
        guard let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence >= 0.3 else { return false }
        let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP), (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP)
        ]
        return fingers.allSatisfy { tipName, pipName in
            guard let tip = try? hand.recognizedPoint(tipName),
                  let pip = try? hand.recognizedPoint(pipName),
                  tip.confidence >= 0.25, pip.confidence >= 0.25 else { return false }
            let tipDistance = hypot(tip.location.x - wrist.location.x, tip.location.y - wrist.location.y)
            let pipDistance = hypot(pip.location.x - wrist.location.x, pip.location.y - wrist.location.y)
            return tipDistance > pipDistance * 1.18
        }
    }

    /// Mean brightness of the luma plane, sampled sparsely (cheap enough to run several times a second).
    private static func averageLuma(_ buffer: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPlaneCount(buffer) > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        var count = 0
        for y in Swift.stride(from: 0, to: height, by: 24) {
            for x in Swift.stride(from: 0, to: width, by: 24) {
                sum += Int(pixels[y * rowBytes + x])
                count += 1
            }
        }
        return count > 0 ? Double(sum) / Double(count) / 255 : nil
    }
}
