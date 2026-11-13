import SwiftUI
import OneTakeUI

// MARK: - 11 Prepare

struct PrepareView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case full = "Full lines"
        case firstLetters = "First letters"
        case hide = "Hide mine"
        var id: String { rawValue }
    }

    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .full
    @State private var peeked: ScriptLine.ID?
    @State private var showPrompterSettings = false
    @State private var showSides = false
    @AppStorage("prompter.size") private var prompterSize = 1
    @AppStorage("prompter.mirror") private var mirrorPrompter = false

    var body: some View {
        let _ = store.readerTrackVersion
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let scene = a.scenes[sceneIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    Text(scene.title).font(.otLargeTitle)

                    Picker("Lines", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Spacer()
                        HStack(spacing: OTSpace.s) {
                            Button {
                                store.push(.sceneAudioFlow(a.id, sceneIndex: sceneIndex))
                            } label: {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 14, weight: .semibold)) // ot-lint:allow
                                    .foregroundStyle(OT.accent)
                                    .frame(width: 32, height: 32) // ot-lint:allow
                                    .background(OT.accentSoft, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Scene audio flow")

                            let readerLines = scene.lines.filter { !$0.isMine }
                            let readerName = readerLines.first?.character.capitalized ?? "Reader"
                            let specificReaderLines = readerLines.filter { $0.character.caseInsensitiveCompare(readerName) == .orderedSame }
                            if !specificReaderLines.isEmpty {
                                Button {
                                    store.push(.reader(a.id, sceneIndex: sceneIndex))
                                } label: {
                                    let recorded = specificReaderLines.indices.filter {
                                        ReaderTrackPlayer.hasRecording(auditionID: a.id, sceneIndex: sceneIndex, line: $0)
                                    }.count
                                    HStack(spacing: OTSpace.xs) {
                                        Image(systemName: recorded == specificReaderLines.count ? "waveform" : "mic")
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("Reader audio").font(.otFootnote.weight(.semibold))
                                            Text("\(recorded) of \(specificReaderLines.count) cues recorded")
                                                .font(.otCaption).foregroundStyle(OT.labelSecondary)
                                        }
                                    }
                                    .foregroundStyle(OT.reader)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let notes = a.castingNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: "person.text.rectangle")
                                    .font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                                    .foregroundStyle(OT.accent)
                                Text("Casting & Character Notes")
                                    .font(.otCaption.weight(.bold))
                                    .foregroundStyle(OT.labelSecondary)
                                    .textCase(.uppercase)
                            }
                            Text(notes)
                                .font(.otCallout)
                                .foregroundStyle(OT.labelPrimary)
                        }
                        .padding(OTSpace.cardInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .otCard(.grouped)
                    }

                    if let myNotes = a.actorNotes, !myNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .semibold)) // ot-lint:allow
                                    .foregroundStyle(OT.warning)
                                Text("My Intent & Choices")
                                    .font(.otCaption.weight(.bold))
                                    .foregroundStyle(OT.labelSecondary)
                                    .textCase(.uppercase)
                            }
                            Text(myNotes)
                                .font(.otCallout)
                                .foregroundStyle(OT.labelPrimary)
                        }
                        .padding(OTSpace.cardInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .otCard(.grouped)
                        .overlay(
                            RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                                .strokeBorder(OT.warning.opacity(0.35), lineWidth: 1)
                        )
                    }

                    ForEach(scene.lines) { line in
                        lineView(line)
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .padding(.bottom, OTSpace.xl)
            }
            .otCanvas()
            .navigationTitle("Scene \(scene.number) of \(a.scenes.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPrompterSettings = true
                    } label: {
                        Label("Text size", systemImage: "textformat.size")
                    }
                }
            }
            .otBottomBar {
                HStack(spacing: OTSpace.m) {
                    Button {
                        store.push(.practiceOptions(a.id, sceneIndex: sceneIndex))
                    } label: {
                        Label("Practice", systemImage: "play.fill").labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(.otSecondary)

                    Button {
                        store.push(.shootSetup(a.id, scene: sceneIndex))
                    } label: {
                        Label("Record", systemImage: "record.circle").labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(.otPrimary)
                }
            }
            .sheet(isPresented: $showPrompterSettings) {
                PrompterSettingsSheet().presentationDetents([.medium])
            }
        } else {
            // No scenes were read from what was added — say so and offer the fix instead of a blank page.
            ContentUnavailableView {
                Label("No sides yet", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("OneTake couldn’t find any character lines in what was added. Paste, import or scan the pages and it will split them into scenes. Cues work as NAME on its own line, or “Maya: line”.")
            } actions: {
                Button("Add sides") {
                    showSides = true
                }
                .buttonStyle(.ot(.primary, size: .medium, fullWidth: false))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .otCanvas()
            .navigationTitle("Sides")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSides) {
                RevisedSidesSheet(auditionID: auditionID)
            }
        }
    }

    @ViewBuilder private func lineView(_ line: ScriptLine) -> some View {
        let textSize = [19, 25, 32][min(max(prompterSize, 0), 2)]
        VStack(alignment: .leading, spacing: OTSpace.xxs) {
            Text(line.isMine ? "\(line.character) · YOU" : line.character)
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(line.isMine ? OT.accent : OT.reader)
            HStack(alignment: .top, spacing: OTSpace.s) {
                if line.isMine {
                    Capsule().fill(OT.accent).frame(width: 3) // ot-lint:allow
                }
                if line.isSilentReactionCue {
                    SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: false)
                } else {
                    Text(display(line))
                        .font(line.isMine ? .system(size: CGFloat(textSize), weight: .semibold) : .system(size: CGFloat(textSize - 2))) // ot-lint:allow
                        .foregroundStyle(line.isMine ? OT.labelPrimary : OT.labelSecondary)
                        .scaleEffect(x: mirrorPrompter ? -1 : 1, y: 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            if line.isMine && mode != .full {
                                peeked = peeked == line.id ? nil : line.id
                                Haptics.tick()
                            }
                        }
                }
            }
        }
        .padding(.vertical, OTSpace.xxs)
    }

    /// Same transform Practice's First-Letter / Mask & Reveal drills use — implemented once, in `otLineDisplay`.
    private func display(_ line: ScriptLine) -> String {
        let shared: LineDisplayMode = switch mode {
        case .full: .full
        case .hide: .hide
        case .firstLetters: .firstLetters
        }
        return otLineDisplay(line, mode: shared, peeked: peeked == line.id)
    }
}

struct DotLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: OTSpace.xxs) {
            Circle().fill(color).frame(width: 8, height: 8) // ot-lint:allow
            configuration.title
        }
    }
}
