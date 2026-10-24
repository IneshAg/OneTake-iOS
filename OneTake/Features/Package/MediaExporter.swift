import AVFoundation
import CoreMedia

/// Composes the real recorded pieces of an audition — slate, full-length, and the circled take for
/// each scene — into one exported .mp4, the way a real "package for delivery" step has to. There's
/// no casting-site API this app can submit the file to, so "send" is real local export + handing the
/// real file to the system share sheet (AirDrop, Mail, Files), not a simulated server round trip.
enum MediaExporter {
    enum ExportError: LocalizedError {
        case trackCreationFailed, nothingToExport, sessionCreationFailed

        var errorDescription: String? {
            switch self {
            case .trackCreationFailed:   "Couldn't set up the export."
            case .nothingToExport:       "Nothing's been recorded yet for this audition."
            case .sessionCreationFailed: "Couldn't start the export session."
            }
        }
    }

    /// One piece that goes on the tape, in tape order.
    struct Clip: Hashable {
        enum Kind: Hashable { case headshot, slate, fullLength, scene(Int) }
        let kind: Kind
        let label: String
        let url: URL
    }

    /// A stretch of the finished tape — what Preview lists and jumps between.
    struct Chapter: Hashable, Identifiable {
        var id: Double { start }
        let kind: Clip.Kind
        let label: String
        let start: Double
        let duration: Double
    }

    /// The tape as a playable/exportable composition, with each clip's orientation re-applied.
    struct Tape {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let chapters: [Chapter]
        var duration: Double { chapters.last.map { $0.start + $0.duration } ?? 0 }
    }

    /// Off by default only when the actor turns it off (Preview's switch) — e.g. a notice that says
    /// "no title cards".
    static var opensWithHeadshot: Bool { UserDefaults.standard.object(forKey: "tape.headshotCard") as? Bool ?? true }

    /// The recorded clips, in order: slate, full length, then the circled (or first) take of each
    /// scene. Shared by the export, Preview and Tape Check, so all three look at the same thing.
    static func clips(for audition: Audition, takes: [Take]) -> [Clip] {
        var clips: [Clip] = []
        if let s = audition.slateVideoURL { clips.append(Clip(kind: .slate, label: "Slate", url: s)) }
        if let f = audition.fullLengthVideoURL { clips.append(Clip(kind: .fullLength, label: "Full length", url: f)) }
        // Takes are keyed by audition + scene *index* (what ShootFlow records), not by the scene's
        // display number, and only this audition's takes are eligible whatever the caller passes in.
        let auditionTakes = takes.filter { $0.auditionID == audition.id }
        for sceneIndex in audition.scenes.indices {
            let sceneTakes = auditionTakes.filter { $0.sceneIndex == sceneIndex }
            if let chosen = (sceneTakes.first(where: \.isCircled) ?? sceneTakes.first), let url = chosen.fileURL {
                clips.append(Clip(kind: .scene(sceneIndex), label: "Scene \(sceneIndex + 1) · Take \(chosen.number)", url: url))
            }
        }
        return clips
    }

    /// Everything on the tape: the audition headshots as an opening card (when taken, and unless
    /// switched off), then the recorded clips.
    static func tapeClips(for audition: Audition, takes: [Take]) async -> [Clip] {
        let recorded = clips(for: audition, takes: takes)
        guard opensWithHeadshot, let first = recorded.first,
              let size = await orientedSize(of: AVURLAsset(url: first.url)),
              let card = await HeadshotCard.video(size: size) else { return recorded }
        return [Clip(kind: .headshot, label: "Headshot", url: card)] + recorded
    }

    /// Joins the clips into one composition. Used for the instant Preview and for the export.
    static func build(_ clips: [Clip]) async throws -> Tape {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.trackCreationFailed }
        guard !clips.isEmpty else { throw ExportError.nothingToExport }

        // Each clip carries its own orientation (portrait capture, front-camera mirroring) in its
        // track's preferredTransform. Copying frames alone drops that, so the transforms are re-applied
        // per clip through a video composition.
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var renderSize: CGSize?
        var chapters: [Chapter] = []
        var cursor = CMTime.zero
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard let duration = try? await asset.load(.duration) else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            if let vTrack = try? await asset.loadTracks(withMediaType: .video).first {
                try? videoTrack.insertTimeRange(range, of: vTrack, at: cursor)
                if let loaded = try? await vTrack.load(.naturalSize, .preferredTransform) {
                    let (naturalSize, transform) = loaded
                    layerInstruction.setTransform(transform, at: cursor)
                    // Sized from the first real recording, so a headshot card never decides the frame.
                    if renderSize == nil, clip.kind != .headshot {
                        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
                        renderSize = CGSize(width: abs(rect.width), height: abs(rect.height))
                    }
                }
            }
            if let aTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: aTrack, at: cursor)
            }
            let label = clip.kind == .headshot || clip.kind == .slate || clip.kind == .fullLength
                ? clip.label : (clip.label.components(separatedBy: " · ").first ?? clip.label)
            chapters.append(Chapter(kind: clip.kind, label: label, start: cursor.seconds, duration: duration.seconds))
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor > .zero else { throw ExportError.nothingToExport }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        instruction.layerInstructions = [layerInstruction]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize ?? CGSize(width: 1080, height: 1920)
        return Tape(composition: composition, videoComposition: videoComposition, chapters: chapters)
    }

    static func orientedSize(of asset: AVURLAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let loaded = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    @MainActor
    static func export(_ audition: Audition, takes: [Take], slate: SlateInfo, progress: @escaping (Double) -> Void) async throws -> URL {
        let tape = try await build(tapeClips(for: audition, takes: takes))
        let composition = tape.composition
        let videoComposition = tape.videoComposition

        let fileName = audition.deliverableFileName(slate: slate)
        let outputDir = MediaStore.directory("Exports")
        let fileURL = outputDir.appendingPathComponent(fileName)
        // Export to a scratch file and only replace the deliverable on success, so a cancelled or
        // failed export never destroys the last good one (or races a retry writing the same name).
        let workingURL = outputDir.appendingPathComponent("exporting-\(UUID().uuidString).mp4")

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.sessionCreationFailed
        }
        export.outputURL = workingURL
        export.outputFileType = .mp4
        export.videoComposition = videoComposition

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progress(Double(export.progress))
        }
        defer { timer.invalidate() }

        try Task.checkCancellation()
        // Cancelling the calling task stops the real export instead of letting it run on unseen.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { cont.resume() }
            }
        } onCancel: {
            export.cancelExport()
        }

        guard export.status == .completed, !Task.isCancelled else {
            try? FileManager.default.removeItem(at: workingURL)
            if export.status == .cancelled || Task.isCancelled { throw CancellationError() }
            throw export.error ?? ExportError.sessionCreationFailed
        }
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: workingURL, to: fileURL)
        progress(1.0)
        return fileURL
    }
}
