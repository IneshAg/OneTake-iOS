import SwiftUI
import OneTakeUI

// MARK: - Dedicated "Following your voice" Floating Glass Pill (Figma y: 668)

struct VoiceFollowingPill: View {
    var isListening: Bool
    var isActorLine: Bool
    var characterName: String
    var isFollowingVoice: Bool
    var isReaderPlaying: Bool
    @State private var waveAnimating = false

    var body: some View {
        HStack(spacing: OTSpace.s) {
            if isActorLine {
                if isFollowingVoice {
                    // Audio waveform visualization
                    HStack(spacing: 2.5) { // ot-lint:allow
                        ForEach(0..<4) { index in
                            RoundedRectangle(cornerRadius: 1.5) // ot-lint:allow
                                .fill(isListening ? OT.prompterGold : Color.white.opacity(0.4)) // ot-lint:allow
                                .frame(width: 2.5, height: barHeight(for: index)) // ot-lint:allow
                        }
                    }
                    .frame(width: 16, height: 16) // ot-lint:allow

                    Text(isListening ? "Following your voice" : "Voice follower paused")
                        .font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(isListening ? OT.prompterGold : Color.white.opacity(0.8)) // ot-lint:allow
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(Color.white) // ot-lint:allow
                    Text("Timed auto-advance")
                        .font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                        .foregroundStyle(Color.white) // ot-lint:allow
                }
            } else {
                Image(systemName: isReaderPlaying ? "speaker.wave.2.fill" : "speaker.wave.1")
                    .font(.system(size: 12, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.reader)
                Text(characterName.isEmpty ? "Reader speaking" : "\(characterName) speaking")
                    .font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.reader)
            }
        }
        .padding(.horizontal, OTSpace.m)
        .padding(.vertical, 7) // ot-lint:allow
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6)) // ot-lint:allow
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isActorLine && isFollowingVoice && isListening
                                ? OT.prompterGold.opacity(0.35)
                                : Color.white.opacity(0.15), // ot-lint:allow
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                waveAnimating = true
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isListening else { return 4 }
        let heights: [(CGFloat, CGFloat)] = [
            (5, 13),
            (11, 6),
            (15, 8),
            (7, 14)
        ]
        let (minH, maxH) = heights[index % heights.count]
        return waveAnimating ? maxH : minH
    }
}
