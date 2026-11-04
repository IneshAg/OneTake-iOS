import XCTest
@testable import OneTake

final class PersistenceTests: XCTestCase {
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
}
