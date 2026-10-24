import AVFoundation
import CoreMedia

/// Composes the real recorded pieces of an audition — slate, full-length, and the circled take for
/// each scene — into one exported .mp4 (or one per piece, when the destination wants them separate),
/// kept under the destination's file size limit, the way a real "package for delivery" step has to. There's
/// no casting-site API this app can submit the file to, so "send" is real local export + handing the
/// real file to the system share sheet (AirDrop, Mail, Files), not a simulated server round trip.
enum MediaExporter {
    enum ExportError: LocalizedError {
        case trackCreationFailed, nothingToExport, sessionCreationFailed
        /// Still over the site's limit at the smallest size we'll make.
        case tooLarge(file: String, megabytes: Int64, limitMegabytes: Int64, site: String)

        var errorDescription: String? {
            switch self {
            case .trackCreationFailed:   "Couldn't set up the export."
            case .nothingToExport:       "Nothing's been recorded yet for this audition."
            case .sessionCreationFailed: "Couldn't start the export session."
            case let .tooLarge(file, megabytes, limit, site):
                "\(file) is still \(megabytes) MB at the smallest size, and \(site) takes up to \(limit) MB a file. Trim the takes, or turn on separate files so each piece is its own upload."
            }
        }
    }

    /// What one export made.
    struct Output {
        /// In tape order: the one joined tape, or one file per piece.
        let files: [URL]
        let joined: Bool
        /// Set (e.g. "720p") when a file had to come down from full quality to fit the size limit.
        let reducedTo: String?
    }

    /// Full quality first; when that comes out over the destination's limit, smaller sizes in turn.
    /// `shortSide` caps the picture's shorter edge (nil keeps the recording's own size).
    private static let qualities: [(shortSide: CGFloat?, label: String?)] = [(nil, nil), (720, "720p"), (540, "540p")]

    /// One recorded piece that goes on the tape, in tape order. (Headshots aren't on the tape: they're
    /// photos, sent alongside it — see `HeadshotStore.deliverables`.)
    struct Clip: Hashable {
        enum Kind: Hashable { case slate, fullLength, scene(Int) }
        let kind: Kind
        let label: String
        let url: URL

        /// Added to the tape's name when this clip is sent as its own file: …_SLATE.mp4, …_SCENE2.mp4.
        var fileSuffix: String {
            switch kind {
            case .slate:          "SLATE"
            case .fullLength:     "FULL_LENGTH"
            case .scene(let i):   "SCENE\(i + 1)"
            }
        }
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

    /// Joins the clips into one composition. Used for the instant Preview and for the export.
    /// `maxShortSide` scales the picture down so its shorter edge is at most that many pixels.
    static func build(_ clips: [Clip], maxShortSide: CGFloat? = nil) async throws -> Tape {
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
        // Set from the first clip, then the same factor applies to every clip.
        var scale: CGFloat = 1
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
                    if renderSize == nil {
                        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
                        let size = CGSize(width: abs(rect.width), height: abs(rect.height))
                        if let maxShortSide, min(size.width, size.height) > maxShortSide {
                            scale = maxShortSide / min(size.width, size.height)
                        }
                        // Encoders want even dimensions.
                        renderSize = CGSize(width: (size.width * scale / 2).rounded() * 2, height: (size.height * scale / 2).rounded() * 2)
                    }
                    layerInstruction.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: cursor)
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
    static func export(_ audition: Audition, takes: [Take], slate: SlateInfo, progress: @escaping (Double) -> Void) async throws -> Output {
        let clips = MediaExporter.clips(for: audition, takes: takes)
        guard !clips.isEmpty else { throw ExportError.nothingToExport }
        let base = (audition.deliverableFileName(slate: slate) as NSString).deletingPathExtension
        let separate = audition.sendsSeparateFiles
        let files: [(name: String, clips: [Clip])] = separate
            ? clips.map { (name: "\(base)_\($0.fileSuffix).mp4", clips: [$0]) }
            : [(name: "\(base).mp4", clips: clips)]

        var urls: [URL] = []
        var lowest = 0
        for (i, file) in files.enumerated() {
            let share = 1 / Double(files.count)
            let made = try await exportFile(file.clips, named: file.name, destination: audition.destination) { p in
                progress((Double(i) + p) * share)
            }
            urls.append(made.url)
            lowest = max(lowest, made.quality)
        }
        progress(1.0)
        return Output(files: urls, joined: !separate, reducedTo: qualities[lowest].label)
    }

    /// Exports one file at full quality, then steps down in size until it fits the destination's limit.
    /// Returns the file and the index into `qualities` it was made at.
    @MainActor
    private static func exportFile(_ clips: [Clip], named name: String, destination: Destination,
                                   progress: @escaping (Double) -> Void) async throws -> (url: URL, quality: Int) {
        let outputDir = MediaStore.directory("Exports")
        let fileURL = outputDir.appendingPathComponent(name)
        let limit = destination.maxFileBytes
        // A full-quality export comes out roughly the size of the recordings, so when those are well
        // over the limit, start one step down rather than spend the time on a file that can't be sent.
        var quality = 0
        if let limit, clips.reduce(Int64(0), { $0 + fileSize($1.url) }) > limit + limit / 4 { quality = 1 }
        while true {
            let tape = try await build(clips, maxShortSide: qualities[quality].shortSide)
            let workingURL = try await render(tape, in: outputDir, progress: progress)
            let size = fileSize(workingURL)
            if let limit, size > limit {
                try? FileManager.default.removeItem(at: workingURL)
                guard quality + 1 < qualities.count else {
                    throw ExportError.tooLarge(file: name, megabytes: size / 1_000_000, limitMegabytes: limit / 1_000_000,
                                               site: destination.rawValue)
                }
                quality += 1
                continue
            }
            try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: workingURL, to: fileURL)
            return (fileURL, quality)
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// Renders a tape to a scratch file and returns it. The deliverable is only replaced once a file
    /// is done and fits, so a cancelled or failed export never destroys the last good one (or races a
    /// retry writing the same name).
    @MainActor
    private static func render(_ tape: Tape, in outputDir: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let workingURL = outputDir.appendingPathComponent("exporting-\(UUID().uuidString).mp4")

        guard let export = AVAssetExportSession(asset: tape.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.sessionCreationFailed
        }
        export.outputURL = workingURL
        export.outputFileType = .mp4
        export.videoComposition = tape.videoComposition

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
        return workingURL
    }
}
