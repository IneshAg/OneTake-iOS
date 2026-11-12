import SwiftUI

// MARK: - 24 Practice (tab)

struct PracticeView: View {
    @Environment(AppStore.self) private var store
    @State private var sidesAuditionID: Audition.ID?
    @AppStorage("practice.showSample") private var showSample = true

    /// Practice pieces with sample data filtered out when "Show sample scene" is off.
    private var displayedPractice: [PracticePiece] {
        showSample ? store.practice : store.practice.filter { !store.isSamplePiece($0) }
    }

    var body: some View {
        Group {
            if displayedPractice.isEmpty {
                EmptyPracticeView(showSample: showSample) {
                    store.push(.practiceSample)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: OTSpace.l) {
                        if let piece = displayedPractice.first {
                            VStack(alignment: .leading, spacing: OTSpace.s) {
                                OTSectionLabel("Pick up where you left off")
                                Text(piece.title).font(.otTitle)
                                Text("\(piece.detail) · \(piece.takesRecorded == 0 ? "no takes yet" : "\(piece.takesRecorded) take\(piece.takesRecorded == 1 ? "" : "s") so far")")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelTertiary)
                                ReadinessDashes(done: piece.linesLearned, total: piece.linesTotal)
                                HStack {
                                    Button {
                                        open(piece)
                                    } label: {
                                        Label("Practise", systemImage: "play.fill")
                                    }
                                    .buttonStyle(.otPrimary)

                                    Button("Record a take") {
                                        store.promotePracticePiece(piece.id)
                                        store.camera = .practiceTake(pieceID: piece.id)
                                    }
                                    .buttonStyle(.otSecondary)
                                }
                            }
                            .padding(OTSpace.m)
                            .otCard(.grouped)
                            .contextMenu {
                                if piece.linesLearned >= piece.linesTotal && piece.linesTotal > 0 {
                                    Button {
                                        store.recordStandaloneRun(pieceID: piece.id, linesOnYourOwn: 0)
                                        Haptics.tick()
                                    } label: {
                                        Label("Mark unlearned", systemImage: "arrow.counterclockwise")
                                    }
                                } else {
                                    Button {
                                        store.recordStandaloneRun(pieceID: piece.id, linesOnYourOwn: piece.linesTotal)
                                        Haptics.success()
                                    } label: {
                                        Label("Mark lines learned", systemImage: "checkmark.circle")
                                    }
                                }
                            }
                        }

                        if !store.auditions.isEmpty && !store.auditions.contains(where: { !$0.scenes.isEmpty }) {
                            noScenesCard
                        }

                        OTSectionLabel("Your pieces")
                        ForEach(displayedPractice) { p in
                            Button { open(p) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                        Text(p.title).font(.otBody).foregroundStyle(OT.labelPrimary)
                                        Text("\(p.detail) · \(p.linesLearned) of \(p.linesTotal) lines learned")
                                            .font(.otFootnote)
                                            .foregroundStyle(OT.labelTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                                }
                                .frame(minHeight: 56) // ot-lint:allow
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canOpen(p))
                            .contextMenu {
                                if p.linesLearned >= p.linesTotal && p.linesTotal > 0 {
                                    Button {
                                        store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: 0)
                                        Haptics.tick()
                                    } label: {
                                        Label("Mark unlearned", systemImage: "arrow.counterclockwise")
                                    }
                                } else {
                                    Button {
                                        store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: p.linesTotal)
                                        Haptics.success()
                                    } label: {
                                        Label("Mark lines learned", systemImage: "checkmark.circle")
                                    }
                                }
                                if p.linesLearned > 0 && p.linesLearned < p.linesTotal {
                                    Button(role: .destructive) {
                                        store.recordStandaloneRun(pieceID: p.id, linesOnYourOwn: 0)
                                        Haptics.tick()
                                    } label: {
                                        Label("Reset progress", systemImage: "arrow.counterclockwise")
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                    .padding(.horizontal, OTSpace.gutter)
                    .padding(.bottom, 120) // ot-lint:allow
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .safeAreaInset(edge: .top) { header }
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: Binding(get: { sidesAuditionID != nil }, set: { if !$0 { sidesAuditionID = nil } })) {
            if let id = sidesAuditionID { RevisedSidesSheet(auditionID: id) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: OTSpace.s) {
            Text("Practice")
                .font(.otLargeTitle)
                .foregroundStyle(OT.labelPrimary)
            Spacer()
            OTIconButton("plus", accessibilityLabel: "Practise a new scene") {
                store.push(.practiceSetup)
            }
            ProfileButton { store.showProfile = true }
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.bottom, 6) // ot-lint:allow
        .background(OT.bgCanvas)
    }

    private var noScenesCard: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            Label("No audition scenes yet", systemImage: "theatermasks").font(.otHeadline)
            Text("Add audition sides, or create a personal scene with +.")
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)
            ForEach(store.auditions) { a in
                Button { sidesAuditionID = a.id } label: {
                    OTIconRow(symbol: "doc.badge.plus", title: "Add sides", detail: "\(a.project) · \(a.role)")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(OTSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .otCard(.grouped)
    }

    private func canOpen(_ p: PracticePiece) -> Bool {
        if let scene = p.scene { return !scene.lines.isEmpty }
        guard let id = p.auditionID, let scene = p.sceneIndex else { return false }
        return store.audition(id)?.scenes.indices.contains(scene) ?? false
    }

    private func open(_ p: PracticePiece) {
        guard canOpen(p) else { return }
        if let id = p.auditionID, let scene = p.sceneIndex {
            store.push(.practiceOptions(id, sceneIndex: scene))
        } else {
            store.promotePracticePiece(p.id)
            store.push(.standalonePractice(p.id))
        }
    }
}

// MARK: - 24a Empty

struct EmptyPracticeView: View {
    var showSample = true
    var openSample: () -> Void = {}

    var body: some View {
        VStack(spacing: OTSpace.m) {
            Spacer()

            Image("onetake-practice-illustration")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340, maxHeight: 300) // ot-lint:allow
                .accessibilityLabel("No practice pieces yet illustration")

            Text("No practice pieces yet")
                .font(.system(size: 26, weight: .bold)) // ot-lint:allow
                .foregroundStyle(OT.labelPrimary)

            if showSample {
                Button(action: openSample) {
                    Label("Try a sample scene", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.otPrimary)
                .padding(.horizontal, OTSpace.xl)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OTSpace.gutter)
    }
}
