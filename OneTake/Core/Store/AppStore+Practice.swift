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
}
