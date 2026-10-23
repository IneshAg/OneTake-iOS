import SwiftUI
import AVKit

// MARK: - 18 Your takes

struct TakesView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var selected: Take.ID?
    @State private var showOneMore = false
    @State private var notesOpen = false

    var body: some View {
        let takes = store.takes
        let current = takes.first { $0.id == (selected ?? takes.first(where: \.isCircled)?.id) } ?? takes.last
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlayerCard(url: current?.fileURL)
                PlaybackBar()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(takes) { take in
                            TakeThumbnail(take: take, isSelected: take.id == current?.id)
                                .onTapGesture { selected = take.id; Haptics.tick() }
                                .onLongPressGesture { store.circle(take); Haptics.success() }
                        }
                    }
                }

                HStack {
                    Text("Take \(takes.first(where: \.isCircled)?.number ?? 0) is circled — that's your send.").font(.otFootnote).foregroundStyle(OT.labelSecondary)
                    Spacer()
                    if let c = current, !c.isCircled {
                        Button("Circle take \(c.number)") { store.circle(c); Haptics.success() }.font(.otFootnote.weight(.semibold))
                    }
                }

                DisclosureGroup(isExpanded: $notesOpen) {
                    VStack(alignment: .leading, spacing: 6) { ForEach(current?.notes ?? [], id: \.self) { Text("• \($0)").font(.otCallout) } }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: {
                    VStack(alignment: .leading) {
                        Label("Notes to self", systemImage: "square.and.pencil").font(.otBody)
                        Text("Never sent · " + (current?.notes.joined(separator: " · ") ?? "")).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    }
                }
                .tint(OT.labelPrimary)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 100)
        }
        .otCanvas()
        .navigationTitle("Your takes").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Compare Takes is cut from MVP — the loop stays record → check → keep/retake/edit, no
            // side-by-side comparison step.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { } label: { Image(systemName: "scissors") }.accessibilityLabel("Trim")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Go again") { showOneMore = true }.buttonStyle(.otSecondary).frame(width: 130)
                Button("Send take \(takes.first(where: \.isCircled)?.number ?? 0)") { store.push(.tapeCheck(auditionID)) }.buttonStyle(.otPrimary)
            }
            .padding(.horizontal, OT.gutter).padding(.vertical, 8).background(OT.bgCanvas)
        }
        .sheet(isPresented: $showOneMore) {
            VStack(spacing: 14) {
                Text("One more?").font(.otTitle)
                Text("Takes 1 to \(takes.count) stay right here. Three solid takes is plenty — trust the one you circled.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary).multilineTextAlignment(.center)
                Button("Record take \(takes.count + 1)") { showOneMore = false; store.camera = .shoot(auditionID) }.buttonStyle(.otPrimary)
                Button("Not now") { showOneMore = false }.buttonStyle(.otSecondary)
            }
            .padding(OT.gutter)
            .presentationDetents([.height(300)])
        }
    }
}

/// AVKit player (UIKit-backed `AVPlayerViewController` via SwiftUI `VideoPlayer`).
struct PlayerCard: View {
    let url: URL?
    var body: some View {
        ZStack {
            if let url { VideoPlayer(player: AVPlayer(url: url)) }
            else {
                HeadshotImage()
                Image(systemName: "play.fill").font(.title).foregroundStyle(.white)
                    .frame(width: 60, height: 60).background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - v2/Playback Bar

struct PlaybackBar: View {
    @State private var position = 0.35
    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $position)
            HStack { Text("0:00"); Spacer(); Text("your lines · tap to jump").foregroundStyle(OT.accent); Spacer(); Text("1:30") }
                .font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
    }
}

// MARK: - v2/Take Thumbnail · Default / Selected / Chosen

struct TakeThumbnail: View {
    let take: Take
    var isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HeadshotImage()
                .frame(width: 104, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? OT.accent : .clear, lineWidth: 2.5).padding(-3))
            HStack(spacing: 4) {
                Text("Take \(take.number)").font(.otHeadline)
                if take.isCircled { Image(systemName: "star.fill").font(.caption).foregroundStyle(OT.accent) }
            }
            Text("\(Int(take.duration) / 60):\(String(format: "%02d", Int(take.duration) % 60)) · \(take.recordedAt.formatted(.relative(presentation: .numeric)))")
                .font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Long-press to circle this take")
    }
}

// MARK: - 19b Tape check

struct TapeCheckView: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @State private var finding: TapeFinding?
    @State private var passedOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ReadinessDial(done: 11, total: 13, size: 84, lineWidth: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to send").font(.otTitle)
                        Text("\(SampleData.findings.count) things are worth a look. Nothing stops you sending.").font(.otCallout).foregroundStyle(OT.labelSecondary)
                    }
                }
                SectionLabel(text: "Worth a look")
                ForEach(SampleData.findings) { f in
                    Button { finding = f } label: {
                        HStack(spacing: 12) {
                            HeadshotImage().frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.category).font(.otCaption.weight(.semibold)).foregroundStyle(OT.warning)
                                Text(f.title).font(.otBody)
                                Text(f.where_).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(OT.labelTertiary)
                        }
                        .frame(minHeight: 60)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                DisclosureGroup(isExpanded: $passedOpen) {
                    Text("Framing, light, slate, format, length, file name, audio sync, eyeline (scene 2), reader level (scene 1), background, focus")
                        .font(.otFootnote).foregroundStyle(OT.labelSecondary).padding(.top, 6)
                } label: {
                    Label("11 checks passed", systemImage: "checkmark.seal.fill").foregroundStyle(OT.success)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 140)
        }
        .otCanvas()
        .navigationTitle("Tape check").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button("Continue to package") { store.push(.package(auditionID)) }.buttonStyle(.otPrimary)
                Button("Watch the \(SampleData.findings.count) moments") { finding = SampleData.findings.first }
                    .font(.otHeadline).foregroundStyle(OT.labelPrimary).frame(maxWidth: .infinity, minHeight: 48)
            }
            .padding(.horizontal, OT.gutter).background(OT.bgCanvas)
        }
        .sheet(item: $finding) { f in
            VStack(alignment: .leading, spacing: 12) {
                Text("\(f.category) · \(f.where_)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.warning)
                Text(f.title).font(.otTitle)
                PlayerCard(url: nil)
                Text(f.advice).font(.otCallout).foregroundStyle(OT.labelSecondary)
                HStack {
                    Button("Watch 0:41") {}.buttonStyle(.otSecondary)
                    Button("I meant it") { finding = nil }.buttonStyle(.otSecondary)
                }
            }
            .padding(OT.gutter)
            .presentationDetents([.medium, .large])
        }
    }
}
