import SwiftUI

// MARK: - 20 Package · Ready to send
//
// There's no casting-site API this app can submit a tape to directly, so "sending" is real:
// MediaExporter actually composes the slate, full-length and circled takes into one file, and
// handing it off happens through the system share sheet (AirDrop, Mail, Files, or the casting
// site's own upload if it's installed) — not a simulated network call that claims a third party
// confirmed receipt it never saw.

struct PackageView: View {
    enum Phase { case review, sending, readyToShare, failed, sent }
    enum ExportStage: Equatable {
        case composing
        case archiving
        case uploading
        case finalizing
    }

    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var phase: Phase = .review
    @State private var exportStage: ExportStage = .composing
    @State private var showDestination = false
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
    @State private var shareDeliverableOverride: PackageDeliverable? = nil
    @State private var showFileNameEditor = false

    var body: some View {
        if let a = store.audition(auditionID) {
            let deliverable = a.packageDeliverable ?? .combinedVideo
            Group {
                switch phase {
                case .review:  review(a)
                case .sending: SendProgressView(audition: a, progress: progress, exportStage: exportStage, uploading: uploading, onCancel: cancelExport)
                case .readyToShare:
                    DeliveryReadyView(
                        audition: a,
                        destination: a.destination,
                        deliverable: deliverable,
                        onShare: {
                            shareDeliverableOverride = nil
                            showShare = true
                        },
                        onShareAlternate: { alt in
                            shareDeliverableOverride = alt
                            showShare = true
                        },
                        onBack: { phase = .review }
                    )
                case .failed:  SendFailedView(message: exportErrorMessage, onRetry: send)
                case .sent:    SentView(audition: a, slate: store.slate) { store.popToRoot(); store.tab = .auditions }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: phase)
            .onChange(of: progress) { _, p in reportUpload(p) }
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showShare) {
                let targetDeliverable = shareDeliverableOverride ?? a.packageDeliverable ?? .combinedVideo
                if let items = shareItems(a, deliverableOverride: targetDeliverable) {
                    ShareSheet(items: items, subject: a.emailSubject(slate: store.slate)) { completed in
                        shareDeliverableOverride = nil
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
        let deliverable = a.packageDeliverable ?? .combinedVideo
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(backLabel: "Back", onBack: { store.pop() })
                    .padding(.top, 4)

                Text("Ready to send.").font(.otLargeTitle)
                Text("Due \(a.due.otDue) · \(a.readyCount) of \(a.totalCount) ready").font(.otCallout).foregroundStyle(OT.labelSecondary)

                HStack { SectionLabel(text: "On the tape, in order"); Spacer(); Text(totalDurationLabel(a)).font(.otHeadline) }
                TapeStrip(legend: legend)

                // 1. Deliverable Format (Combined Video, Separate ZIP, Photos, All)
                SectionLabel(text: "Deliverable Format").padding(.top, 4)
                deliverableFormatCard(a, current: deliverable)

                // 2. Submission Destination (Files, Email, Casting Sites)
                SectionLabel(text: "Submission Destination").padding(.top, 4)
                destinationCard(a)

                // 3. Notice Submission Specs & Validation
                SectionLabel(text: "Submission Specs & Validation").padding(.top, 4)
                submissionSpecsCard(a)

                // 4. Preview & Tape Check
                VStack(spacing: 0) {
                    Button { store.push(.preview(a.id)) } label: {
                        row(symbol: "play.rectangle", title: "Preview tape", detail: "Watch it and change a selected piece", value: nil)
                    }.buttonStyle(.plain)
                    Button { store.push(.tapeCheck(a.id)) } label: {
                        row(symbol: "checkmark.seal.fill", title: "Tape check", detail: "Picture and audio checks", value: "Review", tint: OT.success)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 140)
        }
        .safeAreaInset(edge: .bottom) {
            bottomSendBar(a, deliverable: deliverable)
        }
        .sheet(isPresented: $showDestination) { DestinationSheet(auditionID: a.id).presentationDetents([.medium, .large]) }
    }

    // MARK: - Deliverable Format Card
    private func deliverableFormatCard(_ a: Audition, current: PackageDeliverable) -> some View {
        VStack(spacing: 8) {
            ForEach(PackageDeliverable.allCases) { item in
                let isSelected = item == current
                Button {
                    if let binding = store.binding(for: a.id) {
                        binding.wrappedValue.packageDeliverable = item
                    }
                    Haptics.tick()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? OT.accent : OT.labelSecondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.rawValue)
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Spacer()
                                Text(sizeLabelForDeliverable(item, audition: a))
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(isSelected ? OT.accent : OT.labelTertiary)
                            }
                            Text(item.subtitle)
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                        }

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? OT.accent : OT.labelTertiary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? OT.accentSoft.opacity(0.3) : OT.fillField)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? OT.accent : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .otCard(radius: 18)
    }

    // MARK: - Destination Card
    private func destinationCard(_ a: Audition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: a.destination.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(a.destination.rawValue)
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                    Text(destinationSummary(a))
                        .font(.otCaption)
                        .foregroundStyle(OT.labelSecondary)
                }
                Spacer()
                Button {
                    showDestination = true
                } label: {
                    Text("Change")
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(OT.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Quick destination selector pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickDestinationPill(label: "Files / AirDrop", icon: "folder.fill", destination: .localFiles, current: a.destination)
                    quickDestinationPill(label: "Direct Email", icon: "envelope.fill", destination: .email, current: a.destination)
                    quickDestinationPill(label: "Actors Access", icon: "ticket.fill", destination: .actorsAccess, current: a.destination)
                    quickDestinationPill(label: "Backstage", icon: "theatermasks.fill", destination: .backstage, current: a.destination)
                    quickDestinationPill(label: "Hosted Link", icon: "link", destination: .emailOrLink, current: a.destination)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .otCard(radius: 18)
    }

    private func quickDestinationPill(label: String, icon: String, destination: Destination, current: Destination) -> some View {
        let isSelected = destination == current
        return Button {
            if let binding = store.binding(for: auditionID) {
                binding.wrappedValue.destination = destination
            }
            Haptics.tick()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.otCaption.weight(.medium))
            }
            .foregroundStyle(isSelected ? OT.labelOnAccent : OT.labelSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? AnyShapeStyle(OT.accent) : AnyShapeStyle(OT.fillField), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func destinationSummary(_ a: Audition) -> String {
        switch a.destination {
        case .email:
            let to = a.castingEmail ?? "Casting Office"
            return "To: \(to) · Subject: \(a.emailSubject(slate: store.slate))"
        case .localFiles:
            return "Save .mp4, .zip or photos directly to Files app or AirDrop to computer."
        case .actorsAccess:
            return "Formatted for Actors Access Eco Cast submission (under 500 MB)."
        case .backstage:
            return "Formatted for Backstage application video upload."
        case .castingNetworks:
            return "Formatted for Casting Networks media bank (up to 300 MB)."
        case .spotlight:
            return "Formatted for Spotlight UK / International tape submission."
        case .emailOrLink:
            return "Generates shareable hosted link for Google Drive, YouTube, or application forms."
        }
    }

    // MARK: - Submission Assistant & Validation Specs Card
    private func submissionSpecsCard(_ a: Audition) -> some View {
        let deliverable = a.packageDeliverable ?? .combinedVideo
        let slate = store.slate
        let fileName = deliverable == .separateZip ? separateArchiveName(a) : a.deliverableFileName(slate: slate)
        let hasCustomTemplate = a.submissionInstructions?.fileNameTemplate?.isEmpty == false

        return VStack(alignment: .leading, spacing: 8) {
            // Tappable filename row — opens the name template editor
            Button {
                showFileNameEditor = true
            } label: {
                HStack {
                    Label("Filename:", systemImage: "doc.text")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelTertiary)
                    if hasCustomTemplate {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(OT.accent)
                    }
                    Spacer()
                    Text(fileName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(OT.labelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OT.labelTertiary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFileNameEditor) {
                FileNameTemplateSheet(auditionID: a.id)
                    .environment(store)
            }

            Divider()

            HStack {
                Label("Format:", systemImage: "gearshape")
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelTertiary)
                Spacer()
                Text(deliverable == .separateZip ? "ZIP Archive (H.264 clips + JPEG)" : "H.264 · 1080p MP4")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
            }

            Divider()

            HStack {
                Label("Duration:", systemImage: "clock")
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelTertiary)
                Spacer()
                Text("\(totalDurationLabel(a)) (Under 2 min max)")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.success)
            }

            Divider()

            HStack {
                Label("File Size:", systemImage: "arrow.down.circle")
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelTertiary)
                Spacer()
                Text("\(sizeLabelForDeliverable(deliverable, audition: a)) (Well under 500 MB limit)")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.success)
            }

            Divider()

            HStack {
                Label("Slate:", systemImage: "person.crop.rectangle")
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelTertiary)
                Spacer()
                Text(a.slateVideoURL != nil ? "Recorded & included at start" : "Optional / Separate")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(a.slateVideoURL != nil ? OT.success : OT.labelSecondary)
            }
        }
        .padding(14)
        .otCard(radius: 18)
    }

    private func sizeLabelForDeliverable(_ deliverable: PackageDeliverable, audition a: Audition) -> String {
        switch deliverable {
        case .combinedVideo:
            return exportedSizeLabel(a)
        case .separateZip:
            return separateZipSizeLabel(a)
        case .headshotsOnly:
            let count = HeadshotStore.taken(auditionID: a.id).count
            return "\(count) photo\(count == 1 ? "" : "s")"
        case .completePackage:
            return "\(exportedSizeLabel(a)) + ZIP"
        }
    }

    private func bottomSendBar(_ a: Audition, deliverable: PackageDeliverable) -> some View {
        VStack(spacing: 4) {
            Button { send() } label: {
                HStack(spacing: 8) {
                    Image(systemName: sendButtonIcon(a))
                    Text(sendButtonTitle(a, deliverable: deliverable))
                }
                .font(.otHeadline)
            }
            .buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OT.gutter)
        .background(OT.bgCanvas)
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
            return "Create Hosted Share Link"
        }
    }

    private func row(symbol: String, title: String, detail: String?, value: String?, tint: Color = OT.labelSecondary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.otBody).lineLimit(1)
                if let detail { Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary) }
            }
            Spacer()
            if let value { Text(value).font(.otFootnote).foregroundStyle(OT.labelSecondary) }
            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) { Divider() }
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

    private func totalDurationLabel(_ a: Audition) -> String {
        let takes = store.takes.filter { $0.auditionID == a.id && $0.isCircled }
        guard !takes.isEmpty else { return "—" }
        let total = Int(takes.reduce(0) { $0 + $1.duration })
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func exportedSizeLabel(_ a: Audition) -> String {
        guard let url = a.exportedFileURL, let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return "~\(estimatedSizeMB(a)) MB"
        }
        return "\(size / 1_048_576) MB"
    }

    private func separateZipSizeLabel(_ a: Audition) -> String {
        guard let url = a.separateArchiveURL, let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return "~\(Int(Double(estimatedSizeMB(a)) * 1.1)) MB"
        }
        return "\(size / 1_048_576) MB"
    }

    private func estimatedSizeMB(_ a: Audition) -> Int {
        let takes = store.takes.filter { $0.auditionID == a.id && $0.isCircled }
        let totalSeconds = takes.reduce(0.0) { $0 + $1.duration }
        let estimated = max(8, Int(totalSeconds * 1.5))
        return estimated
    }

    /// Real export, not a simulated upload: `MediaExporter` composes the actual recorded files, and
    /// only once that succeeds does the share sheet open so the real file can actually go somewhere.
    private func send() {
        guard let a = store.audition(auditionID) else { return }
        // A submission link is the one thing that needs an account — the actor's own iCloud. File
        // hand-offs to the casting sites never do.
        let asLink = a.destination == .emailOrLink
        // Account first (Apple or Google), then iCloud, which hosts the file.
        if asLink && store.account == nil {
            // In a build without either capability there is no sign-in screen that could help;
            // say so here instead of presenting a dead end.
            guard AccountAuth.canSignIn else {
                exportErrorMessage = "Sending a link needs an Apple or Google account, and sign-in isn't set up in this build. Choose Files or a casting site to hand over the tape instead."
                phase = .failed
                return
            }
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
        exportStage = .composing
        exportErrorMessage = nil
        let takesForAudition = store.takes.filter { $0.auditionID == a.id }
        let slate = store.slate
        exportTask?.cancel()
        exportTask = Task {
            do {
                // Stage 1: Composing video file (0% to 75% for files, 0% to 55% for link)
                let videoWeight = asLink ? 0.55 : 0.75
                let url = try await MediaExporter.export(a, takes: takesForAudition, slate: slate) { p in
                    Task { @MainActor in
                        progress = min(videoWeight, p * videoWeight)
                    }
                }

                // Stage 2: Archiving separate clips & headshots
                await MainActor.run {
                    exportStage = .archiving
                    progress = videoWeight + 0.05
                }
                let archiveURL = try MediaExporter.makeSeparateArchive(a, takes: takesForAudition, slate: slate)
                await MainActor.run {
                    store.setExportedFile(url, for: a.id)
                    store.setSeparateArchive(archiveURL, for: a.id)
                    progress = asLink ? 0.75 : 0.95
                }

                // Stage 3 (if link): Uploading to iCloud
                if asLink {
                    await MainActor.run {
                        exportStage = .uploading
                        uploading = true
                        progress = 0.80
                    }
                    let link = try await CloudLink.publish(url)
                    await MainActor.run {
                        store.setShareLink(link, for: a.id)
                        progress = 0.95
                        // Uploads can take minutes; if the actor wandered off, tell them it's ready.
                        if UIApplication.shared.applicationState != .active,
                           UserDefaults.standard.object(forKey: "n.delivery") as? Bool ?? true {
                            Reminders.notifyNow(title: "Your link is ready", body: "\(a.project) — open OneTake to send it.")
                        }
                    }
                }

                // Stage 4: Finalizing & smooth completion
                await MainActor.run {
                    exportStage = .finalizing
                    progress = 1.0
                }
                // Brief pause so the user sees 100% and success state before transitioning
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    Haptics.success()
                    phase = .readyToShare
                }
            } catch is CancellationError {
                // Cancelled from the progress screen — cancelExport() already returned to review.
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    phase = .failed
                    endUpload()
                }
            }
        }
    }

    /// What the share sheet hands on: the chosen deliverable (single video, separate clips ZIP, photos, or full package).
    private func shareItems(_ a: Audition, deliverableOverride: PackageDeliverable? = nil) -> [Any]? {
        let deliverable = deliverableOverride ?? a.packageDeliverable ?? .combinedVideo
        let baseName = (a.deliverableFileName(slate: store.slate) as NSString).deletingPathExtension

        if a.destination == .emailOrLink, deliverable == .combinedVideo {
            if let link = a.shareLink {
                let who = store.slate.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Self-tape" : store.slate.name
                return ["\(who) — \(a.role), \(a.project)", link]
            }
        }

        var items: [Any] = []

        if a.destination == .email {
            items.append(a.emailBody(slate: store.slate))
        }

        switch deliverable {
        case .combinedVideo:
            if let video = a.exportedFileURL {
                items.append(video)
            } else if let link = a.shareLink {
                items.append(link)
            }
        case .separateZip:
            if let zip = a.separateArchiveURL {
                items.append(zip)
            } else if let video = a.exportedFileURL {
                items.append(video)
            }
        case .headshotsOnly:
            let headshots = HeadshotStore.deliverables(baseName: baseName, auditionID: a.id)
            items.append(contentsOf: headshots)
            if items.isEmpty, let zip = a.separateArchiveURL {
                items.append(zip)
            }
        case .completePackage:
            if let video = a.exportedFileURL { items.append(video) }
            if let zip = a.separateArchiveURL { items.append(zip) }
            let headshots = HeadshotStore.deliverables(baseName: baseName, auditionID: a.id)
            items.append(contentsOf: headshots)
        }

        if items.isEmpty {
            if let video = a.exportedFileURL { items.append(video) }
            if let zip = a.separateArchiveURL { items.append(zip) }
            if let link = a.shareLink { items.append(link) }
        }

        return items.isEmpty ? nil : items
    }

    private func separateArchiveName(_ a: Audition) -> String {
        if let url = a.separateArchiveURL { return url.lastPathComponent }
        let base = (a.deliverableFileName(slate: store.slate) as NSString).deletingPathExtension
        return "\(base)_SEPARATE.zip"
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        phase = .review
        endUpload()
    }

    /// Link sends show their progress in the Dynamic Island / Lock Screen, so the actor can leave
    /// the app while a big tape uploads.
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

struct TapeStrip: View {
    let legend: [(String, String, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        RoundedRectangle(cornerRadius: 6).fill(item.2).frame(width: max(10, geo.size.width / CGFloat(max(legend.count, 1)) - 3))
                    }
                }
            }
            .frame(height: 44)
            HStack(spacing: 14) {
                ForEach(Array(legend.enumerated()), id: \.offset) { _, item in legendItem(item.0, item.1, item.2) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tape order: " + legend.map { "\($0.0), \($0.1)" }.joined(separator: ", "))
    }

    private func legendItem(_ t: String, _ d: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8); Text(t).font(.otCaption.weight(.semibold)) }
            Text(d).font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
    }
}

// MARK: - 20.1 / 20.2 Where is it going?

struct DestinationSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Where’s it going?", backLabel: "Done", onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 16)

            if let audition = store.binding(for: auditionID) {
                let current = audition.wrappedValue.destination
                List {
                    Section("Destination & Submission Method") {
                        ForEach(Destination.allCases) { d in
                            destinationRow(for: d, isSelected: current == d) {
                                audition.wrappedValue.destination = d
                                Haptics.tick()
                            }
                        }
                    }

                    Section {
                        TextField(
                            current == .email ? "Casting email address (e.g. casting@production.com)" :
                            current == .emailOrLink ? "Hosted link (Google Drive / YouTube / Vimeo / iCloud)" :
                            "\(current.rawValue) account or submission notes",
                            text: destinationDetailBinding(for: audition)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(current == .email ? .emailAddress : .default)
                    } header: {
                        Text(current == .email ? "Casting Recipient Email" : "Details & Notes")
                    } footer: {
                        Text(current == .email ? "We automatically format the cover email, subject line, and attach your chosen deliverable." :
                             current == .localFiles ? "Export directly to your iPhone Files app, AirDrop to your computer, or copy to cloud storage." :
                             "We match the file name and specifications each platform asks for.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .otCanvas()
    }

    @ViewBuilder
    private func destinationRow(for d: Destination, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: d.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? OT.accent : OT.labelSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(d.rawValue).font(.otBody)
                    Text(d.spec).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    if d == .emailOrLink {
                        Text(linkStatus.text).font(.otFootnote).foregroundStyle(linkStatus.color)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OT.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(d == .emailOrLink && !AccountAuth.canSignIn)
        .opacity(d == .emailOrLink && !AccountAuth.canSignIn ? 0.55 : 1)
    }

    private func destinationDetailBinding(for audition: Binding<Audition>) -> Binding<String> {
        Binding(
            get: {
                if let detail = audition.wrappedValue.destinationDetail, !detail.isEmpty {
                    return detail
                }
                if let email = audition.wrappedValue.castingEmail {
                    return email
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                audition.wrappedValue.destinationDetail = trimmed.isEmpty ? nil : trimmed
                if !trimmed.isEmpty && trimmed.contains("@") {
                    audition.wrappedValue.asks.removeAll { $0.hasPrefix("Email: ") }
                    audition.wrappedValue.asks.append("Email: \(trimmed)")
                }
            }
        )
    }

    private var linkStatus: (text: String, color: Color) {
        if !AccountAuth.canSignIn {
            return ("Not available in this build — needs Apple or Google sign-in", OT.warning)
        }
        if !CloudLink.isAvailable {
            return ("Needs iCloud — sign in from Settings", OT.warning)
        }
        return ("Uploads to your iCloud Drive", OT.labelTertiary)
    }
}

// MARK: - 20.3 Exporting

struct SendProgressView: View {
    let audition: Audition
    let progress: Double
    var exportStage: PackageView.ExportStage = .composing
    var uploading = false
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Packaging your tape").padding(.top, 20)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(progress * 100))").font(.system(size: 72, weight: .bold)).monospacedDigit()
                Text("%").font(.otTitle)
                Spacer()
                if progress < 1.0 {
                    ProgressView()
                        .tint(OT.accent)
                        .scaleEffect(1.1)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(OT.success)
                }
            }
            ProgressView(value: min(1.0, max(0.0, progress))).tint(OT.accent)

            Text(statusMessage)
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)
                .padding(.top, 2)

            SectionLabel(text: "Steps").padding(.top, 8)
            step("Found your recorded pieces", done: true, active: false)
            step("Composing main audition video",
                 done: exportStage != .composing,
                 active: exportStage == .composing)
            step("Archiving separate clips & headshots",
                 done: exportStage == .uploading || exportStage == .finalizing || progress >= 1.0,
                 active: exportStage == .archiving)
            if audition.destination == .emailOrLink {
                step("Uploading to your iCloud",
                     done: exportStage == .finalizing || progress >= 1.0,
                     active: exportStage == .uploading)
            }
            step("Tape ready", done: progress >= 1.0, active: exportStage == .finalizing)
            Spacer()
            Button("Cancel", action: onCancel).buttonStyle(.otSecondary)
        }
        .padding(.horizontal, OT.gutter)
    }

    private var statusMessage: String {
        switch exportStage {
        case .composing:
            return "Combining chosen takes and slate into one deliverable video..."
        case .archiving:
            return "Packaging individual clips and headshots into deliverable ZIP..."
        case .uploading:
            return "Uploading your package to iCloud..."
        case .finalizing:
            return "Finalizing delivery package..."
        }
    }

    private func step(_ t: String, done: Bool, active: Bool = false) -> some View {
        HStack(spacing: 10) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OT.success)
            } else if active {
                ProgressView()
                    .controlSize(.small)
                    .tint(OT.accent)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(OT.labelTertiary)
            }
            Text(t).font(.otBody).foregroundStyle(done || active ? OT.labelPrimary : OT.labelTertiary)
        }
        .frame(minHeight: 36)
    }
}

/// Export finishes here: allows the actor to share the chosen deliverable (video, ZIP, photos),
/// or switch to alternate formats and copy email details without re-recording or going back.
struct DeliveryReadyView: View {
    let audition: Audition
    let destination: Destination
    let deliverable: PackageDeliverable
    var onShare: () -> Void
    var onShareAlternate: (PackageDeliverable) -> Void
    var onBack: () -> Void

    @State private var copiedNoticeToast: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(OT.success)
                    Text("Your tape is ready.").font(.otLargeTitle)
                    Text(readySubtitle)
                        .font(.otSubhead)
                        .foregroundStyle(OT.labelSecondary)
                }
                .padding(.top, 24)

                // Deliverable Summary Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: deliverable.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(OT.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deliverable.rawValue)
                                .font(.otHeadline)
                            Text(deliverable.subtitle)
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }

                    Divider()

                    HStack {
                        Label(destination.rawValue, systemImage: destination.icon)
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.labelPrimary)
                        Spacer()
                        if destination == .email, let email = audition.castingEmail {
                            Text(email).font(.otCaption).foregroundStyle(OT.accent)
                        }
                    }
                }
                .padding(16)
                .otCard(radius: 18)

                // Primary Action Button
                Button {
                    onShare()
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                        .font(.otHeadline)
                }
                .buttonStyle(.otPrimary)

                // Alternate formats quick export
                SectionLabel(text: "Also Available to Share")
                VStack(spacing: 8) {
                    if deliverable != .separateZip {
                        Button {
                            onShareAlternate(.separateZip)
                        } label: {
                            HStack {
                                Label("Share Separate Clips (.zip)", systemImage: "doc.zipper")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.otBody)
                            .padding(14)
                            .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    if deliverable != .combinedVideo {
                        Button {
                            onShareAlternate(.combinedVideo)
                        } label: {
                            HStack {
                                Label("Share Combined Video (.mp4)", systemImage: "film")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.otBody)
                            .padding(14)
                            .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    if deliverable != .headshotsOnly {
                        Button {
                            onShareAlternate(.headshotsOnly)
                        } label: {
                            HStack {
                                Label("Share Headshots / Photos", systemImage: "photo.on.rectangle")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.otBody)
                            .padding(14)
                            .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    if destination == .email {
                        Button {
                            let text = audition.emailBody(slate: SlateInfo())
                            UIPasteboard.general.string = text
                            copiedNoticeToast = true
                            Haptics.tick()
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                copiedNoticeToast = false
                            }
                        } label: {
                            HStack {
                                Label(copiedNoticeToast ? "Copied Cover Letter!" : "Copy Cover Letter Text", systemImage: copiedNoticeToast ? "checkmark" : "doc.on.doc")
                                Spacer()
                            }
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(copiedNoticeToast ? OT.success : OT.accent)
                            .padding(12)
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 20)

                Button("Back to package", action: onBack).buttonStyle(.otSecondary)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 40)
        }
    }

    private var readySubtitle: String {
        switch destination {
        case .email:
            return "Prepared for direct email to \(audition.castingOffice.isEmpty ? "casting" : audition.castingOffice)."
        case .localFiles:
            return "Ready to save to your iPhone Files or AirDrop to your computer."
        case .actorsAccess:
            return "Formatted for Actors Access Eco Cast submission."
        case .backstage:
            return "Formatted for Backstage application upload."
        case .castingNetworks:
            return "Formatted for Casting Networks submission."
        case .spotlight:
            return "Formatted for Spotlight submission."
        case .emailOrLink:
            return "Hosted and ready to share via link."
        }
    }

    private var primaryButtonTitle: String {
        switch destination {
        case .email: return "Send via Email"
        case .localFiles: return "Save to Files / AirDrop"
        default: return "Share \(deliverable.shortTitle)"
        }
    }

    private var primaryButtonIcon: String {
        switch destination {
        case .email: return "envelope.fill"
        case .localFiles: return "folder.fill"
        default: return "square.and.arrow.up"
        }
    }
}

// MARK: - 20.4 Couldn't export

struct SendFailedView: View {
    let message: String?
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(OT.warning).padding(.top, 20)
            Text("Couldn't package it").font(.otLargeTitle)
            Text(message ?? "Something went wrong composing your tape. Your takes are untouched on this iPhone — this only affects the combined file.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            Spacer()
            Button("Try again", action: onRetry).buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OT.gutter)
    }
}

// MARK: - 21 Sent

struct SentView: View {
    let audition: Audition
    let slate: SlateInfo
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SHARED · \(sentDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()).uppercased())")
                        .font(.otCaption.weight(.semibold)).foregroundStyle(OT.success)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(OT.success)
                }
                Text("Merged video · \(audition.deliverableFileName(slate: slate))")
                    .font(.otFootnote.weight(.semibold)).lineLimit(2)
                Text("Separate clips · \(separateArchiveName)")
                    .font(.otFootnote).foregroundStyle(OT.labelSecondary).lineLimit(2)
                Text(audition.scenes.isEmpty
                     ? "No scripted scenes"
                     : "\(audition.scenes.count) scene\(audition.scenes.count == 1 ? "" : "s")")
                    .font(.otCaption).foregroundStyle(OT.labelTertiary)
            }
            .padding(16).otCard(radius: 18).rotationEffect(.degrees(1.5)).padding(.top, 30)

            Text(audition.destination == .emailOrLink ? "Your link is ready." : "Shared for \(audition.destination.rawValue).")
                .font(.system(size: 38, weight: .bold))
            HStack(alignment: .firstTextBaseline) {
                Text(earlyText).font(.otTitle).foregroundStyle(OT.success)
                Text("Break a leg.").font(.otHeadline).foregroundStyle(OT.labelSecondary)
            }
            if audition.destination == .emailOrLink, let expires = audition.shareLinkExpires, audition.shareLink != nil {
                Label("Link shared · works until \(expires.formatted(date: .abbreviated, time: .omitted))", systemImage: "link").font(.otFootnote).foregroundStyle(OT.labelSecondary)
            } else {
                Label("Handed off through your Share Sheet to \(audition.destination.rawValue)", systemImage: "square.and.arrow.up").font(.otFootnote).foregroundStyle(OT.labelSecondary)
            }
            Label("All your takes stay here if they ask for another", systemImage: "iphone").font(.otFootnote).foregroundStyle(OT.labelSecondary)
            Spacer()
            Button("Done", action: onDone).buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OT.gutter)
        .onAppear { Haptics.success() }
    }

    private var earlyText: String {
        let h = max(0, Int(audition.due.timeIntervalSince(sentDate) / 3600))
        return h >= 1 ? "\(h) hours early." : "Right on time."
    }

    private var sentDate: Date { audition.sentDate ?? .now }

    private var separateArchiveName: String {
        if let url = audition.separateArchiveURL { return url.lastPathComponent }
        let base = (audition.deliverableFileName(slate: slate) as NSString).deletingPathExtension
        return "\(base)_SEPARATE.zip"
    }
}

// MARK: - Filename Template Editor Sheet

/// A bottom sheet that lets the actor override the deliverable filename pattern for a specific
/// audition. Supports {firstName}, {lastName}, {name}, {role}, {project}, {side}, {scene}, {take}.
/// Leaving the field blank reverts to the app default (`LAST_FIRST_ROLE_PROJECT.mp4`).
private struct FileNameTemplateSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""

    private let tokens = ["{firstName}", "{lastName}", "{name}", "{role}", "{project}", "{side}", "{scene}", "{take}"]

    private var audition: Audition? { store.audition(auditionID) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Match Casting's Instructions")
                        .font(.otHeadline)
                    Text("Enter the exact filename pattern casting asked for. Use tokens for the parts that vary. Leave blank to use the OneTake default.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }

                // Template text field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pattern")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.labelTertiary)
                    TextField(
                        "{lastName}_{firstName}_{role}_{project}",
                        text: $draft,
                        axis: .vertical
                    )
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(OT.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if !draft.isEmpty {
                        Text("Preview: \(previewName)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OT.accent)
                            .lineLimit(2)
                    }
                }

                // Token chips
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available tokens — tap to insert")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(tokens, id: \.self) { token in
                            Button {
                                draft += (draft.isEmpty ? "" : "_") + token
                            } label: {
                                Text(token)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(OT.accent.opacity(0.12))
                                    .foregroundStyle(OT.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                // Reset button
                if audition?.submissionInstructions?.fileNameTemplate?.isEmpty == false {
                    Button(role: .destructive) {
                        store.setFileNameTemplate(nil, for: auditionID)
                        dismiss()
                    } label: {
                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 24)
            .navigationTitle("Filename Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setFileNameTemplate(draft.isEmpty ? nil : draft, for: auditionID)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                draft = audition?.submissionInstructions?.fileNameTemplate ?? ""
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var previewName: String {
        guard let a = audition else { return draft }
        let slate = store.slate
        // Build a fake submissionInstructions with the current draft as the template
        var mockInstructions = AuditionSubmissionInstructions()
        mockInstructions.fileNameTemplate = draft
        var mockAudition = a
        mockAudition.submissionInstructions = mockInstructions
        return mockAudition.deliverableFileName(slate: slate)
    }
}
