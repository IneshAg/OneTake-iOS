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
        XCTAssertEqual(NoticeParser.parse("No scene count here.").scenes, 0)
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

    func testParsesCastingCallFlyerWithoutSides() {
        let text = """
        Casting
        CALL
        BENGALURU
        We are looking for male and female actors for an upcoming project.
        8
        Male Age:
        20-40 years
        Female Age:
        22-60 years
        Location:
        Bengaluru
        Mail us on casting2cast@gmail.com or DM us
        Mention "Escape Plan" in the subject
        Ankita Bajaj CASTING
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Escape Plan")
        XCTAssertEqual(draft.castingOffice, "Ankita Bajaj Casting")
        XCTAssertTrue(draft.asks.contains("Location: Bengaluru"))
        XCTAssertTrue(draft.asks.contains("Email: casting2cast@gmail.com"))
        XCTAssertEqual(draft.candidateRoles, ["Male Actor (20-40 years)", "Female Actor (22-60 years)"])
        XCTAssertEqual(draft.role, "Male Actor (20-40 years)")
        XCTAssertFalse(draft.hasSides)
        XCTAssertEqual(draft.scenes, 0)
        XCTAssertTrue(ScriptParser.parseScenes(from: text, myRole: draft.role).isEmpty)
        XCTAssertTrue(ScriptParser.extractCharacters(from: text).isEmpty)
    }

    func testParsesPilgrimageCastingSidesPacket() {
        let text = """
        PILGRIMAGE
        CASTING SIDES
        Humaira Ghilzai & Bridgette Dutta Portman
        Director: Khaled Abol Naga (Kal)
        The Lab at Georgetown University · November 2026
        HOW TO USE THESE SIDES
        Each side has been selected to reveal character, range, and presence within 1–2
        minutes of screen time. Please read all instructions on your character's page before
        recording.
        Slate first. At the top of your video, look directly into the camera and state your name,
        pronouns, the role you are reading for, and your city.
        Video format. Horizontal (landscape), MP4, 1080p or 720p preferred. Maximum
        500MB. Good light on your face, quiet background. No production quality required.
        If reading for multiple roles, submit a separate video per character.
        Dialogue sides (Nadia). Nadia's sides include a brief dialogue exchange. Simply skip
        or pause over the other character's lines — the director will read between the lines.
        Submit your tape via the link at: kalnaga.com/pilgrimage/casting.html
        THE CHARACTERS IN THIS DOCUMENT
        NOOR — Page 2
        MARYAM — Page 3
        NADIA — Page 4
        SOSAN — Page 5
        FATIMA — Page 6
        NOOR · She/her · Early 60s · Afghan American
        Director note: What I'm looking for...
        SLATE INSTRUCTION Before beginning, look directly into camera and state: your full name · your
        pronouns · the role you are reading for (NOOR) · your location. Maximum total video: 2 minutes.
        THE SIDE — Noor's Confession (Act II, Scene 4)
        Setting: At the Kaaba, Mecca. Noor addresses Maryam directly for the first time.
        You know I've called you my miracle child, Maryam. I had such trouble conceiving.
        I thought it was my fault, that I was the cause. But I wasn't.
        MARYAM · She/her · Mid-30s · Afghan American
        Director note: Maryam's comedy...
        SLATE INSTRUCTION Before beginning, look directly into camera and state: your full name · your
        pronouns · the role you are reading for (MARYAM) · your location.
        SIDE A — The Phone Call (Act I, Scene 5)
        Setting: Hotel lobby, on the phone with her assistant Candace.
        [speaking on phone]
        Candace, I'm about to embark on a journey that Prophet Muhammad made in 632.
        SIDE B — The Aftermath (Act II, Scene 4)
        Setting: Hotel room in Mecca.
        I can't talk to her right now.
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Pilgrimage")
        XCTAssertFalse(draft.candidateRoles.contains("Multiple Roles"))
        XCTAssertFalse(draft.candidateRoles.contains("Setting"))
        XCTAssertFalse(draft.candidateRoles.contains("Casting Sides"))
        XCTAssertEqual(draft.candidateRoles, ["Noor", "Maryam", "Nadia", "Sosan", "Fatima"])
        XCTAssertEqual(draft.role, "Noor")

        let noorScenes = ScriptParser.parseScenes(from: text, myRole: "Noor")
        XCTAssertEqual(noorScenes.count, 1)
        XCTAssertTrue(noorScenes[0].heading.contains("Noor's Confession"))
        XCTAssertEqual(noorScenes[0].lines.first?.character, "Noor")
        XCTAssertTrue(noorScenes[0].lines.first?.isMine == true)

        let maryamScenes = ScriptParser.parseScenes(from: text, myRole: "Maryam")
        XCTAssertEqual(maryamScenes.count, 2)
        XCTAssertTrue(maryamScenes[0].heading.contains("Side A"))
        XCTAssertTrue(maryamScenes[1].heading.contains("Side B"))
        XCTAssertEqual(maryamScenes[0].lines.first?.character, "Maryam")
        XCTAssertTrue(maryamScenes[0].lines.first?.isMine == true)

        let allChars = ScriptParser.extractCharacters(from: text)
        XCTAssertFalse(allChars.contains("Setting"))
        XCTAssertFalse(allChars.contains("Casting Sides"))
        XCTAssertFalse(allChars.contains("How To Use These Sides"))
    }
}
