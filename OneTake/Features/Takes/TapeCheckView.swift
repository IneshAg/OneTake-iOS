import SwiftUI
import OneTakeUI
import AVKit

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
        OTScreen(title: "Review \(displayTitle)", backLabel: "Back", onBack: { store.pop() }) {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 250) // ot-lint:allow
                        .clipShape(RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
                } else {
                    ContentUnavailableView(
                        "Recording unavailable",
                        systemImage: "video.slash",
                        description: Text("This recording may have been moved or deleted.")
                    )
                }

                OTSectionLabel("THIS PART ONLY")

                if isChecking {
                    Label("Checking this recording…", systemImage: "waveform")
                        .font(.otCallout)
                        .foregroundStyle(OT.labelSecondary)
                } else if findings.isEmpty {
                    Label("No suggested changes", systemImage: "checkmark.circle.fill")
                        .font(.otBody.weight(.medium))
                        .foregroundStyle(OT.success)
                } else {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text(finding.title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                            Text(finding.advice).font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OTSpace.cardInset)
                        .otCard(.grouped)
                    }
                }

                Text("Suggestions are advisory. Keep pauses or delivery choices that feel intentional.")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelTertiary)
            }
        }
        .otBottomBar {
            Button(actionTitle, action: editThisElement)
                .buttonStyle(.otPrimary)
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
        OTScreen(title: "Tape check", backLabel: "Back", onBack: { store.pop() }) {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                if let report {
                    results(report)
                } else {
                    HStack(spacing: OTSpace.m) {
                        ProgressView()
                        Text("Checking framing, light and sound…")
                            .font(.otCallout)
                            .foregroundStyle(OT.labelSecondary)
                    }
                    .padding(.top, OTSpace.l)
                }
            }
        }
        .otBottomBar {
            Button("Preview the full tape") {
                store.push(.preview(auditionID))
            }
            .buttonStyle(.otPrimary)
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
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)
        } else {
            let worthReview = report.findings.filter { !$0.isSoftPrompt && $0.clipURL == nil }
            let optionalPrompts = report.findings.filter { $0.isSoftPrompt && $0.clipURL == nil }
            HStack(spacing: OTSpace.m) {
                ReadinessDial(done: report.passed.count, total: report.checkCount, size: 84, lineWidth: 8) // ot-lint:allow
                    .accessibilityLabel("\(report.passed.count) of \(report.checkCount) technical checks passed")
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.findings.isEmpty ? "No technical issues found" : worthReview.isEmpty ? "No clear technical issue" : "Review what stands out")
                        .font(.otTitle)
                    Text(report.findings.isEmpty
                         ? "Nothing stood out. Watch it once, then send."
                         : optionalPrompts.isEmpty
                            ? "These checks are advisory. Nothing blocks sending."
                            : "Timing cues can be intentional. Keep them if they feel right. Nothing blocks sending.")
                        .font(.otCallout)
                        .foregroundStyle(OT.labelSecondary)
                }
            }
            if !reviewElements.isEmpty {
                OTSectionLabel("Review one part at a time")
                Text("Each recording opens on its own, with its own checks and retake action.")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelTertiary)
                ForEach(reviewElements.indices, id: \.self) { index in
                    let item = reviewElements[index]
                    let count = report.findings.filter { $0.clipURL == item.url }.count
                    Button {
                        store.push(.elementReview(auditionID, element: item.element))
                    } label: {
                        HStack(spacing: OTSpace.m) {
                            Image(systemName: item.element == .slate ? "person.text.rectangle" : "film")
                                .font(.title3)
                                .foregroundStyle(OT.accent)
                                .frame(width: 40, height: 40) // ot-lint:allow
                                .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.m))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reviewTitle(item.element)).font(.otBody.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                                Text(count == 0 ? "Ready to review" : "\(count) suggestion\(count == 1 ? "" : "s")")
                                    .font(.otFootnote).foregroundStyle(count == 0 ? OT.success : OT.warning)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                        }
                        .padding(OTSpace.cardInset)
                        .otCard(.grouped)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !report.findings.isEmpty {
                if let guidance = report.aiGuidance {
                    Label(guidance, systemImage: "sparkles")
                        .font(.otCallout)
                        .foregroundStyle(OT.labelSecondary)
                        .padding(OTSpace.cardInset)
                        .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
                }
                if !worthReview.isEmpty {
                    OTSectionLabel("Worth a look")
                    ForEach(worthReview) { findingRow($0) }
                }
                if !optionalPrompts.isEmpty {
                    OTSectionLabel("Check if you want")
                    Text("These timing cues are estimates. A pause or quick start may be intentional.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                    ForEach(optionalPrompts) { findingRow($0) }
                }
            }
            if report.findings.isEmpty, let guidance = report.aiGuidance {
                Label(guidance, systemImage: "sparkles")
                    .font(.otCallout)
                    .foregroundStyle(OT.labelSecondary)
                    .padding(OTSpace.cardInset)
                    .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
            }
            if !report.passed.isEmpty {
                DisclosureGroup(isExpanded: $passedOpen) {
                    Text(report.passed.joined(separator: ", "))
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                        .padding(.top, 6) // ot-lint:allow
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("\(report.passed.count) checks passed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(OT.success)
                }
            }
            Label("Checked on this iPhone — nothing is uploaded.", systemImage: "lock.fill")
                .font(.otFootnote)
                .foregroundStyle(OT.labelTertiary)
        }
    }

    @ViewBuilder private func findingRow(_ f: TapeFinding) -> some View {
        Button { finding = f } label: {
            HStack(spacing: OTSpace.m) {
                Group {
                    if let url = f.clipURL {
                        VideoThumbnail(url: url)
                    } else {
                        Image(systemName: "shippingbox").foregroundStyle(OT.labelSecondary)
                    }
                }
                .frame(width: 64, height: 40) // ot-lint:allow
                .clipShape(RoundedRectangle(cornerRadius: OTRadius.s))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.category)
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(f.isSoftPrompt ? OT.labelSecondary : OT.warning)
                    Text(f.title).font(.otBody)
                    Text(f.where_).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                }
                Spacer()
                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
            }
            .frame(minHeight: 60) // ot-lint:allow
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
        VStack(alignment: .leading, spacing: OTSpace.m) {
            Text("\(finding.category) · \(finding.where_)")
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(finding.isSoftPrompt ? OT.labelSecondary : OT.warning)
            Text(finding.title).font(.otTitle)
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 260) // ot-lint:allow
                    .clipShape(RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
            }
            Text(finding.advice).font(.otCallout).foregroundStyle(OT.labelSecondary)
            HStack {
                if let seconds = finding.seconds, seconds >= 1.0, player != nil {
                    Button("Watch \(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))") {
                        play(from: seconds)
                    }
                    .buttonStyle(.otSecondary)
                } else if player != nil {
                    Button("Watch take") {
                        play(from: 0)
                    }
                    .buttonStyle(.otSecondary)
                }
                Button("I meant it", action: onDismiss).buttonStyle(.otSecondary)
            }
            if let onRetake {
                Text("Recording again saves a new take. Your current send take stays selected until you choose another.")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelTertiary)
                Button("Record another take", action: onRetake).buttonStyle(.otPrimary)
            }
        }
        .padding(OTSpace.gutter)
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
