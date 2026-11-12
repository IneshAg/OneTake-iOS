import SwiftUI

struct PracticeOptionsView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store

    var body: some View {
        if let audition = store.audition(auditionID),
           audition.scenes.indices.contains(sceneIndex) {
            let scene = audition.scenes[sceneIndex]

            OTScreen(
                title: "Practice",
                onBack: { store.pop() }
            ) {
                VStack(alignment: .leading, spacing: OTSpace.l) {
                    VStack(alignment: .leading, spacing: OTSpace.xxs) {
                        Text(scene.title).font(.otLargeTitle)
                        Text("\(audition.project) · \(audition.role)")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                    }

                    Text("Choose how you want to rehearse")
                        .font(.otHeadline)

                    VStack(spacing: OTSpace.s) {
                        practiceButton(
                            title: "Practice the scene",
                            detail: "Follow the scene and speak your lines",
                            symbol: "play.fill"
                        ) {
                            store.push(.runLines(auditionID, sceneIndex: sceneIndex))
                        }
                        practiceButton(
                            title: "First-letter prompts",
                            detail: "Use the first letter of each word",
                            symbol: "textformat"
                        ) {
                            store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: .firstLetter))
                        }
                        practiceButton(
                            title: "Meaningful word gaps",
                            detail: "Hide key words · tap a gap for a clue",
                            symbol: "text.word.spacing"
                        ) {
                            store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: .gapRecall))
                        }
                        practiceButton(
                            title: "Cold read",
                            detail: "Hide your lines and reveal them when needed",
                            symbol: "eye.slash"
                        ) {
                            store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: .maskAndReveal))
                        }
                        practiceButton(
                            title: "Audio gap",
                            detail: "Hear the reader and answer in the pauses",
                            symbol: "waveform"
                        ) {
                            store.push(.runLines(auditionID, sceneIndex: sceneIndex))
                        }
                        practiceButton(
                            title: "Audio walk",
                            detail: "Rehearse hands-free with your reader recordings",
                            symbol: "headphones"
                        ) {
                            store.push(.audioWalk(auditionID, sceneIndex: sceneIndex))
                        }
                        practiceButton(
                            title: "Record a practice take",
                            detail: "Record yourself without submitting a tape",
                            symbol: "record.circle"
                        ) {
                            let piece = store.practicePiece(for: auditionID, sceneIndex: sceneIndex)
                            store.camera = .practiceTake(pieceID: piece.id)
                        }
                    }
                }
            }
        }
    }

    private func practiceButton(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OTSpace.m) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(OT.accent)
                    .frame(width: 42, height: 42) // ot-lint:allow
                    .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.m))
                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                    Text(title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                    Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OT.labelTertiary)
            }
            .padding(OTSpace.m)
            .otCard(.grouped)
        }
        .buttonStyle(.plain)
    }
}
