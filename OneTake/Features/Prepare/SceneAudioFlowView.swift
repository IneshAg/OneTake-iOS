import SwiftUI
import OneTakeUI

// MARK: - 15 Scene Audio Flow & Walkthrough

/// Dedicated scene audio walkthrough allowing actors to see the full scene dialogue flow,
/// tap ANY line to jump playback immediately to that point, scrub between seconds,
/// and rehearse with continuous autoplay across cues.
struct SceneAudioFlowView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var player = ReaderTrackPlayer()
    @State private var activeLineIndex: Int? = nil
    @State private var isContinuousFlow: Bool = true
    @State private var waitingForActor: Bool = false
    @State private var actorCountdown: Int = 3
    @State private var countdownTimer: Timer? = nil

    private var audition: Audition? {
        store.audition(auditionID)
    }

    private var scene: ScriptScene? {
        guard let a = audition, a.scenes.indices.contains(sceneIndex) else { return nil }
        return a.scenes[sceneIndex]
    }

    private var myRole: String {
        audition?.role ?? "You"
    }

    private var allLines: [ScriptLine] {
        scene?.lines ?? []
    }

    var body: some View {
        let readerTrackVersion = store.readerTrackVersion
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.m) {
                        // Overview Card
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            HStack {
                                Label("Scene \(scene?.number ?? 1): Full Dialogue Flow", systemImage: "waveform.badge.magnifyingglass")
                                    .font(.otSubhead.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                                Spacer()
                                Toggle(isOn: $isContinuousFlow) {
                                    Text("Continuous")
                                        .font(.otCaption.weight(.semibold))
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                .toggleStyle(.button)
                                .tint(OT.accent)
                            }

                            Text("Tap ANY line below to start playback from that exact moment. Use the scrubber to play from between seconds.")
                                .font(.otCallout)
                                .foregroundStyle(OT.labelSecondary)

                            HStack(spacing: OTSpace.m) {
                                Button {
                                    jumpToLine(0)
                                } label: {
                                    HStack(spacing: OTSpace.xs) {
                                        Image(systemName: "play.fill")
                                        Text("Play scene from start")
                                    }
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.labelOnAccent)
                                    .padding(.horizontal, OTSpace.m)
                                    .padding(.vertical, OTSpace.s)
                                    .background(OT.accent, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                if activeLineIndex != nil {
                                    Button {
                                        stopAll()
                                    } label: {
                                        HStack(spacing: OTSpace.xxs) {
                                            Image(systemName: "stop.fill")
                                            Text("Stop")
                                        }
                                    }
                                    .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                                }
                            }
                        }
                        .padding(OTSpace.cardInset)
                        .otCard(.grouped)

                        // Dialogue Lines List
                        ForEach(Array(allLines.enumerated()), id: \.offset) { index, line in
                            let isActive = activeLineIndex == index
                            let sameCharLines = allLines.filter { !$0.isMine && $0.character.caseInsensitiveCompare(line.character) == .orderedSame }
                            let cueIndex = sameCharLines.firstIndex(where: { $0.id == line.id }) ?? 0
                            let isRec = !line.isMine && readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: cueIndex)
                            let cueDuration = isRec ? ReaderTrackPlayer.duration(auditionID: auditionID, sceneIndex: sceneIndex, line: cueIndex) : 0

                            VStack(alignment: .leading, spacing: OTSpace.s) {
                                // Header row
                                HStack(spacing: OTSpace.s) {
                                    if line.isMine {
                                        Text("YOU (\(myRole.isEmpty ? "Your role" : myRole))")
                                            .font(.otCaption.weight(.bold))
                                            .foregroundStyle(OT.accent)
                                            .padding(.horizontal, OTSpace.s)
                                            .padding(.vertical, OTSpace.xxs)
                                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                                    } else {
                                        Text(line.character.uppercased())
                                            .font(.otCaption.weight(.bold))
                                            .foregroundStyle(OT.reader)
                                            .padding(.horizontal, OTSpace.s)
                                            .padding(.vertical, OTSpace.xxs)
                                            .background(OT.reader.opacity(0.14), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))

                                        if isRec {
                                            HStack(spacing: OTSpace.xxs) {
                                                Image(systemName: isActive && player.isPlaying ? "waveform" : "checkmark.circle.fill")
                                                Text(formatTime(cueDuration))
                                            }
                                            .font(.system(size: 11, weight: .semibold).monospacedDigit()) // ot-lint:allow
                                            .foregroundStyle(OT.reader)
                                        } else {
                                            HStack(spacing: OTSpace.xxs) {
                                                Image(systemName: "mic.slash")
                                                Text("Needs audio")
                                            }
                                            .font(.system(size: 11, weight: .medium)) // ot-lint:allow
                                            .foregroundStyle(OT.labelTertiary)
                                        }
                                    }

                                    Spacer()

                                    Text("Line \(index + 1)")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelTertiary)
                                }

                                // Dialogue text
                                Text(line.text)
                                    .font(line.isMine ? .otHeadline : .otBody)
                                    .foregroundStyle(OT.labelPrimary)
                                    .lineSpacing(2)

                                // Active Line controls
                                if isActive {
                                    if line.isMine {
                                        if waitingForActor {
                                            HStack(spacing: OTSpace.s) {
                                                Circle().fill(OT.accent).frame(width: 8, height: 8) // ot-lint:allow
                                                Text("Your turn! Speak your line (\(actorCountdown)s)...")
                                                    .font(.otFootnote.weight(.semibold))
                                                    .foregroundStyle(OT.accent)
                                                Spacer()
                                                Button {
                                                    advanceAfterActorLine()
                                                } label: {
                                                    HStack(spacing: OTSpace.xxs) {
                                                        Text("Continue")
                                                        Image(systemName: "chevron.right")
                                                    }
                                                    .font(.otCaption.weight(.bold))
                                                    .foregroundStyle(OT.labelOnAccent)
                                                    .padding(.horizontal, OTSpace.s)
                                                    .padding(.vertical, OTSpace.xxs)
                                                    .background(OT.accent, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(OTSpace.s)
                                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.m))
                                        }
                                    } else if isRec {
                                        // Inline scrubber for recorded reader line
                                        ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: cueIndex, compact: false)
                                            .padding(.top, OTSpace.xxs)
                                    }
                                }
                            }
                            .padding(OTSpace.cardInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .otCard(isActive ? .elevated : .grouped)
                            .overlay(
                                RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous)
                                    .stroke(isActive ? (line.isMine ? OT.accent : OT.reader) : Color.clear, lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(isActive ? 0.08 : 0.03), radius: 6, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !line.isMine && !isRec {
                                    stopAll()
                                    store.push(.recordReader(auditionID, sceneIndex: sceneIndex, initialLineIndex: cueIndex, readerCharacter: line.character))
                                } else {
                                    jumpToLine(index)
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, OTSpace.gutter)
                    .padding(.top, OTSpace.s)
                    .padding(.bottom, OTSpace.xxl)
                }
                .onChange(of: activeLineIndex) { _, newIndex in
                    if let newIndex {
                        withAnimation {
                            scrollProxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        .otCanvas()
        .navigationTitle("Scene Audio Flow")
        .navigationBarTitleDisplayMode(.inline)
        .otBottomBar {
            bottomDeck
        }
        .onAppear {
            player.onPlaybackFinished = {
                handlePlaybackFinished()
            }
        }
        .onDisappear {
            stopAll()
        }
    }

    private var bottomDeck: some View {
        HStack(spacing: OTSpace.m) {
            // Prev Line
            OTIconButton("backward.end.fill", accessibilityLabel: "Previous line") {
                stepCue(forward: false)
            }
            .disabled(allLines.isEmpty)

            // Current line info
            VStack(alignment: .leading, spacing: 2) {
                if let idx = activeLineIndex, allLines.indices.contains(idx) {
                    let l = allLines[idx]
                    Text("Line \(idx + 1) · \(l.isMine ? "YOU" : l.character.capitalized)")
                        .font(.otSubhead.weight(.bold))
                        .foregroundStyle(OT.labelPrimary)
                    Text(l.text)
                        .font(.otCaption)
                        .foregroundStyle(OT.labelSecondary)
                        .lineLimit(1)
                } else {
                    Text("Tap any line to play")
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelSecondary)
                    Text("Walkthrough all scene cues")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)
                }
            }

            Spacer()

            // Play / Pause
            Button {
                if let idx = activeLineIndex {
                    let l = allLines[idx]
                    if l.isMine {
                        advanceAfterActorLine()
                    } else {
                        if player.isPlaying {
                            player.pause()
                        } else if player.currentTime > 0 {
                            player.resume()
                        } else {
                            jumpToLine(idx)
                        }
                    }
                } else {
                    jumpToLine(0)
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold)) // ot-lint:allow
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .frame(width: 48, height: 48) // ot-lint:allow
                    .background(OT.accent, in: Circle())
            }
            .buttonStyle(.plain)

            // Next Line
            OTIconButton("forward.end.fill", accessibilityLabel: "Next line") {
                stepCue(forward: true)
            }
            .disabled(allLines.isEmpty)
        }
    }

    private func jumpToLine(_ index: Int) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        waitingForActor = false
        guard allLines.indices.contains(index) else { return }
        activeLineIndex = index
        let line = allLines[index]

        if line.isMine {
            player.stop()
            if isContinuousFlow {
                waitingForActor = true
                actorCountdown = 3
                let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                    if actorCountdown > 1 {
                        actorCountdown -= 1
                    } else {
                        t.invalidate()
                        advanceAfterActorLine()
                    }
                }
                countdownTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            let sameCharLines = allLines.filter { !$0.isMine && $0.character.caseInsensitiveCompare(line.character) == .orderedSame }
            let cueIndex = sameCharLines.firstIndex(where: { $0.id == line.id }) ?? 0
            if ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: cueIndex) {
                player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: cueIndex, from: 0)
            } else if isContinuousFlow && index + 1 < allLines.count {
                jumpToLine(index + 1)
            }
        }
        Haptics.tick()
    }

    private func advanceAfterActorLine() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        waitingForActor = false
        guard let current = activeLineIndex, current + 1 < allLines.count else {
            activeLineIndex = nil
            return
        }
        jumpToLine(current + 1)
    }

    private func handlePlaybackFinished() {
        guard isContinuousFlow, let current = activeLineIndex, current + 1 < allLines.count else {
            activeLineIndex = nil
            return
        }
        jumpToLine(current + 1)
    }

    private func stepCue(forward: Bool) {
        guard !allLines.isEmpty else { return }
        let current = activeLineIndex ?? (forward ? -1 : allLines.count)
        let next = forward ? current + 1 : current - 1
        if allLines.indices.contains(next) {
            jumpToLine(next)
        } else if forward {
            jumpToLine(0)
        } else {
            jumpToLine(allLines.count - 1)
        }
    }

    private func stopAll() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        waitingForActor = false
        player.stop()
        activeLineIndex = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        return String(format: "%d:%02d", m, s)
    }
}
