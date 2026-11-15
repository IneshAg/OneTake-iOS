import AVFoundation
import SwiftUI
import OneTakeUI

/// Dedicated interactive voice player for recorded voice rehearsal takes and Voice Checker playback.
/// Replaces squished `VideoPlayer` instances with full Play/Pause, Stop, Scrub, and duration controls.
struct OTVoicePlayerView: View {
    let url: URL
    var autoPlay: Bool = false
    @Binding var seekRequest: TimeInterval?

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0

    init(
        url: URL,
        autoPlay: Bool = false,
        seekRequest: Binding<TimeInterval?> = .constant(nil)
    ) {
        self.url = url
        self.autoPlay = autoPlay
        _seekRequest = seekRequest
    }

    private var displayedTime: TimeInterval {
        isScrubbing ? scrubPosition : currentTime
    }

    var body: some View {
        VStack(spacing: OTSpace.m) {
            HStack(spacing: OTSpace.m) {
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.otIcon(.m, weight: .bold))
                        .foregroundStyle(OT.labelOnAccent)
                        .frame(width: OT.minTap, height: OT.minTap) // ot-lint:allow
                        .background(OT.accent, in: Circle())
                }
                .buttonStyle(OTPressStyle(.icon))
                .accessibilityLabel(isPlaying ? "Pause voice recording" : "Play voice recording")

                Button {
                    stopPlayback()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.otIcon(.s, weight: .semibold))
                        .foregroundStyle(OT.labelPrimary)
                        .frame(width: OT.minTap, height: OT.minTap) // ot-lint:allow
                        .background(OT.fillField, in: Circle()) // ot-lint:allow
                }
                .buttonStyle(OTPressStyle(.icon))
                .accessibilityLabel("Stop playback")

                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Slider(
                        value: Binding(
                            get: { displayedTime },
                            set: { newValue in
                                scrubPosition = newValue
                                currentTime = newValue
                            }
                        ),
                        in: 0...max(duration, 0.1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                seek(to: scrubPosition)
                            }
                        }
                    )
                    .tint(OT.accent)
                    .animation(OTMotion.interactive, value: displayedTime)

                    HStack {
                        Text(formatTime(displayedTime))
                        Spacer()
                        Text(formatTime(duration))
                    }
                    .font(.otCaption.monospacedDigit())
                    .foregroundStyle(OT.labelSecondary)
                }
            }

            VoiceWaveformBars(
                isRecording: isPlaying,
                level: isPlaying ? Float(0.35 + abs(sin(currentTime * 5.0)) * 0.5) : 0.08
            )
            .frame(maxWidth: .infinity)
        }
        .otCard(.grouped)
        .onAppear { setupPlayer() }
        .onChange(of: url) { _, _ in
            teardownPlayer()
            setupPlayer()
        }
        .onChange(of: seekRequest) { _, requested in
            guard let requested else { return }
            seek(to: requested)
            if !isPlaying {
                play()
            }
            seekRequest = nil
        }
        .onDisappear { teardownPlayer() }
    }

    private func setupPlayer() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer

        Task {
            if let assetDuration = try? await item.asset.load(.duration) {
                let secs = CMTimeGetSeconds(assetDuration)
                if secs.isFinite && secs > 0 {
                    await MainActor.run { duration = secs }
                }
            }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }
            let secs = CMTimeGetSeconds(time)
            if secs.isFinite {
                currentTime = secs
            }
            if duration <= 0, let itemDuration = avPlayer.currentItem?.duration {
                let d = CMTimeGetSeconds(itemDuration)
                if d.isFinite && d > 0 { duration = d }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isPlaying = false
            currentTime = 0
            avPlayer.seek(to: .zero)
        }

        if autoPlay {
            play()
        }
    }

    private func togglePlayPause() {
        Haptics.tick()
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            play()
        }
    }

    private func play() {
        guard let player else { return }
        if duration > 0 && currentTime >= duration - 0.05 {
            currentTime = 0
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
    }

    private func stopPlayback() {
        Haptics.tick()
        player?.pause()
        player?.seek(to: .zero)
        currentTime = 0
        scrubPosition = 0
        isPlaying = false
    }

    private func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        currentTime = clamped
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    private func teardownPlayer() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player = nil
        isPlaying = false
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
