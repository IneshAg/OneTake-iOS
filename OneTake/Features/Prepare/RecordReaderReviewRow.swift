import SwiftUI
import OneTakeUI

struct RecordReaderReviewRow: View {
    let idx: Int
    let line: ScriptLine
    let auditionID: Audition.ID
    let sceneIndex: Int
    let isRec: Bool
    @Bindable var player: ReaderTrackPlayer
    @Binding var playingReviewIndex: Int?
    @Binding var expandedReviewIndex: Int?
    var onRetake: () -> Void
    var onTrim: () -> Void
    var onRestore: () -> Void

    var body: some View {
        let isSilent = line.isSilentReactionCue
        VStack(alignment: .leading, spacing: OTSpace.s) {
            HStack(spacing: OTSpace.m) {
                Button {
                    if isRec && !isSilent {
                        if player.isPlaying && playingReviewIndex == idx {
                            player.pause()
                        } else if !player.isPlaying && playingReviewIndex == idx {
                            player.resume()
                        } else {
                            player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: idx)
                            playingReviewIndex = idx
                            expandedReviewIndex = idx
                        }
                    }
                } label: {
                    Image(systemName: isSilent ? "face.smiling" : (isRec ? (player.isPlaying && playingReviewIndex == idx ? "pause.fill" : "play.fill") : "mic.slash"))
                        .foregroundStyle(isSilent ? OT.accent : (isRec ? OT.labelPrimary : OT.labelTertiary))
                        .frame(width: 36, height: 36) // ot-lint:allow
                        .background(OT.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isRec || isSilent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Line \(idx + 1)")
                        .font(.otHeadline)
                    Text(isSilent ? "Silent reaction beat [ \(line.text) ] · No audio needed" : line.text)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if isRec {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedReviewIndex == idx {
                                expandedReviewIndex = nil
                            } else {
                                expandedReviewIndex = idx
                            }
                        }
                    } label: {
                        Image(systemName: expandedReviewIndex == idx ? "chevron.up.circle.fill" : "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold)) // ot-lint:allow
                            .foregroundStyle(expandedReviewIndex == idx ? OT.accent : OT.labelTertiary)
                            .frame(width: 32, height: 32) // ot-lint:allow
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expandedReviewIndex == idx ? "Hide audio scrubber" : "Scrub audio")
                }

                Button {
                    onRetake()
                } label: {
                    HStack(spacing: OTSpace.xxs) {
                        Image(systemName: isRec ? "arrow.clockwise" : "mic.fill")
                        Text(isRec ? "Retake" : "Record")
                    }
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(isRec ? OT.accent : OT.reader)
                    .padding(.horizontal, OTSpace.s)
                    .padding(.vertical, OTSpace.xxs)
                    .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isRec {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedReviewIndex == idx {
                            expandedReviewIndex = nil
                        } else {
                            expandedReviewIndex = idx
                        }
                    }
                }
            }

            if isRec && (expandedReviewIndex == idx || playingReviewIndex == idx) {
                ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: idx, compact: false)
                    .padding(.top, OTSpace.xxs)
                HStack(spacing: OTSpace.s) {
                    Button {
                        onTrim()
                    } label: {
                        Label("Trim audio", systemImage: "scissors")
                            .font(.otFootnote.weight(.semibold))
                    }
                    .buttonStyle(.otGlass)

                    if ReaderTrackPlayer.hasOriginal(auditionID: auditionID, sceneIndex: sceneIndex, line: idx) {
                        Button {
                            onRestore()
                        } label: {
                            Label("Restore original", systemImage: "arrow.uturn.backward")
                                .font(.otFootnote.weight(.semibold))
                        }
                        .buttonStyle(.otGlass)
                    }
                }
            }
        }
        .padding(OTSpace.cardInset)
        .otCard(.grouped)
    }
}
