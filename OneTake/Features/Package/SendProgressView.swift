import SwiftUI

enum PackageExportStage: Equatable {
    case preparing
    case composing
    case archiving
    case uploading
    case finalizing
}

struct SendProgressView: View {
    let audition: Audition
    let progress: Double
    var exportStage: PackageExportStage = .composing
    var uploading = false
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            OTSectionLabel("Preparing \(audition.packageDeliverable?.shortTitle ?? "delivery")")
                .padding(.top, OTSpace.s)

            HStack(alignment: .firstTextBaseline, spacing: OTSpace.xs) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 72, weight: .bold)) // ot-lint:allow
                    .monospacedDigit()
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

            ProgressView(value: min(1.0, max(0.0, progress)))
                .tint(OT.accent)

            Text(statusMessage)
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)
                .padding(.top, OTSpace.xxs)

            OTSectionLabel("Steps")
                .padding(.top, OTSpace.s)

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

            Button("Cancel", action: onCancel)
                .buttonStyle(.otSecondary)
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.top, OTSpace.s)
        .padding(.bottom, OTSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .otCanvas()
        .navigationBarBackButtonHidden(true)
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
        HStack(spacing: OTSpace.s) {
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
        .frame(minHeight: 36) // ot-lint:allow
    }
}
