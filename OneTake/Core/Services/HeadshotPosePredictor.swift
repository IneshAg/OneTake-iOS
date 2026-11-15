import AVFoundation
import CoreImage
import CoreML
import Foundation
import Vision

enum HeadshotPoseLabel: String, CaseIterable, Sendable {
    case front
    case leftProfile = "left_profile"
    case rightProfile = "right_profile"
}

struct HeadshotPosePrediction: Equatable, Sendable {
    let pose: HeadshotPoseLabel
    let probabilities: [HeadshotPoseLabel: Float]
    let yawRadians: Double
    let yawDegrees: Double

    var confidence: Float {
        probabilities[pose] ?? 0
    }
}

/// Runs OneTake's bundled `HeadshotPoseClassifier.mlmodel` (`224x224 RGB`) on portrait frames to
/// classify Front (`0°`), Left Profile (`+90°`), and Right Profile (`-90°`) with continuous yaw.
final class HeadshotPosePredictor: @unchecked Sendable {
    static let shared = HeadshotPosePredictor()

    private static let inputDimension = 224
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let model: MLModel?

    init(bundle: Bundle = .main) {
        self.model = Self.loadModel(from: bundle)
    }

    var isAvailable: Bool { model != nil }

    private static func loadModel(from bundle: Bundle) -> MLModel? {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        if let compiledURL = bundle.url(forResource: "HeadshotPoseClassifier", withExtension: "mlmodelc"),
           let loaded = try? MLModel(contentsOf: compiledURL, configuration: config) {
            return loaded
        }
        if let sourceURL = bundle.url(forResource: "HeadshotPoseClassifier", withExtension: "mlmodel"),
           let compiled = try? MLModel.compileModel(at: sourceURL),
           let loaded = try? MLModel(contentsOf: compiled, configuration: config) {
            return loaded
        }
        return nil
    }

    func predict(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> HeadshotPosePrediction? {
        guard let model,
              let resized = makeModelInputBuffer(from: pixelBuffer, orientation: orientation) else {
            return nil
        }
        return predict(resized224Buffer: resized, using: model)
    }

    /// Direct inference entry point for `224x224` pixel buffers (used both internally and by unit tests).
    func predict(resized224Buffer: CVPixelBuffer) -> HeadshotPosePrediction? {
        guard let model else { return nil }
        return predict(resized224Buffer: resized224Buffer, using: model)
    }

    private func predict(resized224Buffer: CVPixelBuffer, using model: MLModel) -> HeadshotPosePrediction? {
        guard let input = try? MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: resized224Buffer)
        ]),
        let output = try? model.prediction(from: input),
        let probArray = output.featureValue(for: "pose_probabilities")?.multiArrayValue else {
            return nil
        }

        let frontP = floatValue(in: probArray, at: 0)
        let leftP = floatValue(in: probArray, at: 1)
        let rightP = floatValue(in: probArray, at: 2)

        let probs: [HeadshotPoseLabel: Float] = [
            .front: frontP,
            .leftProfile: leftP,
            .rightProfile: rightP
        ]
        let bestPose = probs.max(by: { $0.value < $1.value })?.key ?? .front

        let yawRad = Double(output.featureValue(for: "predicted_yaw_radians")?.multiArrayValue.map { floatValue(in: $0, at: 0) } ?? 0)
        let yawDeg = Double(output.featureValue(for: "predicted_yaw_degrees")?.multiArrayValue.map { floatValue(in: $0, at: 0) } ?? 0)

        return HeadshotPosePrediction(
            pose: bestPose,
            probabilities: probs,
            yawRadians: yawRad,
            yawDegrees: yawDeg
        )
    }

    private func floatValue(in array: MLMultiArray, at index: Int) -> Float {
        guard index < array.count else { return 0 }
        return array[index].floatValue
    }

    private func makeModelInputBuffer(from source: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
        var ciImage = CIImage(cvPixelBuffer: source).oriented(orientation)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        // Center-square crop then scale cleanly to 224x224.
        let side = min(extent.width, extent.height)
        let cropOriginX = extent.origin.x + (extent.width - side) / 2
        let cropOriginY = extent.origin.y + (extent.height - side) / 2
        ciImage = ciImage.cropped(to: CGRect(x: cropOriginX, y: cropOriginY, width: side, height: side))

        let scale = CGFloat(Self.inputDimension) / side
        ciImage = ciImage
            .transformed(by: CGAffineTransform(translationX: -cropOriginX, y: -cropOriginY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        var outputBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputDimension,
            Self.inputDimension,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &outputBuffer
        )
        guard status == kCVReturnSuccess, let dst = outputBuffer else { return nil }
        ciContext.render(ciImage, to: dst, bounds: CGRect(x: 0, y: 0, width: Self.inputDimension, height: Self.inputDimension), colorSpace: CGColorSpaceCreateDeviceRGB())
        return dst
    }
}
