import SwiftUI
import AVKit
import OneTakeUI

struct PracticeVideoPlayerSheet: View {
    let url: URL
    var isVoiceTake: Bool = false
    var sceneTitle: String = "Take"
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if isVoiceTake {
                    ScrollView {
                        VStack(spacing: OTSpace.xl) {
                            Spacer(minLength: OTSpace.xl)

                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 84)) // ot-lint:allow
                                .foregroundStyle(OT.reader)

                            VStack(spacing: OTSpace.xs) {
                                Text(sceneTitle)
                                    .font(.otTitle)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Voice rehearsal take")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }

                            OTVoicePlayerView(url: url, autoPlay: true)
                                .padding(.horizontal, OTSpace.gutter)

                            Spacer(minLength: OTSpace.xl)
                        }
                    }
                    .otCanvas()
                } else {
                    VideoPlayer(player: player ?? AVPlayer(url: url))
                        .ignoresSafeArea(edges: .bottom)
                        .background(OT.cameraBg.ignoresSafeArea())
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
            .navigationTitle(isVoiceTake ? "Play voice" : "Preview take")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
