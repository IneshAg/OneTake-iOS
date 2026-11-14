import SwiftUI

/// 07 Audition detail
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
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Sides Revision Banner
                if a.currentSidesRevision > 0 {
                    HStack(spacing: OTSpace.s) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.otIcon(.s, weight: .semibold))
                            .foregroundStyle(OT.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sides Revision \(a.currentSidesRevision)")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text("Updated sides in use. Prior takes and audio are archived.")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }
                    .padding(OTSpace.m)
                    .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
                }

                // Header
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    OTSectionLabel("\(a.resolvedMaterialKind.shortLabel) · \(a.projectType) · reading for \(a.role)" + (a.round.map { " · round \($0)" } ?? ""))
                    Text(a.project).font(.system(size: 40, weight: .bold)).foregroundStyle(OT.labelPrimary) // ot-lint:allow
                    HStack(alignment: .firstTextBaseline, spacing: 5) { // ot-lint:allow
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
                        HStack(spacing: OTSpace.m) {
                            ForEach(a.asks.prefix(3), id: \.self) { Text($0).font(.otFootnote).foregroundStyle(OT.labelSecondary) }
                            if a.asks.count > 3 { Text("+\(a.asks.count - 3)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent) }
                        }
                    }
                }

                // Package
                Button { showPackage = true } label: {
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            OTSectionLabel("Package")
                            Spacer()
                            Label("All pieces", systemImage: "chevron.forward").labelStyle(TrailingIconLabelStyle())
                                .font(.otFootnote).foregroundStyle(OT.accent)
                        }
                        HStack(spacing: 6) { // ot-lint:allow
                            Text("\(a.readyCount) of \(a.totalCount) ready").font(.otHeadline).foregroundStyle(OT.labelPrimary)
                            if let next = a.nextPiece {
                                Text(a.readyCount == 0 ? "· \(next.title) first" : "· \(next.title) next").font(.otCallout).foregroundStyle(OT.labelSecondary)
                            }
                        }
                        PackageStepsBar(pieces: a.pieces)
                    }
                }
                .buttonStyle(.plain)

                UpNextCard(audition: a)

                if let dates = a.importantDates, !dates.isEmpty {
                    MilestoneDatesListCard(dates: dates)
                }

                if let details = a.projectDetails, details.hasReviewableContent {
                    ProjectDetailsCard(details: details)
                }

                if let instructions = a.submissionInstructions {
                    SubmissionInstructionsCard(instructions: instructions)
                }

                sidesCard(a)

                readerTrackCard(a)

                if a.nextPiece?.kind != .headshot {
                    headshotsCard(a)
                }

                let previousTakes = store.takes.filter { $0.auditionID == a.id && $0.previousSides }
                if !previousTakes.isEmpty {
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        OTSectionLabel("Previous Takes (Earlier Sides)")
                        ForEach(previousTakes) { take in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(take.previousSidesLabel ?? "Take \(take.number)")
                                        .font(.otHeadline)
                                        .foregroundStyle(OT.labelPrimary)
                                    Text("Recorded for earlier sides · Revision \(take.sidesRevision ?? 0)")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                                Button("Review") {
                                    store.push(.takes(a.id, sceneIndex: take.sceneIndex))
                                }
                                .buttonStyle(.otCompact)
                            }
                            .otCard(.grouped)
                        }
                    }
                }

                if a.status != .sent && a.readyCount == a.totalCount && a.totalCount > 0 {
                    Button {
                        store.markSent(a.id)
                        Haptics.success()
                    } label: {
                        Label("Mark as Submitted", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.ot(.primary, size: .large, shape: .capsule))
                } else if a.status == .sent {
                    Button {
                        store.unmarkSent(a.id)
                        Haptics.tick()
                    } label: {
                        Label("Undo Submission", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.ot(.secondary, size: .medium, shape: .capsule))
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
        }
        .otCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            OTTrailingToolbarSpacer()
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if a.status == .sent {
                        Button {
                            store.unmarkSent(a.id)
                            Haptics.tick()
                        } label: {
                            Label("Undo submission", systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                    Button { showCallback = true } label: { Label("Start a callback", systemImage: "arrow.uturn.right") }
                    Divider()
                    Button(role: .destructive) { showDelete = true } label: { Label("Delete audition", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
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

    @ViewBuilder private func sidesCard(_ a: Audition) -> some View {
        if a.resolvedMaterialKind == .slateOnly {
            HStack(spacing: OTSpace.m) {
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.otIcon(.s, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(width: 34, height: 34) // ot-lint:allow
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
            .otCard(.grouped)
        } else {
            HStack(spacing: OTSpace.m) {
                if a.scenes.isEmpty {
                    Image(systemName: a.sidesLink != nil ? "link.circle.fill" : "doc.badge.plus")
                        .font(.otIcon(.s, weight: .semibold))
                        .foregroundStyle(OT.accent)
                        .frame(width: 34, height: 34) // ot-lint:allow
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
                                .font(.otIcon(.s))
                                .foregroundStyle(OT.accent)
                                .frame(width: 32, height: 32) // ot-lint:allow
                                .background(OT.accentSoft, in: Circle())
                        }
                    }
                    Button(a.sidesLink != nil ? "Import" : "Add sides") {
                        showSides = true
                    }
                    .buttonStyle(.ot(.secondary, size: .small, fullWidth: false, shape: .capsule))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        OTSectionLabel(a.resolvedMaterialKind == .monologue ? "Monologue" : "Sides")
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
            .otCard(.grouped)
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

            HStack(spacing: OTSpace.m) {
                Image(systemName: isComplete ? "waveform.badge.checkmark" : "person.wave.2.fill")
                    .font(.otIcon(.s, weight: .semibold))
                    .foregroundStyle(isComplete ? OT.success : OT.reader)
                    .frame(width: 34, height: 34) // ot-lint:allow
                    .background(isComplete ? OT.success.opacity(0.15) : OT.reader.opacity(0.15), in: Circle()) // ot-lint:allow

                VStack(alignment: .leading, spacing: 2) {
                    OTSectionLabel("Reader Track · \(readerName)")
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
            .otCard(.grouped)
        }
    }

    @ViewBuilder private func headshotsCard(_ a: Audition) -> some View {
        let hasHeadshots = HeadshotStore.exists(key: "front", auditionID: a.id)
        let count = HeadshotStore.taken(auditionID: a.id).count
        let headshotPiece = a.pieces.first { $0.kind == .headshot }
        let isIncluded = headshotPiece != nil
        let isOpt = headshotPiece?.isOptional ?? true
        HStack(spacing: OTSpace.m) {
            Image(systemName: hasHeadshots ? "photo.fill" : "photo.badge.plus")
                .font(.otIcon(.s, weight: .semibold))
                .foregroundStyle(OT.accent)
                .frame(width: 34, height: 34) // ot-lint:allow
                .background(OT.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                OTSectionLabel(!isIncluded || isOpt ? "Headshots (Optional)" : "Headshots")
                Text(hasHeadshots
                     ? "\(count) photo\(count == 1 ? "" : "s") attached"
                     : (!isIncluded
                        ? "Optional · tap Add to attach"
                        : (isOpt ? "No photos attached" : "Step in flow · or tap Add now")))
                    .font(.otHeadline)
                    .foregroundStyle(OT.labelPrimary)
            }
            Spacer()
            Button(hasHeadshots ? "Manage" : "Add") {
                store.push(.headshots(for: a.id))
            }
            .buttonStyle(.otCompact)
        }
        .otCard(.grouped)
    }
}
