import SwiftUI

struct SubmissionCheckSummaryCard: View {
    let audition: Audition
    var onSelectDeliverable: () -> Void
    var onSelectDestination: () -> Void

    var body: some View {
        let format = audition.packageDeliverable
        let destinationChosen = audition.destinationWasChosen ?? false

        VStack(alignment: .leading, spacing: OTSpace.s) {
            Label("Submission check", systemImage: "checkmark.seal")
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(OT.labelSecondary)

            checkRow(
                title: "Delivery format",
                value: format?.shortTitle ?? "Choose one",
                isReady: format != nil,
                action: onSelectDeliverable
            )

            checkRow(
                title: "Submission destination",
                value: destinationChosen ? audition.destination.rawValue : "Choose one",
                isReady: destinationChosen,
                action: onSelectDestination
            )
        }
        .padding(OTSpace.m)
        .otCard(.grouped)
    }

    private func checkRow(title: String, value: String, isReady: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: OTSpace.s) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(isReady ? OT.success : OT.warning)
                Text(title).foregroundStyle(OT.labelSecondary)
                Spacer(minLength: OTSpace.xs)
                Text(value).foregroundStyle(OT.labelPrimary).lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.labelTertiary)
            }
            .font(.otCaption.weight(.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DeliverableFormatCard: View {
    let audition: Audition
    let current: PackageDeliverable?
    let required: PackageDeliverable?
    var takes: [Take] = []
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: OTSpace.m) {
                Image(systemName: current?.icon ?? "shippingbox")
                    .font(.system(size: 19, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.accent)
                    .frame(width: 28) // ot-lint:allow

                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                    Text(current?.rawValue ?? "Choose a delivery format")
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)

                    if let required {
                        Text(current == required ? "Required by the casting notice" : "Casting requires: \(required.rawValue)")
                            .font(.otCaption.weight(.semibold))
                            .foregroundStyle(OT.accent)
                    } else {
                        Text(current.map { PackageFormatHelper.sizeLabel(for: $0, audition: audition, takes: takes) } ?? "No format specified by casting")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.labelTertiary)
            }
            .padding(OTSpace.m)
            .contentShape(RoundedRectangle(cornerRadius: OTRadius.l))
        }
        .buttonStyle(.plain)
        .otCard(.grouped)
    }
}

struct DestinationCard: View {
    let audition: Audition
    var hasAccount: Bool
    var onChangeDestination: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        let destinationChosen = audition.destinationWasChosen ?? false

        VStack(alignment: .leading, spacing: OTSpace.s) {
            HStack(spacing: OTSpace.m) {
                Image(systemName: audition.destination.icon)
                    .font(.system(size: 20, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.accent)
                    .frame(width: 28) // ot-lint:allow

                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                    Text(destinationChosen ? audition.destination.rawValue : "Choose a submission destination")
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                    Text(destinationChosen ? PackageFormatHelper.destinationSummary(audition) : "No destination specified by casting")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelSecondary)
                }
                Spacer()
                Button(destinationChosen ? "Change" : "Choose", action: onChangeDestination)
                    .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
            }

            if destinationChosen && audition.destination == .emailOrLink && !hasAccount {
                Button(action: onSignIn) {
                    Label("Sign in or create an account", systemImage: "person.crop.circle.badge.plus")
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(OT.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(OTSpace.m)
        .otCard(.grouped)
    }
}

struct SubmissionSpecsCard: View {
    let audition: Audition
    let slate: SlateInfo
    var takes: [Take] = []
    var onEditFileName: () -> Void

    var body: some View {
        let deliverable = audition.packageDeliverable
        let fileName = deliverable == .separateZip
            ? PackageFormatHelper.separateArchiveName(audition, slate: slate)
            : audition.deliverableFileName(slate: slate)
        let hasCustomTemplate = audition.submissionInstructions?.fileNameTemplate?.isEmpty == false

        VStack(alignment: .leading, spacing: OTSpace.s) {
            Button(action: onEditFileName) {
                HStack {
                    Label("Filename:", systemImage: "doc.text")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelTertiary)
                    if hasCustomTemplate {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 11)) // ot-lint:allow
                            .foregroundStyle(OT.accent)
                    }
                    Spacer()
                    Text(deliverable == nil ? "Choose a format above" : fileName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced)) // ot-lint:allow
                        .foregroundStyle(OT.labelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(OT.labelTertiary)
                }
            }
            .buttonStyle(.plain)

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
                Text("\(PackageFormatHelper.totalDurationLabel(audition, takes: takes)) (Under 2 min max)")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.success)
            }

            Divider()

            HStack {
                Label("File Size:", systemImage: "arrow.down.circle")
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelTertiary)
                Spacer()
                Text("\(PackageFormatHelper.sizeLabel(for: deliverable, audition: audition, takes: takes)) (Well under 500 MB limit)")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.success)
            }

            Divider()

            HStack {
                Label("Slate:", systemImage: "person.crop.rectangle")
                    .font(.otCaption.weight(.medium))
                    .foregroundStyle(OT.labelTertiary)
                Spacer()
                Text(audition.slateVideoURL != nil ? "Recorded & included at start" : "Optional / Separate")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(audition.slateVideoURL != nil ? OT.success : OT.labelSecondary)
            }
        }
        .padding(OTSpace.m)
        .otCard(.grouped)
    }
}

enum PackageFormatHelper {
    static func requiredDeliverable(for audition: Audition) -> PackageDeliverable? {
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

    static func destinationSummary(_ a: Audition) -> String {
        switch a.destination {
        case .email:
            let to = a.castingEmail ?? "Casting Office"
            return "To: \(to) · Subject: \(a.emailSubject(slate: SlateInfo()))"
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

    static func sizeLabel(for deliverable: PackageDeliverable?, audition a: Audition, takes: [Take] = []) -> String {
        guard let deliverable else { return "Choose a format" }
        switch deliverable {
        case .combinedVideo:
            return exportedSizeLabel(a, takes: takes)
        case .separateZip:
            return separateZipSizeLabel(a, takes: takes)
        case .headshotsOnly:
            let count = HeadshotStore.taken(auditionID: a.id).count
            return "\(count) photo\(count == 1 ? "" : "s")"
        case .completePackage:
            return "\(exportedSizeLabel(a, takes: takes)) + ZIP"
        }
    }

    static func totalDurationLabel(_ a: Audition, takes: [Take] = []) -> String {
        let circled = takes.filter { $0.auditionID == a.id && $0.isCircled }
        guard !circled.isEmpty else { return "—" }
        let total = Int(circled.reduce(0) { $0 + $1.duration })
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    static func exportedSizeLabel(_ a: Audition, takes: [Take] = []) -> String {
        guard let url = a.exportedFileURL, let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return "~\(estimatedSizeMB(a, takes: takes)) MB"
        }
        return "\(size / 1_048_576) MB"
    }

    static func separateZipSizeLabel(_ a: Audition, takes: [Take] = []) -> String {
        guard let url = a.separateArchiveURL, let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return "~\(Int(Double(estimatedSizeMB(a, takes: takes)) * 1.1)) MB"
        }
        return "\(size / 1_048_576) MB"
    }

    static func estimatedSizeMB(_ a: Audition, takes: [Take] = []) -> Int {
        let circled = takes.filter { $0.auditionID == a.id && $0.isCircled }
        let totalSeconds = circled.reduce(0.0) { $0 + $1.duration }
        return max(8, Int(totalSeconds * 1.5))
    }

    static func separateArchiveName(_ a: Audition, slate: SlateInfo) -> String {
        if let url = a.separateArchiveURL { return url.lastPathComponent }
        let base = (a.deliverableFileName(slate: slate) as NSString).deletingPathExtension
        return "\(base)_SEPARATE.zip"
    }
}
