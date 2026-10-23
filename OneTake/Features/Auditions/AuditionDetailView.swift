import SwiftUI

/// 07 Audition detail (and 7.0 "just added · 0 of 4" when nothing is done yet).
struct AuditionDetailView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var showPackage = false
    @State private var showDelete = false
    @State private var showCallback = false

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
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "\(a.projectType) · reading for \(a.role)")
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { } label: { Label("Revised sides", systemImage: "doc.badge.arrow.up") }
                    Button { } label: { Label("Edit details", systemImage: "pencil") }
                    Button { showCallback = true } label: { Label("Start a callback", systemImage: "arrow.uturn.right") }
                    Divider()
                    Button(role: .destructive) { showDelete = true } label: { Label("Delete audition", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(isPresented: $showPackage) { PackageSheet(auditionID: a.id).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showCallback) { CallbackSheet(audition: a) }
        .confirmationDialog("Delete “\(a.project)”?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.auditions.removeAll { $0.id == a.id }; store.popToRoot() }
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
                Button("Take your headshot") { store.push(.headshots) }.buttonStyle(.otPrimary)
            } else if next?.kind == .slate || next?.kind == .fullLength {
                SectionLabel(text: "Up next · \(next?.title ?? "")")
                Text(next?.kind == .slate ? "Record the slate" : "Full-length shot").font(.otTitle)
                quoteLine(store.slate.spoken)
                Button("Set up the camera") { store.push(.shootSetup(a.id)) }.buttonStyle(.otPrimary)
            } else if next?.kind == .scene, let scene = a.scenes.first {
                HStack { SectionLabel(text: "Up next · scene \(scene.number) of \(a.scenes.count)"); Spacer(); Text("≈ \(scene.estimatedSeconds / 60):\(String(format: "%02d", scene.estimatedSeconds % 60)) · \(scene.lines.filter(\.isMine).count) lines").font(.otFootnote).foregroundStyle(OT.labelTertiary) }
                Text(scene.title).font(.otTitle)
                Text(scene.heading).font(.otCaption).foregroundStyle(OT.labelTertiary)
                if let first = scene.lines.first(where: \.isMine) { quoteLine(first.text) }
                Button("Prepare scene \(scene.number)") { store.push(.prepare(a.id, sceneIndex: 0)) }.buttonStyle(.otPrimary)
            } else if next?.kind == .scene {
                SectionLabel(text: "Up next · \(next?.title ?? "scene")")
                Text("No sides captured yet").font(.otTitle)
                Text("Nothing was readable in what you added this audition from — rescan or retype the sides to prepare and shoot this scene.").font(.otCallout).foregroundStyle(OT.labelSecondary)
            } else {
                SectionLabel(text: "Everything's in")
                Text("Watch it once, then send").font(.otTitle)
                Button("Review the package") { store.push(.package(a.id)) }.buttonStyle(.otPrimary)
            }
        }
        .padding(20)
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
                    Button { open(piece, a); dismiss() } label: {
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
                Label("Each piece opens its own screen.", systemImage: "hand.tap").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                Spacer()
            }
            .padding(OT.gutter)
        }
    }

    private func open(_ piece: Piece, _ a: Audition) {
        switch piece.kind {
        case .headshot: store.push(.headshots)
        case .slate, .fullLength: store.push(.shootSetup(a.id))
        case .scene: store.push(.prepare(a.id, sceneIndex: 0))
        }
    }
}

// MARK: - 7c Start a callback

struct CallbackSheet: View {
    let audition: Audition
    @Environment(\.dismiss) private var dismiss
    @State private var due = Date.now.addingTimeInterval(5 * 86400)
    @State private var notes = ""
    @State private var bringReader = true

    var body: some View {
        NavigationStack {
            Form {
                Section { LabeledContent(audition.project, value: "Round 2") }
                Section("When is it due?") { DatePicker("Due", selection: $due, in: Date.now...) }
                Section("Scenes to tape") { ForEach(audition.scenes) { Label("\($0.number) · \($0.title)", systemImage: "checkmark.circle.fill") } }
                Section {
                    TextField("e.g. “Less angry, more hurt.”", text: $notes, axis: .vertical)
                } header: {
                    Text("Notes from casting")
                } footer: {
                    Text("Shown on Prepare, so you see the adjustment before every take.")
                }
                Section { Toggle("Bring over reader track · Maya", isOn: $bringReader) }
            }
            .navigationTitle("Start a callback").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { dismiss() } }
            }
        }
    }
}
