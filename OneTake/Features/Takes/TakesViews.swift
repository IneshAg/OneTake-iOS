import SwiftUI
import AVKit
import AVFoundation

/// A real frame grabbed from the take's own file — not a stand-in photo — generated once and cached
/// in memory for the life of the view.
struct VideoThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { OT.cameraBg }
        }
        // Runs again when the file changes (a trimmed take gets a new URL), so the frame never goes stale.
        .task(id: url) { image = await Self.thumbnail(url) }
    }

    /// Frames are kept in memory, keyed by file and modification date: lists of takes re-render
    /// often, and a re-recorded slate keeps its file name.
    private static let cache = NSCache<NSString, UIImage>()

    private static func thumbnail(_ url: URL) async -> UIImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(url.path)@\(modified?.timeIntervalSince1970 ?? 0)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // Display size, not the full frame: a 4K frame is ~33 MB decoded.
        generator.maximumSize = CGSize(width: 480, height: 480)
        let image: UIImage? = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.1, preferredTimescale: 30))]) { _, cgImage, _, _, error in
                if let cgImage { cont.resume(returning: UIImage(cgImage: cgImage)) }
                else { cont.resume(throwing: error ?? NSError(domain: "VideoThumbnail", code: -1)) }
            }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

// MARK: - 18 Your takes

struct TakesView: View {
    let auditionID: Audition.ID
    var initialScene: Int? = nil
    @Environment(AppStore.self) private var store
    @State private var selected: Take.ID?
    @State private var showOneMore = false
    @State private var notesOpen = false
    @State private var trimming: Take?
    @State private var newNote = ""
    /// Which scene's takes are showing — each scene has its own circled take.
    @State private var scene: Int?

    private var scenes: [ScriptScene] { store.audition(auditionID)?.scenes ?? [] }

    /// The chosen scene, else the scene of the most recent take, else the first.
    private var shownScene: Int {
        scene ?? initialScene ?? store.takes.last(where: { $0.auditionID == auditionID })?.sceneIndex ?? 0
    }

    var body: some View {
        let takes = store.takes.filter { $0.auditionID == auditionID && ($0.sceneIndex ?? 0) == shownScene }
        let current = takes.first { $0.id == (selected ?? takes.first(where: \.isCircled)?.id) } ?? takes.last
        let circled = takes.first(where: \.isCircled)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if scenes.count > 1 {
                    Picker("Scene", selection: Binding(get: { shownScene }, set: { scene = $0; selected = nil })) {
                        ForEach(scenes.indices, id: \.self) { Text(scenes[$0].title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                PlayerCard(url: current?.fileURL)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(takes) { take in
                            TakeThumbnail(take: take, isSelected: take.id == current?.id)
                                .onTapGesture { selected = take.id; Haptics.tick() }
                                .onLongPressGesture { store.circleOnly(take); Haptics.success() }
                        }
                    }
                }

                HStack {
                    Text(circled.map { "Take \($0.number) is circled — that's your send." }
                         ?? (takes.isEmpty ? "No takes for this scene yet." : "Long-press a take to circle it."))
                        .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                    Spacer()
                    if let c = current, !c.isCircled {
                        Button("Circle take \(c.number)") { store.circleOnly(c); Haptics.success() }.font(.otFootnote.weight(.semibold))
                    }
                }

                DisclosureGroup(isExpanded: $notesOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(current?.notes ?? [], id: \.self) { Text("• \($0)").font(.otCallout) }
                        if let c = current {
                            TextField("Add a note to take \(c.number)", text: $newNote)
                                .submitLabel(.done)
                                .onSubmit { store.addNote(newNote, to: c.id); newNote = "" }
                                .padding(10).background(OT.fillField, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: {
                    VStack(alignment: .leading) {
                        Label("Notes to self", systemImage: "square.and.pencil").font(.otBody)
                        Text((current?.notes.isEmpty ?? true) ? "Never sent · nothing yet" : "Never sent · " + (current?.notes.joined(separator: " · ") ?? ""))
                            .font(.otFootnote).foregroundStyle(OT.labelTertiary).lineLimit(1)
                    }
                }
                .tint(OT.labelPrimary)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 100)
        }
        .otCanvas()
        .navigationTitle("Your takes").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Compare Takes is cut from MVP — the loop stays record → check → keep/retake/edit, no
            // side-by-side comparison step.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { trimming = current } label: { Image(systemName: "scissors") }
                    .disabled(!(current?.fileURL.map(VideoTrimmer.canTrim) ?? false))
                    .accessibilityLabel("Trim")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Go again") { showOneMore = true }.buttonStyle(.otSecondary).frame(width: 130)
                Button(scenes.count > 1 ? "Check the tape" : circled.map { "Send take \($0.number)" } ?? "Check the tape") { store.push(.tapeCheck(auditionID)) }
                    .buttonStyle(.otPrimary)
                    .disabled(!store.takes.contains { $0.auditionID == auditionID })
            }
            .padding(.horizontal, OT.gutter).padding(.vertical, 8).background(OT.bgCanvas)
        }
        .sheet(item: $trimming) { take in
            if let url = take.fileURL {
                VideoTrimmer(url: url) { edited in
                    trimming = nil
                    if let edited { store.replaceTakeFile(take.id, with: edited); Haptics.success() }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showOneMore) {
            VStack(spacing: 14) {
                Text("One more?").font(.otTitle)
                Text("Takes 1 to \(takes.count) stay right here. Three solid takes is plenty — trust the one you circled.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary).multilineTextAlignment(.center)
                Button("Record take \(store.nextTakeNumber(auditionID: auditionID, sceneIndex: shownScene))") { showOneMore = false; store.camera = .shoot(auditionID, scene: shownScene) }.buttonStyle(.otPrimary)
                Button("Not now") { showOneMore = false }.buttonStyle(.otSecondary)
            }
            .padding(OT.gutter)
            .presentationDetents([.height(300)])
        }
    }
}

/// AVKit player (UIKit-backed `AVPlayerViewController` via SwiftUI `VideoPlayer`).
struct PlayerCard: View {
    let url: URL?
    var body: some View {
        ZStack {
            if let url { VideoPlayer(player: AVPlayer(url: url)) }
            else {
                HeadshotImage()
                Image(systemName: "play.fill").font(.title).foregroundStyle(.white)
                    .frame(width: 60, height: 60).background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - v2/Take Thumbnail · Default / Selected / Chosen

struct TakeThumbnail: View {
    let take: Take
    var isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let url = take.fileURL { VideoThumbnail(url: url) } else { HeadshotImage() }
            }
                .frame(width: 104, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? OT.accent : .clear, lineWidth: 2.5).padding(-3))
            HStack(spacing: 4) {
                Text("Take \(take.number)").font(.otHeadline)
                if take.isCircled { Image(systemName: "star.fill").font(.caption).foregroundStyle(OT.accent) }
            }
            Text("\(Int(take.duration) / 60):\(String(format: "%02d", Int(take.duration) % 60)) · \(take.recordedAt.formatted(.relative(presentation: .numeric)))")
                .font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Long-press to circle this take")
    }
}

// MARK: - 19b Tape check

struct TapeCheckView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var report: TapeAnalyzer.Report?
    @State private var finding: TapeFinding?
    @State private var passedOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let report {
                    results(report)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking framing, light and sound…").font(.otCallout).foregroundStyle(OT.labelSecondary)
                    }
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 140)
        }
        .otCanvas()
        .navigationTitle("Tape check").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                // Checked first, then watched: Preview is the last look before packaging.
                Button("Preview the tape") { store.push(.preview(auditionID)) }.buttonStyle(.otPrimary)
                if let first = report?.findings.first(where: { $0.clipURL != nil }) {
                    Button("Watch the moments") { finding = first }
                        .font(.otHeadline).foregroundStyle(OT.labelPrimary).frame(maxWidth: .infinity, minHeight: 48)
                }
            }
            .padding(.horizontal, OT.gutter).background(OT.bgCanvas)
        }
        // Re-runs whenever what's on the tape changes (a different circled take, a new recording).
        .task(id: tapeSignature) {
            report = nil
            guard let a = store.audition(auditionID) else { return }
            let takes = finalizedTakes
            let result = await TapeAnalyzer.analyze(a, takes: takes)
            guard !Task.isCancelled else { return }
            report = result
        }
        .sheet(item: $finding) { f in FindingSheet(finding: f) { finding = nil } }
    }

    private var tapeSignature: [URL] {
        guard let a = store.audition(auditionID) else { return [] }
        return MediaExporter.clips(for: a, takes: finalizedTakes).map(\.url)
    }

    private var finalizedTakes: [Take] {
        store.takes.filter { $0.auditionID == auditionID && $0.isCircled }
    }

    @ViewBuilder private func results(_ report: TapeAnalyzer.Report) -> some View {
        if report.clipCount == 0 {
            Text("Nothing to check yet").font(.otTitle)
            Text("Record your slate and a take, then come back — Tape Check looks at exactly what goes on the tape.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
        } else {
            HStack(spacing: 16) {
                if report.checkCount > 0 {
                    ReadinessDial(done: report.passed.count, total: report.checkCount, size: 84, lineWidth: 8)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.findings.isEmpty ? "Looks good" : "Ready to send").font(.otTitle)
                    Text(report.findings.isEmpty
                         ? "Nothing stood out. Watch it once, then send."
                         : "\(report.findings.count) thing\(report.findings.count == 1 ? " is" : "s are") worth a look. Nothing stops you sending.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                }
            }
            if !report.findings.isEmpty {
                if let guidance = report.aiGuidance {
                    Label(guidance, systemImage: "sparkles")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                        .padding(14).background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                SectionLabel(text: "Worth a look")
                ForEach(report.findings) { f in
                    Button { finding = f } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let url = f.clipURL { VideoThumbnail(url: url) } else { Image(systemName: "shippingbox").foregroundStyle(OT.labelSecondary) }
                            }
                            .frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.category).font(.otCaption.weight(.semibold)).foregroundStyle(OT.warning)
                                Text(f.title).font(.otBody)
                                Text(f.where_).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                        }
                        .frame(minHeight: 60)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            if report.findings.isEmpty, let guidance = report.aiGuidance {
                Label(guidance, systemImage: "sparkles")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)
                    .padding(14).background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !report.passed.isEmpty {
                DisclosureGroup(isExpanded: $passedOpen) {
                    Text(report.passed.joined(separator: ", "))
                        .font(.otFootnote).foregroundStyle(OT.labelSecondary).padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("\(report.passed.count) check\(report.passed.count == 1 ? "" : "s") passed", systemImage: "checkmark.seal.fill").foregroundStyle(OT.success)
                }
            }
            Label("Checked on this iPhone — nothing is uploaded.", systemImage: "lock.fill")
                .font(.otFootnote).foregroundStyle(OT.labelTertiary)
        }
    }
}

/// One finding, with the actual clip cued to the moment it's about.
private struct FindingSheet: View {
    let finding: TapeFinding
    var onDismiss: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(finding.category) · \(finding.where_)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.warning)
            Text(finding.title).font(.otTitle)
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            Text(finding.advice).font(.otCallout).foregroundStyle(OT.labelSecondary)
            HStack {
                if let seconds = finding.seconds, player != nil {
                    Button("Watch \(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))") { play(from: seconds) }
                        .buttonStyle(.otSecondary)
                }
                Button("I meant it", action: onDismiss).buttonStyle(.otSecondary)
            }
        }
        .padding(OT.gutter)
        .presentationDetents([.medium, .large])
        .onAppear {
            guard let url = finding.clipURL else { return }
            let player = AVPlayer(url: url)
            player.seek(to: CMTime(seconds: finding.seconds ?? 0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            self.player = player
        }
        .onDisappear { player?.pause() }
    }

    private func play(from seconds: Double) {
        // Start a moment early so the finding has context.
        player?.seek(to: CMTime(seconds: max(0, seconds - 1), preferredTimescale: 600))
        player?.play()
    }
}
