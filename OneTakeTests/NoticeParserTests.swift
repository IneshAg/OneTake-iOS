import XCTest
@testable import OneTake

final class NoticeParserTests: XCTestCase {
    func testReadsRoleProjectAndAsks() {
        let draft = NoticeParser.parse("Self-tape for MAYA in THE LAST SUMMER (feature). Please slate first, landscape, full length. Send via Actors Access.")
        XCTAssertEqual(draft.role, "Maya")
        XCTAssertEqual(draft.project, "The Last Summer")
        XCTAssertEqual(draft.projectType, "Feature film")
        XCTAssertEqual(draft.destination, .actorsAccess)
        XCTAssertEqual(Set(draft.asks), ["Slate first", "Landscape", "Full length", "Actors Access"])
    }

    func testCountsScenesMentionedInTheNotice() {
        XCTAssertEqual(NoticeParser.parse("Sides attached (2 scenes).").scenes, 2)
        XCTAssertEqual(NoticeParser.parse("No scene count here.").scenes, 1)
    }

    func testAuditionGetsAPiecePerParsedScene() {
        var draft = NoticeParser.parse("""
        INT. ROOM — DAY
        MAYA
        Hello.

        EXT. ROAD — NIGHT
        MAYA
        Goodbye.
        """)
        draft.role = "Maya"
        let audition = draft.makeAudition()
        XCTAssertEqual(audition.scenes.count, 2)
        XCTAssertEqual(audition.pieces.filter { $0.kind == .scene }.map(\.title), ["Scene 1", "Scene 2"])
    }
}
