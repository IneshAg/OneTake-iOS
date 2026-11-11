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

/// Standard industry presets for auto-framing headshots.
enum HeadshotPreset: String, CaseIterable, Identifiable {
    case cardSlot = "Card Slot Fit"
    case theatrical = "Theatrical (4:5)"
    case commercial = "Commercial (3:4)"
    case square = "Square (1:1)"
    case tight = "Tight Close-Up"
    case headAndShoulders = "Head & Shoulders"

    var id: String { rawValue }

    var title: String { rawValue }

    var shortTitle: String {
        switch self {
        case .cardSlot: return "Card Fit"
        case .theatrical: return "4:5"
        case .commercial: return "3:4"
        case .square: return "1:1"
        case .tight: return "Tight"
        case .headAndShoulders: return "H & S"
        }
    }

    var icon: String {
        switch self {
        case .cardSlot: return "rectangle.split.2x1"
        case .theatrical: return "rectangle.portrait"
        case .commercial: return "rectangle.portrait.fill"
        case .square: return "square"
        case .tight: return "face.smiling"
        case .headAndShoulders: return "person.crop.rectangle"
        }
    }

    var description: String {
        switch self {
        case .cardSlot: return "Matched to OneTake audition submission cards"
        case .theatrical: return "Standard 8×10 theatrical print & casting format"
        case .commercial: return "Commercial & print audition portrait ratio"
        case .square: return "Actors Access & casting directory profile icon"
        case .tight: return "Expression & eye focus close-up"
        case .headAndShoulders: return "Balanced chest-up with comfortable headroom"
        }
    }

    func ratio(isProfile: Bool) -> CGFloat {
        if isProfile {
            switch self {
            case .cardSlot: return 171.5 / 145.0
            case .theatrical: return 4.0 / 5.0
            case .commercial: return 3.0 / 4.0
            case .square: return 1.0
            case .tight, .headAndShoulders: return 171.5 / 145.0
            }
        } else {
            switch self {
            case .cardSlot, .theatrical: return 4.0 / 5.0
            case .commercial: return 3.0 / 4.0
            case .square: return 1.0
            case .tight, .headAndShoulders: return 4.0 / 5.0
            }
        }
    }

    func faceFraction(isProfile: Bool) -> CGFloat {
        if isProfile {
            switch self {
            case .tight: return 0.40
            case .headAndShoulders, .theatrical, .commercial, .square, .cardSlot: return 0.28
            }
        } else {
            switch self {
            case .tight: return 0.28
            case .headAndShoulders, .theatrical, .cardSlot: return 0.18
            case .commercial: return 0.20
            case .square: return 0.22
            }
        }
    }

    func faceCenterFromTop(isProfile: Bool) -> CGFloat {
        if isProfile {
            return 0.40
        } else {
            switch self {
            case .tight: return 0.40
            case .headAndShoulders, .theatrical, .commercial, .square, .cardSlot: return 0.38
            }
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
    /// For front headshots, 0.24 gives a relaxed theatrical head-and-shoulders framing with headroom
    /// and full shoulders, preventing the face from zooming in excessively.
    static let faceHeightFraction: CGFloat = 0.24
    /// Where the face centre sits, measured from the top of the crop — eyes land near the upper third.
    static let faceCenterFromTop: CGFloat = 0.39
    /// Keep the shoulders: the crop is at least this many face-widths wide.
    static let minFaceWidths: CGFloat = 3.0
    /// Don't produce tiny crops from a small, far-away face if the photo has more pixels to give.
    static let minShortSide: CGFloat = 800

    static func crop(_ image: UIImage, ratio: CGFloat, isProfile: Bool = false) -> UIImage? {
        guard ratio > 0, let upright = normalized(image), let cgImage = upright.cgImage else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let face = detectSubject(in: cgImage, size: size, isProfile: isProfile)
        let rect = cropRect(imageSize: size, subject: face, ratio: ratio, isProfile: isProfile)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    static func crop(_ image: UIImage, preset: HeadshotPreset, isProfile: Bool = false) -> UIImage? {
        let ratio = preset.ratio(isProfile: isProfile)
        guard ratio > 0, let upright = normalized(image), let cgImage = upright.cgImage else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let face = detectSubject(in: cgImage, size: size, isProfile: isProfile)
        let rect = cropRect(imageSize: size, subject: face, ratio: ratio, preset: preset, isProfile: isProfile)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// The crop, in pixel space of the upright image (top-left origin). Pure, so it can be tested.
    /// - Parameter subject: the face box, or `nil` to fall back to an upper-biased centre crop.
    static func cropRect(imageSize: CGSize, subject: CGRect?, ratio: CGFloat, preset: HeadshotPreset? = nil, isProfile: Bool = false) -> CGRect {
        let imageW = imageSize.width, imageH = imageSize.height
        guard imageW > 0, imageH > 0, ratio > 0 else { return .zero }

        let targetFaceHeightFraction: CGFloat
        let targetAnchorFromTop: CGFloat
        let targetMinFaceWidths: CGFloat

        if let preset {
            targetFaceHeightFraction = preset.faceFraction(isProfile: isProfile)
            targetAnchorFromTop = preset.faceCenterFromTop(isProfile: isProfile)
            targetMinFaceWidths = isProfile ? 2.0 : (preset == .tight ? 1.8 : 2.5)
        } else if isProfile {
            // Profile shots live in wide cards (~1.18 ratio, height ~145 pt).
            // Head needs to fill ~45% of the frame height with proper headroom,
            // avoiding tiny heads with vast ceilings.
            targetFaceHeightFraction = 0.45
            targetAnchorFromTop = 0.42
            targetMinFaceWidths = 2.0
        } else if ratio < 0.7 {
            // Front slot in HeadshotsView is tall (~0.57 ratio, width 171.5 / height 300).
            // A face fraction around 0.21 gives comfortable headroom (~15%)
            // and full shoulders, preventing the face from blowing up into the chin and forehead.
            targetFaceHeightFraction = 0.21
            targetAnchorFromTop = 0.35
            targetMinFaceWidths = 2.4
        } else {
            // Standard theatrical 4:5 headshots (ratio ~0.8)
            targetFaceHeightFraction = faceHeightFraction
            targetAnchorFromTop = faceCenterFromTop
            targetMinFaceWidths = minFaceWidths
        }

        var w: CGFloat
        var h: CGFloat
        let centerX: CGFloat
        let anchorY: CGFloat   // the point placed at `anchorFromTop` of the crop height
        let anchorFromTop: CGFloat

        if let face = subject, face.width > 0, face.height > 0 {
            h = face.height / targetFaceHeightFraction
            w = h * ratio
            if w < face.width * targetMinFaceWidths {
                w = face.width * targetMinFaceWidths
                h = w / ratio
            }
            // Don't hand back a postage stamp when the original has the resolution for more.
            let shortSide = min(w, h)
            let effectiveMin = min(minShortSide, min(imageW, imageH) * 0.45)
            if shortSide < effectiveMin {
                let grow = effectiveMin / shortSide
                w *= grow; h *= grow
            }
            centerX = face.midX
            anchorY = face.midY
            anchorFromTop = targetAnchorFromTop
        } else {
            if ratio >= 1.0 {
                h = min(imageH, imageW / ratio)
                w = h * ratio
            } else {
                w = min(imageW, imageH * ratio)
                h = w / ratio
            }
            centerX = imageW / 2
            anchorY = imageH * (isProfile ? 0.42 : 0.38)
            anchorFromTop = isProfile ? 0.42 : 0.38
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

    /// The largest face, in top-left pixel space; falls back to human body pose / upper body for profile shots
    /// where face detection can miss.
    static func detectSubject(in cgImage: CGImage, size: CGSize, isProfile: Bool = false) -> CGRect? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 1. Standard face detection
        let faces = VNDetectFaceRectanglesRequest()
        #if compiler(>=6.0)
        faces.revision = VNDetectFaceRectanglesRequestRevision3
        #endif
        try? handler.perform([faces])
        if let face = faces.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }),
           face.confidence > 0.3 {
            return pixelRect(face.boundingBox, in: size)
        }

        // 2. Human body pose detection for tracking head joints even in side profile (ears, nose, neck)
        let poseRequest = VNDetectHumanBodyPoseRequest()
        try? handler.perform([poseRequest])
        if let pose = poseRequest.results?.first {
            let headJoints: [VNHumanBodyPoseObservation.JointName] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar, .neck]
            let recognized = headJoints.compactMap { joint -> CGPoint? in
                guard let pt = try? pose.recognizedPoint(joint), pt.confidence > 0.2 else { return nil }
                return CGPoint(x: pt.location.x * size.width, y: (1 - pt.location.y) * size.height)
            }
            if !recognized.isEmpty {
                let minX = recognized.map(\.x).min()!
                let maxX = recognized.map(\.x).max()!
                let minY = recognized.map(\.y).min()!
                let maxY = recognized.map(\.y).max()!
                let w = max(maxX - minX, size.width * 0.12)
                let h = max(maxY - minY, size.height * 0.12)
                let padX = w * 0.25
                let padYTop = h * 0.35
                let padYBottom = h * 0.15
                return CGRect(
                    x: max(0, minX - padX),
                    y: max(0, minY - padYTop),
                    width: min(size.width, w + padX * 2),
                    height: min(size.height, h + padYTop + padYBottom)
                )
            }
        }

        // 3. Upper body detection fallback
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
