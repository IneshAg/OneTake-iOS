import SwiftUI

public struct OTProgressRing: View {
    public let progress: Double
    public let lineWidth: CGFloat

    public init(progress: Double, lineWidth: CGFloat = 4) {
        self.progress = progress
        self.lineWidth = lineWidth
    }

    public init(value: Double, lineWidth: CGFloat = 8) {
        self.progress = value
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(OT.fillQuiet, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(OT.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
