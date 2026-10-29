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

    /// One recorded piece that goes on the tape, in tape order. (Headshots aren't on the tape: they're
    /// photos, sent alongside it — see `HeadshotStore.deliverables`.)
    struct Clip: Hashable {
        enum Kind: Hashable { case slate, fullLength, scene(Int) }
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

    /// Profile → "Slate at the start". Some casting asks for the slate at the end instead.
    static var slateAtStart: Bool { UserDefaults.standard.object(forKey: "slateAtStart") as? Bool ?? true }

    /// The recorded clips, in order: slate, full length, then only the circled take of each
    /// scene — or the scenes first when the slate goes at the end. Shared by the export, Preview and
    /// Tape Check, so all three look at the same thing.
    static func clips(for audition: Audition, takes: [Take], slateAtStart: Bool = Self.slateAtStart) -> [Clip] {
        var slate: [Clip] = []
        if let s = audition.slateVideoURL { slate.append(Clip(kind: .slate, label: "Slate", url: s)) }
        if let f = audition.fullLengthVideoURL { slate.append(Clip(kind: .fullLength, label: "Full length", url: f)) }
        var clips: [Clip] = []
        // Takes are keyed by audition + scene *index* (what ShootFlow records), not by the scene's
        // display number, and only this audition's takes are eligible whatever the caller passes in.
        let auditionTakes = takes.filter { $0.auditionID == audition.id }
        for sceneIndex in audition.scenes.indices {
            let sceneTakes = auditionTakes.filter { $0.sceneIndex == sceneIndex }
            if let chosen = sceneTakes.first(where: \.isCircled), let url = chosen.fileURL {
                clips.append(Clip(kind: .scene(sceneIndex), label: "Scene \(sceneIndex + 1) · Take \(chosen.number)", url: url))
            }
        }
        return slateAtStart ? slate + clips : clips + slate
    }

    /// Writes the individual finalized clips and headshots beside the merged export so casting
    /// materials can also be handed off as one ordinary ZIP file.
    static func makeSeparateArchive(_ audition: Audition, takes: [Take], slate: SlateInfo) throws -> URL {
        let baseName = (audition.deliverableFileName(slate: slate) as NSString).deletingPathExtension
        let archiveURL = MediaStore.directory("Exports").appendingPathComponent("\(baseName)_SEPARATE.zip")
        var entries: [ZipArchive.Entry] = []
        for clip in clips(for: audition, takes: takes) {
            guard FileManager.default.fileExists(atPath: clip.url.path) else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: clip.url.path])
            }
            let ext = clip.url.pathExtension.isEmpty ? "mov" : clip.url.pathExtension
            let name = clip.label.replacingOccurrences(of: " · ", with: " - ").replacingOccurrences(of: " ", with: "_")
            entries.append(ZipArchive.Entry(name: "Videos/\(name).\(ext)", fileURL: clip.url))
        }
        for url in HeadshotStore.deliverables(baseName: baseName) {
            entries.append(ZipArchive.Entry(name: "Headshots/\(url.lastPathComponent)", fileURL: url))
        }
        guard !entries.isEmpty else { throw ExportError.nothingToExport }
        try ZipArchive.write(entries, to: archiveURL)
        return archiveURL
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
                    if renderSize == nil {
                        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
                        renderSize = CGSize(width: abs(rect.width), height: abs(rect.height))
                    }

                }
            }
            if let aTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: aTrack, at: cursor)
            }
            // "Scene 1 · Take 3" → "Scene 1" in the chapter list.
            let label = clip.label.components(separatedBy: " · ").first ?? clip.label
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

    @MainActor
    static func export(_ audition: Audition, takes: [Take], slate: SlateInfo, progress: @escaping (Double) -> Void) async throws -> URL {
        let tape = try await build(clips(for: audition, takes: takes))
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
        export.videoComposition = videoComposition

        try Task.checkCancellation()
        // Progress comes from the export's own state stream (iOS 18+).
        let progressTask = Task { @MainActor in
            for await state in export.states(updateInterval: 0.1) {
                if case .exporting(let exportProgress) = state { progress(exportProgress.fractionCompleted) }
            }
        }
        defer { progressTask.cancel() }

        // Cancelling the calling task stops the real export instead of letting it run on unseen.
        do {
            try await export.export(to: workingURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: workingURL)
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw error
        }
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: workingURL, to: fileURL)
        progress(1.0)
        return fileURL
    }
}
