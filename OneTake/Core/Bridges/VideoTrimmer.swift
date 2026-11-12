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

    static func canTrim(_ url: URL) -> Bool { url.isFileURL && FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.otIcon(.m, weight: .semibold))
                        .frame(width: 44, height: 44) // ot-lint:allow
                        .background(OT.fillField, in: Circle()) // ot-lint:allow
                }
                .accessibilityLabel("Close video editor")
                Spacer()
                Text("Edit video").font(.otHeadline)
                Spacer()
                Color.clear.frame(width: 44, height: 44) // ot-lint:allow
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, OTSpace.s)

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

                        GeometryReader { geo in
                            timelineScrubber(totalWidth: geo.size.width)
                        }
                        .frame(height: 108) // ot-lint:allow

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

    private func timelineScrubber(totalWidth: CGFloat) -> some View {
        let width = max(120, totalWidth)
        let safeDuration = max(0.1, duration)
        let startX = max(0, min(width - 24, CGFloat(trimStart / safeDuration) * width))
        let endX = max(startX + 24, min(width, CGFloat(trimEnd / safeDuration) * width))
        let playheadX = max(0, min(width, CGFloat(playhead / safeDuration) * width))

        return VStack(spacing: OTSpace.xs) {
            HStack {
                HStack(spacing: 4) {
                    Text("START")
                        .font(.system(size: 10, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(OT.labelTertiary)
                    Text(timeLabel(trimStart))
                        .font(.otFootnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.caption2)
                        .foregroundStyle(OT.accent)
                    Text(timeLabel(max(0, trimEnd - trimStart)))
                        .font(.otFootnote.monospacedDigit().weight(.bold))
                        .foregroundStyle(OT.accent)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("END")
                        .font(.system(size: 10, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(OT.labelTertiary)
                    Text(timeLabel(trimEnd))
                        .font(.otFootnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                }
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                    .fill(OT.fillField)
                    .frame(height: 52) // ot-lint:allow
                    .overlay(
                        HStack(spacing: 8) { // ot-lint:allow
                            ForEach(0..<16, id: \.self) { _ in
                                Rectangle()
                                    .fill(OT.labelTertiary.opacity(0.15))
                                    .frame(width: 1, height: 24) // ot-lint:allow
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 8) // ot-lint:allow
                    )

                if startX > 0 {
                    RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                        .fill(Color.black.opacity(0.6)) // ot-lint:allow
                        .frame(width: startX, height: 52) // ot-lint:allow
                }

                if endX < width {
                    RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                        .fill(Color.black.opacity(0.6)) // ot-lint:allow
                        .frame(width: width - endX, height: 52) // ot-lint:allow
                        .offset(x: endX)
                }

                RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                    .stroke(OT.accent, lineWidth: 3) // ot-lint:allow
                    .background(OT.accentSoft.opacity(0.35))
                    .frame(width: max(24, endX - startX), height: 52) // ot-lint:allow
                    .offset(x: startX)

                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous) // ot-lint:allow
                        .fill(OT.accent)
                        .frame(width: 18, height: 52) // ot-lint:allow
                    Image(systemName: "chevron.compact.left")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.black) // ot-lint:allow
                }
                .offset(x: startX)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let rawX = startX + value.translation.width
                            let newSec = Double(max(0, min(endX - 24, rawX)) / width) * duration
                            trimStart = max(0, min(trimEnd - 0.5, newSec))
                            playhead = trimStart
                            seek(to: trimStart)
                        }
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous) // ot-lint:allow
                        .fill(OT.accent)
                        .frame(width: 18, height: 52) // ot-lint:allow
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.black) // ot-lint:allow
                }
                .offset(x: max(0, endX - 18))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let rawX = endX + value.translation.width
                            let newSec = Double(max(startX + 24, min(width, rawX)) / width) * duration
                            trimEnd = min(duration, max(trimStart + 0.5, newSec))
                            playhead = trimEnd
                            seek(to: trimEnd)
                        }
                )

                Rectangle()
                    .fill(Color.white) // ot-lint:allow
                    .frame(width: 2, height: 56) // ot-lint:allow
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: playheadX - 1)
            }
            .frame(height: 56) // ot-lint:allow
            .contentShape(Rectangle())
            .onTapGesture { location in
                let tappedSec = Double(max(0, min(width, location.x)) / width) * duration
                playhead = min(duration, max(0, tappedSec))
                seek(to: playhead)
            }
        }
        .padding(OTSpace.m)
        .otCard(.grouped)
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
