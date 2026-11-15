import SwiftUI
import OneTakeUI

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
    @State private var completionPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double { min(1.0, max(0.0, progress)) }
    private var isComplete: Bool { clampedProgress >= 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            OTSectionLabel("Preparing \(audition.packageDeliverable?.shortTitle ?? "delivery")")
                .padding(.top, OTSpace.s)

            centeredProgressHero
                .frame(maxWidth: .infinity)
                .padding(.vertical, OTSpace.m)

            Text(statusMessage)
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .animation(OTMotion.smooth, value: isComplete)

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
        .onChange(of: isComplete) { _, done in
            guard done else { completionPulse = false; return }
            Haptics.celebrate()
            if !reduceMotion {
                withAnimation(OTMotion.smooth.delay(0.05)) {
                    completionPulse = true
                }
            } else {
                completionPulse = true
            }
        }
    }

    @ViewBuilder
    private var centeredProgressHero: some View {
        let pct = Int((clampedProgress * 100).rounded())
        ZStack {
            // Subtle celebratory halo pulse when package finishes
            Circle()
                .stroke(OT.success.opacity(isComplete ? (completionPulse ? 0.0 : 0.45) : 0), lineWidth: 6) // ot-lint:allow
                .frame(width: 176, height: 176) // ot-lint:allow
                .scaleEffect(completionPulse ? 1.24 : 0.92)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.75), value: completionPulse) // ot-lint:allow

            // Track ring
            Circle()
                .stroke(OT.fillField, lineWidth: 10) // ot-lint:allow
                .frame(width: 164, height: 164) // ot-lint:allow

            // Animated progress arc
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    isComplete ? OT.success : OT.accent,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 164, height: 164) // ot-lint:allow
                .rotationEffect(.degrees(-90))
                .animation(OTMotion.smooth, value: clampedProgress)
                .animation(OTMotion.smooth, value: isComplete)

            // Centered percentage that smoothly morphs into a checkmark tick
            if isComplete {
                ZStack {
                    Circle()
                        .fill(OT.success.opacity(0.16))
                        .frame(width: 112, height: 112) // ot-lint:allow
                    Image(systemName: "checkmark")
                        .font(.system(size: 52, weight: .bold)) // ot-lint:allow
                        .foregroundStyle(OT.success)
                }
                .transition(.scale(scale: 0.45).combined(with: .opacity))
            } else {
                VStack(spacing: OTSpace.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) { // ot-lint:allow
                        Text("\(pct)")
                            .font(.system(size: 48, weight: .bold)) // ot-lint:allow
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.otTitle)
                            .foregroundStyle(OT.labelSecondary)
                    }
                    .foregroundStyle(OT.labelPrimary)

                    Text(uploading ? "Uploading…" : stageShortLabel)
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelTertiary)
                }
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(OTMotion.bouncy, value: isComplete)
        .animation(OTMotion.snappy, value: pct)
    }

    private var stageShortLabel: String {
        switch exportStage {
        case .preparing: "Preparing"
        case .composing: "Composing"
        case .archiving: "Zipping"
        case .uploading: "Uploading"
        case .finalizing: "Finishing"
        }
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
