import SwiftUI

// MARK: - 7 · L2 Package sheet

struct PackageSheet: View {
    let auditionID: Audition.ID
    var onAddSides: (() -> Void)? = nil
    var onSelectPiece: ((Piece) -> Void)? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let a = store.audition(auditionID) {
            NavigationStack {
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    Text("In tape order · \(a.readyCount) of \(a.totalCount) ready")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                ForEach(Array(a.pieces.enumerated()), id: \.element.id) { i, piece in
                    Button {
                        if let onSelectPiece {
                            onSelectPiece(piece)
                            dismiss()
                        } else {
                            dismiss()
                            DispatchQueue.main.async {
                                open(piece, a)
                            }
                        }
                    } label: {
                        HStack(spacing: OTSpace.m) {
                            Image(systemName: piece.isDone ? "checkmark" : piece.kind.symbol)
                                .foregroundStyle(piece.isDone ? OT.labelOnAccent : OT.accent)
                                .frame(width: 44, height: 44) // ot-lint:allow
                                .background(piece.isDone ? OT.accent : OT.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: OTSpace.xs) {
                                    Text("\(i + 1)  \(piece.title)")
                                        .font(.otHeadline)
                                        .foregroundStyle(OT.labelPrimary)
                                    if piece.isOptional {
                                        OTChip("Optional")
                                    }
                                }
                                Text(rowDetail(for: piece))
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelTertiary)
                            }

                            Spacer()

                            if piece.id == a.nextPiece?.id {
                                Text("Next")
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                            }
                            Image(systemName: "chevron.forward")
                                .font(.caption)
                                .foregroundStyle(OT.labelTertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading) // ot-lint:allow
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .padding(.bottom, OTSpace.gutter)
                .otCanvas()
                .navigationTitle("Package")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onAppear { store.syncPieces() }
        }
    }

    private func rowDetail(for piece: Piece) -> String {
        if !piece.detail.isEmpty { return piece.detail }
        if piece.isDone {
            return piece.isOptional ? "Skipped for now" : "Recorded"
        }
        return "not shot yet"
    }

    static func destination(for piece: Piece, in a: Audition, store: AppStore) -> Route? {
        switch piece.kind {
        case .headshot:
            return .headshots(for: a.id)
        case .slate:
            return a.slateVideoURL != nil ? .elementReview(a.id, element: .slate) : .shootSetup(a.id)
        case .fullLength:
            return a.fullLengthVideoURL != nil ? .elementReview(a.id, element: .fullLength) : .shootSetup(a.id)
        case .scene:
            guard !a.scenes.isEmpty else { return nil }
            return .prepare(a.id, sceneIndex: store.sceneIndex(for: piece, in: a.id))
        }
    }

    private func open(_ piece: Piece, _ a: Audition) {
        if let route = Self.destination(for: piece, in: a, store: store) {
            store.push(route)
        } else {
            onAddSides?()
        }
    }
}
