import SwiftUI
import OneTakeUI
import UniformTypeIdentifiers

// MARK: - 12 Reader

struct ReaderView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var player = ReaderTrackPlayer()
    @State private var playingLine: Int?
    @State private var expandedLine: Int?
    @State private var showAudioImporter = false
    @State private var importError: String?
    @AppStorage("readerVolume") private var volume = "Quieter"
    @State private var selectedReader: String? = nil
    @State private var showFullScript = false

    private var myRole: String {
        store.audition(auditionID)?.role ?? ""
    }

    private var availableReaders: [String] {
        guard let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return [] }
        let unowned = scenes[sceneIndex].lines.filter { !$0.isMine }
        var seen = Set<String>()
        var list: [String] = []
        for line in unowned {
            let name = line.character.capitalized
            if !seen.contains(name.lowercased()) {
                seen.insert(name.lowercased())
                list.append(name)
            }
        }
        return list
    }

    private var effectiveReaderName: String {
        if let selected = selectedReader, availableReaders.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            return selected.capitalized
        }
        return availableReaders.first?.capitalized ?? "your reader"
    }

    private var readerLines: [ScriptLine] {
        guard let scenes = store.audition(auditionID)?.scenes, scenes.indices.contains(sceneIndex) else { return [] }
        let allLines = scenes[sceneIndex].lines
        let unowned = allLines.filter { !$0.isMine }
        let target = effectiveReaderName
        return unowned.filter { $0.character.caseInsensitiveCompare(target) == .orderedSame }
    }

    var body: some View {
        // Reader recordings are files, so this observable counter makes the file status update
        // as soon as Record Reader saves a line.
        let readerTrackVersion = store.readerTrackVersion
        OTScreen(title: "Who reads \(effectiveReaderName)?", backLabel: "Back", onBack: { store.pop() }, scrolls: false) {
            List {
                Section {
                    Text("Record \(effectiveReaderName)’s lines in your own voice. We leave the pauses for yours, and it plays under your takes.")
                        .font(.otCallout)
                        .foregroundStyle(OT.labelSecondary)
                }
                .listRowBackground(Color.clear)

                if availableReaders.count > 1 {
                    Section {
                        HStack(spacing: OTSpace.s) {
                            Text("Reader:")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelTertiary)
                            ForEach(availableReaders, id: \.self) { char in
                                let isCurrent = char.caseInsensitiveCompare(effectiveReaderName) == .orderedSame
                                Button {
                                    selectedReader = char
                                    player.stop()
                                    playingLine = nil
                                    Haptics.tick()
                                } label: {
                                    Text(char)
                                        .font(.otCaption.weight(isCurrent ? .bold : .medium))
                                        .foregroundStyle(isCurrent ? OT.bgCanvas : OT.reader)
                                        .padding(.horizontal, OTSpace.s)
                                        .padding(.vertical, OTSpace.xxs)
                                        .background(isCurrent ? AnyShapeStyle(OT.reader) : AnyShapeStyle(OT.fillField), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // Scene Audio Flow Shortcut
                Section {
                    Button {
                        player.stop()
                        playingLine = nil
                        store.push(.sceneAudioFlow(auditionID, sceneIndex: sceneIndex))
                    } label: {
                        HStack(spacing: OTSpace.m) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.system(size: 20, weight: .semibold)) // ot-lint:allow
                                .foregroundStyle(OT.accent)
                                .frame(width: 40, height: 40) // ot-lint:allow
                                .background(OT.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scene Audio Flow & Walkthrough")
                                    .font(.otSubhead.weight(.semibold))
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Play from any line in the scene · Scrub between seconds")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(OT.labelTertiary)
                        }
                        .padding(OTSpace.cardInset)
                        .otCard(.grouped)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)

                Section("\(effectiveReaderName)’s reader tracks") {
                    if readerLines.isEmpty {
                        Text("No reader lines for \(effectiveReaderName) in this scene.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                    } else {
                        ForEach(Array(readerLines.enumerated()), id: \.offset) { index, line in
                            let isSilent = line.isSilentReactionCue
                            let recorded = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: index)
                            VStack(alignment: .leading, spacing: OTSpace.s) {
                                HStack(spacing: OTSpace.m) {
                                    Button {
                                        if recorded {
                                            if playingLine == index && player.isPlaying {
                                                player.pause()
                                            } else if playingLine == index && !player.isPlaying {
                                                player.resume()
                                            } else {
                                                player.play(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: index)
                                                playingLine = index
                                                expandedLine = index
                                            }
                                        }
                                    } label: {
                                        Image(systemName: isSilent ? "face.smiling" : (recorded ? (playingLine == index && player.isPlaying ? "pause.fill" : "play.fill") : "mic.slash"))
                                            .foregroundStyle(isSilent ? OT.accent : (recorded ? OT.labelPrimary : OT.labelTertiary))
                                            .frame(width: 36, height: 36) // ot-lint:allow
                                            .background(OT.accentSoft, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!recorded || isSilent)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Line \(index + 1)").font(.otBody)
                                        Text(isSilent ? "Silent reaction beat [ \(line.text) ] · No audio needed" : (recorded ? "Recorded · \"\(line.text.prefix(40))\"" : "Not recorded yet"))
                                            .font(.otFootnote)
                                            .foregroundStyle(OT.labelTertiary)
                                    }
                                    Spacer()

                                    if recorded {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                if expandedLine == index {
                                                    expandedLine = nil
                                                } else {
                                                    expandedLine = index
                                                }
                                            }
                                        } label: {
                                            Image(systemName: expandedLine == index ? "chevron.up.circle.fill" : "slider.horizontal.3")
                                                .font(.system(size: 16, weight: .semibold)) // ot-lint:allow
                                                .foregroundStyle(expandedLine == index ? OT.accent : OT.labelTertiary)
                                                .frame(width: 32, height: 32) // ot-lint:allow
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(expandedLine == index ? "Hide audio scrubber" : "Scrub audio")
                                    }

                                    Button {
                                        player.stop()
                                        playingLine = nil
                                        store.push(.recordReader(auditionID, sceneIndex: sceneIndex, initialLineIndex: index, readerCharacter: effectiveReaderName))
                                    } label: {
                                        HStack(spacing: OTSpace.xxs) {
                                            Image(systemName: recorded ? "arrow.clockwise" : "mic.fill")
                                            Text(recorded ? "Retake" : "Record")
                                        }
                                        .font(.otCaption.weight(.semibold))
                                        .foregroundStyle(recorded ? OT.accent : OT.reader)
                                        .padding(.horizontal, OTSpace.s)
                                        .padding(.vertical, OTSpace.xxs)
                                        .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if recorded {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if expandedLine == index {
                                                expandedLine = nil
                                            } else {
                                                expandedLine = index
                                            }
                                        }
                                    }
                                }

                                if recorded && (expandedLine == index || playingLine == index) {
                                    ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: index, compact: false)
                                        .padding(.top, OTSpace.xxs)
                                }
                            }
                        }
                    }
                    Picker("\(effectiveReaderName)’s volume on the tape", selection: $volume) {
                        ForEach(["Same as me", "Quieter", "Much quieter"], id: \.self) { Text($0) }
                    }
                }

                Section {
                    Button {
                        store.push(.recordReader(auditionID, sceneIndex: sceneIndex, readerCharacter: effectiveReaderName))
                    } label: {
                        OTIconRow(symbol: "mic", title: "Record reader audio", detail: "Record each cue in your own voice")
                    }
                    .buttonStyle(.plain)

                    Button {
                        showAudioImporter = true
                    } label: {
                        OTIconRow(symbol: "waveform.badge.plus", title: "Add an audio file", detail: "Uses the next reader cue that is not recorded")
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .otBottomBar {
            Button("Continue") {
                if store.auditionsPath.contains(.noticeReview) {
                    store.auditionsPath = [.auditionDetail(auditionID)]
                    store.continueAfterAdd = auditionID
                    store.auditionDraft = .blank
                } else {
                    store.pop()
                }
            }
            .buttonStyle(.otPrimary)
        }
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
            importReaderAudio(result)
        }
        .alert("Audio could not be added", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "")
        }
        .onDisappear { player.stop() }
    }

    private func importReaderAudio(_ result: Result<URL, Error>) {
        guard case .success(let sourceURL) = result else {
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                importError = error.localizedDescription
            }
            return
        }
        guard let nextLine = readerLines.indices.first(where: {
            !ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: $0)
        }) else {
            importError = "Every reader cue already has audio. Delete or re-record one to replace it."
            return
        }
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let destination = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: nextLine)
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.removeItem(at: destination)
            try manager.copyItem(at: sourceURL, to: destination)
            store.readerTracksDidChange()
            Haptics.success()
        } catch {
            importError = error.localizedDescription
        }
    }
}
