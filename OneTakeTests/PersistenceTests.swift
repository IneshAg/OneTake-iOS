import XCTest
@testable import OneTake

final class PersistenceTests: XCTestCase {
    @MainActor
    func testReaderTrimFailurePreservesCurrentEditAndRestoreUsesFirstRecording() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cue = directory.appendingPathComponent("cue.m4a")
        let edit = directory.appendingPathComponent("edit.m4a")
        let original = Data([1, 2, 3])
        try original.write(to: cue)
        try Data([2, 3]).write(to: edit)
        try ReaderTrackPlayer.installEditedRecording(edit, at: cue)
        let current = Data([2])
        try current.write(to: edit)
        try ReaderTrackPlayer.installEditedRecording(edit, at: cue)

        XCTAssertThrowsError(try ReaderTrackPlayer.installEditedRecording(edit, at: cue))
        XCTAssertEqual(try Data(contentsOf: cue), current)
        try ReaderTrackPlayer.restoreOriginalRecording(at: cue)
        XCTAssertEqual(try Data(contentsOf: cue), original)
    }

    @MainActor
    func testReaderRetakeKeepsOnlyTheNewRecordingAndItsOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cue = directory.appendingPathComponent("cue.m4a")
        let staged = directory.appendingPathComponent("staged.m4a")
        let previous = Data([1])
        let newOriginal = Data([2, 3])
        let newTrim = Data([3])
        try previous.write(to: cue)
        try previous.write(to: ReaderTrackPlayer.originalURL(for: cue))

        XCTAssertThrowsError(try ReaderLineRecorder.saveCue(from: staged, to: cue))
        XCTAssertEqual(try Data(contentsOf: cue), previous)
        try newTrim.write(to: staged)
        try newOriginal.write(to: ReaderTrackPlayer.originalURL(for: staged))
        try ReaderLineRecorder.saveCue(from: staged, to: cue)

        XCTAssertEqual(try Data(contentsOf: cue), newTrim)
        try ReaderTrackPlayer.restoreOriginalRecording(at: cue)
        XCTAssertEqual(try Data(contentsOf: cue), newOriginal)
    }

    private func audition(_ project: String) -> Audition {
        Audition(project: project, projectType: "Feature film", role: "Maya", roleSize: "Lead",
                 castingOffice: "Casting office", due: Date(timeIntervalSince1970: 1_800_000_000),
                 asks: [], pieces: [], scenes: [], destination: .actorsAccess, status: .due)
    }

    func testOneUnreadableAuditionDoesNotLoseTheRest() throws {
        let state = PersistedState(auditions: [audition("Good"), audition("Damaged")], slate: SlateInfo(name: "Asha Rao"), isOnboarded: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var auditions = try XCTUnwrap(json["auditions"] as? [[String: Any]])
        auditions[1].removeValue(forKey: "project")
        json["auditions"] = auditions
        let data = try JSONSerialization.data(withJSONObject: json)

        var kept: Data?
        let loaded = try XCTUnwrap(Persistence.decode(data) { kept = $0 })
        XCTAssertEqual(loaded.auditions.map(\.project), ["Good"])
        XCTAssertEqual(loaded.droppedRecords, 1)
        XCTAssertTrue(loaded.isOnboarded)
        XCTAssertEqual(loaded.slate.name, "Asha Rao")
        XCTAssertEqual(kept, data, "the original bytes must be kept before anything overwrites them")
    }

    func testUnreadableFileIsKeptAndNotReplacedWithEmptyState() {
        let garbage = Data("not json".utf8)
        var kept: Data?
        XCTAssertNil(Persistence.decode(garbage) { kept = $0 })
        XCTAssertEqual(kept, garbage)
    }

    func testCleanFileIsNotCopied() throws {
        let data = try JSONEncoder().encode(PersistedState(auditions: [audition("Fine")], isOnboarded: true))
        var copied = false
        let loaded = try XCTUnwrap(Persistence.decode(data) { _ in copied = true })
        XCTAssertEqual(loaded.auditions.count, 1)
        XCTAssertEqual(loaded.droppedRecords, 0)
        XCTAssertFalse(copied)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let loaded = try XCTUnwrap(Persistence.decode(Data("{}".utf8)) { _ in })
        XCTAssertTrue(loaded.auditions.isEmpty)
        XCTAssertFalse(loaded.isOnboarded)
        XCTAssertTrue(loaded.slate.isEmpty)
    }

    func testISO8601DateStringsDecodeAlongsideTheAppDateFormat() throws {
        let a = audition("ISO dates")
        let state = PersistedState(auditions: [a], isOnboarded: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var auditions = try XCTUnwrap(json["auditions"] as? [[String: Any]])
        var record = try XCTUnwrap(auditions.first)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        record["due"] = formatter.string(from: a.due)
        auditions[0] = record
        json["auditions"] = auditions
        let data = try JSONSerialization.data(withJSONObject: json)

        let loaded = try XCTUnwrap(Persistence.decode(data) { _ in })
        XCTAssertEqual(loaded.auditions.first?.due, a.due)
        XCTAssertTrue(loaded.isOnboarded)
    }

    func testClearAllLocalDataCleansPracticeAndTakes() {
        let store = AppStore()
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "INT. ROOM", lines: [
            ScriptLine(character: "MAYA", text: "Line 1", isMine: true),
            ScriptLine(character: "JOHN", text: "Line 2", isMine: false)
        ], estimatedSeconds: 30)
        let piece = store.addStandalonePracticePiece(title: "Monologue", character: "MAYA", scene: scene)
        XCTAssertFalse(store.practice.isEmpty, "Practice pieces must be added")

        store.practicePath = [.standalonePractice(piece.id)]
        store.takes = [Take(number: 1, duration: 5, recordedAt: Date(), isCircled: false, notes: [], fileURL: URL(fileURLWithPath: "/tmp/take.mov"), auditionID: UUID(), sceneIndex: 0)]

        store.clearAllLocalData()

        XCTAssertTrue(store.practice.isEmpty, "Practice pieces must be completely cleaned by clearAllLocalData")
        XCTAssertTrue(store.practicePath.isEmpty, "Practice navigation path must be cleared")
        XCTAssertTrue(store.takes.isEmpty, "Takes must be cleared")
    }

    func testClearPracticeDataCleansOnlyPractice() {
        let store = AppStore()
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "INT. ROOM", lines: [
            ScriptLine(character: "MAYA", text: "Line 1", isMine: true)
        ], estimatedSeconds: 30)
        let piece = store.addStandalonePracticePiece(title: "Monologue", character: "MAYA", scene: scene)
        store.practicePath = [.standalonePractice(piece.id)]
        let initialReaderVersion = store.readerTrackVersion

        store.clearPracticeData()

        XCTAssertTrue(store.practice.isEmpty, "Practice pieces must be cleaned by clearPracticeData")
        XCTAssertTrue(store.practicePath.isEmpty, "Practice path must be emptied")
        XCTAssertGreaterThan(store.readerTrackVersion, initialReaderVersion, "Reader track version should be bumped to notify views")
    }

    func testMediaStorePersistRetakePreservesPreviousRecordingOnFailure() throws {
        let subfolder = "test-retake-\(UUID().uuidString)"
        defer { MediaStore.deleteAll([subfolder]) }

        let temp1 = FileManager.default.temporaryDirectory.appendingPathComponent("temp1-\(UUID().uuidString).mov")
        let temp2 = FileManager.default.temporaryDirectory.appendingPathComponent("temp2-\(UUID().uuidString).mov")
        let data1 = Data("original-recording".utf8)
        let data2 = Data("new-retake".utf8)
        try data1.write(to: temp1)
        try data2.write(to: temp2)
        defer {
            try? FileManager.default.removeItem(at: temp1)
            try? FileManager.default.removeItem(at: temp2)
        }

        // 1. Initial save
        let saved1 = try XCTUnwrap(MediaStore.persist(temp1, as: "slate.mov", in: subfolder))
        XCTAssertEqual(try Data(contentsOf: saved1), data1)

        // 2. Overwrite with valid new recording
        let saved2 = try XCTUnwrap(MediaStore.persist(temp2, as: "slate.mov", in: subfolder))
        XCTAssertEqual(try Data(contentsOf: saved2), data2)

        // 3. Failed save with non-existent temp file does not destroy the existing file
        let bogusTemp = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent.mov")
        let failedSave = MediaStore.persist(bogusTemp, as: "slate.mov", in: subfolder)
        XCTAssertNil(failedSave)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved2.path))
        XCTAssertEqual(try Data(contentsOf: saved2), data2, "Failed retake must leave previous recording intact")

        // 4. Test actual rollback catch branch:
        // When temp file exists so it passes guard, but moveItem(temp -> dest) throws an error,
        // the catch block must restore the backup to dest.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("locked-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let temp3 = tempDir.appendingPathComponent("temp3.mov")
        try Data("retake-that-fails-to-move".utf8).write(to: temp3)
        // Lock parent directory so temp3 cannot be unlinked/moved by FileManager.moveItem
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let rollbackSave = MediaStore.persist(temp3, as: "slate.mov", in: subfolder)
        XCTAssertNil(rollbackSave, "Persist must return nil when moveItem fails")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved2.path), "Dest file must still exist after rollback")
        XCTAssertEqual(try Data(contentsOf: saved2), data2, "Failed move must restore superseded recording from backup")
    }

    @MainActor
    func testRevisedSidesReorderingAndReaderAudioMigration() throws {
        let store = AppStore()
        let auditionID = UUID()

        let scene1 = ScriptScene(
            id: UUID(),
            number: 1,
            title: "Scene 1",
            heading: "INT. OFFICE - DAY",
            lines: [
                ScriptLine(id: UUID(), character: "TOM", text: "Greg, hello.", isMine: true),
                ScriptLine(id: UUID(), character: "GREG", text: "Good morning Tom.", isMine: false)
            ]
        )
        let scene2 = ScriptScene(
            id: UUID(),
            number: 2,
            title: "Scene 2",
            heading: "EXT. STREET - NIGHT",
            lines: [
                ScriptLine(id: UUID(), character: "TOM", text: "Goodbye.", isMine: true),
                ScriptLine(id: UUID(), character: "SHIV", text: "See you later.", isMine: false)
            ]
        )

        var aud = Audition(
            id: auditionID,
            project: "Succession S5",
            projectType: "Series",
            role: "TOM",
            roleSize: "Lead",
            castingOffice: "HBO",
            due: Date().addingTimeInterval(86400),
            asks: [],
            pieces: [],
            scenes: [scene1, scene2],
            destination: .email,
            status: .due
        )
        store.add(aud)

        defer {
            try? FileManager.default.removeItem(at: MediaStore.directory("\(ReaderTrackPlayer.folder)/\(auditionID.uuidString)"))
        }

        // 1. Create original reader audio files
        // Greg is scene 0, line 0 among reader lines
        let gregCueURL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: 0)
        let gregData = Data("greg-audio-cue".utf8)
        try FileManager.default.createDirectory(at: gregCueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try gregData.write(to: gregCueURL)

        // Shiv is scene 1, line 0 among reader lines
        let shivCueURL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 1, line: 0)
        let shivData = Data("shiv-audio-cue".utf8)
        try FileManager.default.createDirectory(at: shivCueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try shivData.write(to: shivCueURL)

        // 2. Add an original take on Scene 0 (marked circled)
        let originalTake = Take(
            id: UUID(),
            number: 1,
            duration: 20.0,
            recordedAt: .now,
            isCircled: true,
            notes: ["Great take"],
            fileURL: nil,
            auditionID: auditionID,
            sceneIndex: 0
        )
        store.addTake(originalTake)

        // 3. New script swaps scene order and modifies Shiv's line:
        // New Scene 1: old Scene 2 with modified line
        // New Scene 2: old Scene 1 unchanged
        let newScene1 = ScriptScene(
            id: UUID(),
            number: 1,
            title: "Scene 1",
            heading: "EXT. STREET - NIGHT",
            lines: [
                ScriptLine(id: UUID(), character: "TOM", text: "Goodbye.", isMine: true),
                ScriptLine(id: UUID(), character: "SHIV", text: "See you tomorrow.", isMine: false) // Modified
            ]
        )
        let newScene2 = ScriptScene(
            id: UUID(),
            number: 2,
            title: "Scene 2",
            heading: "INT. OFFICE - DAY",
            lines: [
                ScriptLine(id: UUID(), character: "TOM", text: "Greg, hello.", isMine: true),
                ScriptLine(id: UUID(), character: "GREG", text: "Good morning Tom.", isMine: false) // Unchanged
            ]
        )

        // 4. Replace sides
        store.replaceSides(of: auditionID, with: [newScene1, newScene2], sourceText: "revised script text")

        // 5. Verify reader audio migration:
        // Greg's audio (previously scene 0, line 0) should now be in new scene 1, line 0!
        let newGregCueURL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 1, line: 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newGregCueURL.path), "Greg's audio cue should migrate to new Scene 2 (index 1)")
        XCTAssertEqual(try Data(contentsOf: newGregCueURL), gregData)

        // Shiv's modified line (in new scene 0, line 0) should NOT have migrated old audio
        let newShivCueURL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newShivCueURL.path), "Shiv's modified line should not inherit audio from the changed line")

        // 6. Verify takes preservation:
        let previousTake = try XCTUnwrap(store.takes.first(where: { $0.id == originalTake.id }))
        XCTAssertTrue(previousTake.previousSides, "Earlier take must be tagged as previous sides")
        XCTAssertFalse(previousTake.isCircled, "Earlier take should no longer be circled for the package")
        XCTAssertEqual(previousTake.previousSidesLabel, "Previous sides · Scene 1")
    }

    func testMultipleReaderCharactersInSameSceneHaveStableCueIDs() throws {
        let store = AppStore()
        let auditionID = UUID()

        // Clean any residual test recordings
        defer {
            try? FileManager.default.removeItem(at: MediaStore.directory("\(ReaderTrackPlayer.folder)/\(auditionID.uuidString)"))
        }

        // Scene with two reader characters (KAT and BARTENDER) and one actor character (TOM)
        let lineKat1 = ScriptLine(id: UUID(), character: "KAT", text: "Hey Tom.", isMine: false)
        let lineBartender1 = ScriptLine(id: UUID(), character: "BARTENDER", text: "What's your poison?", isMine: false)
        let lineTom = ScriptLine(id: UUID(), character: "TOM", text: "Just soda water.", isMine: true)
        let lineKat2 = ScriptLine(id: UUID(), character: "KAT", text: "Make it two.", isMine: false)

        let scene = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "INT. BAR - NIGHT",
            lines: [lineKat1, lineBartender1, lineTom, lineKat2]
        )

        let audition = Audition(
            id: auditionID,
            project: "Cocktail Hour",
            projectType: "Feature Film",
            role: "Tom",
            roleSize: "Lead",
            castingOffice: "Bar Casting",
            due: Date().addingTimeInterval(86400),
            asks: ["Scene 1"],
            pieces: [Piece(kind: .scene, title: "Scene 1", detail: "", isDone: false, isOptional: false)],
            scenes: [scene],
            destination: .email,
            status: .due
        )
        store.add(audition)

        let allUnowned = scene.lines.filter { !$0.isMine }
        XCTAssertEqual(allUnowned.count, 3)

        // Cue indices in scene:
        // Kat line 1: index 0
        // Bartender line 1: index 1
        // Kat line 2: index 2
        let cueIdxKat1 = try XCTUnwrap(allUnowned.firstIndex(where: { $0.id == lineKat1.id }))
        let cueIdxBartender1 = try XCTUnwrap(allUnowned.firstIndex(where: { $0.id == lineBartender1.id }))
        let cueIdxKat2 = try XCTUnwrap(allUnowned.firstIndex(where: { $0.id == lineKat2.id }))

        XCTAssertEqual(cueIdxKat1, 0)
        XCTAssertEqual(cueIdxBartender1, 1)
        XCTAssertEqual(cueIdxKat2, 2)

        // Write simulated audio for Kat's first cue
        let kat1URL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: cueIdxKat1)
        try FileManager.default.createDirectory(at: kat1URL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let kat1Data = "AUDIO_KAT_1".data(using: .utf8)!
        try kat1Data.write(to: kat1URL)

        // Write simulated audio for Bartender's first cue
        let bartender1URL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: cueIdxBartender1)
        let bartender1Data = "AUDIO_BARTENDER_1".data(using: .utf8)!
        try FileManager.default.createDirectory(at: bartender1URL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bartender1Data.write(to: bartender1URL)

        // Write simulated audio for Kat's second cue
        let kat2URL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: cueIdxKat2)
        let kat2Data = "AUDIO_KAT_2".data(using: .utf8)!
        try FileManager.default.createDirectory(at: kat2URL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try kat2Data.write(to: kat2URL)

        // Verify files exist at the distinct scene-level line indices
        XCTAssertTrue(FileManager.default.fileExists(atPath: kat1URL.path), "Kat 1 audio must exist at line-0.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bartender1URL.path), "Bartender 1 audio must exist at line-1.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kat2URL.path), "Kat 2 audio must exist at line-2.m4a")

        XCTAssertEqual(try Data(contentsOf: kat1URL), kat1Data)
        XCTAssertEqual(try Data(contentsOf: bartender1URL), bartender1Data)
        XCTAssertEqual(try Data(contentsOf: kat2URL), kat2Data)

        // Verify ReaderTrackPlayer.hasRecording checks
        XCTAssertTrue(ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: 0, line: cueIdxKat1))
        XCTAssertTrue(ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: 0, line: cueIdxBartender1))
        XCTAssertTrue(ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: 0, line: cueIdxKat2))
    }

    func testRevisedSidesResetSceneCompletionAndChecklistReadiness() throws {
        let store = AppStore()
        let auditionID = UUID()

        // 1. Initial audition with 1 scene
        let scene1 = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "INT. COFFEE SHOP - DAY",
            lines: [
                ScriptLine(id: UUID(), character: "ALICE", text: "Hello.", isMine: true),
                ScriptLine(id: UUID(), character: "BOB", text: "Hi Alice.", isMine: false)
            ]
        )

        let audition = Audition(
            id: auditionID,
            project: "Coffee Talk",
            projectType: "Short Film",
            role: "Alice",
            roleSize: "Lead",
            castingOffice: "Coffee Casting",
            due: Date().addingTimeInterval(86400),
            asks: ["Scene 1"],
            pieces: [Piece(kind: .scene, title: "Scene 1", detail: "", isDone: false, isOptional: false)],
            scenes: [scene1],
            destination: .email,
            status: .due
        )
        store.add(audition)

        // 2. Record a take for Scene 1
        let take1 = Take(
            id: UUID(),
            number: 1,
            duration: 35.0,
            recordedAt: Date(),
            isCircled: true,
            notes: [],
            fileURL: URL(fileURLWithPath: "/tmp/take1.mov"),
            auditionID: auditionID,
            sceneIndex: 0
        )
        store.addTake(take1)

        // Assert scene 1 is complete and audition is ready
        let loadedAudition = try XCTUnwrap(store.audition(auditionID))
        XCTAssertTrue(loadedAudition.pieces[0].isDone, "Scene 1 should be marked done after recording take")
        XCTAssertTrue(loadedAudition.isPackageReady, "Audition package should be ready")
        XCTAssertEqual(loadedAudition.status, .ready)

        // 3. Casting sends revised sides!
        let revisedScene1 = ScriptScene(
            number: 1,
            title: "Scene 1 (Revised)",
            heading: "INT. COFFEE SHOP - NIGHT",
            lines: [
                ScriptLine(id: UUID(), character: "ALICE", text: "We need to talk now.", isMine: true),
                ScriptLine(id: UUID(), character: "BOB", text: "Not here.", isMine: false)
            ]
        )

        store.replaceSides(of: auditionID, with: [revisedScene1], sourceText: "revised sides text")

        // 4. Run syncPieces() as would happen on resume / app launch
        store.syncPieces()

        // 5. Assert that revised scene is NOT marked done, package is NOT ready, status is .due
        let revisedAudition = try XCTUnwrap(store.audition(auditionID))
        let revisedScenePiece = try XCTUnwrap(revisedAudition.pieces.first(where: { $0.kind == .scene }))
        XCTAssertFalse(revisedScenePiece.isDone, "Revised scene must NOT be marked done just because earlier take exists")
        XCTAssertFalse(revisedAudition.isPackageReady, "Package must NOT be ready when revised scene has no take from current sides")
        XCTAssertEqual(revisedAudition.status, .due, "Audition status must be .due after sides revision")

        // 6. Record a take for the revised scene
        let revisedTake = Take(
            id: UUID(),
            number: 2,
            duration: 40.0,
            recordedAt: Date(),
            isCircled: true,
            notes: [],
            fileURL: URL(fileURLWithPath: "/tmp/take2.mov"),
            auditionID: auditionID,
            sceneIndex: 0
        )
        store.addTake(revisedTake)

        let completedAudition = try XCTUnwrap(store.audition(auditionID))
        let completedScenePiece = try XCTUnwrap(completedAudition.pieces.first(where: { $0.kind == .scene }))
        XCTAssertTrue(completedScenePiece.isDone, "Revised scene must be marked done after shooting new take")
        XCTAssertTrue(completedAudition.isPackageReady, "Package should now be ready")
        XCTAssertEqual(completedAudition.status, .ready)
    }

    func testRevisedSidesWhenAllLinesChangeArchivesReaderDirectoryWithoutSelfNestingError() throws {
        let store = AppStore()
        let auditionID = UUID()

        defer {
            try? FileManager.default.removeItem(at: MediaStore.directory("\(ReaderTrackPlayer.folder)/\(auditionID.uuidString)"))
        }

        let oldScene = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "INT. BASEMENT - DAY",
            lines: [
                ScriptLine(id: UUID(), character: "CHARLIE", text: "Speak up.", isMine: false)
            ]
        )
        let audition = Audition(
            id: auditionID,
            project: "Secret Code",
            projectType: "Feature Film",
            role: "Maya",
            roleSize: "Lead",
            castingOffice: "Casting Co",
            due: Date().addingTimeInterval(86400),
            asks: [],
            pieces: [],
            scenes: [oldScene],
            destination: .email,
            status: .due
        )
        store.add(audition)

        let cueURL = ReaderTrackPlayer.url(auditionID: auditionID, sceneIndex: 0, line: 0)
        try FileManager.default.createDirectory(at: cueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old-cue-data".utf8).write(to: cueURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cueURL.path))

        // New scene with completely different heading and text (0 matching lines)
        let newScene = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "EXT. MOUNTAIN - NIGHT",
            lines: [
                ScriptLine(id: UUID(), character: "DENNIS", text: "Look at the stars.", isMine: false)
            ]
        )

        store.replaceSides(of: auditionID, with: [newScene], sourceText: "brand new script")

        let readerDir = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(auditionID.uuidString)", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: readerDir.path), "Reader directory must exist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cueURL.path), "Old cue must not exist at old unmigrated location")

        // Subdirectories should include a previous_sides folder
        let subpaths = (try? FileManager.default.contentsOfDirectory(atPath: readerDir.path)) ?? []
        let hasPreviousSides = subpaths.contains { $0.hasPrefix("previous_sides_") }
        XCTAssertTrue(hasPreviousSides, "Previous sides archive directory must exist without self-nesting move error")
    }

    func testCompareSidesPrioritizesHeadingMatchOverDefaultSceneNumber() throws {
        let store = AppStore()
        let auditionID = UUID()

        // Old scenes: Scene 1 = EXT. BEACH, Scene 2 = INT. CABIN
        let oldScene1 = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "EXT. BEACH - DAY",
            lines: [ScriptLine(id: UUID(), character: "ALEX", text: "Cold water.", isMine: false)]
        )
        let oldScene2 = ScriptScene(
            number: 2,
            title: "Scene 2",
            heading: "INT. CABIN - NIGHT",
            lines: [ScriptLine(id: UUID(), character: "ALEX", text: "Warm fire.", isMine: false)]
        )

        let audition = Audition(
            id: auditionID,
            project: "Getaway",
            projectType: "Feature Film",
            role: "Sam",
            roleSize: "Lead",
            castingOffice: "Beach Casting",
            due: Date().addingTimeInterval(86400),
            asks: [],
            pieces: [],
            scenes: [oldScene1, oldScene2],
            destination: .email,
            status: .due
        )
        store.add(audition)

        // New sides swap the order: Scene 1 is now INT. CABIN, Scene 2 is EXT. BEACH
        let newScene1 = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "INT. CABIN - NIGHT",
            lines: [ScriptLine(id: UUID(), character: "ALEX", text: "Warm fire.", isMine: false)]
        )
        let newScene2 = ScriptScene(
            number: 2,
            title: "Scene 2",
            heading: "EXT. BEACH - DAY",
            lines: [ScriptLine(id: UUID(), character: "ALEX", text: "Cold water.", isMine: false)]
        )

        let summary = try XCTUnwrap(store.compareSides(of: auditionID, with: [newScene1, newScene2]))
        // newScene1 (index 0) has heading INT. CABIN, which matches oldScene2 (index 1)
        XCTAssertEqual(summary.sceneDiffs[0].oldIndex, 1, "Slugline match must take precedence over default Scene 1 number")
        XCTAssertTrue(summary.sceneDiffs[0].isReordered)
        // newScene2 (index 1) has heading EXT. BEACH, which matches oldScene1 (index 0)
        XCTAssertEqual(summary.sceneDiffs[1].oldIndex, 0, "Slugline match must take precedence over default Scene 2 number")
        XCTAssertTrue(summary.sceneDiffs[1].isReordered)
    }
}
