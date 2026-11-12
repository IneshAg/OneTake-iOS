import Foundation

// MARK: - Sides Change Summary & Diff Intelligence

struct SidesChangeSummary {
    struct SceneDiff: Identifiable {
        var id: Int { newIndex }
        let newIndex: Int
        let sceneTitle: String
        let oldIndex: Int?
        let isReordered: Bool
        let unchangedLinesCount: Int
        let revisedLinesCount: Int
        let readerCuesPreservedCount: Int
        let readerCuesNeedRecordingCount: Int
    }

    let sceneDiffs: [SceneDiff]
    let totalUnchangedReaderCues: Int
    let totalNewOrRevisedReaderCues: Int
    let previousTakesCount: Int
    let readerLineMapping: [String: String]
}

extension AppStore {
    /// Compares existing sides against proposed new sides, identifying which scenes were reordered,
    /// which lines are unchanged vs revised, which reader recordings can be migrated, and how many takes will be preserved.
    func compareSides(of id: Audition.ID, with newScenes: [ScriptScene]) -> SidesChangeSummary? {
        guard let audition = audition(id), !audition.scenes.isEmpty else { return nil }
        let oldScenes = audition.scenes
        var sceneDiffs: [SidesChangeSummary.SceneDiff] = []
        var readerMapping: [String: String] = [:]
        var usedOldLines = Set<String>()

        var totalPreserved = 0
        var totalNeedRecording = 0

        for (newIdx, newScene) in newScenes.enumerated() {
            let matchedOldIdx = oldScenes.firstIndex(where: {
                $0.title.lowercased() == newScene.title.lowercased() ||
                $0.heading.lowercased() == newScene.heading.lowercased() ||
                $0.number == newScene.number
            })
            let isReordered = matchedOldIdx != nil && matchedOldIdx != newIdx

            var unchangedLines = 0
            var revisedLines = 0
            var scenePreservedReader = 0
            var sceneNeedRecordingReader = 0

            for (newLineIdx, newLine) in newScene.lines.enumerated() {
                let normNewText = ScriptParser.normalizeDialogue(newLine.text)
                let normNewChar = newLine.character.trimmingCharacters(in: .whitespaces).lowercased()

                var matchedOldCoord: (Int, Int)? = nil

                // Priority 1: Check matched scene first
                if let oldIdx = matchedOldIdx {
                    let oldScene = oldScenes[oldIdx]
                    for (oldLineIdx, oldLine) in oldScene.lines.enumerated() {
                        let coordKey = "\(oldIdx):\(oldLineIdx)"
                        guard !usedOldLines.contains(coordKey) else { continue }
                        let normOldText = ScriptParser.normalizeDialogue(oldLine.text)
                        let normOldChar = oldLine.character.trimmingCharacters(in: .whitespaces).lowercased()
                        if normOldChar == normNewChar && normOldText == normNewText {
                            matchedOldCoord = (oldIdx, oldLineIdx)
                            usedOldLines.insert(coordKey)
                            break
                        }
                    }
                }

                // Priority 2: Search across all old scenes if not in matched scene
                if matchedOldCoord == nil {
                    for (oldIdx, oldScene) in oldScenes.enumerated() {
                        for (oldLineIdx, oldLine) in oldScene.lines.enumerated() {
                            let coordKey = "\(oldIdx):\(oldLineIdx)"
                            guard !usedOldLines.contains(coordKey) else { continue }
                            let normOldText = ScriptParser.normalizeDialogue(oldLine.text)
                            let normOldChar = oldLine.character.trimmingCharacters(in: .whitespaces).lowercased()
                            if normOldChar == normNewChar && normOldText == normNewText {
                                matchedOldCoord = (oldIdx, oldLineIdx)
                                usedOldLines.insert(coordKey)
                                break
                            }
                        }
                        if matchedOldCoord != nil { break }
                    }
                }

                if let matchedOld = matchedOldCoord {
                    unchangedLines += 1
                    if !newLine.isMine {
                        let newReaderIdx = newScene.lines[..<newLineIdx].filter { !$0.isMine }.count
                        let oldReaderIdx = oldScenes[matchedOld.0].lines[..<matchedOld.1].filter { !$0.isMine }.count
                        if ReaderTrackPlayer.hasRecording(auditionID: id, sceneIndex: matchedOld.0, line: oldReaderIdx) {
                            readerMapping["\(newIdx):\(newReaderIdx)"] = "\(matchedOld.0):\(oldReaderIdx)"
                            scenePreservedReader += 1
                            totalPreserved += 1
                        } else {
                            sceneNeedRecordingReader += 1
                            totalNeedRecording += 1
                        }
                    }
                } else {
                    revisedLines += 1
                    if !newLine.isMine {
                        sceneNeedRecordingReader += 1
                        totalNeedRecording += 1
                    }
                }
            }

            sceneDiffs.append(SidesChangeSummary.SceneDiff(
                newIndex: newIdx,
                sceneTitle: newScene.title.isEmpty ? "Scene \(newScene.number)" : newScene.title,
                oldIndex: matchedOldIdx,
                isReordered: isReordered,
                unchangedLinesCount: unchangedLines,
                revisedLinesCount: revisedLines,
                readerCuesPreservedCount: scenePreservedReader,
                readerCuesNeedRecordingCount: sceneNeedRecordingReader
            ))
        }

        let existingTakesCount = takes.filter { $0.auditionID == id && !$0.previousSides }.count

        return SidesChangeSummary(
            sceneDiffs: sceneDiffs,
            totalUnchangedReaderCues: totalPreserved,
            totalNewOrRevisedReaderCues: totalNeedRecording,
            previousTakesCount: existingTakesCount,
            readerLineMapping: readerMapping
        )
    }

    /// Revised sides: swaps in the new scenes and resets the scene pieces (the old takes stay, but the
    /// new pages need shooting). Intelligently reuses reader audio for unchanged lines, and keeps
    /// earlier takes playable under "Previous sides".
    func replaceSides(of id: Audition.ID, with scenes: [ScriptScene], sourceText: String? = nil) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        let hadScenes = !auditions[i].scenes.isEmpty
        let oldScenes = auditions[i].scenes

        // 1. Calculate diff and reader mapping before mutating
        let diff = compareSides(of: id, with: scenes)

        // 2. Intelligent Reader Audio Migration
        if hadScenes, let diff = diff, !diff.readerLineMapping.isEmpty {
            let fm = FileManager.default
            let readerDir = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)", isDirectory: true)
            if fm.fileExists(atPath: readerDir.path) {
                let tempDir = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)_staging_\(UUID().uuidString)", isDirectory: true)
                // Move current folder to temp
                try? fm.moveItem(at: readerDir, to: tempDir)
                try? fm.createDirectory(at: readerDir, withIntermediateDirectories: true)

                // Copy over preserved cues to their new locations
                for (newKey, oldKey) in diff.readerLineMapping {
                    let newParts = newKey.split(separator: ":").compactMap { Int($0) }
                    let oldParts = oldKey.split(separator: ":").compactMap { Int($0) }
                    guard newParts.count == 2, oldParts.count == 2 else { continue }
                    let newScene = newParts[0]
                    let newLine = newParts[1]
                    let oldScene = oldParts[0]
                    let oldLine = oldParts[1]

                    let oldAudioURL = tempDir.appendingPathComponent("scene-\(oldScene)/line-\(oldLine).m4a")
                    let newAudioURL = ReaderTrackPlayer.url(auditionID: id, sceneIndex: newScene, line: newLine)

                    if fm.fileExists(atPath: oldAudioURL.path) {
                        try? fm.createDirectory(at: newAudioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? fm.copyItem(at: oldAudioURL, to: newAudioURL)

                        let oldOrigURL = ReaderTrackPlayer.originalURL(for: oldAudioURL)
                        let newOrigURL = ReaderTrackPlayer.originalURL(for: newAudioURL)
                        if fm.fileExists(atPath: oldOrigURL.path) {
                            try? fm.copyItem(at: oldOrigURL, to: newOrigURL)
                        }
                    }
                }

                // Archive the temp folder into previous_sides so no recordings are ever destroyed
                let archiveDir = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)/previous_sides_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
                try? fm.moveItem(at: tempDir, to: archiveDir)
                readerTrackVersion += 1
            }
        } else if hadScenes {
            // If all lines changed, move old reader tracks to previous_sides archive
            let fm = FileManager.default
            let readerDir = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)", isDirectory: true)
            if fm.fileExists(atPath: readerDir.path) {
                let archiveDir = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)/previous_sides_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
                try? fm.moveItem(at: readerDir, to: archiveDir)
                try? fm.createDirectory(at: readerDir, withIntermediateDirectories: true)
                readerTrackVersion += 1
            }
        }

        if hadScenes {
            auditions[i].sidesRevision = (auditions[i].sidesRevision ?? 0) + 1
        }
        auditions[i].scenes = scenes
        auditions[i].scriptText = sourceText
        if auditions[i].castingNotes == nil, let sourceText {
            auditions[i].castingNotes = NoticeParser.extractCharacterDescription(for: auditions[i].role, in: sourceText)
        }
        auditions[i].pieces.removeAll { $0.kind == .scene }
        auditions[i].pieces += scenes.map {
            let isOpt = NoticeParser.isSceneOptional(scene: $0, in: sourceText ?? "")
            return Piece(kind: .scene, title: $0.title, detail: hadScenes ? "Revised sides" : "", isDone: false, isOptional: isOpt)
        }
        if auditions[i].status == .ready || auditions[i].status == .exported || auditions[i].status == .sent {
            auditions[i].status = .due
        }

        // Preserve earlier takes under "Previous sides"
        for index in takes.indices where takes[index].auditionID == id {
            takes[index].isCircled = false
            takes[index].isPreviousSides = true
            let sceneNum = (takes[index].sceneIndex ?? 0) + 1
            takes[index].previousSidesLabel = "Previous sides · Scene \(sceneNum)"
        }

        for p in practice.indices where practice[p].auditionID == id {
            guard let s = practice[p].sceneIndex, scenes.indices.contains(s) else { continue }
            practice[p].scene = scenes[s]
            practice[p].linesTotal = scenes[s].lines.filter(\.isMine).count
            practice[p].linesLearned = min(practice[p].linesLearned, practice[p].linesTotal)
        }
    }
}
