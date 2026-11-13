import SwiftUI
import AVKit

// MARK: - Video trim editor

/// A compact editor with its close control at the top and the save action safely at the bottom.
/// It exports a new file so callers can keep the source clip and offer an undo path.
struct VideoTrimmer: View {
    let url: URL
    var onFinish: (URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var exportError = false
    @State private var exportSession: AVAssetExportSession?
    @State private var filmstrip: [UIImage] = []

    static func canTrim(_ url: URL) -> Bool { url.isFileURL && FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Edit video")
                    .font(.otHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.otIcon(.m, weight: .semibold))
                            .frame(width: 44, height: 44) // ot-lint:allow
                            .background(OT.fillField, in: Circle()) // ot-lint:allow
                    }
                    .accessibilityLabel("Close video editor")
                    Spacer()
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, OTSpace.m)
            .padding(.bottom, OTSpace.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) { // ot-lint:allow
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 250) // ot-lint:allow
                            .clipShape(RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                            .fill(Color.black)
                            .frame(height: 250) // ot-lint:allow
                            .overlay(ProgressView().tint(.white))
                    }

                    if duration > 0.5 {
                        HStack {
                            Button {
                                if isPlaying { player?.pause(); isPlaying = false }
                                else {
                                    if playhead < trimStart || playhead >= trimEnd {
                                        playhead = trimStart
                                        seek(to: trimStart)
                                    }
                                    player?.play()
                                    isPlaying = true
                                }
                            } label: {
                                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.otFootnote.weight(.semibold))
                            }
                            Spacer()
                            Text("\(timeLabel(playhead)) / \(timeLabel(duration))")
                                .font(.otCaption.monospacedDigit()).foregroundStyle(OT.labelSecondary)
                        }

                        Slider(value: $playhead, in: 0...duration) { editing in
                            if !editing { seek(to: playhead) }
                        }
                        .tint(OT.accent)

                        timelineCard

                        Text("Your original recording will remain available so you can restore it later.")
                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                    }
                }
                .padding(OT.gutter)
            }
        }
        .background(OT.bgCanvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: exportTrim) {
                HStack(spacing: 8) { // ot-lint:allow
                    if isExporting { ProgressView().tint(.white) }
                    Text(isExporting ? "Saving edited clip…" : "Save trimmed clip")
                }
            }
            .buttonStyle(.otPrimary)
            .disabled(duration <= 0.5 || trimEnd - trimStart < 0.5 || isExporting)
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, OTSpace.s)
            .background(.ultraThinMaterial)
        }
        .alert("Couldn't save the edit", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The original clip is still safe. Please try saving the edit again.")
        }
        .task(id: url) {
            let asset = AVURLAsset(url: url)
            do {
                let loadedDuration = try await asset.load(.duration).seconds
                guard loadedDuration.isFinite, loadedDuration > 0 else { return }
                duration = loadedDuration
                trimEnd = loadedDuration
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                filmstrip = await Self.generateFilmstrip(for: asset, duration: loadedDuration, count: 8)
            } catch {
                exportError = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func cancel() {
        exportSession?.cancelExport()
        player?.pause()
        onFinish(nil)
        dismiss()
    }

    private var timelineCard: some View {
        VStack(spacing: OTSpace.s) {
            HStack {
                HStack(spacing: OTSpace.xs) {
                    Text("START")
                        .font(.otCaption.weight(.bold))
                        .foregroundStyle(OT.labelTertiary)
                    Text(timeLabel(trimStart))
                        .font(.otFootnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                }

                Spacer()

                HStack(spacing: OTSpace.xs) {
                    Image(systemName: "scissors")
                        .font(.caption2)
                        .foregroundStyle(OT.accent)
                    Text(timeLabel(max(0, trimEnd - trimStart)))
                        .font(.otFootnote.monospacedDigit().weight(.bold))
                        .foregroundStyle(OT.accent)
                }

                Spacer()

                HStack(spacing: OTSpace.xs) {
                    Text("END")
                        .font(.otCaption.weight(.bold))
                        .foregroundStyle(OT.labelTertiary)
                    Text(timeLabel(trimEnd))
                        .font(.otFootnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                }
            }

            GeometryReader { geo in
                timelineTrack(totalWidth: geo.size.width)
            }
            .frame(height: 58) // ot-lint:allow
        }
        .otCard(.grouped)
    }

    private func timelineTrack(totalWidth: CGFloat) -> some View {
        let width = max(120, totalWidth)
        let handleWidth: CGFloat = 18
        let trackHeight: CGFloat = 52
        let safeDuration = max(0.1, duration)
        let startX = max(0, min(width - handleWidth * 2, CGFloat(trimStart / safeDuration) * width))
        let endX = max(startX + handleWidth * 2, min(width, CGFloat(trimEnd / safeDuration) * width))
        let playheadX = max(0, min(width, CGFloat(playhead / safeDuration) * width))

        return ZStack(alignment: .leading) {
            // Filmstrip frames (or tick marks while frames generate)
            ZStack {
                if !filmstrip.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(filmstrip.indices, id: \.self) { index in
                            Image(uiImage: filmstrip[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: width / CGFloat(filmstrip.count), height: trackHeight) // ot-lint:allow
                                .clipped()
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(0..<16, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(OT.labelTertiary.opacity(0.25))
                                .frame(width: 1, height: 24) // ot-lint:allow
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: width, height: trackHeight) // ot-lint:allow
            .background(OT.fillField)
            .clipShape(RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))

            // Dimmed excluded regions
            if startX > 0 {
                Rectangle()
                    .fill(Color.black.opacity(0.58)) // ot-lint:allow
                    .frame(width: startX, height: trackHeight) // ot-lint:allow
            }
            if endX < width {
                Rectangle()
                    .fill(Color.black.opacity(0.58)) // ot-lint:allow
                    .frame(width: width - endX, height: trackHeight) // ot-lint:allow
                    .offset(x: endX)
            }

            // Active trim window border
            RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                .stroke(OT.accent, lineWidth: 3) // ot-lint:allow
                .frame(width: max(handleWidth * 2, endX - startX), height: trackHeight) // ot-lint:allow
                .offset(x: startX)

            // Playhead needle
            Rectangle()
                .fill(Color.white) // ot-lint:allow
                .frame(width: 2.5, height: 58) // ot-lint:allow
                .shadow(color: .black.opacity(0.6), radius: 2)
                .offset(x: max(0, min(width - 2.5, playheadX - 1.25)))

            // Left handle
            trimHandle(icon: "chevron.compact.left", width: handleWidth, height: trackHeight)
                .offset(x: startX)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("scrubberTrack"))
                        .onChanged { value in
                            let clampedX = max(0, min(endX - handleWidth * 2, value.location.x))
                            let newSec = Double(clampedX / width) * duration
                            trimStart = max(0, min(trimEnd - 0.5, newSec))
                            playhead = trimStart
                            seek(to: trimStart)
                        }
                )

            // Right handle
            trimHandle(icon: "chevron.compact.right", width: handleWidth, height: trackHeight)
                .offset(x: max(handleWidth, endX - handleWidth))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("scrubberTrack"))
                        .onChanged { value in
                            let clampedX = max(startX + handleWidth * 2, min(width, value.location.x))
                            let newSec = Double(clampedX / width) * duration
                            trimEnd = min(duration, max(trimStart + 0.5, newSec))
                            playhead = trimEnd
                            seek(to: trimEnd)
                        }
                )
        }
        .frame(width: width, height: 58, alignment: .leading) // ot-lint:allow
        .coordinateSpace(name: "scrubberTrack")
        .contentShape(Rectangle())
        .onTapGesture { location in
            let clampedX = max(0, min(width, location.x))
            let tappedSec = Double(clampedX / width) * duration
            playhead = min(duration, max(0, tappedSec))
            seek(to: playhead)
        }
    }

    private func trimHandle(icon: String, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: OTRadius.xs, style: .continuous)
                .fill(OT.accent)
                .frame(width: width, height: height) // ot-lint:allow
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(OT.labelOnAccent)
        }
    }

    private static func generateFilmstrip(for asset: AVAsset, duration: Double, count: Int) async -> [UIImage] {
        guard count > 0, duration > 0.1 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        var images: [UIImage] = []
        for i in 0..<count {
            let t = CMTime(seconds: duration * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
            if let cg = try? await generator.image(at: t).image {
                images.append(UIImage(cgImage: cg))
            }
        }
        return images
    }

    private func exportTrim() {
        guard duration > 0.5,
              let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetHighestQuality) else {
            exportError = true
            return
        }
        player?.pause()
        isPlaying = false
        isExporting = true
        exportSession = session
        let outputType: AVFileType = session.supportedFileTypes.contains(.mov) ? .mov : .mp4
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetake-edit-\(UUID().uuidString).\(outputType == .mov ? "mov" : "mp4")")
        session.outputURL = output
        session.outputFileType = outputType
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            duration: CMTime(seconds: trimEnd - trimStart, preferredTimescale: 600)
        )
        Task {
            do {
                try await session.export(to: output, as: outputType)
                isExporting = false
                onFinish(output)
                dismiss()
            } catch {
                try? FileManager.default.removeItem(at: output)
                isExporting = false
                exportError = true
            }
        }
    }
}
