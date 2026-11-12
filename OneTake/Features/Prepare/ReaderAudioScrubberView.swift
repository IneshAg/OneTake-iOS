import SwiftUI
import OneTakeUI

// MARK: - 14 Reader Audio Scrubber

/// Interactive audio scrubbing and playback component.
/// Allows actors to scrub to any timestamp (0.0s to duration), tap to seek, jump -5s/+5s, and play/pause/resume.
struct ReaderAudioScrubberView: View {
    @Bindable var player: ReaderTrackPlayer
    let auditionID: Audition.ID
    let sceneIndex: Int
    let lineIndex: Int
    var compact: Bool = false
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var isDragging: Bool = false
    @State private var dragPosition: Double = 0

    private var isThisLineActive: Bool {
        player.currentAuditionID == auditionID &&
        player.currentSceneIndex == sceneIndex &&
        player.currentLineIndex == lineIndex
    }

    private var isPlaying: Bool {
        isThisLineActive && player.isPlaying
    }

    private var duration: TimeInterval {
        if isThisLineActive && player.duration > 0 {
            return player.duration
        }
        return ReaderTrackPlayer.duration(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
    }

    private var currentTime: TimeInterval {
        if isDragging {
            return dragPosition
        }
        if isThisLineActive {
            return player.currentTime
        }
        return 0
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            expandedBody
        }
    }

    private var compactBody: some View {
        VStack(spacing: OTSpace.xs) {
            HStack(spacing: OTSpace.s) {
                // Play / Pause
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(OT.labelPrimary)
                        .frame(width: 28, height: 28) // ot-lint:allow
                        .background(OT.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)

                // Scrubber Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(OT.fillField)
                            .frame(height: 6) // ot-lint:allow

                        Capsule()
                            .fill(OT.reader)
                            .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 6) // ot-lint:allow

                        Circle()
                            .fill(Color.white) // ot-lint:allow
                            .frame(width: 14, height: 14) // ot-lint:allow
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .offset(x: max(0, min(geo.size.width * CGFloat(progress) - 7, geo.size.width - 14))) // ot-lint:allow
                    }
                    .frame(height: 14) // ot-lint:allow
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                                dragPosition = Double(fraction) * duration
                            }
                            .onEnded { value in
                                let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                                let targetTime = Double(fraction) * duration
                                isDragging = false
                                seek(to: targetTime)
                            }
                    )
                }
                .frame(height: 14) // ot-lint:allow

                // Time label
                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit()) // ot-lint:allow
                    .foregroundStyle(OT.labelTertiary)
            }
        }
    }

    private var expandedBody: some View {
        VStack(spacing: OTSpace.m) {
            // Interactive Scrubber Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(OT.fillField)
                        .frame(height: 8) // ot-lint:allow

                    // Progress track
                    Capsule()
                        .fill(LinearGradient(colors: [OT.reader, OT.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * CGFloat(progress)), height: 8) // ot-lint:allow

                    // Scrubber thumb
                    Circle()
                        .fill(Color.white) // ot-lint:allow
                        .frame(width: 20, height: 20) // ot-lint:allow
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .offset(x: max(0, min(geo.size.width * CGFloat(progress) - 10, geo.size.width - 20))) // ot-lint:allow
                }
                .frame(height: 20) // ot-lint:allow
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                            dragPosition = Double(fraction) * duration
                        }
                        .onEnded { value in
                            let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                            let targetTime = Double(fraction) * duration
                            isDragging = false
                            seek(to: targetTime)
                        }
                )
            }
            .frame(height: 20) // ot-lint:allow

            // Timestamps: Current time & remaining duration
            HStack {
                Text(formatDetailedTime(currentTime))
                    .font(.otCaption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OT.labelPrimary)

                Spacer()

                Text("-\(formatDetailedTime(max(0, duration - currentTime)))")
                    .font(.otCaption.weight(.medium).monospacedDigit())
                    .foregroundStyle(OT.labelTertiary)
            }

            // Scrub Controls Row: -5s, Play/Pause, +5s, Replay
            HStack(spacing: OTSpace.xl) {
                // Rewind 5s
                Button {
                    seekRelative(-5)
                } label: {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 16, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(OT.labelSecondary)
                        .frame(width: 44, height: 44) // ot-lint:allow
                        .background(OT.fillField, in: Circle()) // ot-lint:allow
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rewind 5 seconds")

                // Main Play / Pause Button
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(Color.white) // ot-lint:allow
                        .frame(width: 52, height: 52) // ot-lint:allow
                        .background(OT.accent, in: Circle())
                        .shadow(color: OT.accent.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                // Skip +5s
                Button {
                    seekRelative(5)
                } label: {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 16, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(OT.labelSecondary)
                        .frame(width: 44, height: 44) // ot-lint:allow
                        .background(OT.fillField, in: Circle()) // ot-lint:allow
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip forward 5 seconds")

                // Replay from start
                Button {
                    seek(to: 0)
                    if !isPlaying {
                        player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: 0)
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(OT.labelSecondary)
                        .frame(width: 44, height: 44) // ot-lint:allow
                        .background(OT.fillField, in: Circle()) // ot-lint:allow
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay from beginning")
            }
        }
        .padding(OTSpace.cardInset)
        .otCard(.grouped)
    }

    private func togglePlay() {
        if isPlaying {
            player.pause()
        } else if isThisLineActive && player.currentTime > 0 && player.currentTime < duration {
            player.resume()
        } else {
            player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: isThisLineActive ? player.currentTime : 0)
        }
        Haptics.tick()
    }

    private func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        if isThisLineActive {
            player.seek(to: clamped)
        } else {
            player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: clamped)
        }
        onSeek?(clamped)
        Haptics.tick()
    }

    private func seekRelative(_ delta: TimeInterval) {
        if isThisLineActive {
            player.seekRelative(delta)
        } else {
            let target = max(0, min(delta, duration))
            player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, from: target)
        }
        Haptics.tick()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatDetailedTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        let tenths = Int((clamped.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, tenths)
    }
}
