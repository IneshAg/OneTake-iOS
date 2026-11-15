import SwiftUI
import AVKit
import OneTakeUI

struct PracticeVideoPlayerSheet: View {
    let url: URL
    var isVoiceTake: Bool = false
    var sceneTitle: String = "Take"
    var onTrimmed: ((URL) -> URL?)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var activeURL: URL?
    @State private var showTrimmer = false

    private var currentURL: URL { activeURL ?? url }

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

                            OTVoicePlayerView(url: currentURL, autoPlay: true)
                                .padding(.horizontal, OTSpace.gutter)

                            Spacer(minLength: OTSpace.xl)
                        }
                    }
                    .otCanvas()
                } else {
                    VideoPlayer(player: player ?? AVPlayer(url: currentURL))
                        .ignoresSafeArea(edges: .bottom)
                        .background(OT.cameraBg.ignoresSafeArea())
                        .onAppear {
                            let p = AVPlayer(url: currentURL)
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
                if !isVoiceTake && onTrimmed != nil && VideoTrimmer.canTrim(currentURL) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            player?.pause()
                            showTrimmer = true
                        } label: {
                            Label("Trim", systemImage: "scissors")
                        }
                    }
                }
            }
            .sheet(isPresented: $showTrimmer) {
                VideoTrimmer(url: currentURL) { edited in
                    showTrimmer = false
                    guard let edited else { return }
                    let resolved = onTrimmed?(edited) ?? edited
                    let updated = AVPlayer(url: resolved)
                    player?.pause()
                    player = updated
                    activeURL = resolved
                    updated.play()
                    Haptics.success()
                }
            }
        }
    }
}
