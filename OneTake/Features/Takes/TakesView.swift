import SwiftUI
import OneTakeUI
import AVKit

// MARK: - 18 Your takes

struct TakesView: View {
    let auditionID: Audition.ID
    var initialScene: Int? = nil
    @Environment(AppStore.self) private var store
    @State private var selected: Take.ID?
    @State private var showOneMore = false
    @State private var notesOpen = false
    @State private var trimming: Take?
    @State private var newNote = ""
    /// Which scene's takes are showing — each scene has its own circled take.
    @State private var scene: Int?

    private var scenes: [ScriptScene] { store.audition(auditionID)?.scenes ?? [] }

    /// The chosen scene, else the scene of the most recent take, else the first.
    private var shownScene: Int {
        scene ?? initialScene ?? store.takes.last(where: { $0.auditionID == auditionID })?.sceneIndex ?? 0
    }

    private var hasPreview: Bool {
        store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
    }

    private var hasTapeCheck: Bool {
        store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
    }

    var body: some View {
        let takes = store.takes.filter { $0.auditionID == auditionID && ($0.sceneIndex ?? 0) == shownScene }
        let current = takes.first { $0.id == (selected ?? takes.first(where: \.isCircled)?.id) } ?? takes.last
        let circled = takes.first(where: \.isCircled)

        OTScreen(
            title: "Your takes",
            backLabel: "Back",
            onBack: { store.pop() },
            trailing: {
                OTIconButton("scissors", accessibilityLabel: "Trim") {
                    trimming = current
                }
                .disabled(!(current?.fileURL.map(VideoTrimmer.canTrim) ?? false))
                .opacity((current?.fileURL.map(VideoTrimmer.canTrim) ?? false) ? 1.0 : 0.4)
            }
        ) {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                if scenes.count > 1 {
                    Picker("Scene", selection: Binding(get: { shownScene }, set: { scene = $0; selected = nil })) {
                        ForEach(scenes.indices, id: \.self) { Text(scenes[$0].title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                PlayerCard(url: current?.fileURL)
                    .padding(.top, OTSpace.xxs)

                if let current, current.originalFileURL != nil {
                    Button {
                        store.restoreOriginalTakeFile(current.id)
                        Haptics.success()
                    } label: {
                        Label("Restore original clip", systemImage: "arrow.uturn.backward")
                            .font(.otFootnote.weight(.semibold))
                    }
                    .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OTSpace.m) {
                        ForEach(takes) { take in
                            TakeThumbnail(take: take, isSelected: take.id == current?.id)
                                .onTapGesture { selected = take.id; Haptics.tick() }
                                .onLongPressGesture { store.circleOnly(take); Haptics.success() }
                        }
                    }
                }

                HStack {
                    Text(circled.map { "Take \($0.number) is circled — that's your send." }
                         ?? (takes.isEmpty ? "No takes for this scene yet." : "Long-press a take to circle it."))
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                    Spacer()
                    if let c = current, !c.isCircled {
                        Button("Circle take \(c.number)") {
                            store.circleOnly(c)
                            Haptics.success()
                        }
                        .font(.otFootnote.weight(.semibold))
                    }
                }

                DisclosureGroup(isExpanded: $notesOpen) {
                    VStack(alignment: .leading, spacing: OTSpace.xs) {
                        ForEach(current?.notes ?? [], id: \.self) { Text("• \($0)").font(.otCallout) }
                        if let c = current {
                            TextField("Add a note to take \(c.number)", text: $newNote)
                                .submitLabel(.done)
                                .onSubmit { store.addNote(newNote, to: c.id); newNote = "" }
                                .padding(OTSpace.s)
                                .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, OTSpace.s)
                } label: {
                    VStack(alignment: .leading) {
                        Label("Notes to self", systemImage: "square.and.pencil").font(.otBody)
                        Text((current?.notes.isEmpty ?? true) ? "Never sent · nothing yet" : "Never sent · " + (current?.notes.joined(separator: " · ") ?? ""))
                            .font(.otFootnote).foregroundStyle(OT.labelTertiary).lineLimit(1)
                    }
                }
                .tint(OT.labelPrimary)
            }
        }
        .otBottomBar {
            HStack {
                Button("Go again") {
                    showOneMore = true
                }
                .buttonStyle(.otSecondary)
                .frame(width: 130) // ot-lint:allow

                if hasPreview {
                    Button("Back to preview") {
                        store.popTo(.preview(auditionID))
                    }
                    .buttonStyle(.otPrimary)
                    .disabled(!store.takes.contains { $0.auditionID == auditionID })
                } else if hasTapeCheck {
                    Button("Back to tape check") {
                        store.popTo(.tapeCheck(auditionID))
                    }
                    .buttonStyle(.otPrimary)
                    .disabled(!store.takes.contains { $0.auditionID == auditionID })
                } else if let nextRequiredUnshot = scenes.indices.first(where: { idx in
                    idx != shownScene
                    && !store.takes.contains { $0.auditionID == auditionID && ($0.sceneIndex ?? 0) == idx }
                    && !(store.audition(auditionID)?.pieces.first(where: { $0.kind == .scene && $0.title == scenes[idx].title })?.isOptional ?? false)
                }) {
                    Button("Next: \(scenes[nextRequiredUnshot].title)") {
                        store.camera = .shoot(auditionID, scene: nextRequiredUnshot)
                    }
                    .buttonStyle(.otPrimary)
                } else {
                    Button("Check the tape") {
                        store.push(.tapeCheck(auditionID))
                    }
                    .buttonStyle(.otPrimary)
                    .disabled(!store.takes.contains { $0.auditionID == auditionID })
                }
            }
        }
        .sheet(item: $trimming) { take in
            if let url = take.fileURL {
                VideoTrimmer(url: url) { edited in
                    trimming = nil
                    if let edited {
                        store.replaceTakeFile(take.id, with: edited)
                        Haptics.success()
                    }
                }
            }
        }
        .sheet(isPresented: $showOneMore) {
            VStack(spacing: OTSpace.m) {
                Text("One more?").font(.otTitle)
                Text("Takes 1 to \(takes.count) stay right here. Three solid takes is plenty — trust the one you circled.")
                    .font(.otCallout)
                    .foregroundStyle(OT.labelSecondary)
                    .multilineTextAlignment(.center)
                Button("Record take \(store.nextTakeNumber(auditionID: auditionID, sceneIndex: shownScene))") {
                    showOneMore = false
                    store.camera = .shoot(auditionID, scene: shownScene)
                }
                .buttonStyle(.otPrimary)
                Button("Not now") {
                    showOneMore = false
                }
                .buttonStyle(.otSecondary)
            }
            .padding(OTSpace.gutter)
            .presentationDetents([.height(300)]) // ot-lint:allow
        }
    }
}

/// AVKit player (UIKit-backed `AVPlayerViewController` via SwiftUI `VideoPlayer`).
struct PlayerCard: View {
    let url: URL?
    @State private var player: AVPlayer?

    init(url: URL?) {
        self.url = url
        _player = State(initialValue: url.map { AVPlayer(url: $0) })
    }

    var body: some View {
        ZStack {
            Color.black // ot-lint:allow
            if url != nil, let player {
                VideoPlayer(player: player)
            } else {
                HeadshotImage()
                Image(systemName: "play.fill")
                    .font(.title)
                    .foregroundStyle(Color.white) // ot-lint:allow
                    .frame(width: 60, height: 60) // ot-lint:allow
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(height: 330) // ot-lint:allow
        .clipShape(RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1) // ot-lint:allow
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .onChange(of: url) { _, newURL in
            player?.pause()
            player = newURL.map { AVPlayer(url: $0) }
        }
    }
}

// MARK: - v2/Take Thumbnail · Default / Selected / Chosen

struct TakeThumbnail: View {
    let take: Take
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let url = take.fileURL {
                    VideoThumbnail(url: url)
                } else {
                    HeadshotImage()
                }
            }
            .frame(width: 104, height: 64) // ot-lint:allow
            .clipShape(RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OTRadius.m)
                    .stroke(isSelected ? OT.accent : Color.clear, lineWidth: 2.5) // ot-lint:allow
                    .padding(-3) // ot-lint:allow
            )

            HStack(spacing: 4) {
                Text("Take \(take.number)").font(.otHeadline)
                if take.isCircled {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(OT.accent)
                }
            }
            Text("\(Int(take.duration) / 60):\(String(format: "%02d", Int(take.duration) % 60)) · \(take.recordedAt.formatted(.relative(presentation: .numeric)))")
                .font(.otCaption)
                .foregroundStyle(OT.labelTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Long-press to circle this take")
    }
}
