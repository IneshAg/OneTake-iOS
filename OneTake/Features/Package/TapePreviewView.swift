import AVKit
import SwiftUI

// MARK: - 20.0 Preview the tape
//
// The whole tape exactly as casting gets it — headshots, slate, full length, circled takes — played
// instantly from the clips on this iPhone (no export needed), with chapters to jump between. Comes
// after Tape Check and before Package: the last look before sending.

struct TapePreviewView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @AppStorage("tape.headshotCard") private var opensWithHeadshot = true
    @State private var tape: MediaExporter.Tape?
    @State private var player: AVPlayer?
    @State private var now = 0.0
    @State private var timeObserver: Any?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tape, let player {
                VideoPlayer(player: player)
                    .frame(height: 204)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                chapterBar(tape).padding(.horizontal, 20)
                chapterList(tape).padding(.horizontal, 20).padding(.top, 16)
                if HeadshotStore.exists(key: "front") {
                    Toggle(isOn: $opensWithHeadshot) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open with your headshots").font(.otBody).foregroundStyle(OT.cameraLabel)
                            Text("Front, then profiles · off if the notice says no cards").font(.otCaption).foregroundStyle(OT.cameraLabel2)
                        }
                    }
                    .tint(OT.accent)
                    .padding(.horizontal, 20).padding(.top, 16)
                }
            } else if failed {
                Text("Nothing on the tape yet").font(.otTitle).foregroundStyle(OT.cameraLabel).padding(20)
                Text("Record your slate and a take first.").font(.otCallout).foregroundStyle(OT.cameraLabel2).padding(.horizontal, 20)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 80)
            }
            Spacer(minLength: 0)
        }
        .background(OT.cameraBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Preview").font(.otHeadline).foregroundStyle(OT.cameraLabel)
                    Text("Exactly what casting gets" + (tape.map { " · \(clock($0.duration))" } ?? ""))
                        .font(.otCaption).foregroundStyle(OT.cameraLabel2)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Looks right — package it") { player?.pause(); store.push(.package(auditionID)) }
                    .buttonStyle(.otPrimary)
                    .disabled(tape == nil)
                Button("Change a take") { player?.pause(); store.popTo(.takes(auditionID)) }
                    .buttonStyle(.otSecondaryDark)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        }
        // Rebuilt whenever what's on the tape changes, or the headshot card is switched on/off.
        .task(id: TapeKey(urls: currentClipURLs, headshot: opensWithHeadshot)) { await load() }
        .onDisappear { stop() }
    }

    private struct TapeKey: Hashable { let urls: [URL]; let headshot: Bool }

    private var currentClipURLs: [URL] {
        guard let a = store.audition(auditionID) else { return [] }
        return MediaExporter.clips(for: a, takes: store.takes).map(\.url)
    }

    // MARK: Chapters

    private func chapterBar(_ tape: MediaExporter.Tape) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let total = max(tape.duration, 0.1)
                let spacing = 3.0 * Double(max(tape.chapters.count - 1, 0))
                HStack(spacing: 3) {
                    ForEach(tape.chapters) { chapter in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color(for: chapter, in: tape))
                            .opacity(isCurrent(chapter) || now == 0 ? 1 : 0.55)
                            .frame(width: max(12, (geo.size.width - spacing) * chapter.duration / total))
                            .onTapGesture { seek(to: chapter.start) }
                    }
                }
            }
            .frame(height: 8)
            HStack {
                Text(clock(now)).foregroundStyle(OT.cameraLabel)
                Spacer()
                Text(clock(tape.duration)).foregroundStyle(OT.cameraLabel2)
            }
            .font(.otCaption).monospacedDigit()
        }
    }

    private func chapterList(_ tape: MediaExporter.Tape) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHAPTERS").font(.otCaption.weight(.semibold)).tracking(0.6).foregroundStyle(OT.cameraLabel2)
            ForEach(Array(tape.chapters.enumerated()), id: \.element.id) { index, chapter in
                Button { seek(to: chapter.start) } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.cameraLabel2)
                        Text(chapter.label)
                            .font(isCurrent(chapter) ? .otHeadline : .otBody)
                            .foregroundStyle(OT.cameraLabel)
                        Spacer()
                        Text(clock(chapter.start)).font(.otFootnote).foregroundStyle(OT.cameraLabel2).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Your own pieces in the accent; scenes alternate with the reader colour so neighbours read apart.
    private func color(for chapter: MediaExporter.Chapter, in tape: MediaExporter.Tape) -> Color {
        guard case .scene(let index) = chapter.kind else { return OT.accent }
        return index.isMultiple(of: 2) ? OT.accent : OT.reader
    }

    private func isCurrent(_ chapter: MediaExporter.Chapter) -> Bool {
        now >= chapter.start && now < chapter.start + chapter.duration
    }

    // MARK: Playback

    private func load() async {
        stop()
        tape = nil
        failed = false
        guard let a = store.audition(auditionID) else { return }
        let takes = store.takes
        guard let built = try? await MediaExporter.build(await MediaExporter.tapeClips(for: a, takes: takes)),
              !Task.isCancelled else {
            failed = !Task.isCancelled
            return
        }
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = built.videoComposition
        let player = AVPlayer(playerItem: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { time in
            now = time.seconds
        }
        self.player = player
        tape = built
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
        now = seconds
        Haptics.tick()
    }

    private func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        now = 0
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
