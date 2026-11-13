import SwiftUI

struct SendFailedView: View {
    let message: String?
    var onEditOptions: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(OT.warning)
                .padding(.top, OTSpace.m)

            Text("Couldn't package it")
                .font(.otLargeTitle)

            Text(message ?? "Something went wrong composing your tape. Your takes are untouched on this iPhone — this only affects the combined file.")
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)

            Spacer()

            Button("Back to package options", action: onEditOptions)
                .buttonStyle(.otSecondary)

            Button("Try again", action: onRetry)
                .buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.top, OTSpace.s)
        .padding(.bottom, OTSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .otCanvas()
        .navigationBarBackButtonHidden(true)
    }
}
