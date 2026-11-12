import SwiftUI

// MARK: - 7 · L2 Package sheet

struct PackageSheet: View {
    let auditionID: Audition.ID
    var onAddSides: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let a = store.audition(auditionID) {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                HStack {
                    VStack(alignment: .leading, spacing: OTSpace.xxs) {
                        Text("Package").font(.otTitle)
                        Text("In tape order · \(a.readyCount) of \(a.totalCount) ready").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    }
                    Spacer()
                    OTIconButton("xmark", accessibilityLabel: "Close") {
                        dismiss()
                    }
                }
                ForEach(Array(a.pieces.enumerated()), id: \.element.id) { i, piece in
                    HStack(spacing: OTSpace.m) {
                        Button { dismiss(); open(piece, a) } label: {
                            HStack(spacing: OTSpace.m) {
                                Image(systemName: piece.isDone ? "checkmark" : piece.kind.symbol)
                                    .foregroundStyle(piece.isDone ? OT.labelOnAccent : OT.accent)
                                    .frame(width: 44, height: 44) // ot-lint:allow
                                    .background(piece.isDone ? OT.accent : OT.accentSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: OTSpace.xs) {
                                        Text("\(i + 1)  \(piece.title)").font(.otHeadline)
                                        if piece.isOptional {
                                            OTChip("Optional")
                                        }
                                    }
                                    Text(piece.detail.isEmpty ? "not shot yet" : piece.detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if piece.id == a.nextPiece?.id { Text("Next").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent) }
                        Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                    }
                    .frame(minHeight: 56) // ot-lint:allow
                }
                Spacer()
            }
            .padding(OTSpace.gutter)
        }
    }

    private func open(_ piece: Piece, _ a: Audition) {
        switch piece.kind {
        case .headshot: store.push(.headshots(for: a.id))
        case .slate, .fullLength: store.push(.shootSetup(a.id))
        case .scene:
            if a.scenes.isEmpty {
                onAddSides?()
            } else {
                store.push(.prepare(a.id, sceneIndex: store.sceneIndex(for: piece, in: a.id)))
            }
        }
    }
}
