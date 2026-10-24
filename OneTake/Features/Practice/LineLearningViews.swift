import SwiftUI

// MARK: - Quick Drills — Practice tab's 2×2 grid

/// Four separate, deliberately-launched exercises — distinct from Prepare's own lightweight
/// Full lines / First letters / Hide mine toggle, which is a passive display filter for reading
/// straight through a scene. These are active, structured drills with their own mechanics:
/// First-Letter Prompts and Mask & Reveal reuse the same line-display transform Prepare uses
/// (`otLineDisplay`), Audio Gap Rehearsal reuses Run Lines exactly as-is, and Hands-Free Audio Walk
/// is the only one with a dedicated screen.
struct QuickDrillsGrid: View {
    var onSelect: (LineLearningMode) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Quick Drills")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(LineLearningMode.allCases) { mode in
                    DrillTile(mode: mode) { onSelect(mode) }
                }
            }
        }
    }
}

struct DrillTile: View {
    let mode: LineLearningMode
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(OT.accentSoft)
                    Image(systemName: mode.symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(OT.accent)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(shortTitle).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                    Text(shortSubtitle).font(.otCaption).foregroundStyle(OT.labelTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(height: 68)
            .otCard(radius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title). \(mode.subtitle)")
    }

    private var shortTitle: String {
        switch mode {
        case .firstLetter:   "First-Letter"
        case .maskAndReveal: "Cold Read"
        case .audioGap:      "Partner"
        case .handsFreeWalk: "Audio Walk"
        }
    }
    private var shortSubtitle: String {
        switch mode {
        case .firstLetter:   "Mnemonic"
        case .maskAndReveal: "Vanishing lines"
        case .audioGap:      "On-cue voice"
        case .handsFreeWalk: "Loop run"
        }
    }
}

// MARK: - First-Letter Prompts / Mask & Reveal — same mechanic as Prepare's toggle, run as a drill

struct LineDrillView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    let mode: LineLearningMode
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var peeked: ScriptLine.ID?

    private var displayMode: LineDisplayMode { mode == .firstLetter ? .firstLetters : .hide }

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let scene = a.scenes[sceneIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(mode.title).font(.otLargeTitle)
                    Text(mode.subtitle).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    ForEach(scene.lines) { line in lineView(line) }
                }
                .padding(.horizontal, OT.gutter)
                .padding(.bottom, 100)
            }
            .otCanvas()
            .navigationTitle("Scene \(scene.number) of \(a.scenes.count)")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Done") { dismiss() }.buttonStyle(.otPrimary).padding(OT.gutter)
            }
        }
    }

    @ViewBuilder private func lineView(_ line: ScriptLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.isMine ? "\(line.character) · YOU" : line.character)
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(line.isMine ? OT.accent : OT.reader)
            HStack(alignment: .top, spacing: 10) {
                if line.isMine { Capsule().fill(OT.accent).frame(width: 3) }
                Text(otLineDisplay(line, mode: displayMode, peeked: peeked == line.id))
                    .font(line.isMine ? .system(size: 19, weight: .semibold) : .otBody)
                    .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { if line.isMine { peeked = peeked == line.id ? nil : line.id; Haptics.tick() } }
            }
        }
        .padding(.vertical, 4)
    }
}

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
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "headphones").font(.system(size: 56)).foregroundStyle(OT.accent)
                Text(playing ? "Looping \(scene.title)…" : "Ready to loop \(scene.title)").font(.otTitle)
                Text("Both voices, on repeat. Put your phone away and just listen.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary).multilineTextAlignment(.center)
                Spacer()
                Button(playing ? "Stop" : "Start looping") {
                    playing.toggle()
                    if playing { walker.loop(scene: scene, auditionID: auditionID, sceneIndex: sceneIndex) } else { walker.stop() }
                }
                .buttonStyle(.otPrimary)
                Button("Done") { dismiss() }.buttonStyle(.otSecondary)
            }
            .padding(.horizontal, OT.gutter).padding(.bottom, OT.gutter)
            .otCanvas()
            .navigationTitle("Audio Walk").navigationBarTitleDisplayMode(.inline)
            .onDisappear { walker.stop() }
        }
    }
}

/// Loops a scene's reader tracks and your own line timings continuously, hands-free.
/// Reuses the same on-device reader recordings as Run Lines — no synthetic voice.
@Observable
final class AudioWalkPlayer {
    private var task: Task<Void, Never>?
    private let reader = ReaderTrackPlayer()

    func loop(scene: ScriptScene, auditionID: Audition.ID, sceneIndex: Int) {
        stop()
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
