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



    func testParsesPilgrimageWebCastingPageFields() {

        let text = """

        Casting Call — Pilgrimage | Georgetown University Theater Lab

        Casting Call For The New Play

        Pilgrimage

        Stage Reading Event:

        November 13–16, 2026

        at The Lab at Georgetown University

        Director: Khaled Abol Naga (Kal)

        The Characters

        Noor

        Maryam

        Nadia

        Sosan

        Fatima

        Video Submission Specs

        Orientation: Horizontal / Landscape only

        Deadline: October 15, 2026.

        Upload your video to YouTube, Vimeo, or Google Drive.

        Questions: kal@kalnaga.com

        """



        let draft = NoticeParser.parse(text)

        XCTAssertEqual(draft.project, "Pilgrimage")

        XCTAssertEqual(Set(draft.candidateRoles), Set(["Noor", "Maryam", "Nadia", "Sosan", "Fatima"]))

        XCTAssertFalse(draft.candidateRoles.contains("This Role"))

        XCTAssertNotNil(draft.due)

        XCTAssertTrue(draft.asks.contains("Landscape"))

        XCTAssertEqual(draft.destinationDetail, "kal@kalnaga.com")

        XCTAssertEqual(draft.castingOffice, "")

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



    func testParsesCastingBayFlyerWithBrowserChromeNoise() {

        let text = """

        • - 100 Days Of Sv X Ineshag/Onetal X * History.

        Casting Bay'

        - CASTING CALL

        NOW

        CASTING

        Casting Call: Ad Film

        Casting Mumbai-based actors and fresh faces for an ad film.

        AGE

        18 - 23 years

        AGE

        45 - 55 years

        GENDER

        Female

        GENDER

        Male

        LANGUAGES

        Hindi, English

        LOCATION

        Mumbai

        If you fit the brief, apply at castingbay.app with

        an updated profile, recent photographs, and an

        introduction video.

        AD FILM

        SCAN AND APPLY

        castingbay.app

        """

        let draft = NoticeParser.parse(text)

        XCTAssertEqual(draft.project, "Ad Film")

        XCTAssertEqual(draft.castingOffice, "Casting Bay")

        XCTAssertEqual(draft.projectType, "Commercial")

        XCTAssertTrue(draft.candidateRoles.contains("Female (18 - 23 years)"))

        XCTAssertTrue(draft.candidateRoles.contains("Male (45 - 55 years)"))

        XCTAssertTrue(draft.asks.contains("Intro video"))

        XCTAssertTrue(draft.asks.contains("Headshots"))

        XCTAssertTrue(draft.asks.contains("Location: Mumbai"))

        XCTAssertFalse(draft.project.contains("100 Days"))

        XCTAssertFalse(draft.project.contains("History"))

        XCTAssertFalse(draft.castingOffice.contains("History"))

    }



    func testNoticeOCRResolvesSecurityScopedFileAndExtractsText() async {

        let pdfData = NSMutableData()

        UIGraphicsBeginPDFContextToData(pdfData, CGRect(x: 0, y: 0, width: 300, height: 400), nil)

        UIGraphicsBeginPDFPage()

        let text = "Audition Notice\nRole: Detective Roy\nProject: City Lights\nCasting: Paramount"

        let font = UIFont.systemFont(ofSize: 14)

        (text as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: font])

        UIGraphicsEndPDFContext()



        let tempInputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import_\(UUID().uuidString).pdf")

        try? (pdfData as Data).write(to: tempInputURL)

        defer { try? FileManager.default.removeItem(at: tempInputURL) }



        let resolved = NoticeOCR.resolveSecurityScopedFile(at: tempInputURL)

        defer { resolved.cleanup() }



        let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)

        XCTAssertNotNil(extracted)

        XCTAssertTrue(extracted?.contains("Detective Roy") == true)

        XCTAssertTrue(NoticeOCR.looksReadable(extracted ?? ""))

    }



    func testExtractCharacterDescriptionWithDemographicsAndDirectorNotes() {

        let text = """

        PILGRIMAGE

        CASTING SIDES

        Director: Khaled Abol Naga (Kal)



        THE CHARACTERS IN THIS DOCUMENT

        NOOR — Page 2

        MARYAM — Page 3



        NOOR  ·  She/her  ·  Early 60s  ·  Afghan American

        Director note: What I'm looking for: the weight of a woman who has carried this secret for decades.

        SLATE INSTRUCTION  Before beginning, look directly into camera...

        """



        let noorNotes = NoticeParser.extractCharacterDescription(for: "Noor", in: text)

        XCTAssertNotNil(noorNotes)

        XCTAssertTrue(noorNotes?.contains("NOOR  ·  She/her  ·  Early 60s  ·  Afghan American") == true)

        XCTAssertTrue(noorNotes?.contains("Director note: What I'm looking for: the weight of a woman") == true)

        XCTAssertFalse(noorNotes?.contains("SLATE INSTRUCTION") == true)

        XCTAssertFalse(noorNotes?.contains("Page 2") == true)

    }



    func testDraftMakeAuditionPopulatesCastingAndActorNotes() {

        var draft = NoticeParser.Draft()

        draft.project = "Pilgrimage"

        draft.role = "Noor"

        draft.sourceText = """

        NOOR  ·  She/her  ·  Early 60s  ·  Afghan American

        Director note: Let the pauses breathe. Don't rush the confession.

        """

        draft.actorNotes = "Focus on the subtext of guilt, avoid rushing lines."



        let audition = draft.makeAudition()

        XCTAssertEqual(audition.project, "Pilgrimage")

        XCTAssertEqual(audition.role, "Noor")

        XCTAssertTrue(audition.castingNotes?.contains("NOOR  ·  She/her  ·  Early 60s  ·  Afghan American") == true)

        XCTAssertTrue(audition.castingNotes?.contains("Director note: Let the pauses breathe.") == true)

        XCTAssertEqual(audition.actorNotes, "Focus on the subtext of guilt, avoid rushing lines.")

    }



    func testExtractSidesFromScriptPDFAndParseScenes() async {

        let pdfData = NSMutableData()

        UIGraphicsBeginPDFContextToData(pdfData, CGRect(x: 0, y: 0, width: 612, height: 792), nil)

        UIGraphicsBeginPDFPage()

        let scriptText = """

        SCENE 1 - INT. COFFEE SHOP - DAY



        MAYA

        Did you find the envelope?



        DETECTIVE ROY

        Not yet. But we know where he hid the key.



        MAYA

        Then we're running out of time.

        """

        let font = UIFont.systemFont(ofSize: 14)

        (scriptText as NSString).draw(at: CGPoint(x: 36, y: 50), withAttributes: [.font: font])

        UIGraphicsEndPDFContext()



        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sides_\(UUID().uuidString).pdf")

        try? (pdfData as Data).write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }



        let resolved = NoticeOCR.resolveSecurityScopedFile(at: tempURL)

        defer { resolved.cleanup() }



        let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)

        XCTAssertNotNil(extracted)

        XCTAssertTrue(extracted?.contains("MAYA") == true)

        XCTAssertTrue(extracted?.contains("DETECTIVE ROY") == true)



        let parsed = ScriptParser.parseScenes(from: extracted ?? "", myRole: "Maya")

        XCTAssertFalse(parsed.isEmpty)

        let lines = parsed.flatMap(\.lines)

        XCTAssertEqual(lines.count, 3)

        XCTAssertEqual(lines.filter(\.isMine).count, 2)

    }



    func testExtractSidesFromPlainTextFile() async {

        let scriptText = """

        SCENE 2 - EXT. ROOFTOP - NIGHT



        ALEX

        Look down there.



        SAM

        It's completely clear. Let's move.

        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sides_\(UUID().uuidString).txt")

        try? scriptText.write(to: tempURL, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tempURL) }



        let resolved = NoticeOCR.resolveSecurityScopedFile(at: tempURL)

        defer { resolved.cleanup() }



        let extracted = await NoticeOCR.extractText(fromFileAt: resolved.url)

        XCTAssertNotNil(extracted)

        XCTAssertTrue(extracted?.contains("ALEX") == true)



        let parsed = ScriptParser.parseScenes(from: extracted ?? "", myRole: "Alex")

        XCTAssertFalse(parsed.isEmpty)

        XCTAssertEqual(parsed.flatMap(\.lines).count, 2)

    }



    func testLooksReadableRejectsCorruptBinaryNoiseAndAcceptsShortDialogue() {

        // Valid short dialogue side

        let validDialogue = "NOOR\nI was waiting for you."

        XCTAssertTrue(NoticeOCR.looksReadable(validDialogue))



        // Corrupt binary / random garbage noise

        let corruptBytes = "\u{0000}\u{0001}\u{0002}%%PDF-1.4\u{001F}\u{007F}###@@@$$$%%%^^^&&&***\u{0000}\u{0003}\u{0004}"

        XCTAssertFalse(NoticeOCR.looksReadable(corruptBytes))



        // Empty / whitespace

        XCTAssertFalse(NoticeOCR.looksReadable("   \n\t   "))

        XCTAssertFalse(NoticeOCR.looksReadable("A"))

    }



    func testParsesGreaseAuditionSidesBreakdownAndDialogue() {

        let text = """

        Audition Sides

        A message from the Director

        Grease is such a fun production set all around the stereotypes of high school.



        Audition Sides Page Breakdown

        Please familiarise yourself with all sides in which your character's name is notated next to.

        SANDY, DANNY, PATTY ACT ONE, SCENE SIX PAGE 3

        SANDY ACT TWO, SCENE FIVE PAGE 7

        DANNY ACT ONE, SCENE ONE PAGE 10

        SONNY ACT ONE, SCENE ONE PAGE 11

        JAN, ROGER ACT ONE, SCENE SEVEN PAGE 13

        KENICKIE ACT ONE, SCENE ONE PAGE 15

        DOODY ACT ONE, SCENE THREE PAGE 17

        RIZZO ACT ONE, SCENE FIVE PAGE 18

        RIZZO ACT TWO, SCENE SIX PAGE 21

        MARTY ACT ONE, SCENE FOUR PAGE 24

        FRENCHY ACT TWO, SCENE FOUR PAGE 27

        FRENCHY ACT ONE, SCENE FOUR PAGE 28

        LYNCH ACT ONE, SCENE ONE PAGE 29

        VINCE FONTAINE ACT ONE, SCENE ONE PAGE 30

        VINCE FONTAINE ACT TWO, SCENE ONE PAGE 31

        EUGENE, CHA - CHA ACT TWO, SCENE ONE PAGE 32



        ACT ONE SCENE SIX

        Rydell High School Gymnasium

        SANDY:

        Do a split, give a yell

        Throw a fit for old Rydell

        DANNY:

        Hiya, Sandy.

        SANDY:

        Oh. Hi.

        """

        let draft = NoticeParser.parse(text)

        XCTAssertEqual(draft.project, "Grease")

        XCTAssertTrue(draft.candidateRoles.contains("Sandy"))

        XCTAssertTrue(draft.candidateRoles.contains("Danny"))

        XCTAssertTrue(draft.candidateRoles.contains("Patty"))

        XCTAssertTrue(draft.candidateRoles.contains("Rizzo"))

        XCTAssertTrue(draft.candidateRoles.contains("Vince Fontaine"))



        let scenes = ScriptParser.parseScenes(from: text, myRole: "Sandy")

        XCTAssertFalse(scenes.isEmpty)

        let sandyLines = scenes[0].lines.filter(\.isMine)

        XCTAssertEqual(sandyLines.count, 2)

        XCTAssertEqual(sandyLines[0].text, "Do a split, give a yell Throw a fit for old Rydell")

        XCTAssertEqual(sandyLines[1].text, "Oh. Hi.")

    }



    func testParsesChicagoGenderedAuditionSidesAndMonologues() {

        let text = """

        AUDITION SIDES:

        Choose one of these sides. Memorization is required.

        Now look - "ROXIE ROCKS CHICAGO."



        For Female Identifying:

        Roxie:

        You wanna know something? I always wanted my name in the paper. Before Amos came along, I used to date this well-to-do ugly bootlegger.



        Velma:

        My sister Veronica and I did this double act and my husband, Charlie, traveled around with us.



        Mama Morton:

        Ah, Baby, you can't buy that kind of publicity. You took care of Mama and Mama took care of you.



        For Male Identifying:

        Billy:

        Hey, and pipe down on the swearin'. From here on in, you say nothing rougher than, "Oh, dear." Get it?



        Amos:

        And I believed her! That cheap little tramp. So she was two-timing me, huh?



        For Any Gender:

        Mary Sunshine:

        I don't see how you could possibly delay the trial another second, Mr. Flynn!

        """

        let draft = NoticeParser.parse(text)

        XCTAssertEqual(draft.project, "Chicago")

        XCTAssertTrue(draft.candidateRoles.contains("Roxie"))

        XCTAssertTrue(draft.candidateRoles.contains("Velma"))

        XCTAssertTrue(draft.candidateRoles.contains("Mama Morton"))

        XCTAssertTrue(draft.candidateRoles.contains("Billy"))

        XCTAssertTrue(draft.candidateRoles.contains("Amos"))

        XCTAssertTrue(draft.candidateRoles.contains("Mary Sunshine"))



        let roxieScenes = ScriptParser.parseScenes(from: text, myRole: "Roxie")

        XCTAssertFalse(roxieScenes.isEmpty)

        let roxieLines = roxieScenes.flatMap(\.lines).filter(\.isMine)

        XCTAssertEqual(roxieLines.count, 1)

        XCTAssertTrue(roxieLines[0].text.contains("I always wanted my name in the paper"))

    }



    func testParsesInstagramFlyerWithDemographicsAndDeadline() {

        let text = """

        BENGALURU

        We are looking for male and female actors for an upcoming project.



        Male Age:

        20-40 years



        Female Age:

        22-60 years



        Location:

        Bengaluru



        Mention "Escape Plan" in the subject

        Email: ojas@mccc.in

        Deadline: 5 NOVEMBER 2026

        """

        let draft = NoticeParser.parse(text)

        XCTAssertEqual(draft.project, "Escape Plan")

        XCTAssertEqual(draft.castingOffice, "Mukesh Chhabra Casting Company (MCCC)")

        XCTAssertTrue(draft.asks.contains("Location: Bengaluru"))

        XCTAssertTrue(draft.asks.contains("Email: ojas@mccc.in"))

        XCTAssertTrue(draft.candidateRoles.contains("Male Actor (20-40 years)"))

        XCTAssertTrue(draft.candidateRoles.contains("Female Actor (22-60 years)"))

        XCTAssertNotNil(draft.due)

    }
    @MainActor
    func testAppStoreAutofillSuggestions() {
        let store = AppStore()
        var a1 = Audition(project: "The White Lotus", role: "Tanya McQuoid")
        a1.castingOffice = "Meredith Tucker"
        var a2 = Audition(project: "Succession", role: "Shiv Roy")
        a2.castingOffice = "Francine Maisler"
        store.auditions = [a1, a2]

        // Most recent first
        XCTAssertEqual(store.projectSuggestions.first, "Succession")
        XCTAssertTrue(store.projectSuggestions.contains("The White Lotus"))

        XCTAssertEqual(store.roleSuggestions.first, "Shiv Roy")
        XCTAssertTrue(store.roleSuggestions.contains("Tanya McQuoid"))

        XCTAssertTrue(store.castingOfficeSuggestions.contains("Francine Maisler"))
        XCTAssertTrue(store.castingOfficeSuggestions.contains("Meredith Tucker"))
        XCTAssertTrue(store.castingOfficeSuggestions.contains("Mukesh Chhabra Casting Company (MCCC)"))
    }

    @MainActor
    func testAppStoreCommitAuditionDraftDirectTransition() {
        let store = AppStore()
        var draft = NoticeParser.Draft(project: "Severance", role: "Mark Scout", due: .now.addingTimeInterval(86400))
        draft.castingOffice = "Rachel Tenner"

        // 1. Commit with reader plan: later -> navigates directly to .auditionDetail
        store.commitAuditionDraft(draft, readerAudioPlan: .later)
        XCTAssertEqual(store.auditions.count, 1)
        XCTAssertEqual(store.auditions.first?.project, "Severance")
        XCTAssertEqual(store.auditions.first?.role, "Mark Scout")
        if case .auditionDetail(let id) = store.pendingRouteAfterAdd {
            XCTAssertEqual(id, store.auditions.first?.id)
        } else {
            XCTFail("Expected pendingRouteAfterAdd to be .auditionDetail")
        }

        // 2. Commit with reader lines and reader plan: recordNow -> navigates to .reader
        let scriptWithReader = """
        MARK
        I don't know what's happening down there.

        COBIE
        You don't need to know, Mark. Just do the work.
        """
        var draftWithReader = NoticeParser.Draft(project: "Severance S2", role: "Mark", due: .now.addingTimeInterval(86400))
        draftWithReader.sourceText = scriptWithReader
        draftWithReader.customScenes = ScriptParser.parseScenes(from: scriptWithReader, myRole: "Mark")

        store.commitAuditionDraft(draftWithReader, readerAudioPlan: .recordNow)
        XCTAssertEqual(store.auditions.count, 2)
        if case .reader(let id, let sceneIndex) = store.pendingRouteAfterAdd {
            XCTAssertEqual(id, store.auditions.last?.id)
            XCTAssertEqual(sceneIndex, 0)
        } else {
            XCTFail("Expected pendingRouteAfterAdd to be .reader for recordNow plan")
        }
    }

    @MainActor
    func testReplaceSidesReaderAudioDetectionAndRouting() {
        let store = AppStore()
        var audition = Audition(project: "Succession", role: "Tom Wambsgans")
        store.add(audition)

        let script = """
        TOM
        Greg, you can't make a Tomelette without breaking some Greggs.

        GREG
        I really don't like that phrase, Tom.
        """

        let scenes = ScriptParser.parseScenes(from: script, myRole: "Tom Wambsgans")
        store.replaceSides(of: audition.id, with: scenes, sourceText: script)

        guard let updated = store.audition(audition.id) else {
            XCTFail("Audition not found")
            return
        }

        XCTAssertEqual(updated.scenes.count, 1)
        let readerLines = updated.scenes[0].lines.filter { !$0.isMine }
        XCTAssertEqual(readerLines.count, 1)
        XCTAssertEqual(readerLines.first?.character.capitalized, "Greg")

        // Test reader cue routing
        let firstSceneWithReader = updated.scenes.indices.first(where: { !updated.scenes[$0].lines.filter({ !$0.isMine }).isEmpty })
        XCTAssertEqual(firstSceneWithReader, 0)
    }
}
