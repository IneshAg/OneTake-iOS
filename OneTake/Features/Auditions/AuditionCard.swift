import SwiftUI

// MARK: - Audition card (v2/Audition Card · Due / Ready / Sent)

struct AuditionCard: View {
    let audition: Audition
    var onNext: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: OTSpace.m) {
            HeadshotImage(realKey: "front").id(store.headshotVersion)
                .frame(width: 88, height: 120) // ot-lint:allow
                .clipShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))

            VStack(alignment: .leading, spacing: OTSpace.xs) {
                HStack(alignment: .top) {
                    Text(audition.project).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    if audition.status == .sent {
                        OTChip("Sent", systemImage: "paperplane.fill", tint: OT.success)
                    }
                }
                Text("\(audition.projectType) · \(audition.role)").font(.otFootnote).foregroundStyle(OT.labelSecondary)

                if audition.status == .sent {
                    Label("\(audition.sentDate?.otDayMonth ?? "")" + (audition.shareLinkTimeLeft.map { " · link active \($0)" } ?? ""),
                          systemImage: audition.shareLink != nil ? "link" : "paperplane")
                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                } else {
                    ReadinessDashes(done: audition.readyCount, total: audition.totalCount)
                    statusLine
                    Divider().padding(.vertical, OTSpace.xxs)
                    Button(action: onNext) {
                        HStack(spacing: OTSpace.xs) {
                            Image(systemName: nextSymbol).font(.footnote)
                            Text("Next: \(audition.nextAction)").font(.otSubhead.weight(.semibold))
                            Image(systemName: "arrow.right").font(.footnote)
                        }
                        .foregroundStyle(OT.accent)
                        .frame(minHeight: 32) // ot-lint:allow
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .otCard(.grouped)
    }

    @ViewBuilder private var statusLine: some View {
        if audition.status == .ready {
            OTStatusLine(.success, "Ready to send", detail: "due \(audition.dueRemaining.relativePhrase)")
        } else {
            let labelText = audition.dueRemaining.isPastDue ? "Past due · was due \(audition.due.otDue)" : "Due \(audition.dueRemaining.relativePhrase)"
            OTStatusLine(.due, labelText)
        }
    }

    private var nextSymbol: String {
        switch audition.nextPiece?.kind {
        case .headshot: "person.crop.square"
        case .slate, .fullLength, .scene: audition.nextPiece?.title == "Watch it once" ? "paperplane.fill" : "video.fill"
        case nil: "paperplane.fill"
        }
    }
}
