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
    @State private var showRolePicker = false
    @State private var hasPromptedForRole = false
    @AppStorage("prompter.size") private var prompterSize = 1
    @AppStorage("prompter.mirror") private var mirrorPrompter = false

    private func detectedCharacters(in audition: Audition) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for scene in audition.scenes {
            for line in scene.lines {
                let name = line.character.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                if counts[name] == nil { order.append(name) }
                counts[name, default: 0] += 1
            }
        }
        return order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    static func shouldPromptRoleSelection(audition: Audition, scene: ScriptScene) -> Bool {
        let characters = audition.scenes.flatMap(\.lines)
            .map { $0.character.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !characters.isEmpty else { return false }
        let trimmedRole = audition.role.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRole.isEmpty || trimmedRole.caseInsensitiveCompare("Role") == .orderedSame {
            return true
        }
        return !scene.lines.contains(where: \.isMine)
    }

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
                        let characters = detectedCharacters(in: a)
                        if !characters.isEmpty {
                            Button {
                                showRolePicker = true
                                Haptics.tick()
                            } label: {
                                HStack(spacing: OTSpace.xs) {
                                    Image(systemName: "person.fill")
                                        .font(.otCaption)
                                    Text(scene.lines.contains(where: \.isMine) ? "Role: \(a.role)" : "Select your role")
                                        .font(.otCaption.weight(.semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.otCaption)
                                }
                                .foregroundStyle(scene.lines.contains(where: \.isMine) ? OT.accent : OT.due)
                                .padding(.horizontal, OTSpace.m)
                                .padding(.vertical, OTSpace.xs)
                                .background(scene.lines.contains(where: \.isMine) ? OT.accentSoft : OT.dueTrack, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
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
            .sheet(isPresented: $showRolePicker) {
                roleSelectionSheet(for: a)
                    .presentationDetents([.medium])
            }
            .onAppear {
                guard !hasPromptedForRole else { return }
                hasPromptedForRole = true
                if Self.shouldPromptRoleSelection(audition: a, scene: scene) {
                    showRolePicker = true
                }
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

    @ViewBuilder
    private func roleSelectionSheet(for a: Audition) -> some View {
        let characters = detectedCharacters(in: a)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    Text("Choose the character you’re playing so your lines highlight and reader cues play in your pauses.")
                        .font(.otCallout)
                        .foregroundStyle(OT.labelSecondary)

                    ForEach(characters, id: \.self) { character in
                        let lineCount = a.scenes.flatMap(\.lines).filter {
                            $0.character.caseInsensitiveCompare(character) == .orderedSame
                        }.count
                        let isSelected = character.caseInsensitiveCompare(a.role) == .orderedSame
                        Button {
                            store.updateRole(character, for: a.id)
                            Haptics.success()
                            showRolePicker = false
                        } label: {
                            HStack(spacing: OTSpace.m) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "person.circle")
                                    .font(.otIcon(.m))
                                    .foregroundStyle(isSelected ? OT.accent : OT.labelSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character)
                                        .font(.otHeadline)
                                        .foregroundStyle(OT.labelPrimary)
                                    Text("\(lineCount) \(lineCount == 1 ? "line" : "lines") in sides")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                            }
                            .padding(OTSpace.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .otCard(.grouped, padding: nil)
                        }
                        .buttonStyle(OTPressStyle(.card))
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .padding(.bottom, OTSpace.xl)
            }
            .otCanvas()
            .navigationTitle("Select your role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRolePicker = false }
                }
            }
        }
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
