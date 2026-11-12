import SwiftUI

struct SubmissionInstructionsCard: View {
    let instructions: AuditionSubmissionInstructions

    var body: some View {
        let specs = [
            ("Framing", instructions.videoOrientation, "iphone"),
            ("Required Clips", instructions.requiredVideoCount.map { "\($0) video\($0 == 1 ? "" : "s")" }, "film.stack"),
            ("Takes Allowed", instructions.maxTakes.map { "Up to \($0) takes" }, "repeat"),
            ("File Naming", instructions.fileNamingRule ?? instructions.fileNameTemplate, "doc.text")
        ].filter { $0.1 != nil && $0.1?.isEmpty == false }

        if !specs.isEmpty || !instructions.slateRequirements.isEmpty {
            VStack(alignment: .leading, spacing: OTSpace.s) {
                Label("Filming & Submission Specifications", systemImage: "video.badge.checkmark")
                    .font(.otCaption.weight(.bold))
                    .foregroundStyle(OT.labelPrimary)

                if !specs.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: OTSpace.s) {
                        ForEach(specs, id: \.0) { item in
                            HStack(alignment: .top, spacing: OTSpace.s) {
                                Image(systemName: item.2)
                                    .font(.system(size: 13)) // ot-lint:allow
                                    .foregroundStyle(OT.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.0)
                                        .font(.otEyebrow)
                                        .foregroundStyle(OT.labelTertiary)
                                    Text(item.1 ?? "")
                                        .font(.otFootnote.weight(.medium))
                                        .foregroundStyle(OT.labelPrimary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                if !instructions.slateRequirements.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Slate instructions:")
                            .font(.otEyebrow)
                            .foregroundStyle(OT.labelTertiary)
                        ForEach(instructions.slateRequirements.prefix(2), id: \.self) {
                            Text("• \($0)")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                    }
                    .padding(.top, OTSpace.xxs)
                }
            }
            .padding(OTSpace.m)
            .otCard(.grouped)
        }
    }
}
