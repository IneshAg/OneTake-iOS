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

    func testLongMonologueIsDividedIntoDeliverableThoughtUnits() {
        let monologue = """
        NOOR
        You know I've called you my miracle child, Maryam. I had such trouble conceiving.
        I thought it was my fault, that I was the cause. But I wasn't.
        Right after the Russians invaded Afghanistan, they were rounding up anyone who
        was not a communist sympathizer. They took your father—my husband—in for
        interrogation. People didn't return home to their families after these types of
        arrests. After two weeks of no information, no answers, I thought the worst.
        """
        let scenes = ScriptParser.parseScenes(from: monologue, myRole: "Noor")
        XCTAssertEqual(scenes.count, 1)
        // Instead of 1 gigantic unreadable 78-word wall of text, it should be divided into digestible beats
        XCTAssertGreaterThan(scenes[0].lines.count, 2)
        for line in scenes[0].lines {
            XCTAssertEqual(line.character, "Noor")
            XCTAssertTrue(line.isMine)
            let wordCount = line.text.split(separator: " ").count
            XCTAssertLessThanOrEqual(wordCount, 25, "Line should be a digestible teleprompter beat: \(line.text)")
        }
    }

    func testProtectedAbbreviationsDoNotSplitSentences() {
        let text = "Dr. Stone met with Lt. Col. Davis at 6 p.m. in the U.S. capital."
        let units = ScriptParser.divideIntoThoughtUnits(text)
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0], "Dr. Stone met with Lt. Col. Davis at 6 p.m. in the U.S. capital.")
    }
}
