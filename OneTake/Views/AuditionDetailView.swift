import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import VisionKit

/// 07 Audition detail (and 7.0 "just added · 0 of 4" when nothing is done yet).
struct AuditionDetailView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var showPackage = false
    @State private var showDelete = false
    @State private var showCallback = false
    @State private var showEdit = false
    @State private var showSides = false

    var body: some View {
        if let audition = store.audition(auditionID) {
            content(audition)
        } else {
            ContentUnavailableView("Audition removed", systemImage: "trash")
        }
    }

    private func content(_ a: Audition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top controls (back & options)
                InContentNavHeader(backLabel: "Auditions", onBack: { store.pop() }) {
                    Menu {
                        Button { showEdit = true } label: { Label("Edit details", systemImage: "pencil") }
                        Button { showCallback = true } label: { Label("Start a callback", systemImage: "arrow.uturn.right") }
                        Divider()
                        Button(role: .destructive) { showDelete = true } label: { Label("Delete audition", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OT.labelPrimary)
                            .frame(width: 38, height: 38)
                            .background(OT.fillField, in: Circle())
                            .contentShape(Circle())
                    }
                }
                .padding(.top, 4)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "\(a.projectType) · reading for \(a.role)" + (a.round.map { " · round \($0)" } ?? ""))
                    Text(a.project).font(.system(size: 40, weight: .bold)).foregroundStyle(OT.labelPrimary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        let rem = a.dueRemaining
                        if rem.isPastDue {
                            Text("0").font(.otNumber).foregroundStyle(OT.due)
                            Text("mins left").font(.otHeadline).foregroundStyle(OT.due)
                        } else if rem.days >= 1 {
                            Text("\(rem.days)").font(.otNumber).foregroundStyle(OT.due)
                            Text(rem.days == 1 ? "day" : "days").font(.otHeadline).foregroundStyle(OT.due)
                            if rem.hours > 0 {
                                Text("\(rem.hours)").font(.otNumber).foregroundStyle(OT.due)
                                Text(rem.hours == 1 ? "hr" : "hrs").font(.otHeadline).foregroundStyle(OT.due)
                            }
                            Text("left").font(.otHeadline).foregroundStyle(OT.due)
                        } else if rem.hours >= 1 {
                            Text("\(rem.hours)").font(.otNumber).foregroundStyle(OT.due)
                            Text(rem.hours == 1 ? "hr left" : "hrs left").font(.otHeadline).foregroundStyle(OT.due)
                        } else {
                            let mins = max(1, rem.minutes)
                            Text("\(mins)").font(.otNumber).foregroundStyle(OT.due)
                            Text(mins == 1 ? "min left" : "mins left").font(.otHeadline).foregroundStyle(OT.due)
                        }
                        Text("·  Due \(a.due.otDue)").font(.otCallout).foregroundStyle(OT.labelSecondary)
                    }
                    if !a.asks.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(a.asks.prefix(3), id: \.self) { Text($0).font(.otFootnote).foregroundStyle(OT.labelSecondary) }
                            if a.asks.count > 3 { Text("+\(a.asks.count - 3)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent) }
                        }
                    }
                }

                // Package
                Button { showPackage = true } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "Package")
                            Spacer()
                            Label("All pieces", systemImage: "chevron.forward").labelStyle(TrailingIconLabelStyle())
                                .font(.otFootnote).foregroundStyle(OT.accent)
                        }
                        HStack(spacing: 6) {
                            Text("\(a.readyCount) of \(a.totalCount) ready").font(.otHeadline).foregroundStyle(OT.labelPrimary)
                            if let next = a.nextPiece {
                                Text(a.readyCount == 0 ? "· \(next.title) first" : "· \(next.title) next").font(.otCallout).foregroundStyle(OT.labelSecondary)
                            }
                        }
                        PackageStepsBar(pieces: a.pieces)
                    }
                }
                .buttonStyle(.plain)

                upNext(a)

                sidesCard(a)

                headshotsCard(a)

                if let then = thenLine(a) {
                    Button { showPackage = true } label: {
                        HStack {
                            Text("Then").font(.otFootnote.weight(.semibold))
                            Text(then).font(.otFootnote).foregroundStyle(OT.labelSecondary)
                            Spacer()
                            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                        }
                        .frame(minHeight: OT.minTap)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 40)
        }
        .otCanvas()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showPackage) {
            PackageSheet(auditionID: a.id, onAddSides: { showSides = true })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCallback) { CallbackSheet(audition: a) }
        .sheet(isPresented: $showEdit) { EditAuditionSheet(auditionID: a.id) }
        .sheet(isPresented: $showSides) { RevisedSidesSheet(auditionID: a.id) }
        .confirmationDialog("Delete “\(a.project)”?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.deleteAudition(a.id); store.popToRoot() }
        } message: { Text("Its slate, reader track and any takes are removed from this iPhone. Your headshots stay in Profile.") }
    }

    // MARK: Up next panel

    @ViewBuilder private func upNext(_ a: Audition) -> some View {
        let next = a.nextPiece
        VStack(alignment: .leading, spacing: 12) {
            if next?.kind == .headshot {
                let isOpt = next?.isOptional ?? false
                HStack {
                    SectionLabel(text: isOpt ? "Up next · Headshots (Optional)" : "Up next · Headshots")
                    Spacer()
                    Button(isOpt ? "Make required" : "Make optional") {
                        if let pieceID = next?.id {
                            store.togglePieceOptional(for: a.id, pieceID: pieceID)
                            Haptics.tick()
                        }
                    }
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }
                Text("Audition headshots").font(.otTitle)
                quoteLine(isOpt ? "Optional · sent alongside your video tape as photos." : "Required in package · 3 photos (front, left, right profile).")
                HStack(spacing: 10) {
                    Button("Manage headshots") { store.push(.headshots(for: a.id)) }.buttonStyle(.otPrimary)
                    if isOpt {
                        Button("Skip for now") {
                            if let pieceID = next?.id {
                                store.markPieceDone(a.id, pieceID: pieceID)
                                Haptics.tick()
                            }
                        }
                        .buttonStyle(.otSecondary)
                    }
                }
            } else if next?.kind == .slate || next?.kind == .fullLength {
                let isOpt = next?.isOptional ?? false
                HStack {
                    SectionLabel(text: isOpt ? "Up next · \(next?.title ?? "Slate")" : "Up next · \(next?.title ?? "Slate")")
                    Spacer()
                    Button(isOpt ? "Make required" : "Make optional") {
                        if let pieceID = next?.id {
                            store.togglePieceOptional(for: a.id, pieceID: pieceID)
                            Haptics.tick()
                        }
                    }
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }
                Text(next?.kind == .slate ? "Record the slate" : "Full-length shot").font(.otTitle)
                quoteLine(store.slate.spoken)
                HStack(spacing: 10) {
                    Button("Set up the camera") { store.push(.shootSetup(a.id)) }.buttonStyle(.otPrimary)
                    if isOpt {
                        Button("Skip slate") {
                            if let pieceID = next?.id {
                                store.markPieceDone(a.id, pieceID: pieceID)
                                Haptics.tick()
                            }
                        }
                        .buttonStyle(.otSecondary)
                    }
                }
            } else if let next, next.kind == .scene, let sceneIndex = a.scenes.firstIndex(where: { $0.title == next.title }) {
                let scene = a.scenes[sceneIndex]
                let isOpt = next.isOptional
                HStack {
                    SectionLabel(text: isOpt ? "Up next · scene \(scene.number) of \(a.scenes.count) (Optional)" : "Up next · scene \(scene.number) of \(a.scenes.count)")
                    Spacer()
                    Button(isOpt ? "Make required" : "Make optional") {
                        store.togglePieceOptional(for: a.id, pieceID: next.id)
                        Haptics.tick()
                    }
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }
                Text(scene.title).font(.otTitle)
                Text(scene.heading).font(.otCaption).foregroundStyle(OT.labelTertiary)
                if let first = scene.lines.first(where: \.isMine) { quoteLine(first.text) }
                HStack(spacing: 10) {
                    Button("Prepare scene \(scene.number)") { store.push(.prepare(a.id, sceneIndex: sceneIndex)) }
                        .buttonStyle(.otPrimary)
                    Button("Practise") {
                        store.practicePiece(for: a.id, sceneIndex: sceneIndex)
                        store.push(.runLines(a.id, sceneIndex: sceneIndex))
                    }
                    .buttonStyle(.otSecondary)
                    if isOpt {
                        Button("Skip for now") {
                            store.markPieceDone(a.id, pieceID: next.id)
                            Haptics.tick()
                        }
                        .buttonStyle(.otSecondary)
                    }
                }
            } else if next?.kind == .scene {
                SectionLabel(text: "Up next · \(next?.title ?? "scene")")
                Text("Add your sides below").font(.otTitle)
                Text("Attach your script sides to prepare and shoot this scene.").font(.otCallout).foregroundStyle(OT.labelSecondary)
            } else {
                SectionLabel(text: "Everything's in")
                Text("Watch it once, then send").font(.otTitle)
                Button("Review the package") { store.push(.package(a.id)) }.buttonStyle(.otPrimary)
            }
        }
        .padding(20)
        .otCard()
    }

    @ViewBuilder private func sidesCard(_ a: Audition) -> some View {
        HStack(spacing: 12) {
            if a.scenes.isEmpty {
                Image(systemName: a.sidesLink != nil ? "link.circle.fill" : "doc.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 34, height: 34)
                    .background(OT.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sides")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelTertiary)
                    if let sidesLink = a.sidesLink, !sidesLink.isEmpty {
                        Text(sidesLink.contains("drive.google") ? "Google Drive link attached" : "Sides link attached")
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                    } else {
                        Text("No sides attached yet")
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                    }
                }
                Spacer()
                if let sidesLink = a.sidesLink, let url = URL(string: sidesLink.hasPrefix("http") ? sidesLink : "https://\(sidesLink)") {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 16))
                            .foregroundStyle(OT.accent)
                            .frame(width: 32, height: 32)
                            .background(OT.accentSoft, in: Circle())
                    }
                }
                Button(a.sidesLink != nil ? "Import" : "Add sides") {
                    showSides = true
                }
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(OT.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(OT.accentSoft, in: Capsule())
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: "Sides")
                    Text("\(a.scenes.count) scene\(a.scenes.count == 1 ? "" : "s") · \(a.scenes.flatMap(\.lines).count) lines")
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                }
                Spacer()
                Button("Replace / rescan") {
                    showSides = true
                }
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(OT.accent)
            }
        }
        .padding(16)
        .otCard()
    }

    @ViewBuilder private func headshotsCard(_ a: Audition) -> some View {
        let hasHeadshots = HeadshotStore.exists(key: "front", auditionID: a.id)
        let count = HeadshotStore.taken(auditionID: a.id).count
        let headshotPiece = a.pieces.first { $0.kind == .headshot }
        let isOpt = headshotPiece?.isOptional ?? false
        HStack(spacing: 12) {
            Image(systemName: hasHeadshots ? "photo.fill" : "photo.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OT.accent)
                .frame(width: 34, height: 34)
                .background(OT.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: isOpt ? "Headshots (Optional)" : "Headshots")
                Text(hasHeadshots ? "\(count) photo\(count == 1 ? "" : "s") attached" : (isOpt ? "None attached · optional" : "Required in flow · tap Add"))
                    .font(.otHeadline)
                    .foregroundStyle(OT.labelPrimary)
            }
            Spacer()
            Button(hasHeadshots ? "Manage" : "Add") {
                store.push(.headshots(for: a.id))
            }
            .font(.otFootnote.weight(.semibold))
            .foregroundStyle(OT.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(OT.accentSoft, in: Capsule())
        }
        .padding(16)
        .otCard()
    }

    private func quoteLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(OT.accent).frame(width: 3)
            Text(text).font(.otHeadline).foregroundStyle(OT.labelPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func thenLine(_ a: Audition) -> String? {
        let remaining = a.pieces.filter { !$0.isDone }.dropFirst().map(\.title)
        guard !remaining.isEmpty else { return nil }
        return remaining.joined(separator: " · ") + (a.readyCount == 0 ? " — any order after that" : " — any order is fine")
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.title; configuration.icon.font(.caption2) } }
}

// MARK: - 7 · L2 Package sheet

struct PackageSheet: View {
    let auditionID: Audition.ID
    var onAddSides: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let a = store.audition(auditionID) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Package").font(.otTitle)
                        Text("In tape order · \(a.readyCount) of \(a.totalCount) ready").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }.buttonStyle(.plain)
                }
                ForEach(Array(a.pieces.enumerated()), id: \.element.id) { i, piece in
                    HStack(spacing: 12) {
                        Button { dismiss(); open(piece, a) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: piece.isDone ? "checkmark" : piece.kind.symbol)
                                    .foregroundStyle(piece.isDone ? OT.labelOnAccent : OT.accent)
                                    .frame(width: 44, height: 44)
                                    .background(piece.isDone ? OT.accent : OT.accentSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("\(i + 1)  \(piece.title)").font(.otHeadline)
                                        if piece.isOptional {
                                            Text("Optional")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(OT.surfaceSunken, in: Capsule())
                                                .foregroundStyle(OT.labelSecondary)
                                        }
                                    }
                                    Text(piece.detail.isEmpty ? "not shot yet" : piece.detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if piece.kind == .slate || piece.kind == .headshot || piece.kind == .scene {
                            Button {
                                store.togglePieceOptional(for: a.id, pieceID: piece.id)
                                Haptics.tick()
                            } label: {
                                Text(piece.isOptional ? "Make required" : "Make optional")
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(OT.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if piece.id == a.nextPiece?.id { Text("Next").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent) }
                        Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                    }
                    .frame(minHeight: 56)
                }
                Spacer()
            }
            .padding(OT.gutter)
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

// MARK: - 7c Start a callback

struct CallbackSheet: View {
    let audition: Audition
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var due = Date.now.addingTimeInterval(5 * 86400)
    @State private var castingNotes = ""
    @State private var actorNotes = ""
    @State private var bringReader = true
    @State private var callbackScenes: [ScriptScene] = []
    @State private var initialSceneCount: Int = 0
    @State private var extraScriptText: String = ""
    @State private var showPDFPicker = false
    @State private var isProcessingPDF = false
    @State private var showPDFError = false
    @State private var showExtraSidesSheet = false

    private var readerName: String {
        callbackScenes.first?.lines.first(where: { !$0.isMine })?.character
            ?? audition.scenes.first?.lines.first(where: { !$0.isMine })?.character
            ?? "your reader"
    }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Start a callback", backLabel: "Cancel", onBack: { dismiss() }) {
                Button("Create") {
                    if let id = store.startCallback(
                        from: audition.id,
                        due: due,
                        notes: castingNotes,
                        actorNotes: actorNotes,
                        scenes: callbackScenes,
                        extraScriptText: extraScriptText.isEmpty ? nil : extraScriptText,
                        bringReader: bringReader
                    ) {
                        dismiss()
                        store.push(.auditionDetail(id))
                    }
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            Form {
                Section { LabeledContent(audition.project, value: "Round \((audition.round ?? 1) + 1)") }

                Section("When is it due?") {
                    DatePicker("Due", selection: $due, in: Date.now...)
                    HStack(spacing: 8) {
                        Text("Presets:")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelSecondary)
                        presetTimeChip("5:00 PM") { setDueTime(hour: 17, minute: 0) }
                        presetTimeChip("10:00 AM") { setDueTime(hour: 10, minute: 0) }
                        presetTimeChip("Noon") { setDueTime(hour: 12, minute: 0) }
                        presetTimeChip("11:59 PM") { setDueTime(hour: 23, minute: 59) }
                    }
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scenes to tape")
                                .font(.otHeadline)
                            let extraCount = max(0, callbackScenes.count - initialSceneCount)
                            Text("\(callbackScenes.count) \(callbackScenes.count == 1 ? "scene" : "scenes")\(extraCount > 0 ? " (\(extraCount) added for callback)" : "")")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                        Stepper("", value: Binding(
                            get: { callbackScenes.count },
                            set: { newCount in
                                if newCount > callbackScenes.count && newCount <= 12 {
                                    for num in (callbackScenes.count + 1)...newCount {
                                        callbackScenes.append(ScriptScene(number: num, title: "Scene \(num)", heading: "SCENE \(num)", lines: []))
                                    }
                                } else if newCount < callbackScenes.count && newCount >= max(1, initialSceneCount) {
                                    callbackScenes.removeLast(callbackScenes.count - newCount)
                                }
                            }
                        ), in: max(1, initialSceneCount)...12)
                        .labelsHidden()
                    }

                    ForEach(Array(callbackScenes.enumerated()), id: \.element.id) { index, scene in
                        HStack {
                            Image(systemName: "film")
                                .foregroundStyle(OT.accent)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scene.title.isEmpty ? "Scene \(scene.number)" : scene.title)
                                    .font(.otSubhead.weight(.medium))
                                if scene.lines.isEmpty {
                                    Text("No sides attached")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelTertiary)
                                } else {
                                    let mine = scene.lines.filter(\.isMine).count
                                    Text("\(mine) actor \(mine == 1 ? "line" : "lines")")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                            }
                            Spacer()
                            if index < initialSceneCount {
                                Text("Round 1")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(OT.labelSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            } else {
                                Text("Callback")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(OT.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(OT.accentSoft, in: Capsule())

                                Button {
                                    callbackScenes.remove(at: index)
                                    renumberScenes()
                                    Haptics.tick()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundStyle(OT.labelTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        if callbackScenes.count < 12 {
                            let nextNum = callbackScenes.count + 1
                            callbackScenes.append(ScriptScene(number: nextNum, title: "Scene \(nextNum)", heading: "SCENE \(nextNum)", lines: []))
                            Haptics.tick()
                        }
                    } label: {
                        Label("Add another scene", systemImage: "plus.circle.fill")
                            .font(.otSubhead.weight(.semibold))
                            .foregroundStyle(OT.accent)
                    }
                    .disabled(callbackScenes.count >= 12)
                } header: {
                    Text("Scenes to tape")
                } footer: {
                    Text("Keep your Round 1 scenes and add any new scenes casting requested for this callback.")
                }

                Section {
                    if !extraScriptText.isEmpty {
                        let extraScenesCount = max(0, callbackScenes.count - initialSceneCount)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Extra sides attached")
                                    .font(.otHeadline)
                                Text("\(extraScenesCount) callback \(extraScenesCount == 1 ? "scene" : "scenes") merged with Round 1 sides")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OT.accent)
                                .font(.system(size: 20))
                        }
                    }

                    Button {
                        showPDFPicker = true
                    } label: {
                        HStack {
                            Label(extraScriptText.isEmpty ? "Import extra sides (PDF / Document)…" : "Import more sides (PDF / Document)…", systemImage: "doc.badge.plus")
                                .font(.otSubhead.weight(.medium))
                            Spacer()
                            if isProcessingPDF {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                        .foregroundStyle(OT.accent)
                    }
                    .disabled(isProcessingPDF)

                    Button {
                        showExtraSidesSheet = true
                    } label: {
                        Label(extraScriptText.isEmpty ? "Paste or scan extra sides…" : "Add more sides by pasting or scanning…", systemImage: "pencil.and.list.clipboard")
                            .font(.otSubhead.weight(.medium))
                            .foregroundStyle(OT.accent)
                    }
                } header: {
                    Text("Extra Sides & Script")
                } footer: {
                    Text("Extra sides are kept alongside your original sides so you have all scenes ready in the teleprompter & line runner.")
                }

                Section {
                    TextField("e.g. “Less angry, more hurt.”", text: $castingNotes, axis: .vertical)
                } header: {
                    Text("Notes from casting")
                } footer: {
                    Text("Character breakdown and casting adjustments. Shown on Prepare before every take.")
                }

                Section {
                    TextField("My subtext, scene objective, choices, questions…", text: $actorNotes, axis: .vertical)
                } header: {
                    Text("My notes & understanding")
                } footer: {
                    Text("Private rehearsal notes, intentions, and character choices for this callback.")
                }

                Section { Toggle("Bring over reader track · \(readerName)", isOn: $bringReader) }
            }
            .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            setupInitialState()
        }
        .fileImporter(isPresented: $showPDFPicker, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            switch result {
            case .success(let url):
                isProcessingPDF = true
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer {
                        resolved.cleanup()
                        Task { @MainActor in isProcessingPDF = false }
                    }
                    if let text = await NoticeOCR.extractText(fromFileAt: resolved.url), NoticeOCR.looksReadable(text) {
                        await MainActor.run {
                            appendExtraSides(text: text)
                        }
                    } else {
                        await MainActor.run {
                            showPDFError = true
                            Haptics.warning()
                        }
                    }
                }
            case .failure:
                showPDFError = true
            }
        }
        .sheet(isPresented: $showExtraSidesSheet) {
            CallbackExtraSidesSheet(role: audition.role) { extraText in
                appendExtraSides(text: extraText)
            }
        }
        .alert("We couldn't read this file", isPresented: $showPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No readable text was found in the document. You can scan the pages or paste text directly.")
        }
    }

    private func setupInitialState() {
        if callbackScenes.isEmpty {
            if !audition.scenes.isEmpty {
                callbackScenes = audition.scenes
                initialSceneCount = audition.scenes.count
            } else {
                let scenePieces = audition.pieces.filter { $0.kind == .scene }
                let count = max(1, scenePieces.count)
                callbackScenes = (1...count).map { num in
                    ScriptScene(number: num, title: "Scene \(num)", heading: "SCENE \(num)", lines: [])
                }
                initialSceneCount = callbackScenes.count
            }
        }
        if castingNotes.isEmpty, let c = audition.castingNotes {
            castingNotes = c
        }
        if actorNotes.isEmpty, let a = audition.actorNotes {
            actorNotes = a
        }
    }

    private func appendExtraSides(text: String) {
        let cleaned = ScriptParser.cleanPastedText(text)
        guard !cleaned.isEmpty else { return }

        let parsed = ScriptParser.parseScenes(from: cleaned, myRole: audition.role)
        let startNum = callbackScenes.count + 1

        if !parsed.isEmpty {
            let renumbered = parsed.enumerated().map { idx, scene in
                ScriptScene(
                    number: startNum + idx,
                    title: (scene.title.isEmpty || scene.title.hasPrefix("Scene")) ? "Scene \(startNum + idx)" : scene.title,
                    heading: scene.heading.isEmpty ? "SCENE \(startNum + idx)" : scene.heading,
                    lines: scene.lines,
                    estimatedSeconds: scene.estimatedSeconds
                )
            }
            callbackScenes.append(contentsOf: renumbered)
        } else {
            let roleName = audition.role.isEmpty ? "Me" : audition.role
            let line = ScriptLine(character: roleName, text: cleaned, isMine: true)
            let newScene = ScriptScene(
                number: startNum,
                title: "Scene \(startNum)",
                heading: "SCENE \(startNum)",
                lines: [line]
            )
            callbackScenes.append(newScene)
        }

        if extraScriptText.isEmpty {
            extraScriptText = cleaned
        } else {
            extraScriptText += "\n\n" + cleaned
        }

        if let newNotes = NoticeParser.extractCharacterDescription(for: audition.role, in: cleaned) {
            if castingNotes.isEmpty {
                castingNotes = newNotes
            } else if !castingNotes.contains(newNotes) {
                castingNotes += "\n\n" + newNotes
            }
        }

        Haptics.success()
    }

    private func renumberScenes() {
        for i in callbackScenes.indices {
            let num = i + 1
            callbackScenes[i].number = num
            if callbackScenes[i].title.hasPrefix("Scene ") {
                callbackScenes[i].title = "Scene \(num)"
            }
        }
    }

    private func presetTimeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            Haptics.tick()
        }) {
            Text(title)
                .font(.otCaption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(OT.accent)
        }
        .buttonStyle(.plain)
    }

    private func setDueTime(hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = calendar.dateComponents([.year, .month, .day], from: due)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let newDate = calendar.date(from: comps) {
            due = newDate
        }
    }
}

// MARK: - Callback Extra Sides Sheet

struct CallbackExtraSidesSheet: View {
    let role: String
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var reading = false
    @State private var photoItems: [PhotosPickerItem] = []

    private var parsedScenes: [ScriptScene] {
        ScriptParser.parseScenes(from: text, myRole: role)
    }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(
                title: "Add extra sides",
                backLabel: "Cancel",
                onBack: { dismiss() }
            ) {
                Button("Add sides") {
                    onAdd(text)
                    dismiss()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            Form {
                Section {
                    HStack {
                        Text("Paste from clipboard")
                            .font(.otHeadline)
                        Spacer()
                        Button {
                            let pasted = UIPasteboard.general.string ?? ""
                            let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleaned = ScriptParser.cleanPastedText(trimmed)
                            if !cleaned.isEmpty {
                                text = cleaned
                                Haptics.success()
                            } else {
                                Haptics.tick()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Paste")
                                    .font(.otCaption.weight(.bold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OT.accent, in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Paste or type callback sides here...", text: $text, axis: .vertical)
                        .lineLimit(6...14)

                    Button { showImporter = true } label: {
                        Label("Import a PDF or text file", systemImage: "doc")
                    }

                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Pick from Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        if VNDocumentCameraViewController.isSupported {
                            showScanner = true
                        } else {
                            scannerUnavailable = true
                        }
                    } label: {
                        Label("Scan the pages", systemImage: "doc.viewfinder")
                    }
                } footer: {
                    Text("These extra sides will be appended to your Round 1 script and scenes.")
                }

                if reading {
                    Section {
                        HStack { ProgressView(); Text("Reading pages…") }
                    }
                }

                if !text.isEmpty {
                    Section("Detected in extra sides") {
                        if !parsedScenes.isEmpty {
                            LabeledContent("Scenes found", value: "\(parsedScenes.count)")
                            let mine = parsedScenes.flatMap(\.lines).filter(\.isMine).count
                            LabeledContent("Your lines (\(role.isEmpty ? "Your role" : role))", value: "\(mine)")
                            LabeledContent("Total character lines", value: "\(parsedScenes.flatMap(\.lines).count)")
                        } else {
                            Text("No structured scenes detected yet. We'll still attach this text as a new scene for your teleprompter.")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelTertiary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add sides to callback") {
                    onAdd(text)
                    dismiss()
                }
                .buttonStyle(.otPrimary)
                .padding(.horizontal, OT.gutter)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Camera scanning not available", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning requires a device with camera support. You can paste the sides text or import a PDF/text file.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            guard case .success(let url) = result else { return }
            let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
            reading = true
            Task {
                defer { resolved.cleanup() }
                let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)
                await MainActor.run {
                    if let extracted {
                        text = ScriptParser.cleanPastedText(extracted)
                    }
                    reading = false
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                reading = true
                Task {
                    let recognized = await NoticeOCR.recognizeText(in: pages)
                    await MainActor.run {
                        text = ScriptParser.cleanPastedText(recognized)
                        reading = false
                    }
                }
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            reading = true
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        images.append(img)
                    }
                }
                let recognized = await NoticeOCR.recognizeText(in: images)
                await MainActor.run {
                    text = ScriptParser.cleanPastedText(recognized)
                    photoItems = []
                    reading = false
                }
            }
        }
    }
}

// MARK: - Edit details

struct EditAuditionSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showValidationErrors = false
    @State private var sceneCount: Int = 1
    @State private var showPDFPicker = false
    @State private var showRevisedSides = false
    @State private var isProcessingPDF = false
    @State private var showPDFError = false

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Edit details", backLabel: "Cancel", onBack: { dismiss() }) {
                Button("Done") {
                    if let audition = store.audition(auditionID) {
                        let isProjectEmpty = audition.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let isRoleEmpty = audition.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if isProjectEmpty || isRoleEmpty {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showValidationErrors = true
                            }
                            Haptics.warning()
                            return
                        }
                    }
                    store.updateSceneCount(for: auditionID, count: sceneCount)
                    store.reclassifyRole(for: auditionID)
                    dismiss()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            if let audition = store.binding(for: auditionID) {
                Form {
                    Section("Project") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Project", text: audition.project)
                            if showValidationErrors && audition.wrappedValue.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label("Project name is required", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red)
                            }
                        }
                        TextField("Type (film, series, commercial…)", text: audition.projectType)
                        TextField("Casting office", text: audition.castingOffice)
                    }
                    Section("Role") {
                        let chars = scriptCharacters(for: audition.wrappedValue)
                        if !chars.isEmpty {
                            Picker("Character in script", selection: Binding(
                                get: {
                                    chars.first { $0.caseInsensitiveCompare(audition.wrappedValue.role) == .orderedSame } ?? ""
                                },
                                set: { newValue in
                                    if !newValue.isEmpty {
                                        audition.wrappedValue.role = newValue
                                        Haptics.tick()
                                    }
                                }
                            )) {
                                Text("Custom role").tag("")
                                ForEach(chars, id: \.self) { char in
                                    Text(char).tag(char)
                                }
                            }

                            HStack(spacing: 8) {
                                ForEach(chars, id: \.self) { char in
                                    let isCurrent = char.caseInsensitiveCompare(audition.wrappedValue.role) == .orderedSame
                                    Button {
                                        audition.wrappedValue.role = char
                                        Haptics.tick()
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isCurrent {
                                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                            }
                                            Text(char)
                                        }
                                        .font(.otCaption.weight(isCurrent ? .bold : .medium))
                                        .foregroundStyle(isCurrent ? OT.bgCanvas : OT.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isCurrent ? OT.accent : OT.accentSoft, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)

                            let otherChars = chars.filter { $0.caseInsensitiveCompare(audition.wrappedValue.role) != .orderedSame }
                            if let reader = otherChars.first {
                                Text("Next screen will show: Who reads \(reader)?")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.reader)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Role", text: audition.role)
                            if showValidationErrors && audition.wrappedValue.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label("Character or role name is required", systemImage: "exclamationmark.circle.fill")
                                    .font(.otFootnote)
                                    .foregroundStyle(Color.red)
                            }
                        }
                        TextField("Size (lead, supporting…)", text: audition.roleSize)
                    }
                    Section("Scenes") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scenes to tape")
                                    .font(.otHeadline)
                                Text("\(sceneCount) \(sceneCount == 1 ? "scene" : "scenes") in package")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Stepper("", value: $sceneCount, in: 1...12)
                                .labelsHidden()
                        }

                        ForEach(1...sceneCount, id: \.self) { num in
                            HStack {
                                Image(systemName: "film")
                                    .foregroundStyle(OT.accent)
                                    .font(.system(size: 14))
                                Text("Scene \(num)")
                                    .font(.otSubhead)
                                Spacer()
                                if num <= audition.wrappedValue.scenes.count {
                                    let s = audition.wrappedValue.scenes[num - 1]
                                    if s.lines.isEmpty {
                                        Text("No sides yet")
                                            .font(.otCaption)
                                            .foregroundStyle(OT.labelTertiary)
                                    } else {
                                        let mine = s.lines.filter(\.isMine).count
                                        Text("\(mine) line\(mine == 1 ? "" : "s")")
                                            .font(.otCaption)
                                            .foregroundStyle(OT.labelSecondary)
                                    }
                                } else {
                                    Text("New scene")
                                        .font(.otCaption.weight(.medium))
                                        .foregroundStyle(OT.accent)
                                }
                            }
                        }

                        Button {
                            if sceneCount < 12 {
                                sceneCount += 1
                                Haptics.tick()
                            }
                        } label: {
                            Label("Add another scene", systemImage: "plus.circle.fill")
                                .font(.otSubhead.weight(.semibold))
                                .foregroundStyle(OT.accent)
                        }
                        .disabled(sceneCount >= 12)
                    }
                    Section {
                        // Slate
                        HStack {
                            Label("Slate", systemImage: "person.text.rectangle")
                                .font(.otSubhead.weight(.medium))
                            Spacer()
                            Toggle("Include slate", isOn: Binding(
                                get: { audition.wrappedValue.pieces.contains { $0.kind == .slate } },
                                set: { included in
                                    if included {
                                        if !audition.wrappedValue.pieces.contains(where: { $0.kind == .slate }) {
                                            let isDone = audition.wrappedValue.slateVideoURL != nil
                                            let p = Piece(kind: .slate, title: "Slate", detail: "Name, height, city", isDone: isDone, isOptional: false)
                                            audition.wrappedValue.pieces.insert(p, at: 0)
                                        }
                                    } else {
                                        audition.wrappedValue.pieces.removeAll { $0.kind == .slate }
                                    }
                                }
                            ))
                            .labelsHidden()
                        }

                        if let slateIndex = audition.wrappedValue.pieces.firstIndex(where: { $0.kind == .slate }) {
                            Picker("Slate requirement", selection: Binding(
                                get: { audition.wrappedValue.pieces[slateIndex].isOptional ? "Optional" : "Required" },
                                set: {
                                    let opt = ($0 == "Optional")
                                    audition.wrappedValue.pieces[slateIndex].isOptional = opt
                                    audition.wrappedValue.pieces[slateIndex].title = opt ? "Slate (Optional)" : "Slate"
                                }
                            )) {
                                Text("Required in flow").tag("Required")
                                Text("Optional").tag("Optional")
                            }
                            .pickerStyle(.segmented)
                        }

                        // Headshots
                        HStack {
                            Label("Headshots", systemImage: "person.crop.square")
                                .font(.otSubhead.weight(.medium))
                            Spacer()
                            Toggle("Include headshots", isOn: Binding(
                                get: { audition.wrappedValue.pieces.contains { $0.kind == .headshot } },
                                set: { included in
                                    if included {
                                        if !audition.wrappedValue.pieces.contains(where: { $0.kind == .headshot }) {
                                            let isDone = HeadshotStore.exists(key: "front", auditionID: auditionID)
                                            let p = Piece(kind: .headshot, title: "Headshot", detail: "Photos", isDone: isDone, isOptional: false)
                                            audition.wrappedValue.pieces.append(p)
                                        }
                                    } else {
                                        audition.wrappedValue.pieces.removeAll { $0.kind == .headshot }
                                    }
                                }
                            ))
                            .labelsHidden()
                        }

                        if let headshotIndex = audition.wrappedValue.pieces.firstIndex(where: { $0.kind == .headshot }) {
                            Picker("Headshot requirement", selection: Binding(
                                get: { audition.wrappedValue.pieces[headshotIndex].isOptional ? "Optional" : "Required" },
                                set: {
                                    let opt = ($0 == "Optional")
                                    audition.wrappedValue.pieces[headshotIndex].isOptional = opt
                                    audition.wrappedValue.pieces[headshotIndex].title = opt ? "Headshot (Optional)" : "Headshot"
                                }
                            )) {
                                Text("Required in flow").tag("Required")
                                Text("Optional").tag("Optional")
                            }
                            .pickerStyle(.segmented)
                        }

                        // Scenes requirement
                        let sceneIndices = audition.wrappedValue.pieces.indices.filter { audition.wrappedValue.pieces[$0].kind == .scene }
                        if !sceneIndices.isEmpty {
                            Divider().padding(.vertical, 4)
                            Text("Scenes").font(.otCaption.weight(.semibold)).foregroundStyle(OT.labelSecondary)
                            ForEach(sceneIndices, id: \.self) { scenePieceIndex in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label(audition.wrappedValue.pieces[scenePieceIndex].title, systemImage: "theatermasks.fill")
                                            .font(.otSubhead.weight(.medium))
                                        Spacer()
                                        Text(audition.wrappedValue.pieces[scenePieceIndex].isOptional ? "Optional" : "Required")
                                            .font(.otCaption.weight(.semibold))
                                            .foregroundStyle(audition.wrappedValue.pieces[scenePieceIndex].isOptional ? OT.labelSecondary : OT.accent)
                                    }
                                    Picker("Scene requirement", selection: Binding(
                                        get: { audition.wrappedValue.pieces[scenePieceIndex].isOptional ? "Optional" : "Required" },
                                        set: { opt in
                                            audition.wrappedValue.pieces[scenePieceIndex].isOptional = (opt == "Optional")
                                        }
                                    )) {
                                        Text("Required in flow").tag("Required")
                                        Text("Optional").tag("Optional")
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("Audition Flow & Requirements")
                    } footer: {
                        Text("Scenes, Slate, and Headshots can each be set to Required or Optional depending on casting instructions.")
                    }
                    Section("Due") {
                        DatePicker("Due", selection: audition.due)
                        HStack(spacing: 8) {
                            Text("Presets:")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                            presetTimeChip("5:00 PM") { setAuditionDueTime(audition: audition, hour: 17, minute: 0) }
                            presetTimeChip("10:00 AM") { setAuditionDueTime(audition: audition, hour: 10, minute: 0) }
                            presetTimeChip("Noon") { setAuditionDueTime(audition: audition, hour: 12, minute: 0) }
                            presetTimeChip("11:59 PM") { setAuditionDueTime(audition: audition, hour: 23, minute: 59) }
                        }
                    }
                    Section("Sending to") {
                        Picker("Destination", selection: audition.destination) {
                            ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
                        }
                        TextField(
                            audition.wrappedValue.destination == .emailOrLink
                                ? "Email address or submission link"
                                : "\(audition.wrappedValue.destination.rawValue) account or submission notes",
                            text: Binding(
                                get: {
                                    if let detail = audition.wrappedValue.destinationDetail, !detail.isEmpty {
                                        return detail
                                    }
                                    if let emailAsk = audition.wrappedValue.asks.first(where: { $0.hasPrefix("Email: ") }) {
                                        return emailAsk.replacingOccurrences(of: "Email: ", with: "")
                                    }
                                    return ""
                                },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    audition.wrappedValue.destinationDetail = trimmed.isEmpty ? nil : trimmed
                                    audition.wrappedValue.asks.removeAll { $0.hasPrefix("Email: ") }
                                    if !trimmed.isEmpty {
                                        if trimmed.contains("@") {
                                            audition.wrappedValue.asks.append("Email: \(trimmed)")
                                        } else {
                                            audition.wrappedValue.asks.append(trimmed)
                                        }
                                    }
                                }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(audition.wrappedValue.destination == .emailOrLink ? .emailAddress : .default)
                    }
                    Section("Sides & Script") {
                        let hasSides = !audition.wrappedValue.scenes.isEmpty
                        if hasSides {
                            let totalLines = audition.wrappedValue.scenes.flatMap(\.lines).filter(\.isMine).count
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(audition.wrappedValue.scenes.count) \(audition.wrappedValue.scenes.count == 1 ? "scene" : "scenes") attached")
                                        .font(.otHeadline)
                                    Text("\(totalLines) actor \(totalLines == 1 ? "line" : "lines") detected")
                                        .font(.otCaption)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(OT.accent)
                                    .font(.system(size: 20))
                            }

                            Button {
                                showPDFPicker = true
                            } label: {
                                HStack {
                                    Label("Replace with PDF / Document…", systemImage: "doc.badge.arrow.up")
                                        .font(.otSubhead.weight(.medium))
                                    Spacer()
                                    if isProcessingPDF {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                }
                                .foregroundStyle(OT.accent)
                            }
                            .disabled(isProcessingPDF)

                            Button {
                                showRevisedSides = true
                            } label: {
                                Label("Edit Text / Scan with Camera…", systemImage: "pencil.and.list.clipboard")
                                    .font(.otSubhead.weight(.medium))
                                    .foregroundStyle(OT.accent)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No script sides attached")
                                    .font(.otHeadline)
                                Text("Import a PDF, scan pages, or paste text to enable the teleprompter & line runner.")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            .padding(.vertical, 2)

                            Button {
                                showPDFPicker = true
                            } label: {
                                HStack {
                                    Label("Import Sides PDF / Document", systemImage: "doc.badge.plus")
                                        .font(.otSubhead.weight(.semibold))
                                    Spacer()
                                    if isProcessingPDF {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                }
                                .foregroundStyle(OT.accent)
                            }
                            .disabled(isProcessingPDF)

                            Button {
                                showRevisedSides = true
                            } label: {
                                Label("Scan with Camera or Paste Text…", systemImage: "doc.viewfinder")
                                    .font(.otSubhead.weight(.medium))
                                    .foregroundStyle(OT.accent)
                            }
                        }

                        // Cloud Link (Drive, Dropbox, iCloud)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cloud link (optional)")
                                .font(.otCaption.weight(.medium))
                                .foregroundStyle(OT.labelSecondary)

                            TextField("Google Drive, Dropbox, or cloud link", text: Binding(
                                get: { audition.wrappedValue.sidesLink ?? "" },
                                set: { audition.wrappedValue.sidesLink = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                            if let sidesLink = audition.wrappedValue.sidesLink,
                               let url = URL(string: sidesLink.hasPrefix("http") ? sidesLink : "https://\(sidesLink)") {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text("Open link in browser")
                                    }
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.accent)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.top, 4)
                    }
                    Section {
                        TextField("Character breakdown, director notes, adjustments", text: Binding(
                            get: { audition.wrappedValue.castingNotes ?? "" },
                            set: { audition.wrappedValue.castingNotes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                    } header: {
                        Text("Notes from casting")
                    } footer: {
                        Text("Character breakdown and casting adjustments. Shown on Prepare before every take.")
                    }

                    Section {
                        TextField("My subtext, scene objective, choices, questions", text: Binding(
                            get: { audition.wrappedValue.actorNotes ?? "" },
                            set: { audition.wrappedValue.actorNotes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                    } header: {
                        Text("My notes & understanding")
                    } footer: {
                        Text("Private rehearsal notes, intentions, and character choices. Kept handy while preparing.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let a = store.audition(auditionID) {
                let count = max(a.scenes.count, a.pieces.filter { $0.kind == .scene }.count)
                sceneCount = max(1, count)
            }
        }
        .fileImporter(isPresented: $showPDFPicker, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            switch result {
            case .success(let url):
                isProcessingPDF = true
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer {
                        resolved.cleanup()
                        Task { @MainActor in isProcessingPDF = false }
                    }
                    if let text = await NoticeOCR.extractText(fromFileAt: resolved.url), NoticeOCR.looksReadable(text) {
                        let role = store.audition(auditionID)?.role ?? ""
                        let parsedScenes = ScriptParser.parseScenes(from: text, myRole: role)
                        await MainActor.run {
                            store.replaceSides(of: auditionID, with: parsedScenes, sourceText: text)
                            sceneCount = max(sceneCount, parsedScenes.count)
                            Haptics.success()
                        }
                    } else {
                        await MainActor.run {
                            showPDFError = true
                            Haptics.warning()
                        }
                    }
                }
            case .failure:
                showPDFError = true
            }
        }
        .sheet(isPresented: $showRevisedSides) {
            RevisedSidesSheet(auditionID: auditionID)
        }
        .alert("We couldn't read this file", isPresented: $showPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No readable text was found in the document. You can scan the pages or paste text directly.")
        }
    }

    private func scriptCharacters(for audition: Audition) -> [String] {
        if let script = audition.scriptText, !script.isEmpty {
            let extracted = ScriptParser.extractCharacters(from: script)
            if !extracted.isEmpty { return extracted }
        }
        var found: [String] = []
        for scene in audition.scenes {
            for line in scene.lines {
                let c = line.character.trimmingCharacters(in: .whitespaces)
                if !c.isEmpty && !found.contains(where: { $0.caseInsensitiveCompare(c) == .orderedSame }) {
                    found.append(c)
                }
            }
        }
        return found
    }

    private func presetTimeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            Haptics.tick()
        }) {
            Text(title)
                .font(.otCaption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(OT.accent)
        }
        .buttonStyle(.plain)
    }

    private func setAuditionDueTime(audition: Binding<Audition>, hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = calendar.dateComponents([.year, .month, .day], from: audition.wrappedValue.due)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let newDate = calendar.date(from: comps) {
            audition.wrappedValue.due = newDate
        }
    }
}

// MARK: - Revised sides

/// Add sides to an audition without sides, or swap in revised sides from casting:
/// paste them, import a PDF/text file, or scan pages on device.
struct RevisedSidesSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var editableScenes: [ScriptScene] = []
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var reading = false
    @State private var photoItems: [PhotosPickerItem] = []

    private var audition: Audition? {
        store.audition(auditionID)
    }

    private var isNewSides: Bool {
        audition?.scenes.isEmpty ?? true
    }

    private var parsed: [ScriptScene] {
        let role = audition?.role ?? ""
        return ScriptParser.parseScenes(from: text, myRole: role)
    }

    private var activeScenes: [ScriptScene] {
        editableScenes.isEmpty ? parsed : editableScenes
    }

    var body: some View {
        let role = audition?.role ?? ""
        VStack(spacing: 0) {
            InContentNavHeader(
                title: isNewSides ? "Add sides" : "Revised sides",
                backLabel: "Cancel",
                onBack: { dismiss() }
            ) {
                Button(isNewSides ? "Add" : "Replace") {
                    store.replaceSides(of: auditionID, with: activeScenes, sourceText: text)
                    dismiss()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
                .disabled(activeScenes.isEmpty)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            Form {
                Section {
                    HStack {
                        Text("Paste from clipboard")
                            .font(.otHeadline)
                        Spacer()
                        Button {
                            let pasted = UIPasteboard.general.string ?? ""
                            let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleaned = ScriptParser.cleanPastedText(trimmed)
                            if !cleaned.isEmpty {
                                text = cleaned
                                editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
                                Haptics.success()
                            } else {
                                Haptics.tick()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Paste")
                                    .font(.otCaption.weight(.bold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OT.accent, in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField(isNewSides ? "Or paste or type sides here..." : "Paste the new sides", text: $text, axis: .vertical)
                        .lineLimit(6...14)
                        .onChange(of: text) { _, newText in
                            editableScenes = ScriptParser.parseScenes(from: newText, myRole: role)
                        }

                    Button { showImporter = true } label: {
                        Label("Import a PDF or text file", systemImage: "doc")
                    }

                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Pick from Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        if VNDocumentCameraViewController.isSupported {
                            showScanner = true
                        } else {
                            scannerUnavailable = true
                        }
                    } label: {
                        Label("Scan the pages", systemImage: "doc.viewfinder")
                    }
                } footer: {
                    Text(isNewSides
                         ? "Sides are parsed on your iPhone into character dialogue lines and scenes. Nothing is uploaded."
                         : "Read on this iPhone — nothing is uploaded. Existing takes stay to watch; record and circle takes for these revised scenes before packaging.")
                }

                if reading {
                    Section {
                        HStack { ProgressView(); Text("Reading pages…") }
                    }
                }

                if !text.isEmpty {
                    Section("Detected from sides (Tap speaker or text to edit)") {
                        if !activeScenes.isEmpty {
                            LabeledContent("Scenes", value: "\(activeScenes.count)")
                            LabeledContent("Your lines (\(role.isEmpty ? "Your role" : role))", value: "\(activeScenes.flatMap(\.lines).filter(\.isMine).count)")
                            LabeledContent("Total character lines", value: "\(activeScenes.flatMap(\.lines).count)")

                            ScriptReviewAndEditView(scenes: $editableScenes)
                        } else {
                            Text("No character lines recognised yet. Cues should be in CAPS (e.g. “MAYA”) or “Maya: dialogue”.")
                                .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(isNewSides ? "Add sides" : "Replace sides") {
                    store.replaceSides(of: auditionID, with: activeScenes, sourceText: text)
                    dismiss()
                }
                .buttonStyle(.otPrimary)
                .disabled(activeScenes.isEmpty)
                .padding(.horizontal, OT.gutter)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !isNewSides, let existing = audition?.scriptText, !existing.isEmpty {
                text = existing
                editableScenes = audition?.scenes ?? ScriptParser.parseScenes(from: existing, myRole: role)
            }
        }
        .alert("Camera scanning not available", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning requires a device with camera support. You can paste the sides text or import a PDF/text file.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            guard case .success(let url) = result else { return }
            let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
            reading = true
            Task {
                defer { resolved.cleanup() }
                let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)
                await MainActor.run {
                    if let extracted {
                        let cleaned = ScriptParser.cleanPastedText(extracted)
                        text = cleaned
                        editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
                    }
                    reading = false
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                reading = true
                Task {
                    let recognized = await NoticeOCR.recognizeText(in: pages)
                    await MainActor.run {
                        let cleaned = ScriptParser.cleanPastedText(recognized)
                        text = cleaned
                        editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
                        reading = false
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            reading = true
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                guard !images.isEmpty else {
                    await MainActor.run { reading = false }
                    return
                }
                let recognized = await NoticeOCR.recognizeText(in: images)
                await MainActor.run {
                    let cleaned = ScriptParser.cleanPastedText(recognized)
                    text = cleaned
                    editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
                    reading = false
                    photoItems = []
                }
            }
        }
    }
}
