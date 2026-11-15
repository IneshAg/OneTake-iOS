import Foundation

// MARK: - AppStore Practice Extension

extension AppStore {
    // MARK: Sample Data

    /// Returns `true` when `piece` is the built-in sample ("A late goodbye" / "Sample scene").
    /// Standalone pieces tied to no real audition and carrying the sample fingerprint are matched.
    func isSamplePiece(_ piece: PracticePiece) -> Bool {
        guard piece.auditionID == nil else { return false }
        return piece.title.caseInsensitiveCompare("A late goodbye") == .orderedSame
            || piece.detail.localizedCaseInsensitiveContains("sample")
    }

    /// Removes sample practice pieces and their associated disk folders.
    /// Call when the user turns off "Show sample scene" in Settings.
    func removeSampleData() {
        let samples = practice.filter { isSamplePiece($0) }
        guard !samples.isEmpty else { return }
        let dirs = samples.map { "practice-\($0.id.uuidString)" }
        MediaStore.deleteAll(dirs)
        practice.removeAll { isSamplePiece($0) }
        // Clear practice navigation if it points into a now-deleted piece.
        practicePath.removeAll { route in
            if case .practiceSample = route { return true }
            return false
        }
        if case .practiceTake(let pieceID, _, _) = camera,
           let pid = pieceID, samples.contains(where: { $0.id == pid }) {
            camera = nil
        }
        persist()
    }

    /// Cleans all practice pieces, progress, active practice navigation, and associated practice takes.
    func clearPracticeData() {
        let practiceDirs = practice.map { "practice-\($0.id.uuidString)" }
        let allPracticeFolders = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path))?.filter { $0.hasPrefix("practice-") } ?? []
        MediaStore.deleteAll([ReaderTrackPlayer.folder] + practiceDirs + allPracticeFolders)
        practice.removeAll()
        practicePath.removeAll()
        readerTracksDidChange()
        if case .practiceTake = camera {
            camera = nil
        }
        persist()
    }

    func incrementPracticeTakes(for id: PracticePiece.ID) {
        guard let i = practice.firstIndex(where: { $0.id == id }) else { return }
        practice[i].takesRecorded += 1
    }

    func addStandalonePracticePiece(title: String, character: String, scene: ScriptScene,
                                   detail: String = "Personal scene") -> PracticePiece {
        let piece = PracticePiece(title: title, detail: detail, linesLearned: 0,
                                  linesTotal: scene.lines.filter(\.isMine).count,
                                  character: character, scene: scene)
        practice.insert(piece, at: 0)
        return piece
    }

    func promotePracticePiece(_ id: PracticePiece.ID) {
        guard let index = practice.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let piece = practice.remove(at: index)
        practice.insert(piece, at: 0)
    }

    func recordStandaloneRun(pieceID: PracticePiece.ID, linesOnYourOwn: Int) {
        guard let index = practice.firstIndex(where: { $0.id == pieceID }) else { return }
        let clamped = max(0, min(linesOnYourOwn, practice[index].linesTotal))
        practice[index].linesLearned = clamped
        if let audID = practice[index].auditionID, let sIdx = practice[index].sceneIndex {
            recordRun(auditionID: audID, sceneIndex: sIdx, linesOnYourOwn: clamped)
        } else {
            promotePracticePiece(pieceID)
            persist()
        }
    }

    /// Finds or creates the `PracticePiece` for a given audition scene, so Quick Drills and the
    /// "pick up where you left off" card have something real to point at.
    @discardableResult
    func practicePiece(for auditionID: Audition.ID, sceneIndex: Int) -> PracticePiece {
        if let existing = practice.first(where: { $0.auditionID == auditionID && $0.sceneIndex == sceneIndex }) {
            return existing
        }
        guard let audition = audition(auditionID), audition.scenes.indices.contains(sceneIndex) else {
            let blank = PracticePiece(title: "Practice", detail: "", linesLearned: 0, linesTotal: 0)
            practice.append(blank)
            return blank
        }
        let scene = audition.scenes[sceneIndex]
        let mine = scene.lines.filter(\.isMine)
        let piece = PracticePiece(
            title: scene.title, detail: "\(audition.project) · \(audition.role)",
            linesLearned: 0, linesTotal: mine.count,
            character: audition.role, scene: scene,
            auditionID: auditionID, sceneIndex: sceneIndex
        )
        practice.insert(piece, at: 0)
        return piece
    }

    /// A Run Lines pass that reached the end: the lines said without a prompt become the scene's
    /// "lines learned", and its practice piece moves to the top as the one to pick up next.
    func recordRun(auditionID: Audition.ID, sceneIndex: Int, linesOnYourOwn: Int) {
        guard audition(auditionID)?.scenes.indices.contains(sceneIndex) == true else { return }
        let piece = practicePiece(for: auditionID, sceneIndex: sceneIndex)
        guard let i = practice.firstIndex(where: { $0.id == piece.id }) else { return }
        var updated = practice[i]
        updated.linesLearned = max(0, min(linesOnYourOwn, updated.linesTotal))
        practice.remove(at: i)
        practice.insert(updated, at: 0)
        persist()
    }

    /// Toggles `isLearned` on an individual line inside a practice piece (and mirrors onto the linked audition scene).
    /// Returns the new state for that line plus whether every `isMine` line in the scene is now learned.
    @discardableResult
    func toggleLineLearned(pieceID: PracticePiece.ID, lineID: ScriptLine.ID) -> (nowLearned: Bool, allLearned: Bool)? {
        guard let i = practice.firstIndex(where: { $0.id == pieceID }),
              var scene = practice[i].scene,
              let lineIdx = scene.lines.firstIndex(where: { $0.id == lineID }),
              scene.lines[lineIdx].isMine else { return nil }

        scene.lines[lineIdx].isLearned.toggle()
        let nowLearned = scene.lines[lineIdx].isLearned
        let mine = scene.lines.filter(\.isMine)
        let learnedCount = mine.filter(\.isLearned).count

        practice[i].scene = scene
        practice[i].linesTotal = mine.count
        practice[i].linesLearned = learnedCount

        if let audID = practice[i].auditionID, let sIdx = practice[i].sceneIndex,
           let aIdx = auditions.firstIndex(where: { $0.id == audID }),
           auditions[aIdx].scenes.indices.contains(sIdx) {
            auditions[aIdx].scenes[sIdx].lines = scene.lines
        }

        persist()
        return (nowLearned, !mine.isEmpty && learnedCount == mine.count)
    }

    /// Marks every `isMine` line inside `pieceID` as learned (or resets them all).
    func markAllLinesLearned(pieceID: PracticePiece.ID, learned: Bool) {
        guard let i = practice.firstIndex(where: { $0.id == pieceID }) else { return }
        if var scene = practice[i].scene {
            for idx in scene.lines.indices where scene.lines[idx].isMine {
                scene.lines[idx].isLearned = learned
            }
            let mineCount = scene.lines.filter(\.isMine).count
            practice[i].scene = scene
            practice[i].linesTotal = mineCount
            practice[i].linesLearned = learned ? mineCount : 0

            if let audID = practice[i].auditionID, let sIdx = practice[i].sceneIndex,
               let aIdx = auditions.firstIndex(where: { $0.id == audID }),
               auditions[aIdx].scenes.indices.contains(sIdx) {
                auditions[aIdx].scenes[sIdx].lines = scene.lines
            }
        } else {
            practice[i].linesLearned = learned ? practice[i].linesTotal : 0
        }
        persist()
    }

    /// Updates a standalone practice piece's script from raw edited script text, preserving matching `isLearned` flags.
    func updateStandaloneSceneScript(pieceID: PracticePiece.ID, scriptText: String) {
        guard let i = practice.firstIndex(where: { $0.id == pieceID }) else { return }
        let existing = practice[i]
        let existingLearnedTexts = Set(
            (existing.scene?.lines ?? [])
                .filter { $0.isMine && $0.isLearned }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let role = existing.character.isEmpty
            ? (existing.scene?.lines.first(where: \.isMine)?.character ?? "")
            : existing.character
        var parsedScenes = ScriptParser.parseScenes(from: scriptText, myRole: role)
        var newScene = parsedScenes.first ?? ScriptScene(
            number: existing.scene?.number ?? 1,
            title: existing.title,
            heading: existing.scene?.heading ?? "SCENE",
            lines: [ScriptLine(character: role.isEmpty ? "You" : role, text: scriptText, isMine: true)]
        )
        for idx in newScene.lines.indices where newScene.lines[idx].isMine {
            let key = newScene.lines[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if existingLearnedTexts.contains(key) {
                newScene.lines[idx].isLearned = true
            }
        }
        let mine = newScene.lines.filter(\.isMine)
        practice[i].scene = newScene
        practice[i].linesTotal = mine.count
        practice[i].linesLearned = mine.filter(\.isLearned).count

        if let audID = existing.auditionID, let sIdx = existing.sceneIndex,
           let aIdx = auditions.firstIndex(where: { $0.id == audID }),
           auditions[aIdx].scenes.indices.contains(sIdx) {
            auditions[aIdx].scenes[sIdx] = newScene
        }
        persist()
    }
}
