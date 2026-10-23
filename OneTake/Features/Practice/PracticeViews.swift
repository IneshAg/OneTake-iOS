import SwiftUI

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
                        Text("\(piece.detail) · 3 takes so far").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        ReadinessDashes(done: piece.linesLearned, total: piece.linesTotal)
                        HStack {
                            Button { if let a = store.auditions.first { store.push(.runLines(a.id, sceneIndex: 0)) } } label: { Label("Run lines", systemImage: "play.fill") }.buttonStyle(.otPrimary)
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
    /// the first upcoming audition's first scene — the same fallback already used by "Run lines" above.
    private func start(_ mode: LineLearningMode) {
        guard let a = store.auditions.first else { return }
        let sceneIndex = 0
        switch mode {
        case .firstLetter, .maskAndReveal: store.push(.lineDrill(a.id, sceneIndex: sceneIndex, mode: mode))
        case .audioGap:                    store.push(.runLines(a.id, sceneIndex: sceneIndex))
        case .handsFreeWalk:               store.push(.audioWalk(a.id, sceneIndex: sceneIndex))
        }
    }
}

// MARK: - 24b / 24c Practise a scene

struct PracticeSetupView: View {
    @Environment(AppStore.self) private var store
    @State private var playing = "Sam"
    @State private var reader = "Your recording"

    var body: some View {
        Form {
            Section("Bring it in") {
                Label("Paste", systemImage: "doc.on.clipboard")
                Button { store.camera = .scanSides } label: { Label("Scan pages", systemImage: "doc.viewfinder") }
                Label("PDF or file", systemImage: "folder")
                Label("Type it in", systemImage: "keyboard")
            }
            Section("Who are you playing?") {
                Picker("You play", selection: $playing) { Text("Sam").tag("Sam"); Text("Nina").tag("Nina") }.pickerStyle(.segmented)
            }
            Section("Who reads Nina?") {
                Picker("Reader", selection: $reader) {
                    Text("Your recording").tag("Your recording"); Text("Nobody — I’ll hear the cues in my head").tag("Nobody")
                }
                .pickerStyle(.inline).labelsHidden()
            }
            Section { Label("Practice pieces and takes stay on this iPhone", systemImage: "lock.fill").font(.otFootnote) }
        }
        .navigationTitle("Practise a scene")
        .safeAreaInset(edge: .bottom) {
            Button("Start practising") { if let a = store.auditions.first { store.push(.runLines(a.id, sceneIndex: 0)) } }
                .buttonStyle(.otPrimary).padding(OT.gutter)
        }
    }
}

// MARK: - 24e Practice take (no slate, never sent)

struct PracticeTakeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle()) }
                    Spacer()
                    Text("Practice · TK 4").font(.otFootnote.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32).background(OT.cameraGlass, in: Capsule())
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
        .onDisappear { camera.stop() }
    }
}
