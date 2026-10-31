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
                HStack {
                    Button { store.pop() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(OT.labelPrimary)
                            .frame(width: 38, height: 38)
                            .background(OT.fillField, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer()

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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(a.hoursLeft)").font(.otNumber).foregroundStyle(OT.due)
                        Text("h left").font(.otHeadline).foregroundStyle(OT.due)
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
                HStack { SectionLabel(text: "Up next · piece 1 of \(a.totalCount)"); Spacer(); Text("≈ 2 min").font(.otFootnote).foregroundStyle(OT.labelTertiary) }
                Text("Your headshot").font(.otTitle)
                Text("FRONT · LEFT · RIGHT").font(.otCaption).foregroundStyle(OT.labelTertiary)
                quoteLine("Casting sees this first. A window and a plain wall is all you need.")
                Button("Take your headshot") { store.push(.headshots(for: a.id)) }.buttonStyle(.otPrimary)
            } else if next?.kind == .slate || next?.kind == .fullLength {
                SectionLabel(text: "Up next · \(next?.title ?? "")")
                Text(next?.kind == .slate ? "Record the slate" : "Full-length shot").font(.otTitle)
                quoteLine(store.slate.spoken)
                Button("Set up the camera") { store.push(.shootSetup(a.id)) }.buttonStyle(.otPrimary)
            } else if let next, next.kind == .scene, let sceneIndex = a.scenes.firstIndex(where: { $0.title == next.title }) {
                let scene = a.scenes[sceneIndex]
                HStack { SectionLabel(text: "Up next · scene \(scene.number) of \(a.scenes.count)"); Spacer(); Text("≈ \(scene.estimatedSeconds / 60):\(String(format: "%02d", scene.estimatedSeconds % 60)) · \(scene.lines.filter(\.isMine).count) lines").font(.otFootnote).foregroundStyle(OT.labelTertiary) }
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
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 34, height: 34)
                    .background(OT.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sides")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelTertiary)
                    Text("No sides attached yet")
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                }
                Spacer()
                Button("Add sides") {
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
                    Button { dismiss(); open(piece, a) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: piece.isDone ? "checkmark" : piece.kind.symbol)
                                .foregroundStyle(piece.isDone ? OT.labelOnAccent : OT.accent)
                                .frame(width: 44, height: 44)
                                .background(piece.isDone ? OT.accent : OT.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(i + 1)  \(piece.title)").font(.otHeadline)
                                Text(piece.detail.isEmpty ? "not shot yet" : piece.detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            if piece.id == a.nextPiece?.id { Text("Next").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent) }
                            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                        }
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
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
    @State private var notes = ""
    @State private var bringReader = true

    private var readerName: String {
        audition.scenes.first?.lines.first(where: { !$0.isMine })?.character ?? "your reader"
    }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Start a callback", backLabel: "Cancel", onBack: { dismiss() }) {
                Button("Create") {
                    if let id = store.startCallback(from: audition.id, due: due, notes: notes, bringReader: bringReader) {
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
                Section("When is it due?") { DatePicker("Due", selection: $due, in: Date.now...) }
                Section("Scenes to tape") { ForEach(audition.scenes) { Label("\($0.number) · \($0.title)", systemImage: "checkmark.circle.fill") } }
                Section {
                    TextField("e.g. “Less angry, more hurt.”", text: $notes, axis: .vertical)
                } header: {
                    Text("Notes from casting")
                } footer: {
                    Text("Shown on Prepare, so you see the adjustment before every take.")
                }
                Section { Toggle("Bring over reader track · \(readerName)", isOn: $bringReader) }
            }
            .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Edit details

struct EditAuditionSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Edit details", backLabel: "Cancel", onBack: { dismiss() }) {
                Button("Done") {
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
                        TextField("Project", text: audition.project)
                        TextField("Type (film, series, commercial…)", text: audition.projectType)
                        TextField("Casting office", text: audition.castingOffice)
                    }
                    Section("Role") {
                        TextField("Role", text: audition.role)
                        TextField("Size (lead, supporting…)", text: audition.roleSize)
                    }
                    Section("Due") { DatePicker("Due", selection: audition.due) }
                    Section("Sending to") {
                        Picker("Destination", selection: audition.destination) {
                            ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Section {
                        TextField("Notes from casting", text: Binding(
                            get: { audition.wrappedValue.castingNotes ?? "" },
                            set: { audition.wrappedValue.castingNotes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                    } footer: { Text("Shown on Prepare before every take.") }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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

    var body: some View {
        let role = audition?.role ?? ""
        let parsed = ScriptParser.parseScenes(from: text, myRole: role)
        VStack(spacing: 0) {
            InContentNavHeader(
                title: isNewSides ? "Add sides" : "Revised sides",
                backLabel: "Cancel",
                onBack: { dismiss() }
            ) {
                Button(isNewSides ? "Add" : "Replace") {
                    store.replaceSides(of: auditionID, with: parsed, sourceText: text)
                    dismiss()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
                .disabled(parsed.isEmpty)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            Form {
                Section {
                    HStack {
                        Text("Paste from clipboard")
                            .font(.otHeadline)
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            let pasted = strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !pasted.isEmpty { text = pasted }
                        }
                        .buttonBorderShape(.capsule)
                        .tint(OT.accent)
                    }

                    TextField(isNewSides ? "Or paste or type sides here..." : "Paste the new sides", text: $text, axis: .vertical)
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
                    Section("Detected from sides") {
                        if !parsed.isEmpty {
                            LabeledContent("Scenes", value: "\(parsed.count)")
                            LabeledContent("Your lines (\(role.isEmpty ? "Your role" : role))", value: "\(parsed.flatMap(\.lines).filter(\.isMine).count)")
                            LabeledContent("Total character lines", value: "\(parsed.flatMap(\.lines).count)")
                        } else {
                            Text("No character lines recognised yet. Cues should be in CAPS (e.g. “MAYA”) or “Maya: dialogue”.")
                                .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !isNewSides, let existing = audition?.scriptText, !existing.isEmpty {
                text = existing
            }
        }
        .alert("Camera scanning not available", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning requires a device with camera support. You can paste the sides text or import a PDF/text file.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            if let extracted = NoticeOCR.extractText(fromFileAt: url) { text = extracted }
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                reading = true
                Task {
                    let recognized = await NoticeOCR.recognizeText(in: pages)
                    await MainActor.run { text = recognized; reading = false }
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
                await MainActor.run { text = recognized; reading = false; photoItems = [] }
            }
        }
    }
}
