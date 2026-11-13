import SwiftUI

struct SentView: View {
    let audition: Audition
    let slate: SlateInfo
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.l) {
            VStack(alignment: .leading, spacing: OTSpace.xs) {
                HStack {
                    Text("SHARED · \(sentDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()).uppercased())")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.success)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(OT.success)
                }
                Text("Merged video · \(audition.deliverableFileName(slate: slate))")
                    .font(.otFootnote.weight(.semibold))
                    .lineLimit(2)
                Text("Separate clips · \(separateArchiveName)")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
                    .lineLimit(2)
                Text(audition.scenes.isEmpty
                     ? "No scripted scenes"
                     : "\(audition.scenes.count) scene\(audition.scenes.count == 1 ? "" : "s")")
                    .font(.otCaption)
                    .foregroundStyle(OT.labelTertiary)
            }
            .otCard(.grouped)
            .rotationEffect(.degrees(1.5))
            .padding(.top, OTSpace.l)

            Text(audition.destination == .emailOrLink ? "Your link is ready." : "Shared for \(audition.destination.rawValue).")
                .font(.system(size: 38, weight: .bold)) // ot-lint:allow

            HStack(alignment: .firstTextBaseline) {
                Text(earlyText)
                    .font(.otTitle)
                    .foregroundStyle(OT.success)
                Text("Break a leg.")
                    .font(.otHeadline)
                    .foregroundStyle(OT.labelSecondary)
            }

            if audition.destination == .emailOrLink, let expires = audition.shareLinkExpires, audition.shareLink != nil {
                Label("Link shared · works until \(expires.formatted(date: .abbreviated, time: .omitted))", systemImage: "link")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
            } else {
                Label("Handed off through your Share Sheet to \(audition.destination.rawValue)", systemImage: "square.and.arrow.up")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
            }

            Label("All your takes stay here if they ask for another", systemImage: "iphone")
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.top, OTSpace.s)
        .padding(.bottom, OTSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .otCanvas()
        .navigationBarBackButtonHidden(true)
        .onAppear { Haptics.success() }
    }

    private var earlyText: String {
        let h = max(0, Int(audition.due.timeIntervalSince(sentDate) / 3600))
        return h >= 1 ? "\(h) hours early." : "Right on time."
    }

    private var sentDate: Date { audition.sentDate ?? .now }

    private var separateArchiveName: String {
        if let url = audition.separateArchiveURL { return url.lastPathComponent }
        let base = (audition.deliverableFileName(slate: slate) as NSString).deletingPathExtension
        return "\(base)_SEPARATE.zip"
    }
}
