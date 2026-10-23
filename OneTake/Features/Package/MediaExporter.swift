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

    /// One recorded piece that goes on the tape, in tape order.
    struct Clip: Hashable {
        enum Kind: Hashable { case slate, fullLength, scene(Int) }
        let kind: Kind
        let label: String
        let url: URL
    }

    /// What goes on the tape, in order: slate, full length, then the circled (or first) take of each
    /// scene. Shared by the export and by Tape Check, so the check looks at exactly what gets sent.
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

    @MainActor
    static func export(_ audition: Audition, takes: [Take], slate: SlateInfo, progress: @escaping (Double) -> Void) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.trackCreationFailed }

        let clipURLs = clips(for: audition, takes: takes).map(\.url)
        guard !clipURLs.isEmpty else { throw ExportError.nothingToExport }

        // Each clip carries its own orientation (portrait capture, front-camera mirroring) in its
        // track's preferredTransform. Copying frames alone drops that, so the transforms are re-applied
        // per clip through a video composition.
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var renderSize: CGSize?
        var cursor = CMTime.zero
        for url in clipURLs {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration) else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            if let vTrack = try? await asset.loadTracks(withMediaType: .video).first {
                try? videoTrack.insertTimeRange(range, of: vTrack, at: cursor)
                if let loaded = try? await vTrack.load(.naturalSize, .preferredTransform) {
                    let (naturalSize, transform) = loaded
                    layerInstruction.setTransform(transform, at: cursor)
                    if renderSize == nil {
                        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
                        renderSize = CGSize(width: abs(rect.width), height: abs(rect.height))
                    }
                }
            }
            if let aTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: aTrack, at: cursor)
            }
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
