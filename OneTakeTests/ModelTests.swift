import XCTest
@testable import OneTake

final class ModelTests: XCTestCase {
    private func audition(scenes: [ScriptScene] = []) -> Audition {
        Audition(project: "The Last Summer", projectType: "Feature film", role: "Maya", roleSize: "Lead",
                 castingOffice: "Casting office", due: .now, asks: [], pieces: [], scenes: scenes,
                 destination: .actorsAccess, status: .due)
    }

    func testEmptySlateAsksForDetailsInsteadOfReadingBlanks() {
        let slate = SlateInfo()
        XCTAssertTrue(slate.isEmpty)
        XCTAssertEqual(slate.spoken, "Say your name, height and where you're based.")
        XCTAssertEqual(SlateInfo(name: "Asha Rao", basedIn: "Pune").spoken, "Asha Rao. Pune.")
    }

    func testDeliverableFileName() {
        XCTAssertEqual(audition().deliverableFileName(slate: SlateInfo(name: "Asha Rao")), "RAO_ASHA_MAYA_THELASTSUMMER.mp4")
        XCTAssertEqual(audition().deliverableFileName(slate: SlateInfo()), "ACTOR_MAYA_THELASTSUMMER.mp4")
    }

    func testLegacyPlaceholderIsTheMockupPersona() {
        XCTAssertEqual(SlateInfo.legacyPlaceholder.name, "Kabir Sharma")
        XCTAssertNotEqual(SlateInfo(), SlateInfo.legacyPlaceholder)
    }

    func testMaskingHidesAGrowingShareOfYourWords() {
        let mine = ScriptLine(character: "Maya", text: "one two three four five", isMine: true)
        XCTAssertEqual(otLineDisplay(mine, mode: .masked(level: 1), peeked: false), "___ two three four ____")
        XCTAssertEqual(otLineDisplay(mine, mode: .masked(level: 4), peeked: false), "___ ___ _____ ____ ____")
        XCTAssertEqual(otLineDisplay(mine, mode: .masked(level: 4), peeked: true), mine.text)
        let theirs = ScriptLine(character: "Arjun", text: "one two", isMine: false)
        XCTAssertEqual(otLineDisplay(theirs, mode: .masked(level: 4), peeked: false), "one two")
    }

    func testSlatePositionOrdersTheTape() {
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "SIDES", lines: [], estimatedSeconds: 30)
        var a = audition(scenes: [scene])
        a.slateVideoURL = URL(fileURLWithPath: "/tmp/slate.mov")
        a.fullLengthVideoURL = URL(fileURLWithPath: "/tmp/full.mov")
        let take = Take(number: 1, duration: 30, recordedAt: .now, isCircled: true, notes: [],
                        fileURL: URL(fileURLWithPath: "/tmp/take.mov"), auditionID: a.id, sceneIndex: 0)
        let other = Take(number: 1, duration: 30, recordedAt: .now, isCircled: true, notes: [],
                         fileURL: URL(fileURLWithPath: "/tmp/other.mov"), auditionID: UUID(), sceneIndex: 0)

        let first = MediaExporter.clips(for: a, takes: [other, take], slateAtStart: true).map(\.kind)
        XCTAssertEqual(first, [.slate, .fullLength, .scene(0)])
        let last = MediaExporter.clips(for: a, takes: [other, take], slateAtStart: false).map(\.kind)
        XCTAssertEqual(last, [.scene(0), .slate, .fullLength])
    }
}
