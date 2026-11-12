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
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(OT.fillField, in: Circle())
                }
                .accessibilityLabel("Close video editor")
                Spacer()
                Text("Edit video").font(.otHeadline)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black)
                            .frame(height: 250)
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

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Trim range").font(.otHeadline)
                            VStack(spacing: 4) {
                                HStack {
                                    Text("Start").foregroundStyle(OT.labelSecondary)
                                    Spacer()
                                    Text(timeLabel(trimStart)).monospacedDigit()
                                }
                                Slider(value: $trimStart, in: 0...max(0, trimEnd - 0.5))
                                HStack {
                                    Text("End").foregroundStyle(OT.labelSecondary)
                                    Spacer()
                                    Text(timeLabel(trimEnd)).monospacedDigit()
                                }
                                Slider(value: $trimEnd, in: min(duration, trimStart + 0.5)...duration)
                            }
                            .font(.otFootnote)
                            .tint(OT.accent)
                        }
                        .padding(14)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                HStack(spacing: 8) {
                    if isExporting { ProgressView().tint(.white) }
                    Text(isExporting ? "Saving edited clip…" : "Save trimmed clip")
                }
            }
            .buttonStyle(.otPrimary)
            .disabled(duration <= 0.5 || trimEnd - trimStart < 0.5 || isExporting)
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 10)
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
