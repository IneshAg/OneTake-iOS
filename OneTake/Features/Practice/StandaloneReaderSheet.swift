import SwiftUI
import AVFoundation
import OneTakeUI

/// Records partner ("reader") voice lines for a standalone Practice scene so actors can rehearse
/// against another person's cues without creating an audition first.
struct StandaloneReaderSheet: View {
    let pieceID: PracticePiece.ID
    let scene: ScriptScene

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lineIndex = 0
    @State private var recording = false
    @State private var isProcessing = false
    @State private var microphoneAllowed = false
    @State private var recordingError: String?
    @State private var milestone: OTMilestoneBannerItem?
    @State private var recorder = ReaderLineRecorder()
    @State private var player = ReaderTrackPlayer()

    private var scope: ReaderTrackScope { .practice(pieceID) }
    private var readerLines: [ScriptLine] { scene.lines.filter { !$0.isMine } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.l) {
                    if readerLines.isEmpty {
                        OTCallout(
                            systemImage: "person.2.slash",
                            title: "No other character lines",
                            message: "Edit the script to add another speaker (e.g. READER:) if you want to record partner cues."
                        )
                    } else {
                        let safeIndex = min(max(lineIndex, 0), readerLines.count - 1)
                        let currentLine = readerLines[safeIndex]
                        let recordedCount = readerLines.indices.filter {
                            store.readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(scope: scope, line: $0)
                        }.count

                        HStack {
                            Text("\(recordedCount) of \(readerLines.count) cues recorded")
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(recordedCount == readerLines.count ? OT.success : OT.labelSecondary)
                            Spacer()
                            OTProgressRing(
                                progress: Double(recordedCount) / Double(max(1, readerLines.count))
                            )
                            .frame(width: 24, height: 24) // ot-lint:allow
                        }

                        // Cue selector strip
                        HStack(spacing: OTSpace.xxs) {
                            ForEach(readerLines.indices, id: \.self) { i in
                                let hasRec = store.readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(scope: scope, line: i)
                                Button {
                                    guard !recording && !isProcessing else { return }
                                    player.stop()
                                    lineIndex = i
                                    recordingError = nil
                                    Haptics.tick()
                                } label: {
                                    Capsule()
                                        .fill(i == safeIndex ? OT.accent : (hasRec ? OT.reader : OT.fillQuiet))
                                        .frame(height: i == safeIndex ? 6 : 4) // ot-lint:allow
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Partner cue \(i + 1)")
                            }
                        }

                        // Current cue card
                        VStack(alignment: .leading, spacing: OTSpace.m) {
                            HStack {
                                OTChip(currentLine.character, tint: OT.reader)
                                Spacer()
                                Text("Cue \(safeIndex + 1) of \(readerLines.count)")
                                    .font(.otCaption.monospacedDigit())
                                    .foregroundStyle(OT.labelTertiary)
                            }
                            Text(currentLine.text)
                                .font(.otTitle)
                                .foregroundStyle(OT.labelPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .otCard(.grouped)

                        if let recordingError {
                            OTCallout(
                                systemImage: "exclamationmark.triangle.fill",
                                title: "Couldn't save cue",
                                message: recordingError,
                                tint: OT.warning
                            )
                        }

                        // Recorder controls
                        let hasCurrentRecording = store.readerTrackVersion >= 0
                            && ReaderTrackPlayer.hasRecording(scope: scope, line: safeIndex)

                        HStack(spacing: OTSpace.m) {
                            Button {
                                toggleRecord(index: safeIndex, expectedText: currentLine.text)
                            } label: {
                                Label(
                                    isProcessing ? "Saving…" : (recording ? "Stop & save" : (hasCurrentRecording ? "Re-record cue" : "Record cue")),
                                    systemImage: recording ? "stop.fill" : "mic.fill"
                                )
                            }
                            .buttonStyle(.otPrimary)
                            .disabled(isProcessing)

                            if hasCurrentRecording && !recording {
                                Button {
                                    if player.isPlaying {
                                        player.stop()
                                    } else {
                                        _ = player.play(scope: scope, lineIndex: safeIndex)
                                    }
                                    Haptics.tick()
                                } label: {
                                    Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                                }
                                .buttonStyle(.ot(.secondary, size: .large, fullWidth: false))
                                .accessibilityLabel(player.isPlaying ? "Stop cue playback" : "Play recorded cue")
                            }
                        }

                        if recording {
                            VoiceWaveformBars(isRecording: true, level: recorder.liveAudioLevel)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, OTSpace.s)
                        }

                        // Stepper
                        HStack {
                            Button {
                                guard safeIndex > 0, !recording else { return }
                                player.stop()
                                lineIndex = safeIndex - 1
                                recordingError = nil
                                Haptics.tick()
                            } label: {
                                Label("Previous", systemImage: "chevron.left")
                            }
                            .buttonStyle(.otCompact)
                            .disabled(safeIndex == 0 || recording)

                            Spacer()

                            Button {
                                guard safeIndex + 1 < readerLines.count, !recording else { return }
                                player.stop()
                                lineIndex = safeIndex + 1
                                recordingError = nil
                                Haptics.tick()
                            } label: {
                                Label("Next", systemImage: "chevron.right")
                                    .labelStyle(TrailingIconLabelStyle())
                            }
                            .buttonStyle(.otCompact)
                            .disabled(safeIndex + 1 >= readerLines.count || recording)
                        }
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .padding(.bottom, OTSpace.xl)
            }
            .otCanvas()
            .otMilestoneBanner($milestone)
            .navigationTitle("Partner voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                microphoneAllowed = await AVAudioApplication.requestRecordPermission()
            }
            .onDisappear {
                player.stop()
            }
        }
    }

    private func toggleRecord(index: Int, expectedText: String) {
        if recording {
            recording = false
            isProcessing = true
            Task { @MainActor in
                let result = await recorder.stop(expectedText: expectedText)
                isProcessing = false
                switch result {
                case .success:
                    recordingError = nil
                    store.readerTracksDidChange()
                    Haptics.stepDone()
                    let allDone = readerLines.indices.allSatisfy { ReaderTrackPlayer.hasRecording(scope: scope, line: $0) }
                    if allDone {
                        Haptics.celebrate()
                        milestone = OTMilestoneBannerItem(
                            title: "All partner cues recorded!",
                            subtitle: "Ready for voice & camera practice"
                        )
                    } else if index + 1 < readerLines.count {
                        withAnimation(OTMotion.smooth) { lineIndex = index + 1 }
                    }
                case .tooShort:
                    recordingError = "That cue sounded too short. Speak clearly then tap Stop."
                    Haptics.warning()
                case .noSpeechDetected:
                    recordingError = "No voice detected. Move closer to the mic and try again."
                    Haptics.warning()
                case .recordingFailed(let msg):
                    recordingError = msg
                    Haptics.warning()
                }
            }
        } else {
            player.stop()
            recordingError = nil
            guard microphoneAllowed else {
                recordingError = "Microphone permission is needed to record partner cues."
                Haptics.warning()
                return
            }
            if recorder.start(scope: scope, lineIndex: index) {
                recording = true
                Haptics.impact(.medium)
            } else {
                recordingError = "Couldn't start microphone recorder."
                Haptics.warning()
            }
        }
    }
}
