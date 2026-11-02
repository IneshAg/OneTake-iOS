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
        var draft = NoticeParser.parse(text)
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
        var draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Escape Plan")
        XCTAssertEqual(draft.castingOffice, "Ankita Bajaj Casting")
        XCTAssertTrue(draft.asks.contains("Location: Bengaluru"))
        XCTAssertTrue(draft.asks.contains("Email: casting2cast@gmail.com"))
        XCTAssertEqual(draft.candidateRoles, ["Male Actor (20-40 years)", "Female Actor (22-60 years)"])
        XCTAssertTrue(draft.role.isEmpty)
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
        var draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Pilgrimage")
        XCTAssertFalse(draft.candidateRoles.contains("Multiple Roles"))
        XCTAssertFalse(draft.candidateRoles.contains("Setting"))
        XCTAssertFalse(draft.candidateRoles.contains("Casting Sides"))
        XCTAssertEqual(draft.candidateRoles, ["Noor", "Maryam", "Nadia", "Sosan", "Fatima"])
        XCTAssertTrue(draft.role.isEmpty) // When multiple characters exist, app prompts the user to pick their role
        draft.role = "Noor"
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
        XCTAssertFalse(allChars.contains("Pilgrimage"))
        XCTAssertEqual(Set(allChars), Set(["Noor", "Maryam"]))
    }

    func testNoSluglineInProjectColumn() {
        let text = """
        INT. COFFEE SHOP - DAY
        MAYA
        Hey, did you get my email?

        ARJUN
        Yeah, I saw it.
        """
        let draft = NoticeParser.parse(text)
        // A scene slugline must NEVER be mapped into the project column
        XCTAssertTrue(draft.project.isEmpty, "Project should remain empty when only a slugline is present, found: \(draft.project)")
        XCTAssertTrue(draft.missingRequiredDetails.contains("project"))
    }

    func testNoShootDateInAuditionDeadline() {
        let text = """
        CASTING CALL
        Project: The Silent Valley
        Role: Detective Roy
        Notice Published: October 1, 2026
        Shoot Dates: December 10-20, 2026
        Rehearsals: November 25, 2026
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "The Silent Valley")
        XCTAssertEqual(draft.role, "Detective Roy")
        // Shoot and rehearsal dates must NEVER be set as the audition due date
        XCTAssertNil(draft.due, "Shoot or rehearsal date should not be parsed as audition deadline")
        XCTAssertTrue(draft.missingRequiredDetails.contains("due date"))
    }

    func testDeadlineKeywordExtractedAccurately() {
        let text = """
        Project: The Silent Valley
        Role: Detective Roy
        Shoot Dates: December 10-20, 2026
        Self-tape due by November 5, 2026
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "The Silent Valley")
        XCTAssertEqual(draft.role, "Detective Roy")
        XCTAssertNotNil(draft.due)
        if let due = draft.due {
            let cal = Calendar(identifier: .gregorian)
            XCTAssertEqual(cal.component(.month, from: due), 11)
            XCTAssertEqual(cal.component(.day, from: due), 5)
        }
    }

    func testNoDialogueWordsInAsksRequirements() {
        let text = """
        Project: Cabin Fever
        Role: John
        INT. CABIN - DAY
        JOHN
        Look at that beautiful landscape out there. She's introverted, you know.
        I have a picture of her from years ago.
        """
        let draft = NoticeParser.parse(text)
        // Screenplay action lines or dialogue mentioning landscape, picture, introverted
        // must NEVER trigger audition asks requirements
        XCTAssertFalse(draft.asks.contains("Landscape"))
        XCTAssertFalse(draft.asks.contains("Intro video"))
        XCTAssertFalse(draft.asks.contains("Headshots"))
    }

    func testNoActingDescriptionsInCandidateRoles() {
        let text = """
        We are looking for passionate, grounded actors for an upcoming feature film.
        Seeking authentic performers.
        Character: Arjun
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.role, "Arjun")
        XCTAssertFalse(draft.candidateRoles.contains(where: { $0.lowercased().contains("passionate") }))
        XCTAssertFalse(draft.candidateRoles.contains(where: { $0.lowercased().contains("authentic") }))
    }

    func testCleansRoleWithTrailingDescription() {
        let text = """
        Project: Horizon
        Role: Maya, 20s, an ambitious young painter who struggles with self-doubt
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Horizon")
        XCTAssertEqual(draft.role, "Maya")
    }

    func testProjectTitleWithTrailingRole() {
        let text = """
        Project: The Last Summer - Role of Maya
        Role: Maya
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "The Last Summer")
        XCTAssertEqual(draft.role, "Maya")
    }

    func testCastingOfficeNotPollutedByNoticeHeadlines() {
        let text = """
        URGENT CASTING
        Commercial Casting Bengaluru
        Casting by: Nina Patel
        Project: Fresh Mornings
        Role: Mother
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.castingOffice, "Nina Patel")
        XCTAssertFalse(draft.castingOffice.lowercased().contains("urgent"))
        XCTAssertFalse(draft.castingOffice.lowercased().contains("commercial"))
    }

    func testSubmissionUrlDetection() {
        let text = """
        Project: Pilgrimage
        Role: Noor
        Submit your tape via the link at: kalnaga.com/pilgrimage/casting.html
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.destination, .emailOrLink)
        XCTAssertEqual(draft.destinationDetail, "kalnaga.com/pilgrimage/casting.html")
    }

    func testGoogleDriveSidesLinkDetection() {
        let text = """
        CASTING CALL
        Project: Crimson Tide
        Role: Captain Vance
        Sides link: https://drive.google.com/drive/folders/1A2B3C4D5E6F7G
        Due: Nov 15, 2026
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Crimson Tide")
        XCTAssertEqual(draft.role, "Captain Vance")
        XCTAssertEqual(draft.sidesLink, "https://drive.google.com/drive/folders/1A2B3C4D5E6F7G")
        // Drive link for sides must NOT be treated as the submission destination
        XCTAssertNil(draft.destinationDetail)
        XCTAssertFalse(draft.missingRequiredDetails.contains("script sides"))
    }

    func testSidesLinkAndSubmissionFormCoexistInCorrectColumns() {
        let text = """
        Project: Monsoon Memories
        Role: Rahul
        Download sides from Google Drive: https://drive.google.com/file/d/12345/view
        Self-tape due by November 20, 2026
        Submit tape and details via Google Form: https://forms.gle/xyzAuditionForm
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "Monsoon Memories")
        XCTAssertEqual(draft.role, "Rahul")
        // Sides link in sides column
        XCTAssertEqual(draft.sidesLink, "https://drive.google.com/file/d/12345/view")
        // Submission form in destination column
        XCTAssertEqual(draft.destinationDetail, "https://forms.gle/xyzAuditionForm")
        XCTAssertEqual(draft.destination, .emailOrLink)
        // Neither column pollutes the other
        XCTAssertNotEqual(draft.sidesLink, draft.destinationDetail)
    }

    func testDropboxSidesLinkDetection() {
        let text = """
        Project: The Lost City
        Role: Elena
        Sides attached at: https://dropbox.com/s/sample_sides.pdf
        Email tape to: casting@thelostcity.com
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.sidesLink, "https://dropbox.com/s/sample_sides.pdf")
        XCTAssertEqual(draft.destinationDetail, "casting@thelostcity.com")
        XCTAssertFalse(draft.missingRequiredDetails.contains("script sides"))
    }

    func testPrecedingTextDeterminesDriveUploadVsDriveSides() {
        let text = """
        CASTING CALL
        Project: The Silent Valley
        Role: Detective Roy

        Download sides and scene dialogue from:
        https://drive.google.com/drive/folders/sidesPacket789

        Upload your self-tape video to Google Drive:
        https://drive.google.com/drive/folders/uploadTapes123
        """
        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "The Silent Valley")
        XCTAssertEqual(draft.role, "Detective Roy")
        // Both are Google Drive links! Preceding text correctly separates sides from submission upload:
        XCTAssertEqual(draft.sidesLink, "https://drive.google.com/drive/folders/sidesPacket789")
        XCTAssertEqual(draft.destinationDetail, "https://drive.google.com/drive/folders/uploadTapes123")
        XCTAssertEqual(draft.destination, .emailOrLink)
    }

    func testShortenedUrlClassifiedByPrecedingText() {
        let text = """
        Project: Secret Garden
        Role: Mary

        Audition sides link:
        https://bit.ly/secret-garden-sides

        Submit your tape here:
        https://bit.ly/secret-garden-upload
        """
        let draft = NoticeParser.parse(text)
        // Both are bit.ly links! Preceding text classifies them accurately:
        XCTAssertEqual(draft.sidesLink, "https://bit.ly/secret-garden-sides")
        XCTAssertEqual(draft.destinationDetail, "https://bit.ly/secret-garden-upload")
        XCTAssertEqual(draft.destination, .emailOrLink)
    }
}
