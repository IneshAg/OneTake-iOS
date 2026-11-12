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
                    VStack(alignment: .leading, spacing: 22) {
                        // Time/duration tracking is cut for MVP — a real stats view (practice history, time
                        // invested) comes later, rather than a partial number shown ad hoc here.

                        if let piece = displayedPractice.first {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(text: "Pick up where you left off")
                                Text(piece.title).font(.otTitle)
                                Text("\(piece.detail) · \(piece.takesRecorded == 0 ? "no takes yet" : "\(piece.takesRecorded) take\(piece.takesRecorded == 1 ? "" : "s") so far")").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                ReadinessDashes(done: piece.linesLearned, total: piece.linesTotal)
                                HStack {
                                    Button { open(piece) } label: { Label("Practise", systemImage: "play.fill") }.buttonStyle(.otPrimary)
                                    Button("Record a take") { store.promotePracticePiece(piece.id); store.camera = .practiceTake(pieceID: piece.id) }.buttonStyle(.otSecondary)
                                }
                            }
                            .padding(18).otCard()
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

                        if !store.auditions.isEmpty && !store.auditions.contains(where: { !$0.scenes.isEmpty }) { noScenesCard }

                        SectionLabel(text: "Your pieces")
                        ForEach(displayedPractice) { p in
                            Button { open(p) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(p.title).font(.otBody).foregroundStyle(OT.labelPrimary)
                                        Text("\(p.detail) · \(p.linesLearned) of \(p.linesTotal) lines learned").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                                }
                                .frame(minHeight: 56)
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
                    .padding(.horizontal, OT.gutter)
                    .padding(.bottom, 120)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .safeAreaInset(edge: .top) { header }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .showSystemTabBar()
        .sheet(isPresented: Binding(get: { sidesAuditionID != nil }, set: { if !$0 { sidesAuditionID = nil } })) {
            if let id = sidesAuditionID { RevisedSidesSheet(auditionID: id) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Practice")
                .font(.otLargeTitle)
                .foregroundStyle(OT.labelPrimary)
            Spacer()
            GlassIconButton(systemName: "plus", accessibilityLabel: "Practise a new scene") {
                store.push(.practiceSetup)
            }
            ProfileButton { store.showProfile = true }
        }
        .padding(.horizontal, OT.gutter)
        .padding(.bottom, 6)
        .background(OT.bgCanvas)
    }

    /// Practice works on scenes read from your auditions' sides. When auditions exist without sides, prompt to add them.
    private var noScenesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No audition scenes yet", systemImage: "theatermasks").font(.otHeadline)
            Text("Add audition sides, or create a personal scene with +.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            ForEach(store.auditions) { a in
                Button { sidesAuditionID = a.id } label: {
                    IconRow(symbol: "doc.badge.plus", title: "Add sides", detail: "\(a.project) · \(a.role)")
                }.buttonStyle(.plain)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).otCard()
    }

    /// A piece opens its shared Practice options — as long as the audition it came from still has it.
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

struct PracticeOptionsView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store

    var body: some View {
        if let audition = store.audition(auditionID),
           audition.scenes.indices.contains(sceneIndex) {
            let scene = audition.scenes[sceneIndex]
            VStack(alignment: .leading, spacing: 18) {
                InContentNavHeader(
                    title: "Practice",
                    backLabel: "Back",
                    onBack: { store.pop() }
                )
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.title).font(.otLargeTitle)
                    Text("\(audition.project) · \(audition.role)")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelTertiary)
                }

                Text("Rehearsal studio")
                    .font(.otHeadline)

                VStack(spacing: 12) {
                    Button {
                        let practicePiece = store.practicePiece(for: auditionID, sceneIndex: sceneIndex)
                        store.camera = .practiceTake(pieceID: practicePiece.id)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Rehearse scene")
                                    .font(.otHeadline)
                                    .foregroundStyle(.white)
                                Text("Full lines, first letters, or hidden text · play audio or pause for reader")
                                    .font(.otFootnote)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(16)
                    }
                    .buttonStyle(.otPrimary)

                    practiceButton(
                        title: "Audio walk",
                        detail: "Rehearse hands-free on the go with your reader cues",
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

                Spacer()
            }
            .padding(.horizontal, OT.gutter)
            .otCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
        }
    }

    private func practiceButton(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 42, height: 42)
                    .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                    Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OT.labelTertiary)
            }
            .padding(12)
            .otCard(radius: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 24a Empty

struct EmptyPracticeView: View {
    var showSample = true
    var openSample: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("onetake-practice-illustration")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340, maxHeight: 300)
                .accessibilityLabel("No practice pieces yet illustration")

            Text("No practice pieces yet")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(OT.labelPrimary)

            if showSample {
                Button(action: openSample) {
                    Label("Try a sample scene", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.otPrimary)
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OT.gutter)
    }
}

