import UIKit
import Vision

enum FramingRatio: String, CaseIterable, Identifiable {
    case portrait = "9:16"
    case landscape = "16:9"
    case photo = "4:3"
    case square = "1:1"

    var id: String { rawValue }
    var value: CGFloat {
        switch self {
        case .portrait: 9.0 / 16.0
        case .landscape: 16.0 / 9.0
        case .photo: 4.0 / 3.0
        case .square: 1
        }
    }
}

enum ImageFramer {
    static func crop(_ image: UIImage, ratio: CGFloat) -> UIImage? {
        guard ratio > 0, let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropSize = width / height > ratio
            ? CGSize(width: height * ratio, height: height)
            : CGSize(width: width, height: width / ratio)

        var center = CGPoint(x: width / 2, y: height / 2)
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        if let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            center = CGPoint(x: face.boundingBox.midX * width,
                             y: (1 - face.boundingBox.midY) * height)
        }

        let rect = CGRect(
            x: min(max(center.x - cropSize.width / 2, 0), width - cropSize.width),
            y: min(max(center.y - cropSize.height / 2, 0), height - cropSize.height),
            width: cropSize.width,
            height: cropSize.height
        ).integral
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
