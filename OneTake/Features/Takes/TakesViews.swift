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

    private var hasPreview: Bool {
        store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
    }

    private var hasTapeCheck: Bool {
        store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
    }

    var body: some View {
        let takes = store.takes.filter { $0.auditionID == auditionID && ($0.sceneIndex ?? 0) == shownScene }
        let current = takes.first { $0.id == (selected ?? takes.first(where: \.isCircled)?.id) } ?? takes.last
        let circled = takes.first(where: \.isCircled)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(title: "Your takes", backLabel: "Back", onBack: { store.pop() }) {
                    Button { trimming = current } label: {
                        Image(systemName: "scissors")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OT.labelPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .modifier(GlassButtonCompatibility(enabled: true))
                    .disabled(!(current?.fileURL.map(VideoTrimmer.canTrim) ?? false))
                    .opacity((current?.fileURL.map(VideoTrimmer.canTrim) ?? false) ? 1.0 : 0.4)
                    .accessibilityLabel("Trim")
                }
                .padding(.top, 8)

                if scenes.count > 1 {
                    Picker("Scene", selection: Binding(get: { shownScene }, set: { scene = $0; selected = nil })) {
                        ForEach(scenes.indices, id: \.self) { Text(scenes[$0].title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                PlayerCard(url: current?.fileURL)
                    .padding(.top, 4)
                if let current, current.originalFileURL != nil {
                    Button {
                        store.restoreOriginalTakeFile(current.id)
                        Haptics.success()
                    } label: {
                        Label("Restore original clip", systemImage: "arrow.uturn.backward")
                            .font(.otFootnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(OT.accent)
                }

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
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Go again") { showOneMore = true }.buttonStyle(.otSecondary).frame(width: 130)
                if hasPreview {
                    Button("Back to preview") {
                        store.popTo(.preview(auditionID))
                    }
                    .buttonStyle(.otPrimary)
                    .disabled(!store.takes.contains { $0.auditionID == auditionID })
                } else if hasTapeCheck {
                    Button("Back to tape check") {
                        store.popTo(.tapeCheck(auditionID))
                    }
                    .buttonStyle(.otPrimary)
                    .disabled(!store.takes.contains { $0.auditionID == auditionID })
                } else if let nextRequiredUnshot = scenes.indices.first(where: { idx in
                    idx != shownScene
                    && !store.takes.contains { $0.auditionID == auditionID && ($0.sceneIndex ?? 0) == idx }
                    && !(store.audition(auditionID)?.pieces.first(where: { $0.kind == .scene && $0.title == scenes[idx].title })?.isOptional ?? false)
                }) {
                    Button("Next: \(scenes[nextRequiredUnshot].title)") {
                        store.camera = .shoot(auditionID, scene: nextRequiredUnshot)
                    }
                    .buttonStyle(.otPrimary)
                } else {
                    Button("Check the tape") {
                        store.push(.tapeCheck(auditionID))
                    }
                    .buttonStyle(.otPrimary)
                    .disabled(!store.takes.contains { $0.auditionID == auditionID })
                }
            }
            .padding(.horizontal, OT.gutter).padding(.vertical, 8).background(OT.bgCanvas)
        }
        .sheet(item: $trimming) { take in
            if let url = take.fileURL {
                VideoTrimmer(url: url) { edited in
                    trimming = nil
                    if let edited { store.replaceTakeFile(take.id, with: edited); Haptics.success() }
                }
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
    @State private var player: AVPlayer?

    init(url: URL?) {
        self.url = url
        _player = State(initialValue: url.map { AVPlayer(url: $0) })
    }

    var body: some View {
        ZStack {
            Color.black
            if url != nil, let player { VideoPlayer(player: player) }
            else {
                HeadshotImage(onDark: true)
                Image(systemName: "play.fill").font(.title).foregroundStyle(.white)
                    .frame(width: 60, height: 60).background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .onChange(of: url) { _, newURL in
            player?.pause()
            player = newURL.map { AVPlayer(url: $0) }
        }
    }
}

// MARK: - v2/Take Thumbnail · Default / Selected / Chosen

struct TakeThumbnail: View {
    let take: Take
    var isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let url = take.fileURL { VideoThumbnail(url: url) } else { HeadshotImage(onDark: true) }
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

struct AuditionElementReviewView: View {
    let auditionID: Audition.ID
    let element: AuditionReviewElement
    @Environment(AppStore.self) private var store
    @State private var player: AVPlayer?
    @State private var findings: [TapeFinding] = []
    @State private var isChecking = true

    private var audition: Audition? { store.audition(auditionID) }
    private var displayTitle: String {
        if case .scene(let index) = element, let audition, audition.scenes.indices.contains(index) {
            return audition.scenes[index].title
        }
        return element.title
    }
    private var clipURL: URL? {
        guard let audition else { return nil }
        switch element {
        case .slate: return audition.slateVideoURL
        case .fullLength: return audition.fullLengthVideoURL
        case .scene(let index):
            let takes = store.takes.filter { $0.auditionID == auditionID && $0.sceneIndex == index }
            return (takes.first(where: \.isCircled) ?? takes.last)?.fileURL
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(title: "Review \(displayTitle)", backLabel: "Back", onBack: { store.pop() })
                    .padding(.top, 4)
                if let player {
                    VideoPlayer(player: player).frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ContentUnavailableView("Recording unavailable", systemImage: "video.slash",
                                           description: Text("This recording may have been moved or deleted."))
                }
                SectionLabel(text: "THIS PART ONLY")
                if isChecking {
                    Label("Checking this recording…", systemImage: "waveform")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                } else if findings.isEmpty {
                    Label("No suggested changes", systemImage: "checkmark.circle.fill")
                        .font(.otBody.weight(.medium)).foregroundStyle(OT.success)
                } else {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(finding.title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                            Text(finding.advice).font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).otCard(radius: 14)
                    }
                }
                Text("Suggestions are advisory. Keep pauses or delivery choices that feel intentional.")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
            }
            .padding(.horizontal, OT.gutter).padding(.bottom, 28)
        }
        .otCanvas()
        .safeAreaInset(edge: .bottom) {
            Button(actionTitle, action: editThisElement)
                .buttonStyle(.otPrimary).padding(OT.gutter).background(OT.bgCanvas)
        }
        .task(id: clipURL) {
            player?.pause()
            guard let clipURL else { player = nil; isChecking = false; return }
            player = AVPlayer(url: clipURL)
            isChecking = true
            if let audition {
                let report = await TapeAnalyzer.analyze(audition, takes: store.takes.filter { $0.auditionID == auditionID && $0.isCircled })
                guard !Task.isCancelled else { return }
                findings = report.findings.filter { $0.clipURL == clipURL }
            }
            isChecking = false
        }
        .onDisappear { player?.pause() }
    }

    private var actionTitle: String {
        switch element {
        case .slate: "Retake slate"
        case .fullLength: "Retake full-body shot"
        case .scene: "Choose or record a take"
        }
    }

    private func editThisElement() {
        switch element {
        case .slate: store.camera = .shoot(auditionID, start: .slate)
        case .fullLength: store.camera = .shoot(auditionID, start: .fullLength)
        case .scene(let index): store.push(.takes(auditionID, sceneIndex: index))
        }
    }
}

struct TapeCheckView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var report: TapeAnalyzer.Report?
    @State private var finding: TapeFinding?
    @State private var passedOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(title: "Tape check", backLabel: "Back", onBack: { store.pop() })
                    .padding(.top, 4)

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
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            Button("Preview the full tape") { store.push(.preview(auditionID)) }.buttonStyle(.otPrimary)
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
            if result.findings.isEmpty {
                Haptics.success()
            } else {
                Haptics.warning()
            }
        }
        .sheet(item: $finding) { f in
            FindingSheet(finding: f, onDismiss: { finding = nil }, onRetake: retakeAction(for: f))
        }
    }

    private func retakeAction(for finding: TapeFinding) -> (() -> Void)? {
        guard let flow = retakeFlow(for: finding) else { return nil }
        return {
            self.finding = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                self.store.camera = flow
            }
        }
    }

    private func retakeFlow(for finding: TapeFinding) -> CameraFlow? {
        guard let url = finding.clipURL, let audition = store.audition(auditionID) else { return nil }
        if url == audition.slateVideoURL { return .shoot(auditionID, start: .slate) }
        if url == audition.fullLengthVideoURL { return .shoot(auditionID, start: .fullLength) }
        if let take = store.takes.first(where: { $0.fileURL == url }), let scene = take.sceneIndex {
            return .shoot(auditionID, scene: scene)
        }
        return nil
    }

    private var tapeSignature: [URL] {
        guard let a = store.audition(auditionID) else { return [] }
        return MediaExporter.clips(for: a, takes: finalizedTakes).map(\.url)
    }

    private var finalizedTakes: [Take] {
        store.takes.filter { $0.auditionID == auditionID && $0.isCircled }
    }

    private var reviewElements: [(element: AuditionReviewElement, url: URL)] {
        guard let audition = store.audition(auditionID) else { return [] }
        var items: [(AuditionReviewElement, URL)] = []
        if let url = audition.slateVideoURL { items.append((.slate, url)) }
        if let url = audition.fullLengthVideoURL { items.append((.fullLength, url)) }
        for index in audition.scenes.indices {
            let takes = finalizedTakes.filter { $0.sceneIndex == index }
            if let url = takes.first?.fileURL { items.append((.scene(index), url)) }
        }
        return items.map { (element: $0.0, url: $0.1) }
    }

    private func reviewTitle(_ element: AuditionReviewElement) -> String {
        if case .scene(let index) = element, let audition = store.audition(auditionID), audition.scenes.indices.contains(index) {
            return audition.scenes[index].title
        }
        return element.title
    }

    @ViewBuilder private func results(_ report: TapeAnalyzer.Report) -> some View {
        if report.clipCount == 0 {
            Text("Nothing to check yet").font(.otTitle)
            Text("Record your slate and a take, then come back — Tape Check looks at exactly what goes on the tape.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
        } else {
            let worthReview = report.findings.filter { !$0.isSoftPrompt && $0.clipURL == nil }
            let optionalPrompts = report.findings.filter { $0.isSoftPrompt && $0.clipURL == nil }
            HStack(spacing: 16) {
                ReadinessDial(done: report.passed.count, total: report.checkCount, size: 84, lineWidth: 8)
                    .accessibilityLabel("\(report.passed.count) of \(report.checkCount) technical checks passed")
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.findings.isEmpty ? "No technical issues found" : worthReview.isEmpty ? "No clear technical issue" : "Review what stands out")
                        .font(.otTitle)
                    Text(report.findings.isEmpty
                         ? "Nothing stood out. Watch it once, then send."
                         : optionalPrompts.isEmpty
                            ? "These checks are advisory. Nothing blocks sending."
                            : "Timing cues can be intentional. Keep them if they feel right. Nothing blocks sending.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                }
            }
            if !reviewElements.isEmpty {
                SectionLabel(text: "Review one part at a time")
                Text("Each recording opens on its own, with its own checks and retake action.")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                ForEach(reviewElements.indices, id: \.self) { index in
                    let item = reviewElements[index]
                    let count = report.findings.filter { $0.clipURL == item.url }.count
                    Button { store.push(.elementReview(auditionID, element: item.element)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.element == .slate ? "person.text.rectangle" : "film")
                                .font(.title3).foregroundStyle(OT.accent)
                                .frame(width: 40, height: 40).background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reviewTitle(item.element)).font(.otBody.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                                Text(count == 0 ? "Ready to review" : "\(count) suggestion\(count == 1 ? "" : "s")")
                                    .font(.otFootnote).foregroundStyle(count == 0 ? OT.success : OT.warning)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                        }
                        .padding(12).otCard(radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !report.findings.isEmpty {
                if let guidance = report.aiGuidance {
                    Label(guidance, systemImage: "sparkles")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                        .padding(14).background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if !worthReview.isEmpty {
                    SectionLabel(text: "Worth a look")
                    ForEach(worthReview) { findingRow($0) }
                }
                if !optionalPrompts.isEmpty {
                    SectionLabel(text: "Check if you want")
                    Text("These timing cues are estimates. A pause or quick start may be intentional.")
                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    ForEach(optionalPrompts) { findingRow($0) }
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
                    Label("\(report.passed.count) checks passed", systemImage: "checkmark.seal.fill").foregroundStyle(OT.success)
                }
            }
            Label("Checked on this iPhone — nothing is uploaded.", systemImage: "lock.fill")
                .font(.otFootnote).foregroundStyle(OT.labelTertiary)
        }
    }

    @ViewBuilder private func findingRow(_ f: TapeFinding) -> some View {
        Button { finding = f } label: {
            HStack(spacing: 12) {
                Group {
                    if let url = f.clipURL { VideoThumbnail(url: url) }
                    else { Image(systemName: "shippingbox").foregroundStyle(OT.labelSecondary) }
                }
                .frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.category).font(.otCaption.weight(.semibold))
                        .foregroundStyle(f.isSoftPrompt ? OT.labelSecondary : OT.warning)
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

/// One finding, with the actual clip cued to the moment it's about.
private struct FindingSheet: View {
    let finding: TapeFinding
    var onDismiss: () -> Void
    var onRetake: (() -> Void)? = nil
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(finding.category) · \(finding.where_)").font(.otFootnote.weight(.semibold))
                .foregroundStyle(finding.isSoftPrompt ? OT.labelSecondary : OT.warning)
            Text(finding.title).font(.otTitle)
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            Text(finding.advice).font(.otCallout).foregroundStyle(OT.labelSecondary)
            HStack {
                if let seconds = finding.seconds, seconds >= 1.0, player != nil {
                    Button("Watch \(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))") { play(from: seconds) }
                        .buttonStyle(.otSecondary)
                } else if player != nil {
                    Button("Watch take") { play(from: 0) }
                        .buttonStyle(.otSecondary)
                }
                Button("I meant it", action: onDismiss).buttonStyle(.otSecondary)
            }
            if let onRetake {
                Text("Recording again saves a new take. Your current send take stays selected until you choose another.")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                Button("Record another take", action: onRetake).buttonStyle(.otPrimary)
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
