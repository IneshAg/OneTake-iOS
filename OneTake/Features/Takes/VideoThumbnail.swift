import SwiftUI
import OneTakeUI
import AVKit
import AVFoundation

/// A real frame grabbed from the take's own file — not a stand-in photo — generated once and cached
/// in memory for the life of the view.
struct VideoThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                OT.cameraBg
            }
        }
        // Runs again when the file changes (a trimmed take gets a new URL), so the frame never goes stale.
        .task(id: url) { image = await Self.thumbnail(url) }
    }

    /// Frames are kept in memory, keyed by file and modification date: lists of takes re-render
    /// often, and a re-recorded slate keeps its file name.
    private static let cache = NSCache<NSString, UIImage>()

    private static func thumbnail(_ url: URL) async -> UIImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(url.path)@\(modified?.timeIntervalSince1970 ?? 0)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // Display size, not the full frame: a 4K frame is ~33 MB decoded.
        generator.maximumSize = CGSize(width: 480, height: 480)
        let image: UIImage? = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.1, preferredTimescale: 30))]) { _, cgImage, _, _, error in
                if let cgImage { cont.resume(returning: UIImage(cgImage: cgImage)) }
                else { cont.resume(throwing: error ?? NSError(domain: "VideoThumbnail", code: -1)) }
            }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
