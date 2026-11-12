import SwiftUI

// MARK: - Source Evidence & Provenance View

struct FieldEvidenceSection: View {
    var evidence: [AuditionFieldEvidence]
    var sources: [AuditionSource]
    @State private var isExpanded = false

    var body: some View {
        if !evidence.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Every extracted detail is grounded in the original casting notice or sides:")
                        .font(.system(size: 11))
                        .foregroundStyle(OT.labelTertiary)

                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.field.capitalized)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(OT.accent)
                                Spacer()
                                Text(sourceName(for: item))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(OT.labelTertiary)
                            }

                            Text("“\(item.excerpt)”")
                                .font(.system(size: 11, design: .serif))
                                .italic()
                                .foregroundStyle(OT.labelSecondary)
                                .padding(8)
                                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        if item.id != evidence.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(OT.accent)
                    Text("Source Evidence & Provenance (\(evidence.count) grounded points)")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                }
            }
            .padding(14)
            .otCard(radius: 16)
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
