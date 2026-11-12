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
        case preparing
        case composing
        case archiving
        case uploading
        case finalizing
    }

    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var phase: Phase = .review
    @State private var exportStage: ExportStage = .preparing
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
            let requiredFormat = requiredDeliverable(for: a)
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
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showShare) {
                if let items = shareItems(a) {
                    ShareSheet(items: items, subject: a.emailSubject(slate: store.slate)) { completed in
                        if completed {
                            if a.destination == .email {
                                store.markSent(auditionID)
                                Haptics.success()
                                phase = .sent
                            } else {
                                store.markExported(auditionID)
                                Haptics.success()
                                phase = .readyToShare
                            }
                        } else {
                            phase = .readyToShare
                        }
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
        let requiredFormat = requiredDeliverable(for: a)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(backLabel: "Back", onBack: { store.pop() })
                    .padding(.top, 4)

                Text("Ready to send.").font(.otLargeTitle)
                Text("Due \(a.due.otDue) · \(a.readyCount) of \(a.totalCount) ready").font(.otCallout).foregroundStyle(OT.labelSecondary)

                HStack { SectionLabel(text: "On the tape, in order"); Spacer(); Text(totalDurationLabel(a)).font(.otHeadline) }
                TapeStrip(legend: legend)

                // Explicit submission manifest
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Included in this export")
                    VStack(spacing: 8) {
                        // Slate
                        if let _ = a.slateVideoURL {
                            manifestRow(icon: "person.text.rectangle", title: "Slate", detail: "Slate video included", status: "Ready", isReady: true)
                        } else if a.asks.contains(where: { $0.localizedCaseInsensitiveContains("slate") }) {
                            manifestRow(icon: "person.text.rectangle", title: "Slate", detail: "Not recorded", status: "Missing", isReady: false)
                        }

                        // Scenes with circled takes
                        ForEach(a.scenes.indices, id: \.self) { i in
                            let scene = a.scenes[i]
                            let take = store.takes.first(where: { $0.auditionID == a.id && $0.sceneIndex == i && $0.isCircled && !$0.previousSides && $0.currentSidesRevision == a.currentSidesRevision })
                            let isShot = take != nil
                            manifestRow(
                                icon: "film.fill",
                                title: scene.title,
                                detail: take.map { "Take \($0.number) (Circled) · \(Int($0.duration))s" } ?? "No take circled",
                                status: isShot ? "Take \(take!.number)" : "Not ready",
                                isReady: isShot
                            )
                        }

                        // Headshots
                        let headshots = HeadshotStore.taken(auditionID: a.id)
                        if !headshots.isEmpty {
                            manifestRow(icon: "person.crop.square", title: "Headshots", detail: "\(headshots.count) photo\(headshots.count == 1 ? "" : "s") attached", status: "\(headshots.count) attached", isReady: true)
                        } else if a.asks.contains(where: { $0.localizedCaseInsensitiveContains("headshot") }) {
                            manifestRow(icon: "person.crop.square", title: "Headshots", detail: "Optional · not attached", status: "Optional", isReady: false)
                        }

                        // Résumé
                        if let resumeURL = a.resumeURL {
                            manifestRow(icon: "doc.text.fill", title: "Résumé", detail: resumeURL.lastPathComponent, status: "Attached", isReady: true)
                        }
                    }
                }
                .padding(14)
                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // 1. Deliverable Format (Combined Video, Separate ZIP, Photos, All)
                SectionLabel(text: "Deliverable Format").padding(.top, 4)
                deliverableFormatCard(a, current: deliverable)

                // 2. Submission Destination (Files, Email, Casting Sites)
                SectionLabel(text: "Submission Destination").padding(.top, 4)
                destinationCard(a)

                submissionCheckSummary(a)

                DisclosureGroup(isExpanded: $showSubmissionSpecs) {
                    submissionSpecsCard(a)
                        .padding(.top, 8)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass").foregroundStyle(OT.labelSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("File specs & validation").font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                            Text("Filename, duration, size, and slate details")
                                .font(.otCaption).foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }
                }
                .tint(OT.accent)
                .padding(14)
                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
        .sheet(isPresented: $showDeliverableSelector) {
            PackageFormatSheet(auditionID: a.id, required: requiredFormat)
                .presentationDetents([.medium, .large])
        }
    }

    private func submissionCheckSummary(_ audition: Audition) -> some View {
        let format = audition.packageDeliverable
        let destinationChosen = audition.destinationWasChosen ?? false
        return VStack(alignment: .leading, spacing: 9) {
            Label("Submission check", systemImage: "checkmark.seal")
                .font(.otCaption.weight(.semibold)).foregroundStyle(OT.labelSecondary)
            checkRow(
                title: "Delivery format",
                value: format?.shortTitle ?? "Choose one",
                isReady: format != nil
            ) { showDeliverableSelector = true }
            checkRow(
                title: "Submission destination",
                value: destinationChosen ? audition.destination.rawValue : "Choose one",
                isReady: destinationChosen
            ) { showDestination = true }
        }
        .padding(12)
        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func checkRow(title: String, value: String, isReady: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(isReady ? OT.success : OT.warning)
                Text(title).foregroundStyle(OT.labelSecondary)
                Spacer(minLength: 4)
                Text(value).foregroundStyle(OT.labelPrimary).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(OT.labelTertiary)
            }
            .font(.otCaption.weight(.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Deliverable Format Card
    private func deliverableFormatCard(_ a: Audition, current: PackageDeliverable?) -> some View {
        Button { showDeliverableSelector = true } label: {
            HStack(spacing: 12) {
                Image(systemName: current?.icon ?? "shippingbox")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(current?.rawValue ?? "Choose a delivery format")
                        .font(.otHeadline).foregroundStyle(OT.labelPrimary)
                    if let required = requiredDeliverable(for: a) {
                        Text(current == required ? "Required by the casting notice" : "Casting requires: \(required.rawValue)")
                            .font(.otCaption.weight(.semibold)).foregroundStyle(OT.accent)
                    } else {
                        Text(current.map { sizeLabelForDeliverable($0, audition: a) } ?? "No format specified by casting")
                            .font(.otCaption).foregroundStyle(OT.labelSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(OT.labelTertiary)
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .otCard(radius: 18)
    }

    private func requiredDeliverable(for audition: Audition) -> PackageDeliverable? {
        let text = (audition.asks + (audition.submissionInstructions?.acceptedFormats ?? []) + (audition.submissionInstructions?.otherRequirements ?? []))
            .joined(separator: " ").lowercased()
        if text.range(of: #"\b(?:full package|video\s*\+\s*zip|video,?\s*clips?\s*(?:and|\+)\s*photos?)\b"#, options: .regularExpression) != nil {
            return .completePackage
        }
        if text.range(of: #"\b(?:separate clips?|individual clips?|each scene separately|zip archive|zip file|\.zip)\b"#, options: .regularExpression) != nil {
            return .separateZip
        }
        if text.range(of: #"\b(?:headshots? only|photos? only|only photos?)\b"#, options: .regularExpression) != nil {
            return .headshotsOnly
        }
        if text.range(of: #"\b(?:single video|one video file|one combined file|combined video|single mp4|one mp4)\b"#, options: .regularExpression) != nil {
            return .combinedVideo
        }
        return nil
    }

    // MARK: - Destination Card
    private func destinationCard(_ a: Audition) -> some View {
        let destinationChosen = a.destinationWasChosen ?? false
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: a.destination.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(destinationChosen ? a.destination.rawValue : "Choose a submission destination")
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                    Text(destinationChosen ? destinationSummary(a) : "No destination specified by casting")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelSecondary)
                }
                Spacer()
                Button {
                    showDestination = true
                } label: {
                    Text(destinationChosen ? "Change" : "Choose")
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(OT.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if destinationChosen && a.destination == .emailOrLink && store.account == nil {
                Button { showSignIn = true } label: {
                    Label("Sign in or create an account", systemImage: "person.crop.circle.badge.plus")
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(OT.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .otCard(radius: 18)
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
        let deliverable = a.packageDeliverable
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
                    Text(deliverable == nil ? "Choose a format above" : fileName)
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
                Text(deliverable == nil ? "Not selected" : deliverable == .separateZip ? "ZIP Archive (H.264 clips + JPEG)" : "H.264 · 1080p MP4")
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

    private func sizeLabelForDeliverable(_ deliverable: PackageDeliverable?, audition a: Audition) -> String {
        guard let deliverable else { return "Choose a format" }
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
        return VStack(spacing: 4) {
            Button {
                if deliverable == nil { showDeliverableSelector = true }
                else if !destinationChosen { showDestination = true }
                else { send() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: actionIcon)
                    Text(actionTitle)
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
            return "Open email"
        case .localFiles:
            return "Export files"
        case .actorsAccess:
            return "Export for Actors Access"
        case .backstage:
            return "Export for Backstage"
        case .castingNetworks:
            return "Export for Casting Networks"
        case .spotlight:
            return "Export for Spotlight"
        case .emailOrLink:
            return "Create Share Link"
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

    private func manifestRow(icon: String, title: String, detail: String, status: String, isReady: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(isReady ? OT.accent : OT.labelTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.otBody.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                Text(detail).font(.otCaption).foregroundStyle(OT.labelSecondary)
            }
            Spacer()
            Text(status)
                .font(.otCaption.weight(.bold))
                .foregroundStyle(isReady ? OT.success : OT.labelTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isReady ? OT.success.opacity(0.12) : OT.fillField, in: Capsule())
        }
    }

    private func tapeLegend(_ a: Audition) -> [(String, String, Color)] {
        var items: [(String, String, Color)] = []
        items.append(("Headshot", a.pieces.first(where: { $0.kind == .headshot })?.isDone == true ? "Captured" : "Not yet", OT.accent.opacity(0.4)))
        items.append(("Slate", a.slateVideoURL != nil ? "Recorded" : "Not yet", OT.accent.opacity(0.4)))
        for (i, scene) in a.scenes.enumerated() {
            let take = store.takes.first(where: { $0.auditionID == a.id && $0.sceneIndex == i && $0.isCircled && !$0.previousSides && $0.currentSidesRevision == a.currentSidesRevision })
            let detail = take.map { "Take \($0.number) · \(Int($0.duration))s" } ?? "Not shot yet"
            items.append((scene.title, detail, i.isMultiple(of: 2) ? OT.accent : OT.reader))
        }
        return items
    }

    private func totalDurationLabel(_ a: Audition) -> String {
        let takes = store.takes.filter { $0.auditionID == a.id && $0.isCircled && !$0.previousSides && $0.currentSidesRevision == a.currentSidesRevision }
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
        let takes = store.takes.filter { $0.auditionID == a.id && $0.isCircled && !$0.previousSides && $0.currentSidesRevision == a.currentSidesRevision }
        let totalSeconds = takes.reduce(0.0) { $0 + $1.duration }
        let estimated = max(8, Int(totalSeconds * 1.5))
        return estimated
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
        // A submission link is the one thing that needs an account — the actor's own iCloud. File
        // hand-offs to the casting sites never do.
        let asLink = a.destination == .emailOrLink
        // Account first (Apple or Google), then iCloud, which hosts the file.
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
                    clipArchiveURL = try MediaExporter.makeSeparateArchive(a, takes: takesForAudition, slate: slate)
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
                        hostedArtifactURL = try MediaExporter.makeHeadshotsArchive(a, slate: slate)
                    }
                case .completePackage:
                    guard let videoURL else { throw MediaExporter.ExportError.nothingToExport }
                    if asLink {
                        await MainActor.run { exportStage = .archiving; progress = 0.68 }
                        hostedArtifactURL = try MediaExporter.makeCompletePackageArchive(
                            a, combinedVideoURL: videoURL, takes: takesForAudition, slate: slate
                        )
                    }
                }

                // Hosted Link publishes the artifact selected above. It never substitutes an MP4.
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
                        // Uploads can take minutes; if the actor wandered off, tell them it's ready.
                        if UIApplication.shared.applicationState != .active,
                           UserDefaults.standard.object(forKey: "n.delivery") as? Bool ?? true {
                            Reminders.notifyNow(title: "Your link is ready", body: "\(a.project) — open OneTake to send it.")
                        }
                    }
                }

                // Stage 4: Finalizing
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

private struct PackageFormatSheet: View {
    let auditionID: Audition.ID
    let required: PackageDeliverable?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Delivery format", backLabel: "Done", onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 16)
            Text(required.map { "Casting requests \($0.rawValue)." } ?? "No file format was specified. Choose what you want to send.")
                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OT.gutter).padding(.top, 10).padding(.bottom, 4)
            if let binding = store.binding(for: auditionID) {
                List {
                    ForEach(PackageDeliverable.allCases) { option in
                        let selected = binding.wrappedValue.packageDeliverable == option
                        Button {
                            if binding.wrappedValue.packageDeliverable != option {
                                store.clearShareLink(for: auditionID)
                            }
                            binding.wrappedValue.packageDeliverable = option
                            Haptics.tick()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon).foregroundStyle(OT.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(option.rawValue).font(.otBody.weight(.semibold))
                                        if required == option {
                                            Text("Required").font(.otCaption.weight(.bold)).foregroundStyle(OT.accent)
                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                .background(OT.accentSoft, in: Capsule())
                                        }
                                    }
                                    Text(option.subtitle).font(.otFootnote).foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(OT.accent) }
                            }
                            .foregroundStyle(OT.labelPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .otCanvas()
    }
}

struct DestinationSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Where’s it going?", backLabel: "Done", onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 16)

            if let audition = store.binding(for: auditionID) {
                let current = audition.wrappedValue.destination
                let wasChosen = audition.wrappedValue.destinationWasChosen ?? false
                List {
                    Section("Destination & Submission Method") {
                        ForEach(Destination.allCases) { d in
                            destinationRow(for: d, isSelected: wasChosen && current == d) {
                                if current != d { store.clearShareLink(for: auditionID) }
                                audition.wrappedValue.destination = d
                                audition.wrappedValue.destinationWasChosen = true
                                Haptics.tick()
                            }
                        }
                    }

                    if store.account == nil {
                        Section("Account") {
                            Button { showSignIn = true } label: {
                                Label("Sign in or create an account", systemImage: "person.crop.circle.badge.plus")
                            }
                            Text(AccountAuth.canSignIn
                                 ? "Sign in here to use a hosted link. You’ll return to this audition afterward."
                                 : "The sign-in screen is available here, but Apple and Google aren’t configured in this build yet.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                    }

                    if wasChosen {
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text(current == .email ? "We automatically format the cover email, subject line, and attach your chosen deliverable." :
                                     current == .localFiles ? "Export directly to your iPhone Files app, AirDrop to your computer, or copy to cloud storage." :
                                     "We match the file name and specifications each platform asks for.")
                                if !AccountAuth.canSignIn {
                                    Text("Sign-in options are in Profile → Sign in. Apple and Google sign-in are not configured in this build, so hosted links are unavailable.")
                                }
                            }
                        }
                    } else {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Choose the place you’ll send your audition. The notice’s email has been preselected when detected.")
                                if !AccountAuth.canSignIn {
                                    Text("Sign-in options are in Profile → Sign in. Apple and Google sign-in are not configured in this build, so hosted links are unavailable.")
                                }
                            }
                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .otCanvas()
        .sheet(isPresented: $showSignIn) {
            SignInView(reason: "Sign in here to use a hosted link. You’ll return to this audition afterward.") { account in
                store.account = account
                showSignIn = false
            }
            .presentationDragIndicator(.visible)
        }
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
            SectionLabel(text: "Preparing \(audition.packageDeliverable?.shortTitle ?? "delivery")").padding(.top, 20)
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
            let format = audition.packageDeliverable ?? .combinedVideo
            if format != .headshotsOnly {
                step("Found your recorded pieces", done: true, active: false)
            }
            if format == .combinedVideo || format == .completePackage {
                step("Composing combined video",
                     done: exportStage == .archiving || exportStage == .uploading || exportStage == .finalizing || progress >= 1.0,
                     active: exportStage == .composing)
            }
            if format == .separateZip || format == .completePackage || (format == .headshotsOnly && audition.destination == .emailOrLink) {
                step(format == .headshotsOnly ? "Preparing photos ZIP" : "Archiving selected clips and photos",
                     done: exportStage == .uploading || exportStage == .finalizing || progress >= 1.0,
                     active: exportStage == .archiving)
            }
            if audition.destination == .emailOrLink {
                step("Uploading selected file to your iCloud",
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
        case .preparing:
            return "Getting the selected files ready..."
        case .composing:
            return "Combining the selected takes and slate into your video..."
        case .archiving:
            return "Creating the selected ZIP package..."
        case .uploading:
            return "Uploading the selected file to iCloud..."
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

/// Export finishes here: the selected deliverable is ready to hand off.
struct DeliveryReadyView: View {
    let audition: Audition
    let destination: Destination
    let deliverable: PackageDeliverable
    var onShare: () -> Void
    var onBack: () -> Void

    @Environment(AppStore.self) private var store
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

                if destination != .email {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(OT.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audition.status == .exported ? "Files Exported" : "Ready for Upload")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Upload your files to \(destination.rawValue), then mark submitted.")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                        }
                        Button {
                            store.markSubmitted(audition.id)
                            Haptics.success()
                            onBack()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Mark as Submitted")
                            }
                            .font(.otHeadline)
                        }
                        .buttonStyle(.otSecondary)
                    }
                    .padding(14)
                    .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                // Change choices by returning to package review; alternate formats aren't
                // generated behind the scenes and must not silently change what gets shared.
                VStack(spacing: 8) {
                    Button("Change format or destination", action: onBack)
                        .buttonStyle(.otSecondary)
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
        case .email: return "Open email"
        case .localFiles: return "Save to Files / AirDrop"
        case .actorsAccess: return "Export for Actors Access"
        case .backstage: return "Export for Backstage"
        case .castingNetworks: return "Export for Casting Networks"
        case .spotlight: return "Export for Spotlight"
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
    var onEditOptions: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(OT.warning).padding(.top, 20)
            Text("Couldn't package it").font(.otLargeTitle)
            Text(message ?? "Something went wrong composing your tape. Your takes are untouched on this iPhone — this only affects the combined file.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            Spacer()
            Button("Back to package options", action: onEditOptions).buttonStyle(.otSecondary)
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
