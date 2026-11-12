import SwiftUI

// MARK: - Readiness dashes (v2/Readiness Dashes)

struct ReadinessDashes: View {
    let done: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i < done ? OT.accent : OT.fillQuiet)
                        .frame(width: 14, height: 4)
                }
            }
            Text("\(done) of \(total)").font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) ready")
    }
}
