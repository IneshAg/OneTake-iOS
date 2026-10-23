import SwiftUI
import AVKit

// MARK: - 20 Package · Ready to send
//
// There's no casting-site API this app can submit a tape to directly, so "sending" is real:
// MediaExporter actually composes the slate, full-length and circled takes into one file, and
// handing it off happens through the system share sheet (AirDrop, Mail, Files, or the casting
// site's own upload if it's installed) — not a simulated network call that claims a third party
// confirmed receipt it never saw.

struct PackageView: View {
    enum Phase { case review, sending, failed, sent }

    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var phase: Phase = .review
    @State private var showDestination = false
    @State private var showShare = false
    @State private var showPreview = false
    @State private var progress = 0.0
    @State private var exportErrorMessage: String?

    var body: some View {
        if let a = store.audition(auditionID) {
            Group {
                switch phase {
                case .review:  review(a)
                case .sending: SendProgressView(audition: a, progress: progress, onCancel: { phase = .review })
                case .failed:  SendFailedView(message: exportErrorMessage, onRetry: send)
                case .sent:    SentView(audition: a, slate: store.slate) { store.popToRoot(); store.tab = .auditions }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: phase)
            .otCanvas()
            .sheet(isPresented: $showShare) {
                if let url = a.exportedFileURL {
                    ShareSheet(items: [url]) { completed in
                        if completed { store.markSent(auditionID); Haptics.success(); phase = .sent }
                    }
                }
            }
            .sheet(isPresented: $showPreview) {
                if let url = a.exportedFileURL { VideoPlayer(player: AVPlayer(url: url)) }
            }
        }
    }

    private func review(_ a: Audition) -> some View {
        let legend = tapeLegend(a)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ready to send.").font(.otLargeTitle)
                Text("Due \(a.due.otDue) · \(a.readyCount) of \(a.totalCount) ready").font(.otCallout).foregroundStyle(OT.labelSecondary)

                HStack { SectionLabel(text: "On the tape, in order"); Spacer(); Text(totalDurationLabel(a)).font(.otHeadline) }
                TapeStrip(legend: legend)

                VStack(spacing: 0) {
                    row(symbol: "film", title: a.deliverableFileName(slate: store.slate), detail: "Named the way casting asked · one file", value: nil)
                    Button { showDestination = true } label: { row(symbol: "paperplane", title: a.destination.rawValue, detail: nil, value: exportedSizeLabel(a)) }.buttonStyle(.plain)
                    Button { store.push(.tapeCheck(a.id)) } label: { row(symbol: "checkmark.seal.fill", title: "Tape check", detail: nil, value: "Review", tint: OT.success) }.buttonStyle(.plain)
                    row(symbol: "waveform", title: "Audio", detail: nil, value: "From your takes", tint: OT.success)
                    if a.exportedFileURL != nil {
                        Button { showPreview = true } label: { row(symbol: "play.rectangle", title: "Preview the whole tape", detail: "What's actually in the exported file", value: nil) }.buttonStyle(.plain)
                    } else {
                        row(symbol: "play.rectangle", title: "Preview the whole tape", detail: "Available once you've exported it", value: nil)
                    }
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 140)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button { send() } label: { Label("Send to \(a.destination.rawValue)", systemImage: "paperplane.fill").labelStyle(TrailingIconLabelStyle()) }
                    .buttonStyle(.otPrimary)
                Button("Choose different takes") { store.push(.takes(a.id)) }
                    .font(.otHeadline).foregroundStyle(OT.labelPrimary).frame(maxWidth: .infinity, minHeight: 48)
            }
            .padding(.horizontal, OT.gutter).background(OT.bgCanvas)
        }
        .sheet(isPresented: $showDestination) { DestinationSheet(auditionID: a.id).presentationDetents([.medium]) }
    }

    private func row(symbol: String, title: String, detail: String?, value: String?, tint: Color = OT.labelSecondary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.otBody).lineLimit(1)
                if let detail { Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary) }
            }
            Spacer()
            if let value { Text(value).font(.otFootnote).foregroundStyle(OT.labelSecondary) }
            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tapeLegend(_ a: Audition) -> [(String, String, Color)] {
        var items: [(String, String, Color)] = []
        items.append(("Headshot", a.pieces.first(where: { $0.kind == .headshot })?.isDone == true ? "Captured" : "Not yet", OT.accent.opacity(0.4)))
        items.append(("Slate", a.slateVideoURL != nil ? "Recorded" : "Not yet", OT.accent.opacity(0.4)))
        for (i, scene) in a.scenes.enumerated() {
            let take = store.takes.first(where: { $0.auditionID == a.id && $0.sceneIndex == i && $0.isCircled })
            let detail = take.map { "Take \($0.number) · \(Int($0.duration))s" } ?? "Not shot yet"
            items.append((scene.title, detail, i.isMultiple(of: 2) ? OT.accent : OT.reader))
        }
        return items
    }

    private func totalDurationLabel(_ a: Audition) -> String {
        let takes = store.takes.filter { $0.auditionID == a.id && $0.isCircled }
        guard !takes.isEmpty else { return "—" }
        let total = Int(takes.reduce(0) { $0 + $1.duration })
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func exportedSizeLabel(_ a: Audition) -> String {
        guard let url = a.exportedFileURL, let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return "Not exported yet"
        }
        return "\(size / 1_048_576) MB"
    }

    /// Real export, not a simulated upload: `MediaExporter` composes the actual recorded files, and
    /// only once that succeeds does the share sheet open so the real file can actually go somewhere.
    private func send() {
        guard let a = store.audition(auditionID) else { return }
        phase = .sending
        progress = 0
        exportErrorMessage = nil
        let takesForAudition = store.takes.filter { $0.auditionID == a.id }
        let slate = store.slate
        Task {
            do {
                let url = try await MediaExporter.export(a, takes: takesForAudition, slate: slate) { p in
                    Task { @MainActor in progress = p }
                }
                await MainActor.run {
                    store.setExportedFile(url, for: a.id)
                    phase = .review
                    showShare = true
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    phase = .failed
                }
            }
        }
    }
}

struct TapeStrip: View {
    let legend: [(String, String, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        RoundedRectangle(cornerRadius: 6).fill(item.2).frame(width: max(10, geo.size.width / CGFloat(max(legend.count, 1)) - 3))
                    }
                }
            }
            .frame(height: 44)
            HStack(spacing: 14) {
                ForEach(Array(legend.enumerated()), id: \.offset) { _, item in legendItem(item.0, item.1, item.2) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tape order: " + legend.map { "\($0.0), \($0.1)" }.joined(separator: ", "))
    }

    private func legendItem(_ t: String, _ d: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8); Text(t).font(.otCaption.weight(.semibold)) }
            Text(d).font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
    }
}

// MARK: - 20.1 / 20.2 Where is it going?

struct DestinationSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Destination.allCases) { d in
                        Button {
                            if let i = store.auditions.firstIndex(where: { $0.id == auditionID }) { store.auditions[i].destination = d }
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) { Text(d.rawValue).font(.otBody); Text(d.spec).font(.otFootnote).foregroundStyle(OT.labelTertiary) }
                                Spacer()
                                if store.audition(auditionID)?.destination == d { Image(systemName: "checkmark.circle.fill").foregroundStyle(OT.accent) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("We match the file name each site asks for. Every destination hands off through your Share Sheet — there's no direct upload API.")
                }
            }
            .navigationTitle("Where’s it going?").navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 20.3 Exporting

struct SendProgressView: View {
    let audition: Audition
    let progress: Double
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Packaging your tape").padding(.top, 20)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(progress * 100))").font(.system(size: 72, weight: .bold)).monospacedDigit()
                Text("%").font(.otTitle)
            }
            ProgressView(value: progress).tint(OT.accent)
            Text("Joining your slate, full length and circled takes into one file.").font(.otFootnote).foregroundStyle(OT.labelTertiary)
            SectionLabel(text: "Steps").padding(.top, 8)
            step("Found your recorded pieces", done: true)
            step("Composing one file", done: progress < 1, active: progress < 1)
            step("Done — opens your Share Sheet", done: progress >= 1)
            Text("Exported locally — nothing leaves this iPhone until you choose where to send it next.")
                .font(.otFootnote).foregroundStyle(OT.labelTertiary)
            Spacer()
            Button("Cancel", action: onCancel).buttonStyle(.otSecondary)
        }
        .padding(.horizontal, OT.gutter)
    }

    private func step(_ t: String, done: Bool, active: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : active ? "arrow.triangle.2.circlepath.circle.fill" : "circle")
                .foregroundStyle(done ? OT.success : active ? OT.accent : OT.labelTertiary)
            Text(t).font(.otBody).foregroundStyle(done || active ? OT.labelPrimary : OT.labelTertiary)
        }
        .frame(minHeight: 36)
    }
}

// MARK: - 20.4 Couldn't export

struct SendFailedView: View {
    let message: String?
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(OT.warning).padding(.top, 20)
            Text("Couldn't package it").font(.otLargeTitle)
            Text(message ?? "Something went wrong composing your tape. Your takes are untouched on this iPhone — this only affects the combined file.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            Spacer()
            Button("Try again", action: onRetry).buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OT.gutter)
    }
}

// MARK: - 21 Sent

struct SentView: View {
    let audition: Audition
    let slate: SlateInfo
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SHARED · \(Date.now.formatted(.dateTime.weekday(.abbreviated).hour().minute()).uppercased())")
                        .font(.otCaption.weight(.semibold)).foregroundStyle(OT.success)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(OT.success)
                }
                Text(audition.deliverableFileName(slate: slate)).font(.otFootnote.weight(.semibold))
                Text("Headshot · slate · \(audition.scenes.count) scene\(audition.scenes.count == 1 ? "" : "s")").font(.otFootnote).foregroundStyle(OT.labelSecondary)
            }
            .padding(16).otCard(radius: 18).rotationEffect(.degrees(1.5)).padding(.top, 30)

            Text("It’s on its way.").font(.system(size: 38, weight: .bold))
            HStack(alignment: .firstTextBaseline) {
                Text(earlyText).font(.otTitle).foregroundStyle(OT.success)
                Text("Break a leg.").font(.otHeadline).foregroundStyle(OT.labelSecondary)
            }
            Label("Handed off through your Share Sheet to \(audition.destination.rawValue)", systemImage: "square.and.arrow.up").font(.otFootnote).foregroundStyle(OT.labelSecondary)
            Label("All your takes stay here if they ask for another", systemImage: "iphone").font(.otFootnote).foregroundStyle(OT.labelSecondary)
            Spacer()
            Button("Done", action: onDone).buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OT.gutter)
        .onAppear { Haptics.success() }
    }

    private var earlyText: String {
        let h = audition.hoursLeft
        return h >= 1 ? "\(h) hours early." : "Right on time."
    }
}
