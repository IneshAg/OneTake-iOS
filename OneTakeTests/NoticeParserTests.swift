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

    func testParsesUnstructuredCastingNotice() {
        let text = """
        Casting Call
        For a theatrical Hindi feature film.
        We are looking for a female lead.
        Age Group: 20 - 26 years
        Project folder "Heer Ranjha"
        Actors who have already auditioned need not apply again.
        Please send across your intro video & pictures to
        vaishak@anticasting.in
        Shortlisted candidates will be contacted.
        Anti-Casting
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Heer Ranjha")
        XCTAssertEqual(draft.projectType, "Feature film")
        XCTAssertEqual(draft.role, "Female Lead (20 - 26 years)")
        XCTAssertEqual(draft.castingOffice, "Anti-Casting")
        XCTAssertTrue(draft.asks.contains("Intro video"))
        XCTAssertTrue(draft.asks.contains("Headshots"))
        XCTAssertTrue(draft.asks.contains("Email: vaishak@anticasting.in"))
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
