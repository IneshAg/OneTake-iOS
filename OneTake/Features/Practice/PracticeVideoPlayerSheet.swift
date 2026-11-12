import SwiftUI
import AVKit

struct PracticeVideoPlayerSheet: View {
    let url: URL
    var isVoiceTake: Bool = false
    var sceneTitle: String = "Take"
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            OTNavHeader(title: isVoiceTake ? "Voice rehearsal take" : "Preview take", backLabel: "Close", onBack: { dismiss() })
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.m)
                .padding(.bottom, OTSpace.s)
                .background(Color.black)

            if isVoiceTake {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.06, blue: 0.12), Color(red: 0.04, green: 0.03, blue: 0.06)], // ot-lint:allow
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack(spacing: OTSpace.xl) {
                        Spacer()

                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 96)) // ot-lint:allow
                            .foregroundStyle(OT.reader)

                        VStack(spacing: 6) { // ot-lint:allow
                            Text(sceneTitle)
                                .font(.otTitle)
                                .foregroundStyle(.white)
                            Text("Voice rehearsal take")
                                .font(.otFootnote)
                                .foregroundStyle(.white.opacity(0.65))
                        }

                        VideoPlayer(player: player ?? AVPlayer(url: url))
                            .frame(height: 60) // ot-lint:allow
                            .padding(.horizontal, OTSpace.gutter)

                        Spacer()
                    }
                }
            } else {
                VideoPlayer(player: player ?? AVPlayer(url: url))
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
