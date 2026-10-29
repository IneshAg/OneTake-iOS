import AVKit
import SwiftUI

// MARK: - 20.0 Preview the tape
//
// Exactly what casting gets, in order: the audition headshots as photos to click through, then the
// tape — slate, full length, circled takes — played instantly from the clips on this iPhone (no
// export needed), with chapters to jump between. Comes after Tape Check and before Package: the
// last look before sending.

struct TapePreviewView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var tape: MediaExporter.Tape?
    /// The audition headshots, sent as photos alongside the tape.
    @State private var photos: [(title: String, image: UIImage)] = []
    /// Showing the headshot photos (chapter 1) rather than the video.
    @State private var showingPhotos = false
    @State private var photoIndex = 0
    @State private var player: AVPlayer?
    @State private var now = 0.0
    @State private var timeObserver: Any?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tape, let player {
                Group {
                    if showingPhotos, !photos.isEmpty { photoViewer } else { VideoPlayer(player: player) }
                }
                .frame(height: 204)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                chapterBar(tape).padding(.horizontal, 20)
                chapterList(tape).padding(.horizontal, 20).padding(.top, 16)
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
        // Rebuilt whenever what's on the tape changes (a different circled take, a retake, a trim).
        .task(id: currentClipURLs) { await load() }
        .onDisappear { stop() }
    }

    private var currentClipURLs: [URL] {
        guard let a = store.audition(auditionID) else { return [] }
        return MediaExporter.clips(for: a, takes: store.takes).map(\.url)
    }

    // MARK: Headshots

    /// Swipe, or tap to go to the next photo; past the last one, the tape starts — the same order
    /// casting meets you in.
    private var photoViewer: some View {
        TabView(selection: $photoIndex) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                Image(uiImage: photo.image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .overlay(alignment: .bottomLeading) {
                        Text("\(photo.title) · \(index + 1) of \(photos.count)")
                            .font(.otCaption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(OT.cameraGlass, in: Capsule())
                            .padding(10)
                    }
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .contentShape(Rectangle())
        .onTapGesture {
            if photoIndex + 1 < photos.count { withAnimation { photoIndex += 1 } } else { seek(to: 0) }
        }
        .accessibilityHint("Swipe for the next headshot")
    }

    private func showPhotos() {
        player?.pause()
        photoIndex = 0
        showingPhotos = true
        Haptics.tick()
    }

    // MARK: Chapters

    private func chapterBar(_ tape: MediaExporter.Tape) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let total = max(tape.duration, 0.1)
                let photoWidth = photos.isEmpty ? 0.0 : 24.0 + 3
                let spacing = 3.0 * Double(max(tape.chapters.count - 1, 0)) + photoWidth
                HStack(spacing: 3) {
                    // Photos aren't timed, so their chapter is a short fixed segment at the start.
                    if !photos.isEmpty {
                        RoundedRectangle(cornerRadius: 4).fill(OT.accent)
                            .opacity(showingPhotos ? 1 : 0.55)
                            .frame(width: 24)
                            .onTapGesture { showPhotos() }
                    }
                    ForEach(tape.chapters) { chapter in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color(for: chapter, in: tape))
                            .opacity(!showingPhotos && isCurrent(chapter) ? 1 : 0.55)
                            .frame(width: max(12, (geo.size.width - spacing) * chapter.duration / total))
                            .onTapGesture { seek(to: chapter.start) }
                    }
                }
            }
            .frame(height: 8)
            HStack {
                Text(showingPhotos ? "Headshots · \(photoIndex + 1) of \(photos.count)" : clock(now)).foregroundStyle(OT.cameraLabel)
                Spacer()
                Text(clock(tape.duration)).foregroundStyle(OT.cameraLabel2)
            }
            .font(.otCaption).monospacedDigit()
        }
    }

    private func chapterList(_ tape: MediaExporter.Tape) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHAPTERS").font(.otCaption.weight(.semibold)).tracking(0.6).foregroundStyle(OT.cameraLabel2)
            if photos.isEmpty {
                Button { store.push(.headshots(for: auditionID)) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.square").foregroundStyle(OT.warning)
                        Text("No headshots yet").font(.otBody).foregroundStyle(OT.cameraLabel)
                        Spacer()
                        Text("Take them").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent)
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button { showPhotos() } label: {
                    HStack(spacing: 12) {
                        Text("1").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.cameraLabel2)
                        Text("Headshots").font(showingPhotos ? .otHeadline : .otBody).foregroundStyle(OT.cameraLabel)
                        Spacer()
                        Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")").font(.otFootnote).foregroundStyle(OT.cameraLabel2)
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button("Change headshots") {
                    player?.pause()
                    store.push(.headshots(for: auditionID))
                }
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(OT.accent)
            }
            ForEach(Array(tape.chapters.enumerated()), id: \.element.id) { index, chapter in
                Button { open(chapter) } label: {
                    HStack(spacing: 12) {
                        Text("\(index + (photos.isEmpty ? 1 : 2))").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.cameraLabel2)
                        Text(chapter.label)
                            .font(!showingPhotos && isCurrent(chapter) ? .otHeadline : .otBody)
                            .foregroundStyle(OT.cameraLabel)
                        Spacer()
                        Text(clock(chapter.duration)).font(.otFootnote).foregroundStyle(OT.cameraLabel2).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func open(_ chapter: MediaExporter.Chapter) {
        player?.pause()
        switch chapter.kind {
        case .slate:
            store.camera = .shoot(auditionID, start: .slate)
        case .fullLength:
            store.camera = .shoot(auditionID, start: .fullLength)
        case .scene(let index):
            store.push(.takes(auditionID, sceneIndex: index))
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
        photos = HeadshotStore.taken.compactMap { angle in HeadshotStore.load(key: angle.key).map { (title: angle.title, image: $0) } }
        showingPhotos = !photos.isEmpty
        photoIndex = 0
        guard let built = try? await MediaExporter.build(MediaExporter.clips(for: a, takes: takes)),
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
        showingPhotos = false
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
