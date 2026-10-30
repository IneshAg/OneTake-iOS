import UIKit
import Vision

enum FramingRatio: String, CaseIterable, Identifiable {
    case headshot = "4:5"
    case portrait = "3:4"
    case square = "1:1"
    case photo = "4:3"
    case landscape = "16:9"

    var id: String { rawValue }
    /// Width ÷ height.
    var value: CGFloat {
        switch self {
        case .headshot: 4.0 / 5.0
        case .portrait: 3.0 / 4.0
        case .square: 1
        case .photo: 4.0 / 3.0
        case .landscape: 16.0 / 9.0
        }
    }
}

/// Reframes a headshot as head-and-shoulders around the detected face.
///
/// Two things made the old version "pan in" instead of reframing:
/// - It worked on the raw sensor buffer (`cgImage`) and ignored `imageOrientation`, so for camera
///   photos the ratio and the face position were applied in the wrong (rotated) space.
/// - It always took the largest crop of the ratio and only moved it, so it never framed the face —
///   and repeated runs cropped the already-cropped photo again.
enum ImageFramer {
    /// Fraction of the crop height the detected face box should take (Vision's box is ~brows→chin).
    static let faceHeightFraction: CGFloat = 0.33
    /// Where the face centre sits, measured from the top of the crop — eyes land near the upper third.
    static let faceCenterFromTop: CGFloat = 0.43
    /// Keep the shoulders: the crop is at least this many face-widths wide.
    static let minFaceWidths: CGFloat = 2.6
    /// Don't produce tiny crops from a small, far-away face if the photo has more pixels to give.
    static let minShortSide: CGFloat = 800

    static func crop(_ image: UIImage, ratio: CGFloat) -> UIImage? {
        guard ratio > 0, let upright = normalized(image), let cgImage = upright.cgImage else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let face = detectSubject(in: cgImage, size: size)
        let rect = cropRect(imageSize: size, subject: face, ratio: ratio)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// The crop, in pixel space of the upright image (top-left origin). Pure, so it can be tested.
    /// - Parameter subject: the face box, or `nil` to fall back to an upper-biased centre crop.
    static func cropRect(imageSize: CGSize, subject: CGRect?, ratio: CGFloat) -> CGRect {
        let imageW = imageSize.width, imageH = imageSize.height
        guard imageW > 0, imageH > 0, ratio > 0 else { return .zero }

        var w: CGFloat
        var h: CGFloat
        let centerX: CGFloat
        let anchorY: CGFloat   // the point placed at `anchorFromTop` of the crop height
        let anchorFromTop: CGFloat

        if let face = subject, face.width > 0, face.height > 0 {
            h = face.height / faceHeightFraction
            w = h * ratio
            if w < face.width * minFaceWidths {
                w = face.width * minFaceWidths
                h = w / ratio
            }
            // Don't hand back a postage stamp when the original has the resolution for more.
            let shortSide = min(w, h)
            if shortSide < minShortSide {
                let grow = minShortSide / shortSide
                w *= grow; h *= grow
            }
            centerX = face.midX
            anchorY = face.midY
            anchorFromTop = faceCenterFromTop
        } else {
            w = imageW; h = imageW / ratio
            centerX = imageW / 2
            anchorY = imageH * 0.45
            anchorFromTop = 0.45
        }

        // Fit inside the photo, keeping the ratio (never upscale past the original pixels).
        let fit = min(1, imageW / w, imageH / h)
        w *= fit; h *= fit

        let x = min(max(centerX - w / 2, 0), imageW - w)
        let y = min(max(anchorY - h * anchorFromTop, 0), imageH - h)
        return CGRect(x: x, y: y, width: w, height: h).integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// Redraws the photo with its orientation baked in so pixels, Vision and the crop all agree.
    static func normalized(_ image: UIImage) -> UIImage? {
        if image.imageOrientation == .up, image.cgImage != nil { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }

    /// The largest face, in top-left pixel space; falls back to an upper body for profile shots
    /// where face detection can miss.
    private static func detectSubject(in cgImage: CGImage, size: CGSize) -> CGRect? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        let faces = VNDetectFaceRectanglesRequest()
        try? handler.perform([faces])
        if let face = faces.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            return pixelRect(face.boundingBox, in: size)
        }
        let body = VNDetectHumanRectanglesRequest()
        body.upperBodyOnly = true
        try? handler.perform([body])
        if let person = body.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            // Approximate the head as the top part of an upper-body box.
            let box = pixelRect(person.boundingBox, in: size)
            let headH = box.height * 0.38
            let headW = min(box.width * 0.5, headH * 0.8)
            return CGRect(x: box.midX - headW / 2, y: box.minY + headH * 0.15, width: headW, height: headH)
        }
        return nil
    }

    /// Vision's normalized, bottom-left-origin rect → pixel rect with a top-left origin.
    private static func pixelRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: normalized.minX * size.width,
               y: (1 - normalized.maxY) * size.height,
               width: normalized.width * size.width,
               height: normalized.height * size.height)
    }

    private static func area(_ r: CGRect) -> CGFloat { r.width * r.height }
}
