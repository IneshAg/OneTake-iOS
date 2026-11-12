import SwiftUI
import AVFoundation

struct ReaderAudioTrimmer: View {
    let url: URL
    var onFinish: (URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var duration: Double = 0
    @State private var playhead: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var showExportError = false

    var body: some View {
        VStack(spacing: 0) {
            OTNavHeader(title: "Trim reader audio", backLabel: "Cancel", onBack: cancel)
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.m)

            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.l) {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .semibold)) // ot-lint:allow
                            .foregroundStyle(OT.reader)
                            .frame(width: 54, height: 54) // ot-lint:allow
                            .background(OT.reader.opacity(0.12), in: RoundedRectangle(cornerRadius: OTRadius.l))
                        VStack(alignment: .leading, spacing: 3) { // ot-lint:allow
                            Text("Keep the part you want")
                                .font(.otHeadline)
                            Text("The original recording stays available to restore.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                    }

                    VStack(spacing: OTSpace.m) {
                        Button(action: togglePlayback) {
                            Label(isPlaying ? "Pause preview" : "Play preview", systemImage: isPlaying ? "pause.fill" : "play.fill")
                                .font(.otSubhead.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48) // ot-lint:allow
                        }
                        .buttonStyle(.otSecondary)

                        Slider(value: $playhead, in: 0...max(duration, 0.01)) { editing in
                            if !editing { seek(to: playhead) }
                        }
                        .tint(OT.reader)

                        HStack {
                            Text(timeLabel(playhead))
                            Spacer()
                            Text("\(timeLabel(trimEnd - trimStart)) kept")
                            Spacer()
                            Text(timeLabel(duration))
                        }
                        .font(.otCaption.monospacedDigit())
                        .foregroundStyle(OT.labelSecondary)

                        VStack(spacing: 10) { // ot-lint:allow
                            HStack {
                                Text("Start")
                                Spacer()
                                Text(timeLabel(trimStart)).monospacedDigit()
                            }
                            Slider(value: $trimStart, in: 0...max(0, trimEnd - 0.5))
                            HStack {
                                Text("End")
                                Spacer()
                                Text(timeLabel(trimEnd)).monospacedDigit()
                            }
                            Slider(value: $trimEnd, in: min(duration, trimStart + 0.5)...max(min(duration, trimStart + 0.5), duration))
                        }
                        .font(.otFootnote.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                        .tint(OT.accent)
                        .padding(OTSpace.m)
                        .otCard(.grouped)
                    }

                    Label("Trimming cuts off unwanted audio at the start or end. It doesn’t remove background noise between words.", systemImage: "info.circle")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(OTSpace.gutter)
            }
        }
        .background(OT.bgCanvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: exportTrim) {
                HStack(spacing: OTSpace.xs) {
                    if isExporting { ProgressView().tint(.white) }
                    Text(isExporting ? "Saving trimmed audio…" : "Save trimmed audio")
                }
            }
            .buttonStyle(.otPrimary)
            .disabled(duration <= 0.5 || trimEnd - trimStart < 0.5 || isExporting)
            .padding(.horizontal, OTSpace.gutter)
            .padding(.vertical, 10) // ot-lint:allow
            .background(.ultraThinMaterial)
        }
        .alert("Couldn’t save the trim", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your reader recording is unchanged. Try saving again.")
        }
        .task(id: url) { await loadAudio() }
        .onDisappear { stopPreview() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func loadAudio() async {
        do {
            let asset = AVURLAsset(url: url)
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
            duration = seconds
            trimEnd = seconds
            let preview = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = preview
            timeObserver = preview.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { time in
                let current = time.seconds
                guard current.isFinite else { return }
                playhead = current
                if isPlaying && current >= trimEnd {
                    preview.pause()
                    preview.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
                    isPlaying = false
                }
            }
        } catch {
            showExportError = true
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead < trimStart || playhead >= trimEnd {
                playhead = trimStart
                seek(to: trimStart)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func stopPreview() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        isPlaying = false
    }

    private func cancel() {
        stopPreview()
        onFinish(nil)
        dismiss()
    }

    private func exportTrim() {
        guard trimEnd - trimStart >= 0.5,
              let exporter = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetAppleM4A),
              exporter.supportedFileTypes.contains(.m4a) else {
            showExportError = true
            return
        }
        stopPreview()
        isExporting = true
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("reader-trim-\(UUID().uuidString).m4a")
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 44100),
            duration: CMTime(seconds: trimEnd - trimStart, preferredTimescale: 44100)
        )
        Task {
            do {
                try await exporter.export(to: output, as: .m4a)
                isExporting = false
                onFinish(output)
                dismiss()
            } catch {
                try? FileManager.default.removeItem(at: output)
                isExporting = false
                showExportError = true
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
