import SwiftUI
import OneTakeUI

// MARK: - Milestone Dates List Card

struct MilestoneDatesListCard: View {
    var dates: [AuditionDate]
    var onAddDate: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            HStack {
                Label("Key Dates & Deadlines", systemImage: "calendar.badge.clock")
                    .font(.otCaption.weight(.bold))
                    .foregroundStyle(OT.labelPrimary)
                Spacer()
                if let onAddDate {
                    Button(action: onAddDate) {
                        HStack(spacing: OTSpace.xs) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add date")
                        }
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if dates.isEmpty {
                Text("No additional milestone dates detected.")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelTertiary)
                    .padding(.vertical, OTSpace.xs)
            } else {
                VStack(spacing: OTSpace.s) {
                    ForEach(dates) { item in
                        HStack(spacing: OTSpace.s) {
                            Image(systemName: item.kind.icon)
                                .font(.otIcon(.s))
                                .foregroundStyle(item.kind == .submissionDeadline ? OT.due : OT.accent)
                                .frame(width: 24) // ot-lint:allow

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label.isEmpty ? item.kind.title : item.label)
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.labelPrimary)
                                if let text = item.sourceText, !text.isEmpty {
                                    Text(text)
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelTertiary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(item.formattedDate)
                                .font(.otCaption.weight(.bold).monospaced())
                                .foregroundStyle(item.kind == .submissionDeadline ? OT.due : OT.labelSecondary)
                        }
                        .padding(.vertical, OTSpace.xs)
                        if item.id != dates.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .otCard(.grouped)
    }
}
