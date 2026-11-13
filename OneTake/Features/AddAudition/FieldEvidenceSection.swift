import SwiftUI
import OneTakeUI

// MARK: - Source Evidence & Provenance View

struct FieldEvidenceSection: View {
    var evidence: [AuditionFieldEvidence]
    var sources: [AuditionSource]
    @State private var isExpanded = false

    var body: some View {
        if !evidence.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    Text("Every extracted detail is grounded in the original casting notice or sides:")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)

                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            HStack {
                                Text(item.field.capitalized)
                                    .font(.otCaption.weight(.bold))
                                    .foregroundStyle(OT.accent)
                                Spacer()
                                Text(sourceName(for: item))
                                    .font(.otCaption.weight(.semibold).monospaced())
                                    .foregroundStyle(OT.labelTertiary)
                            }

                            Text("“\(item.excerpt)”")
                                .font(.otCaption)
                                .italic()
                                .foregroundStyle(OT.labelSecondary)
                                .padding(OTSpace.s)
                                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                        }
                        if item.id != evidence.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, OTSpace.s)
            } label: {
                HStack(spacing: OTSpace.s) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(OT.accent)
                    Text("Source Evidence & Provenance (\(evidence.count) grounded points)")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                }
            }
            .otCard(.grouped)
        }
    }

    private func sourceName(for item: AuditionFieldEvidence) -> String {
        if let page = item.pageNumber {
            return "Page \(page)"
        }
        if let source = sources.first(where: { $0.id == item.sourceID }) {
            return source.name
        }
        return "Notice"
    }
}
