import SwiftUI

// MARK: - Milestone Dates List Card

struct MilestoneDatesListCard: View {
    var dates: [AuditionDate]
    var onAddDate: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Key Dates & Deadlines", systemImage: "calendar.badge.clock")
                    .font(.otCaption.weight(.bold))
                    .foregroundStyle(OT.labelPrimary)
                Spacer()
                if let onAddDate {
                    Button(action: onAddDate) {
                        HStack(spacing: 4) {
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
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(dates) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.kind.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.kind == .submissionDeadline ? OT.due : OT.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label.isEmpty ? item.kind.title : item.label)
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.labelPrimary)
                                if let text = item.sourceText, !text.isEmpty {
                                    Text(text)
                                        .font(.system(size: 11))
                                        .foregroundStyle(OT.labelTertiary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(item.formattedDate)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(item.kind == .submissionDeadline ? OT.due : OT.labelSecondary)
                        }
                        .padding(.vertical, 4)
                        if item.id != dates.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(14)
        .otCard(radius: 16)
    }
}
