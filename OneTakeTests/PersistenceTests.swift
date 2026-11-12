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
    }
}
