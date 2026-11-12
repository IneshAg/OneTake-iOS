import SwiftUI
import OneTakeUI

// MARK: - Hands-Free Audio Walk — loops the whole scene's audio, no screen interaction

struct AudioWalkView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var walker = AudioWalkPlayer()
    @State private var playing = false

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let scene = a.scenes[sceneIndex]
            let _ = store.readerTrackVersion
            let unowned = scene.lines.filter { !$0.isMine }
            let readerName = unowned.first?.character.capitalized ?? "Reader"
            let specificReaderLines = unowned.filter { $0.character.caseInsensitiveCompare(readerName) == .orderedSame }
            let readerLines = specificReaderLines.count
            let recorded = (0..<readerLines).filter {
                ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: $0)
            }.count

            OTScreen(
                title: "Audio Walk",
                backLabel: "Back",
                onBack: {
                    walker.stop()
                    store.pop()
                },
                scrolls: false
            ) {
                VStack(spacing: OTSpace.l) {
                    Spacer()
                    Image(systemName: "headphones")
                        .font(.otIcon(.xxl))
                        .foregroundStyle(OT.accent)
                    Text(playing ? "Looping \(scene.title)…" : "Ready to loop \(scene.title)")
                        .font(.otTitle)
                    Text("Your recorded reader lines, with a pause the length of each of yours, on repeat. Say your lines into the gaps.")
                        .font(.otCallout)
                        .foregroundStyle(OT.labelSecondary)
                        .multilineTextAlignment(.center)

                    if recorded < readerLines {
                        Text("\(recorded) of \(readerLines) reader lines recorded. Record the rest before starting the Audio Walk.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.warning)
                        Button {
                            store.push(.recordReader(auditionID, sceneIndex: sceneIndex))
                        } label: {
                            Label("Record the reader", systemImage: "mic")
                        }
                        .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                    }
                    if readerLines == 0 {
                        Text("This scene has no reader lines to play.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    Text("The screen stays on while it loops, so it keeps going in your pocket.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .otBottomBar {
                VStack(spacing: OTSpace.s) {
                    Button(playing ? "Stop" : "Start looping") {
                        playing.toggle()
                        if playing {
                            walker.loop(scene: scene, auditionID: auditionID, sceneIndex: sceneIndex)
                        } else {
                            walker.stop()
                        }
                    }
                    .buttonStyle(.ot(.primary))
                    .disabled(readerLines == 0 || recorded < readerLines)

                    Button("Done") {
                        walker.stop()
                        dismiss()
                    }
                    .buttonStyle(.ot(.secondary))
                }
            }
            .keepScreenAwake()
            .onDisappear { walker.stop() }
        }
    }
}

/// Loops a scene's reader tracks and your own line timings continuously, hands-free.
/// Reuses the same on-device reader recordings as Run Lines — no synthetic voice.
@MainActor
@Observable
final class AudioWalkPlayer {
    private var task: Task<Void, Never>?
    private let reader = ReaderTrackPlayer()

    func loop(scene: ScriptScene, auditionID: Audition.ID, sceneIndex: Int) {
        stop()
        let readerLines = scene.lines.filter { !$0.isMine }.count
        guard readerLines > 0,
              (0..<readerLines).allSatisfy({ index in
                  FileManager.default.fileExists(atPath: ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: index).path)
              }) else { return }
        task = Task {
            while !Task.isCancelled {
                var readerIndex = 0
                for line in scene.lines {
                    if Task.isCancelled { return }
                    if line.isMine {
                        try? await Task.sleep(for: .seconds(Double(line.text.count) * 0.06 + 0.6))
                    } else {
                        reader.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: readerIndex)
                        readerIndex += 1
                        try? await Task.sleep(for: .seconds(Double(line.text.count) * 0.06 + 0.8))
                    }
                }
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        reader.stop()
    }
}
