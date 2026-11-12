import SwiftUI
import AVFoundation

// MARK: - AppStore Auditions Extension

extension AppStore {
    func startAuditionDraft(_ draft: NoticeParser.Draft, directToReview: Bool = false) {
        auditionDraft = draft
        showAddAudition = false
        pendingRouteAfterAdd = (directToReview || draft.missingRequiredDetails.isEmpty) ? .noticeReview : .missingDetails
    }

    /// Commits a confirmed draft directly into a persistent Audition, skipping redundant review screens
    /// and navigating directly to the Audition Detail or Reader recording.
    func commitAuditionDraft(_ draft: NoticeParser.Draft, readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .later) {
        let audition = draft.makeAudition()
        add(audition)
        auditionDraft = .blank
        showAddAudition = false
        tab = .auditions
        if readerAudioPlan == .recordNow,
           let firstScene = audition.scenes.indices.first(where: { !audition.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
            pendingRouteAfterAdd = .reader(audition.id, sceneIndex: firstScene)
        } else {
            pendingRouteAfterAdd = .auditionDetail(audition.id)
            continueAfterAdd = audition.id
        }
    }

    // MARK: Lookup

    func audition(_ id: Audition.ID) -> Audition? { auditions.first { $0.id == id } }

    /// Looks the audition up by ID on every get/set — capturing its index would go stale (editing the
    /// wrong audition, or crashing) as soon as `add` inserts at the top or one is removed.
    func binding(for id: Audition.ID) -> Binding<Audition>? {
        guard let initial = audition(id) else { return nil }
        return Binding(
            get: { self.audition(id) ?? initial },
            set: { newValue in
                guard let i = self.auditions.firstIndex(where: { $0.id == id }) else { return }
                self.auditions[i] = newValue
            }
        )
    }

    /// The audition Home should push the actor toward: soonest due, not sent.
    var nextPriority: Audition? {
        auditions.filter { $0.status != .sent }.min { $0.due < $1.due }
    }

    var active: [Audition] { auditions.filter { !$0.archived && $0.status != .sent }.sorted { $0.due < $1.due } }
    var sent: [Audition] { auditions.filter { !$0.archived && $0.status == .sent } }
    var archived: [Audition] { auditions.filter { $0.archived }.sorted { $0.due < $1.due } }

    // MARK: Mutations

    func add(_ audition: Audition) {
        auditions.insert(audition, at: 0)
        syncPieces()
    }

    /// Synchronizes checklist piece status (scenes, slate, full length, headshots) with real disk recordings and takes.
    func syncPieces() {
        for i in auditions.indices where auditions[i].status != .sent {
            let id = auditions[i].id
            // Headshots
            let hasAuditionHeadshot = HeadshotStore.isComplete(auditionID: id)
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .headshot {
                if hasAuditionHeadshot {
                    auditions[i].pieces[j].isDone = true
                } else if !auditions[i].pieces[j].isOptional {
                    auditions[i].pieces[j].isDone = false
                }
            }
            // Slate
            let hasSlate = auditions[i].slateVideoURL != nil
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .slate {
                if hasSlate {
                    auditions[i].pieces[j].isDone = true
                } else if !auditions[i].pieces[j].isOptional {
                    auditions[i].pieces[j].isDone = false
                }
            }
            // Full length
            let hasFullLength = auditions[i].fullLengthVideoURL != nil
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .fullLength {
                if hasFullLength {
                    auditions[i].pieces[j].isDone = true
                } else if !auditions[i].pieces[j].isOptional {
                    auditions[i].pieces[j].isDone = false
                }
            }
            // Scenes: if an audition has recorded takes for a scene in the current sides revision, that scene is done!
            let currentRev = auditions[i].currentSidesRevision
            let auditionTakes = takes.filter { $0.auditionID == id && !$0.previousSides && $0.currentSidesRevision == currentRev }
            let sceneTitles = !auditions[i].scenes.isEmpty
                ? auditions[i].scenes.map(\.title)
                : auditions[i].pieces.filter { $0.kind == .scene }.map(\.title)
            for (sceneIndex, title) in sceneTitles.enumerated() {
                let hasTake = auditionTakes.contains { ($0.sceneIndex ?? 0) == sceneIndex }
                for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .scene && auditions[i].pieces[j].title == title {
                    if hasTake {
                        auditions[i].pieces[j].isDone = true
                    } else if !auditions[i].pieces[j].isOptional {
                        // Preserve an explicit skip for optional scenes. Required scenes only
                        // count as complete when a take exists.
                        auditions[i].pieces[j].isDone = false
                    }
                }
            }
            if auditions[i].status != .sent {
                auditions[i].status = auditions[i].isPackageReady ? .ready : .due
            }
        }
    }

    func readerTracksDidChange() { readerTrackVersion += 1 }

    /// The scene the camera should open on: the first one whose checklist piece isn't done, else the
    /// first with no takes yet, else the first.
    func sceneToShoot(_ id: Audition.ID) -> Int {
        guard let a = audition(id), !a.scenes.isEmpty else { return 0 }
        let undone = Set(a.pieces.filter { $0.kind == .scene && !$0.isDone }.map(\.title))
        if let i = a.scenes.indices.first(where: { undone.contains(a.scenes[$0].title) }) { return i }
        if let i = a.scenes.indices.first(where: { i in !takes.contains { $0.auditionID == id && ($0.sceneIndex ?? 0) == i } }) { return i }
        return 0
    }

    /// The scene a checklist piece is about (scene pieces share their scene's title).
    func sceneIndex(for piece: Piece, in id: Audition.ID) -> Int {
        audition(id)?.scenes.firstIndex { $0.title == piece.title } ?? sceneToShoot(id)
    }

    /// Removes an audition and everything recorded for it on this iPhone: takes, slate and full
    /// length, reader tracks, practice pieces made from its scenes, its exported tape, and its
    /// audition-specific headshots. Profile default headshots are left untouched.
    func deleteAudition(_ id: Audition.ID) {
        guard let audition = audition(id) else { return }
        HeadshotStore.removeAuditionHeadshots(for: id)
        let fm = FileManager.default
        try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("audition-\(id.uuidString)", isDirectory: true))
        try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)", isDirectory: true))
        // Export file names come from role + project, so two auditions can share one; keep it if so.
        let otherAuditions = auditions.filter { $0.id != id }
        if let export = audition.exportedFileURL,
           !otherAuditions.contains(where: { $0.exportedFileURL?.standardizedFileURL == export.standardizedFileURL }) {
            try? fm.removeItem(at: export)
        }
        let exports = MediaStore.directory("Exports")
        let archiveURL = audition.separateArchiveURL ?? exports.appendingPathComponent(
            "\((audition.deliverableFileName(slate: slate) as NSString).deletingPathExtension)_SEPARATE.zip"
        )
        let archiveBase = archiveURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_SEPARATE", with: "")
        let sameNamedExportStillUsed = otherAuditions.contains { other in
            let otherArchive = other.separateArchiveURL ?? exports.appendingPathComponent(
                "\((other.deliverableFileName(slate: slate) as NSString).deletingPathExtension)_SEPARATE.zip"
            )
            return otherArchive.standardizedFileURL == archiveURL.standardizedFileURL
        }
        if !sameNamedExportStillUsed {
            try? fm.removeItem(at: archiveURL)
            for angle in HeadshotStore.angles {
                try? fm.removeItem(at: exports.appendingPathComponent("\(archiveBase)_HEADSHOT_\(angle.key.uppercased()).jpg"))
            }
        }
        for piece in practice where piece.auditionID == id {
            try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("practice-\(piece.id.uuidString)", isDirectory: true))
        }
        practice.removeAll { $0.auditionID == id }
        takes.removeAll { $0.auditionID == id }
        auditions.removeAll { $0.id == id }
    }

    func archiveAudition(_ id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].isArchived = true
        Haptics.tick()
    }

    func unarchiveAudition(_ id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].isArchived = false
        Haptics.success()
    }

    /// Adjusts the total number of scenes for an audition directly (e.g. from Edit Details).
    /// Adding scenes inserts new checklist pieces and empty scene containers ready for shooting or sides.
    func updateSceneCount(for id: Audition.ID, count: Int) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        let target = max(1, count)
        let currentScenes = auditions[i].scenes
        let currentScenePieces = auditions[i].pieces.filter { $0.kind == .scene }
        let currentCount = max(currentScenes.count, currentScenePieces.count)

        guard target != currentCount else { return }

        if target > currentCount {
            if auditions[i].scenes.isEmpty && currentCount > 0 {
                for n in 1...currentCount {
                    auditions[i].scenes.append(ScriptScene(number: n, title: "Scene \(n)", heading: "SCENE \(n)", lines: [], estimatedSeconds: 60))
                }
            }
            for n in (currentCount + 1)...target {
                let newScene = ScriptScene(
                    number: n,
                    title: "Scene \(n)",
                    heading: "SCENE \(n)",
                    lines: [],
                    estimatedSeconds: 60
                )
                auditions[i].scenes.append(newScene)

                let newPiece = Piece(
                    kind: .scene,
                    title: "Scene \(n)",
                    detail: "",
                    isDone: false
                )
                if let lastSceneIdx = auditions[i].pieces.lastIndex(where: { $0.kind == .scene }) {
                    auditions[i].pieces.insert(newPiece, at: lastSceneIdx + 1)
                } else if let slateIdx = auditions[i].pieces.firstIndex(where: { $0.kind == .slate }) {
                    auditions[i].pieces.insert(newPiece, at: slateIdx + 1)
                } else {
                    auditions[i].pieces.append(newPiece)
                }
            }
        } else {
            let diff = currentCount - target
            for _ in 0..<diff {
                if auditions[i].scenes.count > target {
                    auditions[i].scenes.removeLast()
                }
                if let lastSceneIdx = auditions[i].pieces.lastIndex(where: { $0.kind == .scene }) {
                    auditions[i].pieces.remove(at: lastSceneIdx)
                }
            }
        }

        if auditions[i].status == .ready { auditions[i].status = .due }
    }

    func updateRole(for id: Audition.ID, to newRole: String) {
        guard let index = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[index].role = newRole
        reclassifyRole(for: id)
        readerTracksDidChange()
    }

    func reclassifyRole(for id: Audition.ID) {
        guard let index = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let scriptText = auditions[index].scriptText, !scriptText.isEmpty {
            auditions[index].scenes = ScriptParser.parseScenes(from: scriptText, myRole: auditions[index].role)
            if let notes = NoticeParser.extractCharacterDescription(for: auditions[index].role, in: scriptText) {
                auditions[index].castingNotes = notes
            }
        } else {
            auditions[index].scenes = ScriptParser.reclassify(auditions[index].scenes, myRole: auditions[index].role)
        }
        for practiceIndex in practice.indices where practice[practiceIndex].auditionID == id {
            guard let sceneIndex = practice[practiceIndex].sceneIndex,
                  auditions[index].scenes.indices.contains(sceneIndex) else { continue }
            let scene = auditions[index].scenes[sceneIndex]
            practice[practiceIndex].scene = scene
            practice[practiceIndex].linesTotal = scene.lines.filter(\.isMine).count
            practice[practiceIndex].linesLearned = min(practice[practiceIndex].linesLearned, practice[practiceIndex].linesTotal)
        }
    }

    /// A callback: a new audition for the next round of the same role, with casting's notes, its own
    /// due date and a fresh checklist. Reader recordings can come along so they needn't be re-recorded.
    @discardableResult
    func startCallback(
        from id: Audition.ID,
        due: Date,
        notes: String,
        actorNotes: String? = nil,
        scenes: [ScriptScene]? = nil,
        extraScriptText: String? = nil,
        bringReader: Bool
    ) -> Audition.ID? {
        guard let original = audition(id) else { return nil }
        let finalScenes = (scenes != nil && !scenes!.isEmpty) ? scenes! : original.scenes

        // Build fresh pieces:
        // 1. Slate (if original had slate)
        var newPieces: [Piece] = []
        if let origSlate = original.pieces.first(where: { $0.kind == .slate }) {
            newPieces.append(Piece(kind: .slate, title: origSlate.title, detail: origSlate.detail, isDone: false, isOptional: origSlate.isOptional))
        }

        // 2. Scenes
        for (idx, scene) in finalScenes.enumerated() {
            let isNew = idx >= original.scenes.count
            let detail = isNew ? "Callback scene" : ""
            let origScene = original.pieces.first { $0.kind == .scene && $0.title == scene.title }
            let isOpt = origScene?.isOptional ?? NoticeParser.isSceneOptional(scene: scene, in: original.scriptText ?? "")
            newPieces.append(Piece(kind: .scene, title: scene.title.isEmpty ? "Scene \(scene.number)" : scene.title, detail: detail, isDone: false, isOptional: isOpt))
        }

        // 3. Headshot / Full Length (if original had them)
        if let origHeadshot = original.pieces.first(where: { $0.kind == .headshot }) {
            newPieces.append(Piece(kind: .headshot, title: origHeadshot.title, detail: origHeadshot.detail, isDone: false, isOptional: origHeadshot.isOptional))
        }
        if let origFullLength = original.pieces.first(where: { $0.kind == .fullLength }) {
            newPieces.append(Piece(kind: .fullLength, title: origFullLength.title, detail: origFullLength.detail, isDone: false, isOptional: origFullLength.isOptional))
        }
        newPieces = Piece.defaultFlowOrder(newPieces)

        var callback = Audition(
            project: original.project,
            projectType: original.projectType,
            role: original.role,
            roleSize: original.roleSize,
            castingOffice: original.castingOffice,
            due: due,
            asks: original.asks,
            pieces: newPieces,
            scenes: finalScenes,
            destination: original.destination,
            status: .due
        )
        callback.destinationDetail = original.destinationDetail
        callback.round = (original.round ?? 1) + 1

        let trimmedCasting = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        callback.castingNotes = trimmedCasting.isEmpty ? original.castingNotes : trimmedCasting

        let trimmedActor = (actorNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        callback.actorNotes = trimmedActor.isEmpty ? original.actorNotes : trimmedActor

        // Combine script text
        let extra = (extraScriptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            if let orig = original.scriptText, !orig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                callback.scriptText = orig + "\n\n--- Callback Sides ---\n\n" + extra
            } else {
                callback.scriptText = extra
            }
        } else {
            callback.scriptText = original.scriptText
        }

        if bringReader {
            let from = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)", isDirectory: true)
            let to = MediaStore.directory(ReaderTrackPlayer.folder).appendingPathComponent(callback.id.uuidString, isDirectory: true)
            try? FileManager.default.copyItem(at: from, to: to)
            readerTracksDidChange()
        }
        add(callback)
        return callback.id
    }

    func markDone(_ kind: PieceKind, in id: Audition.ID, title: String? = nil) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let j = auditions[i].pieces.firstIndex(where: { $0.kind == kind && !$0.isDone && (title == nil || $0.title == title) }) {
            auditions[i].pieces[j].isDone = true
        }
        if auditions[i].isPackageReady { auditions[i].status = .ready }
    }

    func togglePieceOptional(for id: Audition.ID, pieceID: UUID) {
        guard let index = auditions.firstIndex(where: { $0.id == id }),
              let pieceIndex = auditions[index].pieces.firstIndex(where: { $0.id == pieceID }) else { return }
        auditions[index].pieces[pieceIndex].isOptional.toggle()
        let isOpt = auditions[index].pieces[pieceIndex].isOptional
        if auditions[index].pieces[pieceIndex].kind == .headshot {
            auditions[index].pieces[pieceIndex].title = isOpt ? "Headshot (Optional)" : "Headshot"
        } else if auditions[index].pieces[pieceIndex].kind == .slate {
            auditions[index].pieces[pieceIndex].title = isOpt ? "Slate (Optional)" : "Slate"
        }
        if auditions[index].status != .sent {
            auditions[index].status = auditions[index].isPackageReady ? .ready : .due
        }
    }

    func markPieceDone(_ id: Audition.ID, pieceID: UUID, isDone: Bool = true) {
        guard let index = auditions.firstIndex(where: { $0.id == id }),
              let pieceIndex = auditions[index].pieces.firstIndex(where: { $0.id == pieceID }) else { return }
        auditions[index].pieces[pieceIndex].isDone = isDone
        if auditions[index].status != .sent {
            auditions[index].status = auditions[index].isPackageReady ? .ready : .due
        }
    }

    func markSent(_ id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].status = .sent
        auditions[i].sentDate = .now
    }

    func markExported(_ id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].status = .exported
    }

    func markSubmitted(_ id: Audition.ID) {
        markSent(id)
    }

    /// Circles `take` and un-circles every other take in the *same* audition+scene — scoped, so
    /// circling a take in one audition no longer silently un-circles another audition's send pick.
    func circleOnly(_ take: Take) {
        for i in takes.indices where takes[i].auditionID == take.auditionID && takes[i].sceneIndex == take.sceneIndex {
            takes[i].isCircled = takes[i].id == take.id
        }
        syncPieces()
    }

    func setSlateVideo(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].slateVideoURL = url
        syncPieces()
    }

    func keepOriginalSlate(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let previous = auditions[i].slateVideoURL, previous != url { try? FileManager.default.removeItem(at: previous) }
        if let backup = auditions[i].slateOriginalVideoURL, backup != url { try? FileManager.default.removeItem(at: backup) }
        auditions[i].slateVideoURL = url
        auditions[i].slateOriginalVideoURL = nil
        invalidateExport(for: id)
    }

    func acceptSlateTrim(_ trimmed: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }),
              let original = auditions[i].slateOriginalVideoURL ?? auditions[i].slateVideoURL,
              let replacement = moveEditedClip(trimmed, beside: original, stem: "slate-auto-trimmed") else { return }
        auditions[i].slateOriginalVideoURL = original
        auditions[i].slateVideoURL = replacement
        invalidateExport(for: id)
    }

    func restoreOriginalSlate(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let original = auditions[i].slateOriginalVideoURL else { return }
        if let current = auditions[i].slateVideoURL, current != original { try? FileManager.default.removeItem(at: current) }
        auditions[i].slateVideoURL = original
        auditions[i].slateOriginalVideoURL = nil
        invalidateExport(for: id)
    }

    func setFullLengthVideo(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let previous = auditions[i].fullLengthVideoURL, previous != url { try? FileManager.default.removeItem(at: previous) }
        if let original = auditions[i].fullLengthOriginalVideoURL, original != url { try? FileManager.default.removeItem(at: original) }
        auditions[i].fullLengthVideoURL = url
        auditions[i].fullLengthOriginalVideoURL = nil
        syncPieces()
    }

    func replaceSlateVideo(for id: Audition.ID, with edited: URL) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let old = auditions[i].slateVideoURL,
              let replacement = moveEditedClip(edited, beside: old, stem: "slate") else { return }
        if let original = auditions[i].slateOriginalVideoURL {
            if old != original { try? FileManager.default.removeItem(at: old) }
        } else {
            auditions[i].slateOriginalVideoURL = old
        }
        auditions[i].slateVideoURL = replacement
        invalidateExport(for: id)
    }

    func replaceFullLengthVideo(for id: Audition.ID, with edited: URL) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let old = auditions[i].fullLengthVideoURL,
              let replacement = moveEditedClip(edited, beside: old, stem: "full-length") else { return }
        if let original = auditions[i].fullLengthOriginalVideoURL {
            if old != original { try? FileManager.default.removeItem(at: old) }
        } else {
            auditions[i].fullLengthOriginalVideoURL = old
        }
        auditions[i].fullLengthVideoURL = replacement
        invalidateExport(for: id)
    }

    func restoreOriginalFullLengthVideo(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }),
              let original = auditions[i].fullLengthOriginalVideoURL,
              FileManager.default.fileExists(atPath: original.path) else { return }
        if let current = auditions[i].fullLengthVideoURL, current != original { try? FileManager.default.removeItem(at: current) }
        auditions[i].fullLengthVideoURL = original
        auditions[i].fullLengthOriginalVideoURL = nil
        invalidateExport(for: id)
    }

    private func moveEditedClip(_ edited: URL, beside original: URL, stem: String) -> URL? {
        let ext = edited.pathExtension.isEmpty ? (original.pathExtension.isEmpty ? "mov" : original.pathExtension) : edited.pathExtension
        let destination = original.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-trimmed-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: edited, to: destination)
            return destination
        } catch { return nil }
    }

    private func invalidateExport(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let url = auditions[i].exportedFileURL { try? FileManager.default.removeItem(at: url) }
        if let url = auditions[i].separateArchiveURL { try? FileManager.default.removeItem(at: url) }
        auditions[i].exportedFileURL = nil
        auditions[i].separateArchiveURL = nil
    }

    func setShareLink(_ link: CloudLink.Published, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].shareLink = link.url
        auditions[i].shareLinkExpires = link.expires
    }

    func clearShareLink(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].shareLink = nil
        auditions[i].shareLinkExpires = nil
    }

    /// Saves a custom filename template for this audition's deliverables.
    /// Supported tokens: `{name}`, `{firstName}`, `{lastName}`, `{role}`, `{project}`,
    /// `{side}`, `{scene}`, `{take}`, `{song}`.
    /// Pass `nil` to revert to the app default (`LAST_FIRST_ROLE_PROJECT.mp4`).
    func setFileNameTemplate(_ template: String?, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if auditions[i].submissionInstructions == nil {
            auditions[i].submissionInstructions = AuditionSubmissionInstructions()
        }
        let trimmed = template?.trimmingCharacters(in: .whitespacesAndNewlines)
        auditions[i].submissionInstructions?.fileNameTemplate = (trimmed?.isEmpty == false) ? trimmed : nil
        // Template change means old exports (which used the old name) are stale.
        invalidateExport(for: id)
    }

    func setExportedFile(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].exportedFileURL = url
    }

    func setSeparateArchive(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].separateArchiveURL = url
    }

    /// Next take number for a scene — one past the highest real take, so numbers never repeat even
    /// after a take is removed (a count-based number would collide with an existing take).
    func nextTakeNumber(auditionID: Audition.ID, sceneIndex: Int) -> Int {
        (takes.filter { $0.auditionID == auditionID && $0.sceneIndex == sceneIndex }.map(\.number).max() ?? 0) + 1
    }

    /// Appends a real take, circling it automatically if it's the first for that scene (so there's
    /// always a sensible send pick without the actor having to remember to circle one).
    func addTake(_ take: Take) {
        var take = take
        if let id = take.auditionID {
            let currentRev = audition(id)?.currentSidesRevision ?? 0
            take.sidesRevision = currentRev
            take.isPreviousSides = false
            if let scene = take.sceneIndex,
               !takes.contains(where: { $0.auditionID == id && $0.sceneIndex == scene && $0.isCircled && !$0.previousSides && $0.currentSidesRevision == currentRev }) {
                take.isCircled = true
            }
        }
        takes.append(take)
        syncPieces()
    }

    /// Swaps a take's file for its trimmed version. The new file gets a new name, so thumbnails and
    /// Tape Check (which key off the URL) pick up the change.
    func replaceTakeFile(_ id: Take.ID, with edited: URL) {
        guard let i = takes.firstIndex(where: { $0.id == id }), let old = takes[i].fileURL else { return }
        let ext = edited.pathExtension.isEmpty ? (old.pathExtension.isEmpty ? "mov" : old.pathExtension) : edited.pathExtension
        let dest = old.deletingLastPathComponent().appendingPathComponent("take-\(takes[i].number)-\(UUID().uuidString).\(ext)")
        do { try FileManager.default.moveItem(at: edited, to: dest) } catch { return }
        let original = takes[i].originalFileURL ?? old
        if old != original { try? FileManager.default.removeItem(at: old) }
        takes[i].fileURL = dest
        takes[i].originalFileURL = original
        if let auditionID = takes[i].auditionID { invalidateExport(for: auditionID) }
        Task { @MainActor in
            guard let seconds = try? await AVURLAsset(url: dest).load(.duration).seconds,
                  let j = self.takes.firstIndex(where: { $0.id == id }) else { return }
            self.takes[j].duration = seconds
        }
    }

    func restoreOriginalTakeFile(_ id: Take.ID) {
        guard let i = takes.firstIndex(where: { $0.id == id }),
              let original = takes[i].originalFileURL,
              FileManager.default.fileExists(atPath: original.path) else { return }
        let edited = takes[i].fileURL
        takes[i].fileURL = original
        takes[i].originalFileURL = nil
        if let edited, edited != original { try? FileManager.default.removeItem(at: edited) }
        if let auditionID = takes[i].auditionID { invalidateExport(for: auditionID) }
        Task { @MainActor in
            guard let seconds = try? await AVURLAsset(url: original).load(.duration).seconds,
                  let j = self.takes.firstIndex(where: { $0.id == id }) else { return }
            self.takes[j].duration = seconds
        }
    }

    /// A private note on a take — never sent, just for the actor.
    func addNote(_ note: String, to id: Take.ID) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = takes.firstIndex(where: { $0.id == id }) else { return }
        takes[i].notes.append(trimmed)
    }
}
