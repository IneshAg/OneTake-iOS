import SwiftUI

// MARK: - Package steps bar (v2/Package Steps)

struct PackageStepsBar: View {
    let pieces: [Piece]
    var body: some View {
        let nextIndex = pieces.firstIndex { !$0.isDone }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { i, piece in
                    Capsule()
                        .fill(piece.isDone ? OT.accent : (i == nextIndex ? OT.accent.opacity(0.4) : OT.fillQuiet))
                        .frame(height: 8)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { i, piece in
                    Text(piece.title)
                        .font(.otCaption.weight(i == nextIndex ? .semibold : .regular))
                        .foregroundStyle(i == nextIndex ? OT.accent : OT.labelTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
