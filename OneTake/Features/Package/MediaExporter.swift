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

    @MainActor
    static func export(_ audition: Audition, takes: [Take], slate: SlateInfo, progress: @escaping (Double) -> Void) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.trackCreationFailed }

        var clipURLs: [URL] = []
        if let s = audition.slateVideoURL { clipURLs.append(s) }
        if let f = audition.fullLengthVideoURL { clipURLs.append(f) }
        for scene in audition.scenes {
            let sceneTakes = takes.filter { $0.sceneIndex == scene.number - 1 }
            if let chosen = (sceneTakes.first(where: \.isCircled) ?? sceneTakes.first), let url = chosen.fileURL {
                clipURLs.append(url)
            }
        }
        guard !clipURLs.isEmpty else { throw ExportError.nothingToExport }

        var cursor = CMTime.zero
        for url in clipURLs {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration) else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            if let vTrack = try? await asset.loadTracks(withMediaType: .video).first {
                try? videoTrack.insertTimeRange(range, of: vTrack, at: cursor)
            }
            if let aTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: aTrack, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        let fileName = audition.deliverableFileName(slate: slate)
        let outputDir = MediaStore.directory("Exports")
        let fileURL = outputDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.sessionCreationFailed
        }
        export.outputURL = fileURL
        export.outputFileType = .mp4

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progress(Double(export.progress))
        }
        defer { timer.invalidate() }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }

        if let error = export.error { throw error }
        progress(1.0)
        return fileURL
    }
}
