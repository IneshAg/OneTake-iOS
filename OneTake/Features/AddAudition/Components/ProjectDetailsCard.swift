import SwiftUI

// MARK: - Project Details & Production Info Card

struct ProjectDetailsCard: View {
    var details: AuditionProjectDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("About this project", systemImage: "building.2.crop.circle")
                .font(.otCaption.weight(.bold))
                .foregroundStyle(OT.labelPrimary)

            if let synopsis = details.synopsis, !synopsis.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project summary").font(.system(size: 11, weight: .semibold)).foregroundStyle(OT.labelTertiary)
                    Text(synopsis)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }
            }

            let terms = [
                ("Pay & Terms", details.payTerms, "dollarsign.circle.fill"),
                ("Union Status", details.unionStatus, "person.3.sequence.fill"),
                ("Location", details.productionLocation ?? details.castingArea, "mappin.circle.fill"),
                ("Company / Team", [details.productionCompany, details.producer, details.director].compactMap { $0 }.joined(separator: " · "), "film.fill")
            ].filter { $0.1 != nil && $0.1?.isEmpty == false }

            if !terms.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(terms, id: \.0) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.2)
                                .font(.system(size: 13))
                                .foregroundStyle(OT.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.0)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(OT.labelTertiary)
                                Text(item.1 ?? "")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(OT.labelPrimary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .otCard(radius: 16)
    }
}
