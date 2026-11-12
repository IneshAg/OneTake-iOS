import SwiftUI

struct VoiceWaveformBars: View {
    let isRecording: Bool
    let level: Float

    // 10 bar heights from Figma node 1109:10274: 6, 14, 22, 10, 26, 18, 8, 20, 12, 4
    private let baseHeights: [CGFloat] = [6, 14, 22, 10, 26, 18, 8, 20, 12, 4]

    var body: some View {
        HStack(spacing: 3) { // ot-lint:allow
            ForEach(0..<baseHeights.count, id: \.self) { i in
                let factor: CGFloat = isRecording ? max(0.4, CGFloat(sin(Double(i) * 0.9 + Double(level) * 8) + 1.2)) : 0.85
                RoundedRectangle(cornerRadius: 2, style: .continuous) // ot-lint:allow
                    .fill(isRecording ? OT.reader : Color.white.opacity(0.45)) // ot-lint:allow
                    .frame(width: 3, height: max(4, min(32, baseHeights[i] * factor))) // ot-lint:allow
                    .animation(.easeInOut(duration: 0.12), value: level)
            }
        }
    }
}
