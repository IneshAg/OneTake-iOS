import XCTest
@testable import OneTake

final class ScriptParserTests: XCTestCase {
    func testCuesBecomeLinesAndYourRoleIsMarkedMine() {
        let sides = """
        MAYA
        You're late.

        ARJUN (CONT'D)
        I know. Traffic.
        """
        let scenes = ScriptParser.parseScenes(from: sides, myRole: "Arjun")
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.map(\.character), ["Maya", "Arjun"])
        XCTAssertEqual(scenes[0].lines.map(\.isMine), [false, true])
        XCTAssertEqual(scenes[0].lines[1].text, "I know. Traffic.")
    }

    func testSluglinesStartNewScenes() {
        let sides = """
        INT. CAFÉ — DAY

        MAYA
        You're late.

        ARJUN
        I know.

        CUT TO:

        EXT. STREET — NIGHT

        ARJUN
        Wait!
        """
        let scenes = ScriptParser.parseScenes(from: sides, myRole: "Arjun")
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes.map(\.title), ["Scene 1", "Scene 2"])
        XCTAssertEqual(scenes.map(\.number), [1, 2])
        XCTAssertEqual(scenes[0].heading, "INT. CAFÉ — DAY")
        XCTAssertEqual(scenes[1].heading, "EXT. STREET — NIGHT")
        XCTAssertEqual(scenes[0].lines.count, 2)
        XCTAssertEqual(scenes[1].lines.map(\.text), ["Wait!"])
    }

    func testSceneHeadersStartNewScenes() {
        let sides = """
        SCENE 1
        MAYA: Hi.
        ARJUN: Hello.
        Scene 2:
        MAYA: Bye.
        """
        let scenes = ScriptParser.parseScenes(from: sides, myRole: "Maya")
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[1].lines.map(\.text), ["Bye."])
        XCTAssertTrue(scenes[1].lines[0].isMine)
    }

    func testDialogueThatStartsWithSceneIsNotAHeading() {
        XCTAssertFalse(ScriptParser.isSceneHeading("Scene 2 was better."))
        XCTAssertTrue(ScriptParser.isSceneHeading("SC. 14A — KITCHEN"))
        XCTAssertTrue(ScriptParser.isSceneHeading("INT/EXT CAR - MOVING"))
        XCTAssertFalse(ScriptParser.isSceneHeading("Int. was the word she used."))
    }

    func testNothingReadableGivesNoScenes() {
        XCTAssertTrue(ScriptParser.parseScenes(from: "Please send your tape by Friday.", myRole: "Maya").isEmpty)
    }

    func testRoleCanBeCorrectedAfterScenesWereParsed() {
        let parsed = ScriptParser.parseScenes(from: """
        MAYA
        I have the letter.

        MAYA
        I still have it.

        ARJUN
        Give it to me.
        """, myRole: "Female Lead")
        XCTAssertFalse(parsed[0].lines[0].isMine)

        let corrected = ScriptParser.reclassify(parsed, myRole: "Maya")
        XCTAssertTrue(corrected[0].lines[0].isMine)
        XCTAssertTrue(corrected[0].lines[1].isMine)
        XCTAssertFalse(corrected[0].lines[2].isMine)
    }

    func testActionLinesAndParentheticalsAreNotAttachedToDialogue() {
        let sides = """
        INT. KITCHEN — DAY
        Maya sits at the counter, nervously tapping her fingers.

        MAYA
        (whispers)
        I don't think we should do this.

        Maya looks away, fighting back tears.

        ARJUN
        Why not?

        Arjun walks over and takes her hand.

        MAYA
        Because it's crazy.
        """
        let scenes = ScriptParser.parseScenes(from: sides, myRole: "Maya")
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.count, 3)
        XCTAssertEqual(scenes[0].lines[0].character, "Maya")
        XCTAssertEqual(scenes[0].lines[0].text, "I don't think we should do this.")
        XCTAssertTrue(scenes[0].lines[0].isMine)

        XCTAssertEqual(scenes[0].lines[1].character, "Arjun")
        XCTAssertEqual(scenes[0].lines[1].text, "Why not?")
        XCTAssertFalse(scenes[0].lines[1].isMine)

        XCTAssertEqual(scenes[0].lines[2].character, "Maya")
        XCTAssertEqual(scenes[0].lines[2].text, "Because it's crazy.")
        XCTAssertTrue(scenes[0].lines[2].isMine)
    }

    func testInlineParentheticalsAreStrippedFromDialogue() {
        let sides = """
        MAYA: I can't do this (crying) anymore.
        ARJUN: Please (he sighs) listen to me.
        """
        let scenes = ScriptParser.parseScenes(from: sides, myRole: "Maya")
        XCTAssertEqual(scenes[0].lines[0].text, "I can't do this anymore.")
        XCTAssertEqual(scenes[0].lines[1].text, "Please listen to me.")
    }
}
