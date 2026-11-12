import SwiftUI
import OneTakeUI
import AVKit

struct SlateTrimReview: Identifiable {
    let id = UUID()
    let original: URL
    let trimmed: URL
    let suggestion: SilenceTrimmer.Suggestion
}

struct SlateTrimReviewView: View {
    let original: URL
    let trimmed: URL
    let removedLeading: Double
    let removedTrailing: Double
    let keepTrimmed: () -> Void
    let keepOriginal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            HStack {
                Spacer()
                Button("Use original", action: keepOriginal)
                    .font(.otHeadline)
                    .foregroundStyle(OT.accent)
            }
            .padding(.top, OTSpace.m)

            Text("Review slate trim").font(.otLargeTitle)
            Text("Long silent edges were trimmed with a short pause kept before and after. Your original is saved and can be restored from Package.")
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)

            VideoPlayer(player: AVPlayer(url: trimmed))
                .frame(height: 260) // ot-lint:allow
                .clipShape(RoundedRectangle(cornerRadius: OTRadius.l))

            Text("Removed about \(removedLeading, specifier: "%.1f") s at the start and \(removedTrailing, specifier: "%.1f") s at the end.")
                .font(.otFootnote)
                .foregroundStyle(OT.labelTertiary)

            Button("Keep trimmed slate", action: keepTrimmed).buttonStyle(.otPrimary)
            Button("Use original slate", action: keepOriginal).buttonStyle(.otSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OTSpace.gutter)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}
