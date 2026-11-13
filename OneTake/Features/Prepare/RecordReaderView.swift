import SwiftUI
import OneTakeUI

// MARK: - 13 Record the reader yourself

struct RecordReaderView: View {
    let auditionID: Audition.ID
    let sceneIndex: Int
    var initialLineIndex: Int? = nil
    var readerCharacter: String? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lineIndex = 0
    @State private var recording = false
    @State private var isProcessing = false
    @State private var microphoneAllowed = false
    @State private var recordingError: String?
    @State private var successBanner: String?
    @State private var recorder = ReaderLineRecorder()
    @State private var player = ReaderTrackPlayer()
    @State private var isPreviewPlaying = false
    @State private var playingReviewIndex: Int?
    @State private var expandedReviewIndex: Int?
    @State private var selectedReader: String? = nil
    @State private var showFullScript = false
    @State private var showAudioTrimmer = false
    @State private var trimTargetLineIndex: Int?
    @State private var restoreTargetLineIndex: Int?
    @State private var showRestoreOriginalConfirmation = false

    var body: some View {
        if let a = store.audition(auditionID), a.scenes.indices.contains(sceneIndex) {
            let allUnowned = a.scenes[sceneIndex].lines.filter { !$0.isMine }
            let availableReaders: [String] = {
                var seen = Set<String>()
                var list: [String] = []
                for line in allUnowned {
                    let name = line.character.capitalized
                    if !seen.contains(name.lowercased()) {
                        seen.insert(name.lowercased())
                        list.append(name)
                    }
                }
                return list
            }()
            let readerName: String = {
                if let sel = selectedReader, availableReaders.contains(where: { $0.caseInsensitiveCompare(sel) == .orderedSame }) {
                    return sel.capitalized
                }
                if let rc = readerCharacter, availableReaders.contains(where: { $0.caseInsensitiveCompare(rc) == .orderedSame }) {
                    return rc.capitalized
                }
                return allUnowned.first?.character.capitalized ?? "Reader"
            }()
            let readerLines = allUnowned.filter { $0.character.caseInsensitiveCompare(readerName) == .orderedSame }
            let readerTrackVersion = store.readerTrackVersion

            ScrollView {
                VStack(alignment: .leading, spacing: OTSpace.l) {
                    if availableReaders.count > 1 {
                        readerPicker(availableReaders: availableReaders, readerName: readerName)
                    }

                // Interactive Progress & Line Selector
                HStack(spacing: OTSpace.xxs) {
                    ForEach(readerLines.indices, id: \.self) { i in
                        let isRec = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: i)
                        Button {
                            guard !recording && !isProcessing else { return }
                            player.stop()
                            isPreviewPlaying = false
                            playingReviewIndex = nil
                            lineIndex = i
                            recordingError = nil
                            Haptics.tick()
                        } label: {
                            Capsule()
                                .fill(i == lineIndex ? OT.accent : (isRec ? OT.reader : OT.fillQuiet))
                                .frame(height: i == lineIndex ? 6 : 4) // ot-lint:allow
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Line \(i + 1)")
                    }
                }

                // Prev / Next Line Stepper
                HStack {
                    Button {
                        guard lineIndex > 0, !recording, !isProcessing else { return }
                        player.stop()
                        isPreviewPlaying = false
                        playingReviewIndex = nil
                        lineIndex -= 1
                        recordingError = nil
                        Haptics.tick()
                    } label: {
                        HStack(spacing: OTSpace.xxs) {
                            Image(systemName: "chevron.left")
                            Text("Prev line")
                        }
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(lineIndex > 0 ? OT.accent : OT.labelTertiary.opacity(0.4))
                    }
                    .disabled(lineIndex <= 0 || recording || isProcessing)

                    Spacer()

                    if lineIndex < readerLines.count {
                        Text("Line \(lineIndex + 1) of \(readerLines.count)")
                            .font(.otFootnote.weight(.medium))
                            .foregroundStyle(OT.labelSecondary)
                    } else {
                        Text("Reviewing all \(readerLines.count) lines")
                            .font(.otFootnote.weight(.medium))
                            .foregroundStyle(OT.reader)
                    }

                    Spacer()

                    Button {
                        guard !recording, !isProcessing else { return }
                        player.stop()
                        isPreviewPlaying = false
                        playingReviewIndex = nil
                        if lineIndex < readerLines.count {
                            lineIndex += 1
                        }
                        recordingError = nil
                        Haptics.tick()
                    } label: {
                        HStack(spacing: OTSpace.xxs) {
                            Text(lineIndex < readerLines.count - 1 ? "Next line" : (lineIndex == readerLines.count - 1 ? "Review" : ""))
                            if lineIndex < readerLines.count {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(lineIndex < readerLines.count ? OT.accent : Color.clear)
                    }
                    .disabled(lineIndex >= readerLines.count || recording || isProcessing)
                }

                let allSceneLines = a.scenes[sceneIndex].lines

                // View Mode: Focused Cue (with preceding actor context) vs Full Scene Script
                HStack(spacing: OTSpace.s) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showFullScript = false }
                    } label: {
                        HStack(spacing: OTSpace.xxs) {
                            Image(systemName: "quote.bubble")
                            Text("Cue focus")
                        }
                        .font(.otCaption.weight(!showFullScript ? .bold : .medium))
                        .foregroundStyle(!showFullScript ? OT.bgCanvas : OT.labelSecondary)
                        .padding(.horizontal, OTSpace.s)
                        .padding(.vertical, OTSpace.xxs)
                        .background(!showFullScript ? AnyShapeStyle(OT.accent) : AnyShapeStyle(OT.fillField), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showFullScript = true }
                    } label: {
                        HStack(spacing: OTSpace.xxs) {
                            Image(systemName: "text.alignleft")
                            Text("All \(allSceneLines.count) lines")
                        }
                        .font(.otCaption.weight(showFullScript ? .bold : .medium))
                        .foregroundStyle(showFullScript ? OT.bgCanvas : OT.labelSecondary)
                        .padding(.horizontal, OTSpace.s)
                        .padding(.vertical, OTSpace.xxs)
                        .background(showFullScript ? AnyShapeStyle(OT.accent) : AnyShapeStyle(OT.fillField), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                if showFullScript {
                    // Full Scene Script: Every line is visible with active line highlighted
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            ForEach(allSceneLines) { sLine in
                                let matchedReaderIdx = readerLines.firstIndex(where: { $0.id == sLine.id })
                                let isCurrentActive = matchedReaderIdx == lineIndex

                                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                    HStack(spacing: OTSpace.xs) {
                                        Text(sLine.isMine ? "\(sLine.character.uppercased()) (YOU)" : sLine.character.uppercased())
                                            .font(.otCaption.weight(.bold))
                                            .foregroundStyle(sLine.isMine ? OT.accent : OT.reader)

                                        if isCurrentActive {
                                            Text("RECORDING CUE")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced)) // ot-lint:allow
                                                .foregroundStyle(OT.bgCanvas)
                                                .padding(.horizontal, 6) // ot-lint:allow
                                                .padding(.vertical, OTSpace.xxs)
                                                .background(OT.reader, in: Capsule())
                                        }

                                        Spacer()

                                        if let rIdx = matchedReaderIdx {
                                            let hasRec = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: rIdx)
                                            if hasRec {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(OT.reader)
                                            }
                                        }
                                    }

                                    Text(sLine.text)
                                        .font(.otBody)
                                        .foregroundStyle(OT.labelPrimary)
                                }
                                .padding(OTSpace.cardInset)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .otCard(isCurrentActive ? .elevated : .grouped)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OTRadius.card)
                                        .stroke(isCurrentActive ? OT.reader : (sLine.isMine ? OT.accent.opacity(0.2) : Color.clear), lineWidth: 1.5)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let rIdx = matchedReaderIdx, !recording, !isProcessing {
                                        player.stop()
                                        isPreviewPlaying = false
                                        lineIndex = rIdx
                                        Haptics.tick()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, OTSpace.xxs)
                    }
                    .frame(maxHeight: 260) // ot-lint:allow
                }

                if lineIndex < readerLines.count {
                    let line = readerLines[lineIndex]
                    let isCurrentRecorded = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex)
                    let currentGlobalIdx = allSceneLines.firstIndex(where: { $0.id == line.id })
                    let prevCue: ScriptLine? = {
                        guard let idx = currentGlobalIdx, idx > 0 else { return nil }
                        return allSceneLines[idx - 1]
                    }()
                    let nextCue: ScriptLine? = {
                        guard let idx = currentGlobalIdx, idx + 1 < allSceneLines.count else { return nil }
                        return allSceneLines[idx + 1]
                    }()

                    if !showFullScript, let prev = prevCue {
                        // Preceding line context: what the reader is responding to
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            HStack(spacing: OTSpace.xxs) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 11, weight: .bold)) // ot-lint:allow
                                Text("CUE: \(prev.isMine ? "\(prev.character.uppercased()) (YOU)" : prev.character.uppercased())")
                                    .font(.otCaption.weight(.bold))
                            }
                            .foregroundStyle(prev.isMine ? OT.accent : OT.reader)

                            Text(prev.text)
                                .font(.otCallout)
                                .foregroundStyle(OT.labelSecondary)
                                .lineLimit(3)
                        }
                        .padding(OTSpace.cardInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .otCard(.grouped)
                        .overlay(RoundedRectangle(cornerRadius: OTRadius.l).stroke(OT.separator, lineWidth: 1))
                    }

                    HStack {
                        OTSectionLabel("\(readerName) · line \(lineIndex + 1)")
                        Spacer()
                        if line.isSilentReactionCue {
                            HStack(spacing: OTSpace.xxs) {
                                Image(systemName: "face.smiling")
                                Text("Silent beat · No audio needed")
                            }
                            .font(.otCaption.weight(.semibold))
                            .foregroundStyle(OT.reader)
                        } else if isCurrentRecorded {
                            HStack(spacing: OTSpace.xxs) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Recorded")
                            }
                            .font(.otCaption.weight(.semibold))
                            .foregroundStyle(OT.reader)
                        } else {
                            HStack(spacing: OTSpace.xxs) {
                                Image(systemName: "mic")
                                Text("Needs audio")
                            }
                            .font(.otCaption.weight(.medium))
                            .foregroundStyle(OT.labelTertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: OTSpace.m) {
                        if line.isSilentReactionCue {
                            SilentReactionCue(cueText: line.text, isMine: false, inPrompter: false)
                        } else {
                            Text(line.text)
                                .font(.system(size: 26, weight: .bold)) // ot-lint:allow
                                .lineSpacing(4)
                                .foregroundStyle(OT.labelPrimary)
                        }

                        if isCurrentRecorded && !line.isSilentReactionCue {
                            VStack(alignment: .leading, spacing: OTSpace.s) {
                                Text("Play & Scrub Recorded Audio")
                                    .font(.otCaption.weight(.semibold))
                                    .foregroundStyle(OT.labelSecondary)

                                ReaderAudioScrubberView(player: player, auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex, compact: false)

                                HStack(spacing: OTSpace.s) {
                                    Button {
                                        beginAudioTrim(lineIndex)
                                    } label: {
                                        Label("Trim audio", systemImage: "scissors")
                                            .font(.otFootnote.weight(.semibold))
                                    }
                                    .buttonStyle(.otGlass)

                                    if ReaderTrackPlayer.hasOriginal(auditionID: auditionID, sceneIndex: sceneIndex, line: lineIndex) {
                                        Button {
                                            requestOriginalRestore(lineIndex)
                                        } label: {
                                            Label("Restore original", systemImage: "arrow.uturn.backward")
                                                .font(.otFootnote.weight(.semibold))
                                        }
                                        .buttonStyle(.otGlass)
                                    }
                                }

                                Text("Tap Record below to retake this line")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelTertiary)
                            }
                            .padding(.top, OTSpace.xxs)
                        }
                    }
                    .padding(OTSpace.cardInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .otCard(.elevated)

                    if !showFullScript, let next = nextCue {
                        HStack(spacing: OTSpace.xs) {
                            Text("NEXT:")
                                .font(.otCaption.weight(.bold))
                                .foregroundStyle(next.isMine ? OT.accent : OT.reader)
                            Text("\(next.isMine ? "\(next.character.uppercased()) (YOU)" : next.character.uppercased()): \(next.text)")
                                .font(.otCaption)
                                .foregroundStyle(OT.labelTertiary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, OTSpace.xxs)
                    }

                    if let recordingError {
                        HStack(spacing: OTSpace.s) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(OT.warning)
                            Text(recordingError)
                                .font(.otFootnote)
                                .foregroundStyle(OT.warning)
                        }
                        .padding(OTSpace.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OT.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: OTRadius.m))
                    }

                    if let successBanner {
                        HStack(spacing: OTSpace.s) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OT.reader)
                            Text(successBanner)
                                .font(.otFootnote.weight(.medium))
                                .foregroundStyle(OT.reader)
                        }
                        .padding(OTSpace.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OT.reader.opacity(0.12), in: RoundedRectangle(cornerRadius: OTRadius.m))
                    }

                    Spacer()

                    if line.isSilentReactionCue {
                        Button {
                            if lineIndex + 1 < readerLines.count {
                                lineIndex += 1
                            } else {
                                lineIndex = readerLines.count
                            }
                            Haptics.tick()
                        } label: {
                            Text(lineIndex < readerLines.count - 1 ? "Continue to next line" : "Review reader cues")
                                .font(.otHeadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.otPrimary)
                        .padding(.top, OTSpace.s)
                    } else {
                        if recording {
                            VStack(spacing: OTSpace.s) {
                                HStack(spacing: OTSpace.xs) {
                                    Circle().fill(Color.red).frame(width: 8, height: 8) // ot-lint:allow
                                    Text("Listening... Say the line clearly")
                                        .font(.otFootnote.weight(.semibold))
                                        .foregroundStyle(OT.labelPrimary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(OT.fillField)
                                            .frame(height: 6) // ot-lint:allow
                                        Capsule()
                                            .fill(OT.accent)
                                            .frame(width: max(8, geo.size.width * CGFloat(recorder.liveAudioLevel)), height: 6) // ot-lint:allow
                                            .animation(.easeOut(duration: 0.08), value: recorder.liveAudioLevel)
                                    }
                                }
                                .frame(height: 6) // ot-lint:allow
                                .padding(.horizontal, OTSpace.xxl)
                                Text("Tap stop when finished")
                                    .font(.otCaption)
                                    .foregroundStyle(OT.labelTertiary)
                            }
                        } else if isProcessing {
                            HStack(spacing: OTSpace.s) {
                                ProgressView()
                                Text("Verifying speech...")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(isCurrentRecorded ? "Tap record to retake this line" : "Tap record when you're ready")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelTertiary)
                                .frame(maxWidth: .infinity)
                        }

                        RecordButton(isRecording: recording) {
                            handleRecordTap(readerLines: readerLines, isCurrentRecorded: isCurrentRecorded)
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(isProcessing)
                    }
                } else {
                    // All lines completed or Review Mode
                    VStack(alignment: .leading, spacing: OTSpace.m) {
                        Text("All \(readerLines.count) lines done")
                            .font(.otLargeTitle)
                        Text("Review your recorded cues below, or retake any line if needed.")
                            .font(.otCallout)
                            .foregroundStyle(OT.labelSecondary)

                        ScrollView {
                            VStack(spacing: OTSpace.s) {
                                ForEach(Array(readerLines.enumerated()), id: \.offset) { idx, line in
                                    let isRec = readerTrackVersion >= 0 && ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: idx)
                                    RecordReaderReviewRow(
                                        idx: idx,
                                        line: line,
                                        auditionID: auditionID,
                                        sceneIndex: sceneIndex,
                                        isRec: isRec,
                                        player: player,
                                        playingReviewIndex: $playingReviewIndex,
                                        expandedReviewIndex: $expandedReviewIndex,
                                        onRetake: {
                                            player.stop()
                                            isPreviewPlaying = false
                                            playingReviewIndex = nil
                                            lineIndex = idx
                                            recordingError = nil
                                            successBanner = nil
                                            Haptics.tick()
                                        },
                                        onTrim: {
                                            beginAudioTrim(idx)
                                        },
                                        onRestore: {
                                            requestOriginalRestore(idx)
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, OTSpace.xxs)
                        }

                        Spacer()

                        Button {
                            player.stop()
                            recorder.cancel()
                            store.push(.sceneAudioFlow(auditionID, sceneIndex: sceneIndex))
                        } label: {
                            HStack(spacing: OTSpace.s) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                Text("Rehearse in Scene Audio Flow")
                            }
                            .font(.otSubhead.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48) // ot-lint:allow
                            .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: OTRadius.l))
                        }
                        .buttonStyle(.plain)

                        Button("Save and finish") {
                            player.stop()
                            recorder.cancel()
                            store.pop()
                        }
                        .buttonStyle(.otPrimary)
                    }
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
            }
            .otCanvas()
            .navigationTitle("Record \(readerName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        player.stop()
                        recorder.cancel()
                        store.push(.sceneAudioFlow(auditionID, sceneIndex: sceneIndex))
                    } label: {
                        Label("Scene audio flow", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showAudioTrimmer) {
                if let trimTargetLineIndex {
                    let sourceURL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: trimTargetLineIndex)
                    ReaderAudioTrimmer(url: sourceURL) { editedURL in
                        guard let editedURL else { self.trimTargetLineIndex = nil; return }
                        do {
                            try ReaderTrackPlayer.installEditedRecording(editedURL, at: sourceURL)
                            player.stop()
                            store.readerTracksDidChange()
                            successBanner = "Trimmed audio saved. The original can be restored."
                            recordingError = nil
                        } catch {
                            recordingError = "Couldn’t save the trimmed audio. Your existing reader audio is unchanged."
                        }
                        self.trimTargetLineIndex = nil
                    }
                }
            }
            .confirmationDialog("Restore the original reader recording?", isPresented: $showRestoreOriginalConfirmation, titleVisibility: .visible) {
                Button("Restore original") { restoreOriginalRecording() }
                Button("Cancel", role: .cancel) { restoreTargetLineIndex = nil }
            } message: {
                Text("This replaces the trimmed version with the original recording.")
            }
            .task {
                microphoneAllowed = await SpeechFollower.requestAccess()
                if let audition = store.audition(auditionID), audition.scenes.indices.contains(sceneIndex) {
                    let scene = audition.scenes[sceneIndex]
                    let allUnowned = scene.lines.filter { !$0.isMine }
                    let available: [String] = {
                        var seen = Set<String>()
                        var list: [String] = []
                        for line in allUnowned {
                            let name = line.character.capitalized
                            if !seen.contains(name.lowercased()) {
                                seen.insert(name.lowercased())
                                list.append(name)
                            }
                        }
                        return list
                    }()
                    if let readerCharacter, available.contains(where: { $0.caseInsensitiveCompare(readerCharacter) == .orderedSame }) {
                        selectedReader = readerCharacter
                    }
                    let rName = selectedReader ?? readerCharacter ?? available.first ?? "Reader"
                    let rLines = allUnowned.filter { $0.character.caseInsensitiveCompare(rName) == .orderedSame }

                    if let initialLineIndex, rLines.indices.contains(initialLineIndex) {
                        lineIndex = initialLineIndex
                    } else {
                        // Open on the first unrecorded line; if all recorded, start on 0 so the user can review/retake
                        lineIndex = rLines.indices.first(where: {
                            !ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: sceneIndex, line: $0)
                        }) ?? 0
                    }
                }
            }
            .onDisappear {
                player.stop()
                recorder.cancel()
            }
        }
    }

    @ViewBuilder
    private func readerPicker(availableReaders: [String], readerName: String) -> some View {
        let selection = Binding(
            get: { readerName },
            set: { char in
                guard !recording && !isProcessing else { return }
                player.stop()
                isPreviewPlaying = false
                selectedReader = char
                lineIndex = 0
                recordingError = nil
                Haptics.tick()
            }
        )
        Group {
            if availableReaders.count <= 3 {
                Picker("Reader", selection: selection) {
                    ForEach(availableReaders, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Reader", selection: selection) {
                    ForEach(availableReaders, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
        .disabled(recording || isProcessing)
    }

    private func beginAudioTrim(_ line: Int) {
        player.stop()
        isPreviewPlaying = false
        playingReviewIndex = nil
        trimTargetLineIndex = line
        showAudioTrimmer = true
    }

    private func requestOriginalRestore(_ line: Int) {
        player.stop()
        isPreviewPlaying = false
        playingReviewIndex = nil
        restoreTargetLineIndex = line
        showRestoreOriginalConfirmation = true
    }

    private func restoreOriginalRecording() {
        guard let line = restoreTargetLineIndex else { return }
        let recordingURL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: sceneIndex, line: line)
        do {
            try ReaderTrackPlayer.restoreOriginalRecording(at: recordingURL)
            store.readerTracksDidChange()
            successBanner = "Original reader audio restored."
            recordingError = nil
        } catch {
            recordingError = "Couldn’t restore the original reader audio."
        }
        restoreTargetLineIndex = nil
    }

    private func handleRecordTap(readerLines: [ScriptLine], isCurrentRecorded: Bool) {
        if recording {
            recording = false
            isProcessing = true
            recordingError = nil
            let currentLineText = readerLines[lineIndex].text
            let recordedIndex = lineIndex

            Task {
                let result = await recorder.stop(expectedText: currentLineText)
                isProcessing = false
                switch result {
                case .success(let duration):
                    store.readerTracksDidChange()
                    Haptics.success()
                    let baseMsg = isCurrentRecorded ? "Retake saved for Line \(recordedIndex + 1)" : "Line \(recordedIndex + 1) recorded"
                    if let issue = recorder.lastAudioIssues.first {
                        successBanner = "\(baseMsg) (\(String(format: "%.1f", duration))s) · \(issue.rawValue)"
                    } else {
                        successBanner = "\(baseMsg) (\(String(format: "%.1f", duration))s)"
                    }
                    recordingError = nil

                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if successBanner != nil { successBanner = nil }
                    }

                    if recordedIndex + 1 < readerLines.count {
                        lineIndex = recordedIndex + 1
                    } else {
                        lineIndex = readerLines.count // Go to Review mode
                    }

                case .tooShort(let duration):
                    Haptics.warning()
                    recordingError = "No speech detected (recording was blank, only \(String(format: "%.1f", duration))s). Please speak your line clearly before tapping stop."

                case .noSpeechDetected:
                    Haptics.warning()
                    recordingError = "No speech detected. The microphone didn't pick up audio. Please check your microphone or speak louder."

                case .recordingFailed(let message):
                    Haptics.warning()
                    recordingError = message
                }
            }
        } else if !microphoneAllowed {
            recordingError = "Allow microphone access in Settings to record reader lines."
            Haptics.warning()
        } else {
            player.stop()
            isPreviewPlaying = false
            recordingError = nil
            successBanner = nil
            if recorder.start(auditionID: auditionID, sceneIndex: sceneIndex, lineIndex: lineIndex) {
                recording = true
                Haptics.impact(.heavy)
            } else {
                recordingError = "Recording couldn't start. Check microphone access and try again."
                Haptics.warning()
            }
        }
    }
}
