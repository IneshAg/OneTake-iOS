import SwiftUI

// MARK: - Progress ring / readiness dial (v2/Progress Ring)

/// Segmented dial: one segment per package piece. Done = accent, next = soft accent, todo = quiet track.
struct ReadinessDial: View {
    let done: Int
    let total: Int
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6
    var onDark = false

    var body: some View {
        let gap = 0.035
        let seg = (1.0 - Double(total) * gap) / Double(total)
        ZStack {
            ForEach(0..<total, id: \.self) { i in
                let start = Double(i) * (seg + gap) + gap / 2
                Circle()
                    .trim(from: start, to: start + seg)
                    .stroke(color(for: i), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: -2) {
                Text("\(done)").font(.system(size: size * 0.3, weight: .bold)).monospacedDigit()
                Text("of \(total)").font(.system(size: size * 0.18, weight: .medium))
            }
            .foregroundStyle(onDark ? .white : OT.labelPrimary)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) pieces ready")
    }

    private func color(for i: Int) -> Color {
        if i < done { return onDark ? .white : OT.accent }
        if i == done { return (onDark ? Color.white : OT.accent).opacity(0.45) }
        return onDark ? .white.opacity(0.22) : OT.fillQuiet
    }
}
