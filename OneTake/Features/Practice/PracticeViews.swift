import SwiftUI
import AVKit

// MARK: - 24 Practice (tab)

struct PracticeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Practice").font(.otLargeTitle)
                    Spacer()
                    Button { store.push(.practiceSetup) } label: {
                        Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(OT.labelOnAccent)
                            .frame(width: 44, height: 44).background(OT.accent, in: Circle())
                    }
                    .accessibilityLabel("Practise a new scene")
                }
                Text("Nothing due? Run a scene anyway.").font(.otCallout).foregroundStyle(OT.labelSecondary)
                // Time/duration tracking is cut for MVP — a real stats view (practice history, time
                // invested) comes later, rather than a partial number shown ad hoc here.

                if let piece = store.practice.first {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Pick up where you left off")
                        Text(piece.title).font(.otTitle)
                        Text("\(piece.detail) · \(piece.takesRecorded == 0 ? "no takes yet" : "\(piece.takesRecorded) take\(piece.takesRecorded == 1 ? "" : "s") so far")").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        ReadinessDashes(done: piece.linesLearned, total: piece.linesTotal)
                        HStack {
                            Button { if let id = piece.auditionID, let scene = piece.sceneIndex { store.push(.runLines(id, sceneIndex: scene)) } } label: { Label("Run lines", systemImage: "play.fill") }.buttonStyle(.otPrimary)
                            Button("Record a take") { store.camera = .practiceTake }.buttonStyle(.otSecondary)
                        }
                    }
                    .padding(18).otCard()
                }

                QuickDrillsGrid { mode in start(mode) }

                SectionLabel(text: "Your pieces")
                ForEach(store.practice) { p in
                    HStack {
                        VStack(alignment: .leading) { Text(p.title).font(.otBody); Text(p.detail).font(.otFootnote).foregroundStyle(OT.labelTertiary) }
                        Spacer()
                        Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                    }
                    .frame(minHeight: 56)
                    Divider()
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 120)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Quick Drills need a scene to operate on: prefer the piece currently being picked up, else
    /// the first upcoming audition's first scene — creating a real `PracticePiece` for it if one
    /// doesn't exist yet, so progress has somewhere real to be tracked.
    private func start(_ mode: LineLearningMode) {
        let auditionID: Audition.ID
        let sceneIndex: Int
        if let piece = store.practice.first, let id = piece.auditionID, let scene = piece.sceneIndex {
            auditionID = id
            sceneIndex = scene
        } else if let a = store.auditions.first(where: { !$0.scenes.isEmpty }) {
            auditionID = a.id
            sceneIndex = 0
            store.practicePiece(for: auditionID, sceneIndex: sceneIndex)
        } else {
            return
        }
        switch mode {
        case .firstLetter, .maskAndReveal: store.push(.lineDrill(auditionID, sceneIndex: sceneIndex, mode: mode))
        case .audioGap:                    store.push(.runLines(auditionID, sceneIndex: sceneIndex))
        case .handsFreeWalk:               store.push(.audioWalk(auditionID, sceneIndex: sceneIndex))
        }
    }
}

// MARK: - 24b / 24c Practise a scene

struct PracticeSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// "Bring it in" here deliberately reuses Add Audition's real scan/paste/file import rather than
    /// duplicating that OCR pipeline for a second entry point — picking an audition below covers the
    /// common case (practicing a scene you've already added) for now.
    var body: some View {
        Form {
            Section("Choose a scene") {
                let withScenes = store.auditions.filter { !$0.scenes.isEmpty }
                if withScenes.isEmpty {
                    Text("Add an audition with sides first — Practice pulls real scenes from your auditions.")
                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                } else {
                    ForEach(withScenes) { a in
                        ForEach(Array(a.scenes.enumerated()), id: \.element.id) { i, scene in
                            Button { start(auditionID: a.id, sceneIndex: i) } label: {
                                IconRow(symbol: "theatermasks", title: scene.title, detail: "\(a.project) · \(a.role)")
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section { Label("Practice pieces and takes stay on this iPhone", systemImage: "lock.fill").font(.otFootnote) }
        }
        .navigationTitle("Practise a scene")
    }

    private func start(auditionID: Audition.ID, sceneIndex: Int) {
        store.practicePiece(for: auditionID, sceneIndex: sceneIndex)
        dismiss()
        store.push(.runLines(auditionID, sceneIndex: sceneIndex))
    }
}

// MARK: - 24e Practice take (no slate, never sent)

struct PracticeTakeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()

    private var piece: PracticePiece? { store.practice.first }

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle()) }
                    Spacer()
                    Text("Practice · TK \((piece?.takesRecorded ?? 0) + 1)").font(.otFootnote.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32).background(OT.cameraGlass, in: Capsule())
                    Spacer()
                    Color.clear.frame(width: 44)
                }
                Spacer()
                Label("Practice · no slate, never sent", systemImage: "lock.fill").font(.otFootnote).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 30).background(.black.opacity(0.55), in: Capsule())
                RecordButton(isRecording: camera.state == .recording) {
                    camera.state == .recording ? camera.stopRecording() : camera.startRecording()
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, OT.gutter)
        }
        .preferredColorScheme(.dark)
        .keepScreenAwake()
        .task { if await CameraController.requestAccess() { camera.configure() } }
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            if camera.state == .recording { camera.stopRecording() } else { camera.startRecording() }
        }
        .onChange(of: camera.state) { _, newState in
            guard newState == .ready, let url = camera.lastRecording, let piece else { return }
            let number = piece.takesRecorded + 1
            if MediaStore.persist(url, as: "take-\(number)-\(UUID().uuidString).mov", in: "practice-\(piece.id.uuidString)") != nil {
                store.incrementPracticeTakes(for: piece.id)
            }
        }
        .onDisappear { camera.stop() }
    }
}
