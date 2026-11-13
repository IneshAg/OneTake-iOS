import SwiftUI
import OneTakeUI

struct NoticeErrorView: View {
    var onRetry: () -> Void
    var onScan: () -> Void
    var onType: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.otIcon(.xl))
                .foregroundStyle(OT.warning)
            Text("We couldn't read this notice")
                .font(.otLargeTitle)
                .foregroundStyle(OT.labelPrimary)
            Text("No readable text was found — it may be a photo without text, blurry, or very small print. Nothing was lost — pick how to continue.")
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)

            Button(action: onRetry) {
                OTIconRow(symbol: "arrow.clockwise", title: "Try again", detail: "Go back and pick the photo, scan or file again")
            }
            .buttonStyle(.plain)

            Button(action: onScan) {
                OTIconRow(symbol: "doc.viewfinder", title: "Scan the pages instead", detail: "Clearer than a screenshot")
            }
            .buttonStyle(.plain)

            Button(action: onType) {
                OTIconRow(symbol: "keyboard", title: "Type the details", detail: "Name, role and due date — 30 seconds")
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.top, OTSpace.s)
        .padding(.bottom, OTSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .otCanvas()
    }
}
