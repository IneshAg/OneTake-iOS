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
                    HStack(spacing: 8) {
                        Button { showEdit = true } label: {
                            Label("Edit details", systemImage: "pencil")
                        }
                        .modifier(GlassCapsuleButtonCompatibility())

                        Menu {
                        Button { showCallback = true } label: { Label("Start a callback", systemImage: "arrow.uturn.right") }
                        Divider()
                        Button(role: .destructive) { showDelete = true } label: { Label("Delete audition", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(OT.labelPrimary)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .modifier(GlassButtonCompatibility(enabled: true))
                    }
                }
                .padding(.top, 4)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "\(a.resolvedMaterialKind.shortLabel) · \(a.projectType) · reading for \(a.role)" + (a.round.map { " · round \($0)" } ?? ""))
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

                if let dates = a.importantDates, !dates.isEmpty {
                    MilestoneDatesListCard(dates: dates)
                }

                if let details = a.projectDetails, details.hasReviewableContent {
                    ProjectDetailsCard(details: details)
                }

                if let instructions = a.submissionInstructions {
                    submissionInstructionsCard(instructions)
                }

                sidesCard(a)

                readerTrackCard(a)

                // The next-piece card already owns the headshot action when headshots are up next.
                if a.nextPiece?.kind != .headshot {
                    headshotsCard(a)
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
                SectionLabel(text: isOpt ? "Up next · Headshots (Optional)" : "Up next · Headshots")
                Text("Audition headshots").font(.otTitle)
                quoteLine(isOpt ? "Sent alongside your video tape as photos." : "Required in package · 3 photos (front, left, right profile).")
                HStack(spacing: 10) {
                    let photoCount = HeadshotStore.taken(auditionID: a.id).count
                    Button(photoCount == 0 ? "Add headshots" : "Manage headshots") {
                        store.push(.headshots(for: a.id))
                    }.buttonStyle(.otPrimary)
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
                let title = next?.kind == .slate ? "Slate" : "Full-body shot"
                SectionLabel(text: isOpt ? "Up next · \(title) (Optional)" : "Up next · \(title)")
                if next?.kind == .slate {
                    Text("Record the slate").font(.otTitle)
                    quoteLine(store.slate.spoken)
                } else {
                    Text("Full-body shot").font(.otTitle)
                    Text("Record a separate head-to-toe view, as requested.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                }
                HStack(spacing: 10) {
                    Button("Set up the camera") { store.push(.shootSetup(a.id)) }.buttonStyle(.otPrimary)
                    if isOpt {
                        Button(next?.kind == .slate ? "Skip slate" : "Skip full-body shot") {
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
                SectionLabel(text: isOpt ? "Up next · scene \(scene.number) of \(a.scenes.count) (Optional)" : "Up next · scene \(scene.number) of \(a.scenes.count)")
                Text(scene.title).font(.otTitle)
                Text(scene.heading).font(.otCaption).foregroundStyle(OT.labelTertiary)
                if let first = scene.lines.first(where: \.isMine) { quoteLine(first.text) }
                HStack(spacing: 10) {
                    Button("Prepare scene \(scene.number)") { store.push(.prepare(a.id, sceneIndex: sceneIndex)) }
                        .buttonStyle(.otSecondary)
                    Button("Tape scene \(scene.number)") {
                        store.camera = .shoot(a.id, scene: sceneIndex)
                    }
                    .buttonStyle(.otPrimary)
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
        if a.resolvedMaterialKind == .slateOnly {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 34, height: 34)
                    .background(OT.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Material Type")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelTertiary)
                    Text("Slate & Intro Call Only")
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                }
                Spacer()
            }
            .padding(16)
            .otCard()
        } else {
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
                        SectionLabel(text: a.resolvedMaterialKind == .monologue ? "Monologue" : "Sides")
                        Text("\(a.scenes.count) scene\(a.scenes.count == 1 ? "" : "s") · \(a.scenes.flatMap(\.lines).count) lines")
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                    }
                    Spacer()
                    Button(a.resolvedMaterialKind == .monologue ? "Edit monologue" : "Edit sides") {
                        showSides = true
                    }
                    .font(.otFootnote.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }
            }
            .padding(16)
            .otCard()
        }
    }

    @ViewBuilder private func submissionInstructionsCard(_ instructions: AuditionSubmissionInstructions) -> some View {
        let specs = [
            ("Framing", instructions.videoOrientation, "iphone"),
            ("Required Clips", instructions.requiredVideoCount.map { "\($0) video\($0 == 1 ? "" : "s")" }, "film.stack"),
            ("Takes Allowed", instructions.maxTakes.map { "Up to \($0) takes" }, "repeat"),
            ("File Naming", instructions.fileNamingRule ?? instructions.fileNameTemplate, "doc.text")
        ].filter { $0.1 != nil && $0.1?.isEmpty == false }

        if !specs.isEmpty || !instructions.slateRequirements.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Filming & Submission Specifications", systemImage: "video.badge.checkmark")
                    .font(.otCaption.weight(.bold))
                    .foregroundStyle(OT.labelPrimary)

                if !specs.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(specs, id: \.0) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.2)
                                    .font(.system(size: 13))
                                    .foregroundStyle(OT.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.0)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(OT.labelTertiary)
                                    Text(item.1 ?? "")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(OT.labelPrimary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                if !instructions.slateRequirements.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Slate instructions:").font(.system(size: 10, weight: .semibold)).foregroundStyle(OT.labelTertiary)
                        ForEach(instructions.slateRequirements.prefix(2), id: \.self) {
                            Text("• \($0)").font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .otCard(radius: 16)
        }
    }

    private func recordedReaderCueCount(for a: Audition) -> Int {
        var count = 0
        for (sIndex, scene) in a.scenes.enumerated() {
            let readerIndices = scene.lines.indices.filter { !scene.lines[$0].isMine }
            for (lineOffset, _) in readerIndices.enumerated() {
                if ReaderTrackPlayer.hasRecording(auditionID: a.id, sceneIndex: sIndex, line: lineOffset) {
                    count += 1
                }
            }
        }
        return count
    }

    @ViewBuilder private func readerTrackCard(_ a: Audition) -> some View {
        let unownedLines = a.scenes.flatMap(\.lines).filter { !$0.isMine }
        if !unownedLines.isEmpty {
            let readerName = unownedLines.first?.character.capitalized ?? "Reader"
            let totalCues = unownedLines.count
            let recordedCount = recordedReaderCueCount(for: a)
            let isComplete = recordedCount == totalCues && totalCues > 0
            let firstSceneIndex = a.scenes.indices.first(where: { !a.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) ?? 0

            HStack(spacing: 12) {
                Image(systemName: isComplete ? "waveform.badge.checkmark" : "person.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isComplete ? OT.success : OT.reader)
                    .frame(width: 34, height: 34)
                    .background(isComplete ? OT.success.opacity(0.15) : OT.reader.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: "Reader Track · \(readerName)")
                    Text(recordedCount == 0
                         ? "\(totalCues) cue\(totalCues == 1 ? "" : "s") · not recorded yet"
                         : "\(recordedCount) of \(totalCues) cue\(totalCues == 1 ? "" : "s") recorded")
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                }

                Spacer()

                Button(recordedCount == 0 ? "Record" : (isComplete ? "Review" : "Continue")) {
                    store.push(.reader(a.id, sceneIndex: firstSceneIndex))
                }
                .buttonStyle(.otCompact)
            }
            .padding(16)
            .otCard()
        }
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
                Text(hasHeadshots ? "\(count) photo\(count == 1 ? "" : "s") attached" : (isOpt ? "No photos attached" : "Required in flow · tap Add"))
                    .font(.otHeadline)
                    .foregroundStyle(OT.labelPrimary)
            }
            Spacer()
            Button(hasHeadshots ? "Manage" : "Add") {
                store.push(.headshots(for: a.id))
            }
            .buttonStyle(.otCompact)
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
    @State private var recordCallbackReaderNow = false

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
                        if recordCallbackReaderNow,
                           let cbAudition = store.audition(id),
                           let firstScene = cbAudition.scenes.indices.first(where: { !cbAudition.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
                            store.push(.reader(id, sceneIndex: firstScene))
                        } else {
                            store.push(.auditionDetail(id))
                        }
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

                Section {
                    Toggle("Bring over reader track · \(readerName)", isOn: $bringReader)
                    if !bringReader || !extraScriptText.isEmpty {
                        Toggle("Record cues for callback scenes after creating", isOn: $recordCallbackReaderNow)
                    }
                }
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
                .font(.otCaption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    @State private var importError = false
    @State private var emptyClipboardAlert = false

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

            ScrollView {
                VStack(spacing: 16) {
                    // 4 Action Buttons Grid (replaces long text rows)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        Button {
                            showImporter = true
                        } label: {
                            SidesInputTile(
                                icon: "doc.badge.plus",
                                title: "Import PDF",
                                subtitle: "PDF or script file",
                                color: OT.accent
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            pasteFromClipboard()
                        } label: {
                            SidesInputTile(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "Paste Text",
                                subtitle: "From clipboard",
                                color: Color(uiColor: .systemIndigo)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            if VNDocumentCameraViewController.isSupported {
                                showScanner = true
                            } else {
                                scannerUnavailable = true
                            }
                        } label: {
                            SidesInputTile(
                                icon: "doc.viewfinder",
                                title: "Scan Pages",
                                subtitle: "Camera scanner",
                                color: Color(uiColor: .systemPurple)
                            )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(selection: $photoItems, matching: .images) {
                            SidesInputTile(
                                icon: "photo.on.rectangle",
                                title: "Photos",
                                subtitle: "Camera roll",
                                color: Color(uiColor: .systemTeal)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if reading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading pages and parsing sides…")
                                .font(.otSubhead)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                    }

                    // Script Text Area Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CALLBACK SIDES TEXT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OT.labelSecondary)
                            Spacer()
                            if !text.isEmpty {
                                Button("Clear") {
                                    withAnimation { text = "" }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OT.danger)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste or type callback sides here...\nThese extra sides will be appended to your Round 1 script.")
                                    .font(.otCallout)
                                    .foregroundStyle(OT.labelTertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }

                            ScriptTextEditor(text: $text)
                                .frame(minHeight: 140, maxHeight: 220)
                        }
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                    }

                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DETECTED IN EXTRA SIDES")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OT.labelSecondary)

                            if !parsedScenes.isEmpty {
                                HStack(spacing: 8) {
                                    SidesChip(title: "Scenes", value: "\(parsedScenes.count)", isAccent: false)
                                    SidesChip(title: role.isEmpty ? "Your role" : role, value: "\(parsedScenes.flatMap(\.lines).filter(\.isMine).count)", isAccent: true)
                                    SidesChip(title: "Total lines", value: "\(parsedScenes.flatMap(\.lines).count)", isAccent: false)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(OT.labelTertiary)
                                    Text("No structured scenes detected yet. We'll still attach this text as a new scene for your teleprompter.")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelTertiary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, OT.gutter)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
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
        .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs the iPhone camera. Use Photo or File instead.")
        }
        .alert("Couldn't read this file", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn't extract readable text from this file. If it's a scanned document or photocopy, try taking a photo or pasting the script directly.")
        }
        .alert("Clipboard is empty", isPresented: $emptyClipboardAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No text was found on your clipboard. Copy sides from an email, script, or PDF viewer, then tap Paste.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf, .text]) { result in
            switch result {
            case .success(let url):
                reading = true
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer {
                        resolved.cleanup()
                        Task { @MainActor in reading = false }
                    }
                    let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)
                    await MainActor.run {
                        if let extracted, !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            text = ScriptParser.cleanPastedText(extracted)
                            Haptics.success()
                        } else {
                            importError = true
                            Haptics.warning()
                        }
                    }
                }
            case .failure:
                importError = true
                Haptics.warning()
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
                        Haptics.success()
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
                       let img = UIImage(data: data) {
                        images.append(img)
                    }
                }
                guard !images.isEmpty else {
                    await MainActor.run { reading = false }
                    return
                }
                let recognized = await NoticeOCR.recognizeText(in: images)
                await MainActor.run {
                    text = ScriptParser.cleanPastedText(recognized)
                    photoItems = []
                    reading = false
                    Haptics.success()
                }
            }
        }
        .interactiveDismissDisabled(!text.isEmpty)
    }

    private func pasteFromClipboard() {
        let pasted = UIPasteboard.general.string ?? ""
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = ScriptParser.cleanPastedText(trimmed)
        if !cleaned.isEmpty {
            text = cleaned
            Haptics.success()
        } else {
            emptyClipboardAlert = true
            Haptics.warning()
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
    @State private var recordReaderAfterSave = false

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
                    if recordReaderAfterSave,
                       let updated = store.audition(auditionID),
                       let firstScene = updated.scenes.indices.first(where: { !updated.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
                        store.push(.reader(auditionID, sceneIndex: firstScene))
                    }
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            if let audition = store.binding(for: auditionID) {
                Form {
                    Section("Audition Type") {
                        Picker("Type", selection: Binding(
                            get: { audition.wrappedValue.resolvedMaterialKind },
                            set: { audition.wrappedValue.materialKind = $0 }
                        )) {
                            ForEach(AuditionMaterialKind.allCases) { kind in
                                Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                            }
                        }
                    }

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
                                    chars.first { $0.caseInsensitiveCompare(audition.wrappedValue.role) == .orderedSame } ?? Self.customRoleTag
                                },
                                set: { newValue in
                                    if newValue != Self.customRoleTag {
                                        audition.wrappedValue.role = newValue
                                        Haptics.tick()
                                    }
                                }
                            )) {
                                Text("Enter a different role manually").tag(Self.customRoleTag)
                                ForEach(chars, id: \.self) { char in
                                    Text(char).tag(char)
                                }
                            }
                            .pickerStyle(.menu)

                            Text("Choose a character detected in the sides, or enter a different role below.")
                                .font(.otCaption).foregroundStyle(OT.labelTertiary)

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
                                        .background(isCurrent ? AnyShapeStyle(OT.accent) : AnyShapeStyle(OT.accentSoft), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)

                            let otherChars = chars.filter { $0.caseInsensitiveCompare(audition.wrappedValue.role) != .orderedSame }
                            if let reader = otherChars.first {
                                Toggle("Record cues for \(reader) after saving", isOn: $recordReaderAfterSave)
                                    .font(.otCaption.weight(.medium))
                                    .foregroundStyle(OT.reader)
                            }
                        } else {
                            Label("No character names were found in the script. Enter your role below.", systemImage: "text.magnifyingglass")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Your role / character", text: audition.role)
                                .textInputAutocapitalization(.words)
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
                        VStack(alignment: .leading, spacing: 12) {
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
                                            let insertAt = audition.wrappedValue.pieces.firstIndex(where: { $0.kind == .headshot }).map { $0 + 1 } ?? 0
                                            audition.wrappedValue.pieces.insert(p, at: insertAt)
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
                                            let insertAt = audition.wrappedValue.pieces.firstIndex(where: { $0.kind != .headshot }) ?? audition.wrappedValue.pieces.endIndex
                                            audition.wrappedValue.pieces.insert(p, at: insertAt)
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
                            Text("Scenes")
                                .font(.otCaption.weight(.semibold))
                                .foregroundStyle(OT.labelSecondary)
                                .padding(.top, 4)
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                    } header: {
                        Text("Audition Flow & Requirements")
                    } footer: {
                        Text("Scenes, Slate, and Headshots can each be set to Required or Optional depending on casting instructions.")
                    }
                    Section {
                        ForEach(audition.wrappedValue.pieces) { piece in
                            HStack(spacing: 10) {
                                Image(systemName: piece.kind.symbol)
                                    .foregroundStyle(OT.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(piece.title).font(.otBody.weight(.medium))
                                    Text(piece.isOptional ? "Optional" : "Required")
                                        .font(.otCaption).foregroundStyle(piece.isOptional ? OT.labelSecondary : OT.accent)
                                }
                            }
                        }
                        .onMove { source, destination in
                            audition.wrappedValue.pieces.move(fromOffsets: source, toOffset: destination)
                            Haptics.tick()
                        }
                    } header: {
                        HStack {
                            Text("Flow order")
                            Spacer()
                            EditButton()
                        }
                    } footer: {
                        Text("Tap Edit, then drag items to choose the order you prepare them.")
                    }
                    Section("Due") {
                        DatePicker("Due", selection: audition.due)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quick time")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    presetTimeChip("5:00 PM") { setAuditionDueTime(audition: audition, hour: 17, minute: 0) }
                                    presetTimeChip("10:00 AM") { setAuditionDueTime(audition: audition, hour: 10, minute: 0) }
                                    presetTimeChip("12:00 PM") { setAuditionDueTime(audition: audition, hour: 12, minute: 0) }
                                    presetTimeChip("11:59 PM") { setAuditionDueTime(audition: audition, hour: 23, minute: 59) }
                                }
                            }
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

    private static let customRoleTag = "__onetake_custom_role__"

    private func scriptCharacters(for audition: Audition) -> [String] {
        var candidates = (audition.roleBreakdowns ?? []).map(\.name)
        if let script = audition.scriptText, !script.isEmpty {
            candidates += ScriptParser.extractCharacters(from: script)
        }
        for scene in audition.scenes {
            candidates += scene.lines.map(\.character)
        }
        var found: [String] = []
        for candidate in candidates {
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !ScriptParser.isBlacklistedNoticeWord(name),
                  !found.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            found.append(name)
        }
        return found
    }

    private func presetTimeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            Haptics.tick()
        }) {
            Text(title)
                .font(.otCaption.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    @State private var importError = false
    @State private var emptyClipboardAlert = false

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

    @State private var readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .recordNow

    private var readerLines: [ScriptLine] {
        activeScenes.flatMap(\.lines).filter { !$0.isMine }
    }

    private var detectedReaderName: String {
        readerLines.first?.character.capitalized ?? "Reader"
    }

    var body: some View {
        let role = audition?.role ?? ""
        VStack(spacing: 0) {
            InContentNavHeader(
                title: isNewSides ? "Add sides" : "Edit sides",
                backLabel: "Cancel",
                onBack: { dismiss() }
            ) {
                Button(isNewSides ? "Add" : "Save changes") {
                    store.replaceSides(of: auditionID, with: activeScenes, sourceText: text)
                    dismiss()
                    if readerAudioPlan == .recordNow,
                       let firstScene = activeScenes.indices.first(where: { !activeScenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
                        store.push(.reader(auditionID, sceneIndex: firstScene))
                    }
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
                .disabled(activeScenes.isEmpty)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 16) {
                    // 4 Action Buttons Grid (replaces long text rows)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        Button {
                            showImporter = true
                        } label: {
                            SidesInputTile(
                                icon: "doc.badge.plus",
                                title: "Import PDF",
                                subtitle: "PDF or script file",
                                color: OT.accent
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            pasteFromClipboard(role: role)
                        } label: {
                            SidesInputTile(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "Paste Text",
                                subtitle: "From clipboard",
                                color: Color(uiColor: .systemIndigo)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            if VNDocumentCameraViewController.isSupported {
                                showScanner = true
                            } else {
                                scannerUnavailable = true
                            }
                        } label: {
                            SidesInputTile(
                                icon: "doc.viewfinder",
                                title: "Scan Pages",
                                subtitle: "Camera scanner",
                                color: Color(uiColor: .systemPurple)
                            )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(selection: $photoItems, matching: .images) {
                            SidesInputTile(
                                icon: "photo.on.rectangle",
                                title: "Photos",
                                subtitle: "Camera roll",
                                color: Color(uiColor: .systemTeal)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if reading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading pages and parsing sides…")
                                .font(.otSubhead)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                    }

                    // Script Text Area Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(isNewSides ? "SCRIPT TEXT" : "REVISED SIDES TEXT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OT.labelSecondary)
                            Spacer()
                            if !text.isEmpty {
                                Button("Clear") {
                                    withAnimation {
                                        text = ""
                                        editableScenes = []
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OT.danger)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(isNewSides ? "Or paste or type sides here...\nCues in CAPS (e.g. MAYA) or “Maya: dialogue”." : "Paste the new sides here...")
                                    .font(.otCallout)
                                    .foregroundStyle(OT.labelTertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }

                            ScriptTextEditor(text: $text)
                                .frame(minHeight: 140, maxHeight: 220)
                                .onChange(of: text) { _, newText in
                                    editableScenes = ScriptParser.parseScenes(from: newText, myRole: role)
                                }
                        }
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                    }

                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("DETECTED SIDES")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(OT.labelSecondary)
                                Spacer()
                                Text("Tap speaker or text to edit")
                                    .font(.system(size: 11))
                                    .foregroundStyle(OT.labelTertiary)
                            }

                            if !activeScenes.isEmpty {
                                HStack(spacing: 8) {
                                    SidesChip(title: "Scenes", value: "\(activeScenes.count)", isAccent: false)
                                    SidesChip(title: role.isEmpty ? "Your role" : role, value: "\(activeScenes.flatMap(\.lines).filter(\.isMine).count)", isAccent: true)
                                    if !readerLines.isEmpty {
                                        SidesChip(title: "Reader (\(detectedReaderName))", value: "\(readerLines.count)", isAccent: false)
                                    }
                                    SidesChip(title: "Total lines", value: "\(activeScenes.flatMap(\.lines).count)", isAccent: false)
                                }

                                if !readerLines.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Label("Reader audio", systemImage: "person.wave.2.fill")
                                                .font(.otHeadline)
                                                .foregroundStyle(OT.labelPrimary)
                                            Spacer()
                                            HStack(spacing: 4) {
                                                Text("Reader:").font(.otCaption.weight(.bold)).foregroundStyle(OT.reader)
                                                Text(detectedReaderName).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.reader)
                                            }
                                        }
                                        Text("Record \(detectedReaderName)’s \(readerLines.count) cue\(readerLines.count == 1 ? "" : "s") in your voice so it plays under your takes.")
                                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                                        Picker("Reader audio", selection: $readerAudioPlan) {
                                            Text("Record cues now").tag(AddAuditionFlow.ReaderAudioPlan.recordNow)
                                            Text("Add later").tag(AddAuditionFlow.ReaderAudioPlan.later)
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                    .padding(14)
                                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                ScriptReviewAndEditView(scenes: $editableScenes)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(OT.labelTertiary)
                                    Text("No character lines recognised yet. Cues should be in CAPS (e.g. “MAYA”) or “Maya: dialogue”.")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelTertiary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, OT.gutter)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(isNewSides ? "Add sides" : "Save changes") {
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
        .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs the iPhone camera. Use Photo or File instead.")
        }
        .alert("Couldn't read this file", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn't extract readable text from this file. If it's a scanned document or photocopy, try taking a photo or pasting the script directly.")
        }
        .alert("Clipboard is empty", isPresented: $emptyClipboardAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No text was found on your clipboard. Copy sides from an email, script, or PDF viewer, then tap Paste.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf, .text]) { result in
            switch result {
            case .success(let url):
                reading = true
                let resolved = NoticeOCR.resolveSecurityScopedFile(at: url)
                Task {
                    defer {
                        resolved.cleanup()
                        Task { @MainActor in reading = false }
                    }
                    let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)
                    await MainActor.run {
                        if let extracted, !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let cleaned = ScriptParser.cleanPastedText(extracted)
                            text = cleaned
                            editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
                            Haptics.success()
                        } else {
                            importError = true
                            Haptics.warning()
                        }
                    }
                }
            case .failure:
                importError = true
                Haptics.warning()
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
                        Haptics.success()
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
                    Haptics.success()
                }
            }
        }
        .interactiveDismissDisabled(!text.isEmpty)
    }

    private func pasteFromClipboard(role: String) {
        let pasted = UIPasteboard.general.string ?? ""
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = ScriptParser.cleanPastedText(trimmed)
        if !cleaned.isEmpty {
            text = cleaned
            editableScenes = ScriptParser.parseScenes(from: cleaned, myRole: role)
            Haptics.success()
        } else {
            emptyClipboardAlert = true
            Haptics.warning()
        }
    }
}
