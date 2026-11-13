import SwiftUI

// MARK: - 20 Package · Ready to send

struct PackageView: View {
    enum Phase { case review, sending, readyToShare, failed, sent }
    typealias ExportStage = PackageExportStage

    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var phase: Phase = .review
    @State private var exportStage: PackageExportStage = .preparing
    @State private var showDestination = false
    @State private var showDeliverableSelector = false
    @State private var showSubmissionSpecs = false
    @State private var showShare = false
    @State private var progress = 0.0
    @State private var exportErrorMessage: String?
    @State private var exportTask: Task<Void, Never>?
    /// True while the exported tape is uploading to iCloud for an "Email or link" send.
    @State private var uploading = false
    /// Last progress pushed to the Live Activity — updates are throttled to 5% steps.
    @State private var reportedProgress = -1.0
    @State private var showSignIn = false
    @State private var trimmingClip: PackageTrimTarget?
    @State private var showFileNameEditor = false

    var body: some View {
        if let a = store.audition(auditionID) {
            let requiredFormat = PackageFormatHelper.requiredDeliverable(for: a)
            let deliverable = a.packageDeliverable ?? requiredFormat ?? .combinedVideo
            Group {
                switch phase {
                case .review:  review(a)
                case .sending: SendProgressView(audition: a, progress: progress, exportStage: exportStage, uploading: uploading, onCancel: cancelExport)
                case .readyToShare:
                    DeliveryReadyView(
                        audition: a,
                        destination: a.destination,
                        deliverable: deliverable,
                        onShare: { showShare = true },
                        onBack: { phase = .review }
                    )
                case .failed:  SendFailedView(message: exportErrorMessage, onEditOptions: { phase = .review }, onRetry: send)
                case .sent:    SentView(audition: a, slate: store.slate) { store.popToRoot(); store.tab = .auditions }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: phase)
            .onAppear {
                if a.packageDeliverable == nil, let requiredFormat,
                   let binding = store.binding(for: a.id) {
                    binding.wrappedValue.packageDeliverable = requiredFormat
                }
            }
            .onChange(of: progress) { _, p in reportUpload(p) }
            .sheet(isPresented: $showShare) {
                if let items = shareItems(a) {
                    ShareSheet(items: items, subject: a.emailSubject(slate: store.slate)) { completed in
                        if completed { store.markSent(auditionID); Haptics.success(); phase = .sent }
                        else { phase = .readyToShare }
                        endUpload()
                    }
                }
            }
            .sheet(isPresented: $showSignIn) {
                SignInView(reason: "A link puts your tape online, so it's tied to your account. Everything else in OneTake works without one.") { account in
                    store.account = account
                    showSignIn = false
                    send()
                }
            }
            .sheet(item: $trimmingClip) { target in
                VideoTrimmer(url: target.url) { edited in
                    trimmingClip = nil
                    guard let edited else { return }
                    switch target.kind {
                    case .slate: store.replaceSlateVideo(for: auditionID, with: edited)
                    case .fullLength: store.replaceFullLengthVideo(for: auditionID, with: edited)
                    }
                    Haptics.success()
                }
            }
        }
    }

    private func review(_ a: Audition) -> some View {
        let legend = tapeLegend(a)
        let deliverable = a.packageDeliverable
        let requiredFormat = PackageFormatHelper.requiredDeliverable(for: a)

        return OTScreen(
            title: "",
            backLabel: "Back",
            onBack: { store.pop() }
        ) {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                Text("Ready to send.").font(.otLargeTitle)
                Text("Due \(a.due.otDue) · \(a.readyCount) of \(a.totalCount) ready")
                    .font(.otCallout)
                    .foregroundStyle(OT.labelSecondary)

                HStack {
                    OTSectionLabel("On the tape, in order")
                    Spacer()
                    Text(PackageFormatHelper.totalDurationLabel(a, takes: store.takes)).font(.otHeadline)
                }
                TapeStrip(legend: legend)

                // 1. Deliverable Format (Combined Video, Separate ZIP, Photos, All)
                OTSectionLabel("Deliverable Format").padding(.top, OTSpace.xs)
                DeliverableFormatCard(
                    audition: a,
                    current: deliverable,
                    required: requiredFormat,
                    takes: store.takes,
                    onSelect: { showDeliverableSelector = true }
                )

                // 2. Submission Destination (Files, Email, Casting Sites)
                OTSectionLabel("Submission Destination").padding(.top, OTSpace.xs)
                DestinationCard(
                    audition: a,
                    hasAccount: store.account != nil,
                    onChangeDestination: { showDestination = true },
                    onSignIn: { showSignIn = true }
                )

                SubmissionCheckSummaryCard(
                    audition: a,
                    onSelectDeliverable: { showDeliverableSelector = true },
                    onSelectDestination: { showDestination = true }
                )

                DisclosureGroup(isExpanded: $showSubmissionSpecs) {
                    SubmissionSpecsCard(audition: a, slate: store.slate, takes: store.takes) {
                        showFileNameEditor = true
                    }
                    .padding(.top, OTSpace.s)
                } label: {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: "doc.text.magnifyingglass").foregroundStyle(OT.labelSecondary)
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text("File specs & validation").font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                            Text("Filename, duration, size, and slate details")
                                .font(.otCaption).foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }
                }
                .tint(OT.accent)
                .otCard(.grouped)

                // 4. Preview & Tape Check
                VStack(spacing: 0) {
                    Button { store.push(.preview(a.id)) } label: {
                        row(symbol: "play.rectangle", title: "Preview tape", detail: "Watch it and change a selected piece", value: nil, showDivider: true)
                    }
                    .buttonStyle(.plain)

                    Button { store.push(.tapeCheck(a.id)) } label: {
                        row(symbol: "checkmark.seal.fill", title: "Tape check", detail: "Picture and audio checks", value: "Review", tint: OT.success, showDivider: false)
                    }
                    .buttonStyle(.plain)
                }
                .otCard(.grouped, padding: OTSpace.m)
            }
        }
        .otBottomBar {
            bottomSendBar(a, deliverable: deliverable)
        }
        .sheet(isPresented: $showDestination) {
            DestinationSheet(auditionID: a.id).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDeliverableSelector) {
            PackageFormatSheet(auditionID: a.id, required: requiredFormat)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFileNameEditor) {
            FileNameTemplateSheet(auditionID: a.id)
                .environment(store)
        }
    }

    private func bottomSendBar(_ a: Audition, deliverable: PackageDeliverable?) -> some View {
        let destinationChosen = a.destinationWasChosen ?? false
        let actionTitle: String
        let actionIcon: String
        if let deliverable {
            actionTitle = destinationChosen ? sendButtonTitle(a, deliverable: deliverable) : "Choose submission destination"
            actionIcon = destinationChosen ? sendButtonIcon(a) : "paperplane"
        } else {
            actionTitle = "Choose delivery format"
            actionIcon = "shippingbox"
        }
        return Button {
            if deliverable == nil { showDeliverableSelector = true }
            else if !destinationChosen { showDestination = true }
            else { send() }
        } label: {
            HStack(spacing: OTSpace.s) {
                Image(systemName: actionIcon)
                Text(actionTitle)
            }
            .font(.otHeadline)
        }
        .buttonStyle(.otPrimary)
    }

    private func sendButtonIcon(_ a: Audition) -> String {
        switch a.destination {
        case .email: return "envelope.fill"
        case .localFiles: return "square.and.arrow.up"
        default: return "paperplane.fill"
        }
    }

    private func sendButtonTitle(_ a: Audition, deliverable: PackageDeliverable) -> String {
        switch a.destination {
        case .email:
            return "Email \(deliverable.shortTitle) to Casting"
        case .localFiles:
            return "Export \(deliverable.shortTitle) to Files / AirDrop"
        case .actorsAccess:
            return "Export \(deliverable.shortTitle) for Actors Access"
        case .backstage:
            return "Export \(deliverable.shortTitle) for Backstage"
        case .castingNetworks:
            return "Export \(deliverable.shortTitle) for Casting Networks"
        case .spotlight:
            return "Export \(deliverable.shortTitle) for Spotlight"
        case .emailOrLink:
            let item: String
            switch deliverable {
            case .combinedVideo: item = "Video Link"
            case .separateZip: item = "Clips ZIP Link"
            case .headshotsOnly: item = "Photos ZIP Link"
            case .completePackage: item = "Full Package Link"
            }
            return "Create \(item)"
        }
    }

    private func row(symbol: String, title: String, detail: String?, value: String?, tint: Color = OT.labelSecondary, showDivider: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: OTSpace.m) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 24) // ot-lint:allow
                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                    Text(title).font(.otBody).lineLimit(1).foregroundStyle(OT.labelPrimary)
                    if let detail { Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary) }
                }
                Spacer()
                if let value { Text(value).font(.otFootnote).foregroundStyle(OT.labelSecondary) }
                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
            }
            .frame(minHeight: 54) // ot-lint:allow

            if showDivider {
                Divider()
                    .padding(.leading, 38) // ot-lint:allow
            }
        }
    }

    private func tapeLegend(_ a: Audition) -> [(String, String, Color)] {
        var items: [(String, String, Color)] = []
        items.append(("Headshot", a.pieces.first(where: { $0.kind == .headshot })?.isDone == true ? "Captured" : "Not yet", OT.accent.opacity(0.4)))
        items.append(("Slate", a.slateVideoURL != nil ? "Recorded" : "Not yet", OT.accent.opacity(0.4)))
        for (i, scene) in a.scenes.enumerated() {
            let take = store.takes.first(where: { $0.auditionID == a.id && $0.sceneIndex == i && $0.isCircled })
            let detail = take.map { "Take \($0.number) · \(Int($0.duration))s" } ?? "Not shot yet"
            items.append((scene.title, detail, i.isMultiple(of: 2) ? OT.accent : OT.reader))
        }
        return items
    }

    /// Real export, not a simulated upload: `MediaExporter` composes the actual recorded files, and
    /// only once that succeeds does the share sheet open so the real file can actually go somewhere.
    private func send() {
        guard let a = store.audition(auditionID) else { return }
        guard a.packageDeliverable != nil else {
            showDeliverableSelector = true
            return
        }
        guard a.destinationWasChosen ?? false else {
            showDestination = true
            return
        }
        let asLink = a.destination == .emailOrLink
        if asLink && store.account == nil {
            showSignIn = true
            return
        }
        if asLink && !CloudLink.isAvailable {
            exportErrorMessage = CloudLink.CloudError.iCloudUnavailable.errorDescription
            phase = .failed
            return
        }
        uploading = false
        phase = .sending
        progress = 0
        exportStage = .preparing
        exportErrorMessage = nil
        store.clearShareLink(for: a.id)
        let takesForAudition = store.takes.filter { $0.auditionID == a.id }
        let slate = store.slate
        exportTask?.cancel()
        exportTask = Task {
            do {
                let format = a.packageDeliverable ?? .combinedVideo
                let needsVideo = format == .combinedVideo || format == .completePackage
                let needsClipArchive = format == .separateZip || format == .completePackage
                var videoURL: URL?
                var clipArchiveURL: URL?
                var hostedArtifactURL: URL?

                if needsVideo {
                    await MainActor.run { exportStage = .composing; progress = 0.05 }
                    let videoWeight = asLink ? 0.48 : 0.82
                    videoURL = try await MediaExporter.export(a, takes: takesForAudition, slate: slate) { p in
                        Task { @MainActor in progress = max(progress, p * videoWeight) }
                    }
                    if let videoURL {
                        await MainActor.run { store.setExportedFile(videoURL, for: a.id) }
                    }
                }

                if needsClipArchive {
                    await MainActor.run {
                        exportStage = .archiving
                        progress = max(progress, needsVideo ? 0.52 : 0.10)
                    }
                    clipArchiveURL = try await Task.detached(priority: .userInitiated) {
                        try MediaExporter.makeSeparateArchive(a, takes: takesForAudition, slate: slate)
                    }.value
                    if let clipArchiveURL {
                        await MainActor.run { store.setSeparateArchive(clipArchiveURL, for: a.id) }
                    }
                }

                switch format {
                case .combinedVideo:
                    hostedArtifactURL = videoURL
                case .separateZip:
                    hostedArtifactURL = clipArchiveURL
                case .headshotsOnly:
                    let baseName = (a.deliverableFileName(slate: slate) as NSString).deletingPathExtension
                    let photos = HeadshotStore.deliverables(baseName: baseName, auditionID: a.id)
                    guard !photos.isEmpty else { throw MediaExporter.ExportError.nothingToExport }
                    if asLink {
                        await MainActor.run { exportStage = .archiving; progress = 0.4 }
                        hostedArtifactURL = try await Task.detached(priority: .userInitiated) {
                            try MediaExporter.makeHeadshotsArchive(a, slate: slate)
                        }.value
                    }
                case .completePackage:
                    guard let videoURL else { throw MediaExporter.ExportError.nothingToExport }
                    if asLink {
                        await MainActor.run { exportStage = .archiving; progress = 0.68 }
                        hostedArtifactURL = try await Task.detached(priority: .userInitiated) {
                            try MediaExporter.makeCompletePackageArchive(
                                a, combinedVideoURL: videoURL, takes: takesForAudition, slate: slate
                            )
                        }.value
                    }
                }

                if asLink {
                    guard let hostedArtifactURL else { throw MediaExporter.ExportError.nothingToExport }
                    await MainActor.run {
                        exportStage = .uploading
                        uploading = true
                        progress = max(progress, 0.76)
                    }
                    let link = try await CloudLink.publish(hostedArtifactURL)
                    await MainActor.run {
                        store.setShareLink(link, for: a.id)
                        progress = 0.95
                        if UIApplication.shared.applicationState != .active,
                           UserDefaults.standard.object(forKey: "n.delivery") as? Bool ?? true {
                            Reminders.notifyNow(title: "Your link is ready", body: "\(a.project) — open OneTake to send it.")
                        }
                    }
                }

                await MainActor.run {
                    exportStage = .finalizing
                    progress = 1.0
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    Haptics.success()
                    phase = .readyToShare
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    phase = .failed
                    endUpload()
                }
            }
        }
    }

    private func shareItems(_ a: Audition) -> [Any]? {
        guard let deliverable = a.packageDeliverable else { return nil }
        let baseName = (a.deliverableFileName(slate: store.slate) as NSString).deletingPathExtension

        if a.destination == .emailOrLink {
            guard let link = a.shareLink else { return nil }
            let who = store.slate.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Self-tape" : store.slate.name
            return ["\(who) — \(a.role), \(a.project)", link]
        }

        var items: [Any] = []

        if a.destination == .email {
            items.append(a.emailBody(slate: store.slate))
        }

        switch deliverable {
        case .combinedVideo:
            guard let video = a.exportedFileURL else { return nil }
            items.append(video)
        case .separateZip:
            guard let zip = a.separateArchiveURL else { return nil }
            items.append(zip)
        case .headshotsOnly:
            let headshots = HeadshotStore.deliverables(baseName: baseName, auditionID: a.id)
            items.append(contentsOf: headshots)
            guard !headshots.isEmpty else { return nil }
        case .completePackage:
            guard let video = a.exportedFileURL, let zip = a.separateArchiveURL else { return nil }
            items.append(video)
            items.append(zip)
        }

        return items.isEmpty ? nil : items
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        phase = .review
        endUpload()
    }

    private func reportUpload(_ p: Double) {
        guard phase == .sending, let a = store.audition(auditionID), a.destination == .emailOrLink,
              p - reportedProgress >= 0.05 || p >= 1 else { return }
        reportedProgress = p
        LiveActivitySync.setUploadProgress(p, for: a)
    }

    private func endUpload() {
        guard reportedProgress >= 0, let a = store.audition(auditionID) else { return }
        reportedProgress = -1
        LiveActivitySync.setUploadProgress(nil, for: a)
    }
}

private struct PackageTrimTarget: Identifiable {
    enum Kind: String { case slate, fullLength }
    let kind: Kind
    let url: URL
    var id: String { kind.rawValue }
}
