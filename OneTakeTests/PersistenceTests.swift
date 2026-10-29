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
}
