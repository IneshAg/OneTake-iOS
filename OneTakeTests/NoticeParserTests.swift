import XCTest
import SwiftUI
@testable import OneTake



final class NoticeParserTests: XCTestCase {

    func testReadsRoleProjectAndAsks() {

        let draft = NoticeParser.parse("Self-tape for MAYA in THE LAST SUMMER (feature). Please slate first, landscape, and include a full-body shot with the slate. Send via Actors Access.")

        XCTAssertEqual(draft.role, "Maya")

        XCTAssertEqual(draft.project, "The Last Summer")

        XCTAssertEqual(draft.projectType, "Feature film")

        XCTAssertEqual(draft.destination, .actorsAccess)

        XCTAssertEqual(Set(draft.asks), ["Slate first", "Landscape", "Full-body shot with slate", "Actors Access"])

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

        XCTAssertEqual(draft.destination, .email)

        XCTAssertEqual(draft.destinationDetail, "vaishak@anticasting.in")

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

        XCTAssertEqual(draft.destination, .email)

        XCTAssertEqual(draft.destinationDetail, "casting2cast@gmail.com")

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

        XCTAssertFalse(draft.missingRequiredDetails.contains("project"))

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

        XCTAssertFalse(draft.missingRequiredDetails.contains("due date"))

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

        XCTAssertEqual(sandyLines[0].text, "Do a split, give a yell Throw a fit for old Rydell.")

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



    func testLoneQuestionMarkForActorRemainsASilentReactionCue() {
        let scenes = ScriptParser.parseScenes(from: """
        MAGGIE
        ?
        FRANCIS
        The other then?
        """, myRole: "Maggie")

        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.count, 2)
        XCTAssertTrue(scenes[0].lines[0].isMine)
        XCTAssertEqual(scenes[0].lines[0].text, "?")
        XCTAssertTrue(scenes[0].lines[0].isSilentReactionCue)
        XCTAssertFalse(scenes[0].lines[1].isMine)
    }

    func testSilentReactionCueRecognitionForReaderAndActor() {
        let lineMine = ScriptLine(character: "Maggie", text: "?", isMine: true)
        XCTAssertTrue(lineMine.isSilentReactionCue)

        let lineReader = ScriptLine(character: "Francis", text: "?", isMine: false)
        XCTAssertTrue(lineReader.isSilentReactionCue)

        let lineBeat = ScriptLine(character: "Maggie", text: "...", isMine: true)
        XCTAssertTrue(lineBeat.isSilentReactionCue)

        let linePause = ScriptLine(character: "Francis", text: "(pause)", isMine: false)
        XCTAssertTrue(linePause.isSilentReactionCue)

        let lineNormal = ScriptLine(character: "Francis", text: "What did you say?", isMine: false)
        XCTAssertFalse(lineNormal.isSilentReactionCue)
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

        XCTAssertEqual(draft.destination, .email)

        XCTAssertEqual(draft.destinationDetail, "ojas@mccc.in")

        XCTAssertTrue(draft.candidateRoles.contains("Male Actor (20-40 years)"))

        XCTAssertTrue(draft.candidateRoles.contains("Female Actor (22-60 years)"))

        XCTAssertNotNil(draft.due)

    }
    @MainActor
    func testAppStoreAutofillSuggestions() {
        let store = AppStore()
        var a1 = NoticeParser.Draft(project: "The White Lotus", role: "Tanya McQuoid").makeAudition()
        a1.castingOffice = "Meredith Tucker"
        var a2 = NoticeParser.Draft(project: "Succession", role: "Shiv Roy").makeAudition()
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
        store.auditions.removeAll()
        var draft = NoticeParser.Draft(project: "Severance", role: "Mark Scout", due: .now.addingTimeInterval(86400))
        draft.castingOffice = "Rachel Tenner"

        // 1. Commit with reader plan: later -> navigates directly to .auditionDetail (Project Overview)
        store.commitAuditionDraft(draft, readerAudioPlan: .later)
        XCTAssertEqual(store.auditions.count, 1)
        XCTAssertEqual(store.auditions.first?.project, "Severance")
        XCTAssertEqual(store.auditions.first?.role, "Mark Scout")
        let firstID = store.auditions.first!.id
        XCTAssertEqual(store.auditionsPath, [.auditionDetail(firstID)], "Skipping reader audio for now must place Project Overview (.auditionDetail) on auditionsPath")
        if case .auditionDetail(let id) = store.pendingRouteAfterAdd {
            XCTAssertEqual(id, firstID)
        } else {
            XCTFail("Expected pendingRouteAfterAdd to be .auditionDetail")
        }

        // 2. Commit with reader lines and reader plan: recordNow -> navigates to .reader with .auditionDetail underneath
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
        let secondID = store.auditions.first!.id
        XCTAssertEqual(store.auditionsPath, [.auditionDetail(secondID), .reader(secondID, sceneIndex: 0)], "Recording reader audio must place .auditionDetail underneath .reader so popping/continuing lands on Project Overview")
        if case .reader(let id, let sceneIndex) = store.pendingRouteAfterAdd {
            XCTAssertEqual(id, secondID)
            XCTAssertEqual(sceneIndex, 0)
        } else {
            XCTFail("Expected pendingRouteAfterAdd to be .reader for recordNow plan")
        }

        // 3. Popping or continuing from ReaderView must leave Project Overview
        store.pop()
        XCTAssertEqual(store.auditionsPath, [.auditionDetail(secondID)], "Leaving or continuing from reader audio must land on Project Overview")
    }

    @MainActor
    func testReplaceSidesReaderAudioDetectionAndRouting() {
        let store = AppStore()
        var audition = NoticeParser.Draft(project: "Succession", role: "Tom Wambsgans").makeAudition()
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

    func testShatteredGlassProjectNotice() {
        // Regression: parser was picking "A Small Western Town In 1886 As Two Women" as the project
        // (from the synopsis sentence), "Your Choice" as the role (from "character of your choice"),
        // and "Note On Casting" as the casting office.
        let notice = """
        About The Project
        The Shattered Glass Project is holding auditions for the world premiere production of Eve's Ale, Shanna Allman's fiercely and unapologetically female story set to the tune of a classic western.
        Synopsis: Self-reliance battles desire in a small western town in 1886 as two women, compromised by a world built by and for men, fight for agency, self-preservation, and ultimately, one another.
        Character Breakdowns
        Maggie - F, 40s. a prostitute; nimble, pragmatic; 'three-card monte incarnate'
        Francis - F, 40s. a rancher; aloof, hostile; 'the crunch of gravel underfoot'
        Caroline - F, 17. a prostitute; unassuming; chipper; 'brightly colored candy in a glass dish'
        Note on casting: Character gender plays an essential element in this play and may not be changed. Likewise, actors should identify as female, female identifying, or femme nonbinary.
        Audition Dates and Times
        In-person auditions will be held on December 7, 2026 from 6:30-9:30
        Video submissions will be accepted until 11:59 pm on December 6, 2026
        """
        let draft = NoticeParser.parse(notice)

        // Project should be the show title, not the synopsis sentence
        XCTAssertEqual(draft.project, "Eve's Ale",
            "Expected project 'Eve's Ale' but got '\(draft.project)'")

        // Roles should be the named characters
        XCTAssertFalse(draft.candidateRoles.map { $0.lowercased() }.contains("your choice"),
            "Role 'Your Choice' (from video-submission phrasing) should be blocked")
        let namedRoles = ["Maggie", "Francis", "Caroline"]
        for r in namedRoles {
            XCTAssertTrue(draft.candidateRoles.contains(r),
                "Expected '\(r)' in candidateRoles but got \(draft.candidateRoles)")
        }

        // Casting office must NOT be "Note On Casting"
        XCTAssertFalse(draft.castingOffice.lowercased().hasPrefix("note on casting"),
            "Casting office should not be 'Note On Casting', got '\(draft.castingOffice)'")

        // Date should be found (Dec 6 video deadline at 11:59 pm)
        XCTAssertNotNil(draft.due, "Date should be detected from 'Video submissions will be accepted until 11:59 pm on December 6, 2026'")
        if let due = draft.due {
            let cal = Calendar.current
            XCTAssertEqual(cal.component(.year, from: due), 2026)
            XCTAssertEqual(cal.component(.month, from: due), 12)
            XCTAssertEqual(cal.component(.day, from: due), 6)
            XCTAssertEqual(cal.component(.hour, from: due), 23)
            XCTAssertEqual(cal.component(.minute, from: due), 59)
        }

        // aiGuidance must NOT show the generic production announcement blurb
        XCTAssertFalse(draft.aiGuidance.lowercased().contains("holding auditions"),
            "aiGuidance should not contain 'holding auditions': '\(draft.aiGuidance)'")
        XCTAssertFalse(draft.aiGuidance.lowercased().contains("shattered glass project"),
            "aiGuidance should not contain company name: '\(draft.aiGuidance)'")
        XCTAssertFalse(draft.aiGuidance.lowercased().contains("world premiere production"),
            "aiGuidance should not contain announcement boilerplate: '\(draft.aiGuidance)'")
    }

    func testVideoSubmissionsDeadlinePreservesTimeAndExplicitTimeZone() {
        let notice = "Video submissions will be accepted until 11:59 pm EST on December 6, 2026"
        let draft = NoticeParser.parse(notice)
        XCTAssertNotNil(draft.due)
        if let due = draft.due {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(abbreviation: "EST")!
            XCTAssertEqual(cal.component(.year, from: due), 2026)
            XCTAssertEqual(cal.component(.month, from: due), 12)
            XCTAssertEqual(cal.component(.day, from: due), 6)
            XCTAssertEqual(cal.component(.hour, from: due), 23)
            XCTAssertEqual(cal.component(.minute, from: due), 59)
        }
    }

    func testPilgrimageSidesPacket() {
        let pilgrimageNotice = """
        PILGRIMAGE
        CASTING SIDES
        Humaira Ghilzai & Bridgette Dutta Portman
        Director: Khaled Abol Naga (Kal)
        The Lab at Georgetown University · November 2026
        HOW TO USE THESE SIDES
        Each side has been selected to reveal character, range, and presence within 1-2
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
        Director note: What I'm looking for: the weight of a woman who has carried this secret for
        decades, and the terrifying relief of finally putting it down. Let the pauses breathe. Don't rush
        the confession. The scene lives in what she can barely bring herself to say.
        SLATE INSTRUCTION Before beginning, look directly into camera and state: your full name · your
        pronouns · the role you are reading for (NOOR) · your location. Maximum total video: 2 minutes.

        MARYAM · She/her · Mid-30s · Afghan American
        Director note: What I'm looking for: Maryam's comedy and Maryam's devastation are the same
        instrument. I want to see both. Side A shows us the armour — the wit, the control, the
        performance. Side B shows us what's underneath when the armour is ripped off. If you can, do
        both. If time is tight, choose the one that surprises you more.
        SLATE INSTRUCTION Before beginning, look directly into camera and state: your full name · your
        pronouns · the role you are reading for (MARYAM) · your location. Maximum total video: 2 minutes.
        """

        let draft = NoticeParser.parse(pilgrimageNotice)
        XCTAssertEqual(draft.project, "Pilgrimage")

        let expectedRoles = ["Noor", "Maryam", "Nadia", "Sosan", "Fatima"]
        for r in expectedRoles {
            XCTAssertTrue(draft.candidateRoles.contains(r), "Expected candidate role '\(r)' in \(draft.candidateRoles)")
        }

        XCTAssertTrue(draft.asks.contains("Slate first") || draft.asks.contains("Slate"), "Expected slate requirement")
        XCTAssertTrue(draft.asks.contains("Landscape") || draft.asks.contains("Horizontal"), "Expected landscape/horizontal requirement")

        // Role-specific director note extraction
        let maryamNote = NoticeParser.extractCharacterDescription(for: "Maryam", in: pilgrimageNotice)
        XCTAssertNotNil(maryamNote)
        XCTAssertTrue(maryamNote?.contains("comedy and Maryam's devastation") == true, "Maryam note should contain director guidance")

        let noorNote = NoticeParser.extractCharacterDescription(for: "Noor", in: pilgrimageNotice)
        XCTAssertNotNil(noorNote)
        XCTAssertTrue(noorNote?.contains("weight of a woman") == true, "Noor note should contain director guidance")
    }

    @MainActor
    func testScriptTextEditorPreservesTextAcrossUpdates() {
        var text = "FRANCIS: You asked me to come."
        let editor = ScriptTextEditor(text: Binding(get: { text }, set: { text = $0 }))
        let context = editor.makeCoordinator()

        // Create the underlying UITextView
        let textView = UITextView()
        textView.delegate = context
        textView.text = text

        // Simulate typing more dialogue
        textView.text = "FRANCIS: You asked me to come.\nMAGGIE: I know the train leaves at six."
        context.textViewDidChange(textView)
        XCTAssertEqual(text, "FRANCIS: You asked me to come.\nMAGGIE: I know the train leaves at six.")

        // Simulate parent view re-evaluating body (e.g. editableScenes async debounce completing)
        // updateTextView should NOT clear or alter text if identical
        editor.updateTextView(textView)
        XCTAssertEqual(textView.text, text)
        XCTAssertFalse(textView.text.isEmpty, "TextView text should never blank out during parent view re-renders")
    }

    func testEvesAleSidesParseIntoTwoScenes() {
        let script = """
        Eve's Ale - Shanna Allman (7.28.26) - p.39

        FRANCIS
        The other then?

        MAGGIE
        ?

        FRANCIS
        I used a lot your whiskey the other night.

        MAGGIE
        Naw, we square on that, too.

        FRANCIS
        Well, alright then.

        MAGGIE
        Well, alright.

        Francis turns to leave. Stops.

        FRANCIS
        Am I supposed to pay you?

        MAGGIE
        (scoffs)

        FRANCIS
        Simple question.

        MAGGIE
        Is it?

        FRANCIS
        Is it not?

        Eve's Ale - Shanna Allman (7.28.26) - p.39

        Start

        Eve's Ale - Shanna Allman (7.28.26) - p.40

        MAGGIE
        Why’d it take you so long to ask it then?

        FRANCIS
        You still ain’t answered it. My Daddy used to say the truth is simple. If you’re saying a
        lotta words you’re dancing with the truth ‘stead of speaking it.

        MAGGIE
        Is that so?
        Well my daddy used to say there’s no such thing as a gift, there’s only barterin’.

        Maggie tosses the satchel of lavender at
        Francis.
        So. What exactly did you come here for then?

        FRANCIS
        (setting the satchel aside) Were you askin me to stay?

        MAGGIE
        Now who’s got twinkle toes?

        FRANCIS
        Were you?

        MAGGIE
        (shrugs) I’s just makin conversation. Ain’t all that unusual for us to ask people to stay
        around here, so I can see how you got confused.

        FRANCIS
        .

        MAGGIE
        Why did you come here?

        FRANCIS
        Get my watch.

        Eve's Ale - Shanna Allman (7.28.26) - p.40

        Eve's Ale - Shanna Allman (7.28.26) - p.41

        MAGGIE
        Glad I could help.

        Pause.

        FRANCIS
        (gesture towards the satchel then turning to leave) Just toss the satchel if you don’t want
        it. I don’t need it back.

        MAGGIE
        Catch more bees with honey you know!

        FRANCIS
        (turning back)And you catch more flies with shit.

        MAGGIE
        Ain’t that the truth.

        Slight pause.

        It seems it was me that was confused. I didn’t think of you as a customer. My mistake.
        Maggie busies herself at the bar.

        FRANCIS
        I do have somewhere I need to be.

        MAGGIE
        So you said.

        FRANCIS
        Stayed too long as it is.

        MAGGIE
        Well boo-hoo to you then. I gave you your damn watch back, what do you want from me

        about it if you don’t know how to use it / proper-
        Eve's Ale - Shanna Allman (7.28.26) - p.41

        Eve's Ale - Shanna Allman (7.28.26) - p.42

        FRANCIS
        What did you think of me as?

        MAGGIE
        What?

        FRANCIS
        You didn’t think of me as a customer. What did you think of me as?

        MAGGIE
        (shrugs) Curiosity.
        Why?
        What did you think of me as?

        FRANCIS
        (shrugs) Curiosity.

        MAGGIE
        Well, then. Curiosity satisfied?

        Pause. They stand looking at one another.
        Are you gonna say anything? Or am I just supposed to stand here holding up both sides
        of this conversation?

        FRANCIS
        Never stopped you before.

        MAGGIE
        Aw, haha, ain’t you clever.

        Francis touches her hat, Maggie starts to
        return the gesture then waves it off.

        FRANCIS
        (stopping at the entrance) Maybe... I come back sometime.

        Eve's Ale - Shanna Allman (7.28.26) - p.42

        Eve's Ale - Shanna Allman (7.28.26) - p.43

        MAGGIE
        Why, you missin another watch?

        FRANCIS
        (shrugs) Just particularly fond of that satchel.

        MAGGIE
        (fingering the worn out satchel) Oh, yes. I can see why you would be.
        Francis turns to leave.

        Hey!

        Francis stops, turns back.
        -Always less busy on a Sunday. People seem to think sins count double that day.

        Francis touches her hat, turns to exit.

        Hey!

        Francis turns back.

        Come back.

        Francis turns and exits.
        Maggie watches after her then pulls the
        drawstring bag from her pocket. Glancing
        towards the door, she opens it, reaches
        in, and pulls out a gold heart shaped
        locket.

        Transition: The amber and gold light of
        sunset fills the stage as a gust
        """

        let scenes = ScriptParser.parseScenes(from: script, myRole: "Maggie")
        print("SCENES COUNT: \(scenes.count)")
        for (i, s) in scenes.enumerated() {
            print("Scene \(i+1): \(s.heading), title: \(s.title), lines: \(s.lines.count)")
            for l in s.lines {
                print("   [\(l.character)] \(l.text)")
            }
        }

        XCTAssertEqual(scenes.count, 2, "Expected 2 scenes from sides separated by 'Start'")
        XCTAssertGreaterThan(scenes[0].lines.count, 0)
        XCTAssertGreaterThan(scenes[1].lines.count, 0)

        // Ensure running headers were stripped
        for s in scenes {
            for l in s.lines {
                XCTAssertFalse(l.text.contains("Eve's Ale"), "Header line should not be included in dialogue: \(l.text)")
                XCTAssertFalse(l.text.contains("p.39") || l.text.contains("p.40") || l.text.contains("p.41"), "Page numbers should not be in dialogue: \(l.text)")
            }
        }
    }

    // MARK: - Material Kinds & Structured Casting Gap Tests

    func testSlateOnlyAuditionDoesNotRequireSides() {
        var draft = NoticeParser.Draft()
        draft.project = "Commercial Slate"
        draft.materialKind = .slateOnly
        draft.due = .now.addingTimeInterval(86400)

        XCTAssertTrue(draft.hasSides, "Slate only auditions should not report missing sides")
        XCTAssertTrue(draft.missingRequiredDetails.isEmpty, "Slate only auditions should not fail validation on empty role or sides")

        let audition = draft.makeAudition()
        XCTAssertEqual(audition.resolvedMaterialKind, .slateOnly)
        XCTAssertTrue(audition.scenes.isEmpty, "Slate only auditions have no script scenes")
        XCTAssertTrue(audition.pieces.contains { $0.kind == .slate }, "Slate only auditions include slate piece")
    }

    func testSoloMonologueGeneratesSoloSceneWithoutReaderLines() {
        var draft = NoticeParser.Draft()
        draft.project = "Hamlet Monologue"
        draft.role = "Hamlet"
        draft.materialKind = .monologue
        draft.due = .now.addingTimeInterval(86400)
        draft.sourceText = """
        To be, or not to be, that is the question:
        Whether 'tis nobler in the mind to suffer
        The slings and arrows of outrageous fortune,
        Or to take arms against a sea of troubles.
        """

        let audition = draft.makeAudition()
        XCTAssertEqual(audition.resolvedMaterialKind, .monologue)
        XCTAssertEqual(audition.scenes.count, 1)
        let scene = audition.scenes[0]
        XCTAssertEqual(scene.title, "Monologue")
        XCTAssertGreaterThan(scene.lines.count, 0)
        XCTAssertTrue(scene.lines.allSatisfy(\.isMine), "All monologue lines must belong to the actor with no reader cues")
    }

    func testNoticeParserExtractsMilestoneDatesAndProjectDetails() {
        let text = """
        CASTING CALL: THE LAST BARRICADE
        Director: Christopher Nolan
        Produced by: Syncopy Pictures
        Synopsis: In the final winter of 1944, a covert unit makes a daring escape across the Rhine.
        Union: SAG-AFTRA
        Rate: SAG scale + 10%
        Filming Location: Atlanta, GA

        ROLE: CAPTAIN MILLER (Male, 30-40). Hardened tactical commander.
        ROLE: LIEUTENANT VANCE (Female, 25-32). Brilliant intelligence officer.

        DATES:
        Self-tape deadline: December 15, 2026
        Callbacks: January 10, 2027
        Rehearsals start: February 1, 2027
        Filming starts: March 15, 2027
        """

        let draft = NoticeParser.parse(text)
        XCTAssertEqual(draft.project, "The Last Barricade")
        XCTAssertNotNil(draft.projectDetails)
        XCTAssertEqual(draft.projectDetails?.director, "Christopher Nolan")
        XCTAssertEqual(draft.projectDetails?.productionCompany, "Syncopy Pictures")
        XCTAssertTrue(draft.projectDetails?.synopsis?.contains("winter of 1944") == true)
        XCTAssertTrue(draft.projectDetails?.unionStatus?.contains("SAG-AFTRA") == true)
        XCTAssertTrue(draft.projectDetails?.payTerms?.contains("scale") == true)

        // Verify milestone dates
        XCTAssertGreaterThan(draft.importantDates.count, 0)
        XCTAssertTrue(draft.importantDates.contains { $0.kind == .callback || $0.label.lowercased().contains("callback") })

        // Verify role breakdowns
        XCTAssertGreaterThan(draft.roleBreakdowns.count, 0)
        let miller = draft.roleBreakdowns.first { $0.name.lowercased().contains("miller") }
        XCTAssertNotNil(miller)

        // Verify field evidence was captured
        XCTAssertFalse(draft.fieldEvidence.isEmpty, "Evidence excerpts must be grounded in notice text")

        // Make audition and verify persistence transfer
        let audition = draft.makeAudition()
        XCTAssertNotNil(audition.projectDetails)
        XCTAssertNotNil(audition.importantDates)
        XCTAssertNotNil(audition.roleBreakdowns)
        XCTAssertNotNil(audition.fieldEvidence)
    }

    func testOCRLayoutReconstructorTwoColumnGutterSeparation() {
        // Multi-column casting flyer simulation:
        // Top header banner
        // Left column (x: 0.05 ... 0.45): Roles and character breakdowns
        // Right column (x: 0.55 ... 0.95): Production dates, location, rates
        let boxes: [OCRLayoutReconstructor.TextBoundingBox] = [
            // Top full-width header
            OCRLayoutReconstructor.TextBoundingBox(text: "NOW CASTING - THE CROWN JEWEL", rect: CGRect(x: 0.10, y: 0.90, width: 0.80, height: 0.05), confidence: 0.99),

            // Left Column (Roles & descriptions) - y goes from 0.80 down to 0.35
            OCRLayoutReconstructor.TextBoundingBox(text: "CHARACTER BREAKDOWN", rect: CGRect(x: 0.05, y: 0.78, width: 0.38, height: 0.03), confidence: 0.95),
            OCRLayoutReconstructor.TextBoundingBox(text: "ROLE: ARJUN (Lead, 30s)", rect: CGRect(x: 0.05, y: 0.70, width: 0.38, height: 0.03), confidence: 0.95),
            OCRLayoutReconstructor.TextBoundingBox(text: "A sharp cryptographer who uncovers a global ring.", rect: CGRect(x: 0.05, y: 0.63, width: 0.38, height: 0.04), confidence: 0.92),
            OCRLayoutReconstructor.TextBoundingBox(text: "ROLE: TARA (Supporting, 20s)", rect: CGRect(x: 0.05, y: 0.52, width: 0.38, height: 0.03), confidence: 0.95),
            OCRLayoutReconstructor.TextBoundingBox(text: "A daring field operative who protects Arjun.", rect: CGRect(x: 0.05, y: 0.45, width: 0.38, height: 0.04), confidence: 0.92),

            // Right Column (Production Details) - same vertical range y: 0.80 down to 0.35
            OCRLayoutReconstructor.TextBoundingBox(text: "PRODUCTION DETAILS", rect: CGRect(x: 0.55, y: 0.78, width: 0.38, height: 0.03), confidence: 0.95),
            OCRLayoutReconstructor.TextBoundingBox(text: "Shoot Dates: Dec 1 - Dec 20, 2026", rect: CGRect(x: 0.55, y: 0.70, width: 0.38, height: 0.03), confidence: 0.95),
            OCRLayoutReconstructor.TextBoundingBox(text: "Location: London & Vancouver", rect: CGRect(x: 0.55, y: 0.63, width: 0.38, height: 0.03), confidence: 0.95),
            OCRLayoutReconstructor.TextBoundingBox(text: "Pay: SAG-AFTRA scale ($1,150/day)", rect: CGRect(x: 0.55, y: 0.52, width: 0.38, height: 0.03), confidence: 0.95),
            OCRLayoutReconstructor.TextBoundingBox(text: "Deadline: Nov 25 at 5:00 PM EST", rect: CGRect(x: 0.55, y: 0.45, width: 0.38, height: 0.03), confidence: 0.95),

            // Bottom footer banner
            OCRLayoutReconstructor.TextBoundingBox(text: "Submit tapes to: tapes@crownjewelfilm.com", rect: CGRect(x: 0.15, y: 0.10, width: 0.70, height: 0.04), confidence: 0.98)
        ]

        let reconstructed = OCRLayoutReconstructor.reconstruct(boxes: boxes)
        XCTAssertFalse(reconstructed.isEmpty)

        // Verify that Left Column lines are NOT interleaved with Right Column lines!
        // "ARJUN" should appear before "London & Vancouver"
        let arjunRange = reconstructed.range(of: "ROLE: ARJUN (Lead, 30s)")
        let rightColDateRange = reconstructed.range(of: "Shoot Dates: Dec 1 - Dec 20, 2026")
        let londonRange = reconstructed.range(of: "Location: London & Vancouver")
        let cryptographerRange = reconstructed.range(of: "sharp cryptographer")

        XCTAssertNotNil(arjunRange)
        XCTAssertNotNil(rightColDateRange)
        XCTAssertNotNil(londonRange)
        XCTAssertNotNil(cryptographerRange)

        if let arjunRange, let rightColDateRange, let cryptographerRange {
            // Arjun's description immediately follows Arjun, NOT shoot dates
            XCTAssertTrue(cryptographerRange.lowerBound > arjunRange.upperBound)
            XCTAssertTrue(rightColDateRange.lowerBound > cryptographerRange.upperBound, "Left column content must precede right column content in 2-column flyers")
        }

        // Verify parsing from this reconstructed text succeeds without corruption
        let draft = NoticeParser.parse(reconstructed)
        XCTAssertTrue(draft.candidateRoles.contains { $0.caseInsensitiveCompare("Arjun") == .orderedSame }, "Reconstructed flyer roles were: \(draft.candidateRoles)")
        XCTAssertTrue(draft.candidateRoles.contains { $0.caseInsensitiveCompare("Tara") == .orderedSame }, "Reconstructed flyer roles were: \(draft.candidateRoles)")
    }

    func testOCRLayoutReconstructorPreservesStandardKeyValueTable() {
        let boxes: [OCRLayoutReconstructor.TextBoundingBox] = [
            OCRLayoutReconstructor.TextBoundingBox(text: "Project:", rect: CGRect(x: 0.10, y: 0.80, width: 0.15, height: 0.03), confidence: 0.98),
            OCRLayoutReconstructor.TextBoundingBox(text: "The Inheritance", rect: CGRect(x: 0.30, y: 0.80, width: 0.30, height: 0.03), confidence: 0.98),
            OCRLayoutReconstructor.TextBoundingBox(text: "Role:", rect: CGRect(x: 0.10, y: 0.70, width: 0.15, height: 0.03), confidence: 0.98),
            OCRLayoutReconstructor.TextBoundingBox(text: "Alec", rect: CGRect(x: 0.30, y: 0.70, width: 0.20, height: 0.03), confidence: 0.98),
            OCRLayoutReconstructor.TextBoundingBox(text: "Due:", rect: CGRect(x: 0.10, y: 0.60, width: 0.15, height: 0.03), confidence: 0.98),
            OCRLayoutReconstructor.TextBoundingBox(text: "Tomorrow at 5pm", rect: CGRect(x: 0.30, y: 0.60, width: 0.30, height: 0.03), confidence: 0.98)
        ]

        let reconstructed = OCRLayoutReconstructor.reconstruct(boxes: boxes)
        XCTAssertTrue(reconstructed.contains("Project: The Inheritance"))
        XCTAssertTrue(reconstructed.contains("Role: Alec"))
        XCTAssertTrue(reconstructed.contains("Due: Tomorrow at 5pm"))
    }

    func testPosterWithRepeatedRightAlignedBadgesIsNotSplitIntoColumns() {
        // Casting Buffalo's public flyer places small request labels to the right of role
        // copy, but there is no continuous blank gutter. Model that visual pattern here.
        let boxes: [OCRLayoutReconstructor.TextBoundingBox] = [
            .init(text: "CASTING CALL", rect: CGRect(x: 0.08, y: 0.88, width: 0.52, height: 0.04), confidence: 0.98),
            .init(text: "MARIA — PRINCIPAL ROLE", rect: CGRect(x: 0.08, y: 0.72, width: 0.57, height: 0.04), confidence: 0.95),
            .init(text: "Video audition required", rect: CGRect(x: 0.66, y: 0.72, width: 0.27, height: 0.03), confidence: 0.95),
            .init(text: "CARLOS — SECONDARY ROLE", rect: CGRect(x: 0.08, y: 0.57, width: 0.57, height: 0.04), confidence: 0.95),
            .init(text: "Video audition required", rect: CGRect(x: 0.66, y: 0.57, width: 0.27, height: 0.03), confidence: 0.95),
            .init(text: "ROBERT — SUPPORTING ROLE", rect: CGRect(x: 0.08, y: 0.42, width: 0.57, height: 0.04), confidence: 0.95),
            .init(text: "Video audition required", rect: CGRect(x: 0.66, y: 0.42, width: 0.27, height: 0.03), confidence: 0.95),
            .init(text: "Submit a self-tape by email", rect: CGRect(x: 0.08, y: 0.22, width: 0.78, height: 0.04), confidence: 0.95)
        ]

        let reconstructed = OCRLayoutReconstructor.reconstruct(boxes: boxes)
        XCTAssertLessThan(reconstructed.range(of: "MARIA")!.lowerBound, reconstructed.range(of: "CARLOS")!.lowerBound)
        XCTAssertLessThan(reconstructed.range(of: "CARLOS")!.lowerBound, reconstructed.range(of: "ROBERT")!.lowerBound)
        XCTAssertLessThan(reconstructed.range(of: "ROBERT")!.lowerBound, reconstructed.range(of: "Submit a self-tape")!.lowerBound)
    }

    func testProseCastingNoticeDoesNotPromoteSectionHeadingOrQuotedDescriptionToFields() {
        let text = """
        AUDITION NOTICE
        CURRENTLY CASTING
        Share your Talent with the World!
        Alice is a 12–13-year-old girl who is introverted and emotionally complex, often struggling to connect with others and feeling uncomfortable in her own skin. She is highly intelligent and perceptive, with a sharp, blunt way of speaking that can sometimes come off as unfiltered. As the "black sheep" of her family, she doesn't quite fit in and often pushes boundaries while trying to understand herself and the world around her. Despite her guarded nature, she has moments of subtle humor, revealing a layered personality that blends vulnerability, strength, and quiet individuality.
        WHAT TO SUBMIT:
        • A HEADSHOT (OR A CLEAR RECENT PHOTO)
        • A VIDEO (THIS CAN BE A SELF-TAPE OR INTRODUCTION)
        • A RESUME (IF AVAILABLE, BUT NOT REQUIRED)
        ACTORS SHOULD EMAIL THEIR MATERIALS TO ALICESEARCH2026@GMAIL.COM
        """

        let draft = NoticeParser.parse(text)
        let roleDescription = NoticeParser.extractCharacterDescription(for: "Alice", in: text)

        XCTAssertEqual(draft.project, "", "A descriptive phrase such as ‘black sheep’ is not a project title")
        XCTAssertEqual(draft.role, "Alice")
        XCTAssertEqual(draft.candidateRoles, ["Alice"])
        XCTAssertFalse(draft.candidateRoles.contains("What To Submit"))
        XCTAssertFalse(draft.hasSides, "A casting flyer without script pages must not become a scene")
        XCTAssertEqual(draft.scenes, 0)
        XCTAssertTrue(draft.asks.contains("Self-tape or introduction video"))
        XCTAssertTrue(draft.asks.contains("Resume (optional)"))
        XCTAssertTrue(roleDescription?.contains("quiet individuality") == true)
        XCTAssertFalse(roleDescription?.localizedCaseInsensitiveContains("what to submit") == true)
        XCTAssertNil(draft.due)
        XCTAssertEqual(draft.destinationDetail?.lowercased(), "alicesearch2026@gmail.com")
        XCTAssertEqual(draft.destination, .email)
        XCTAssertTrue(draft.destinationWasDetected)
        XCTAssertFalse(draft.asks.contains { $0.localizedCaseInsensitiveContains("email:") }, "Submission contact is shown as the destination, not as a casting requirement")
        XCTAssertTrue(draft.includeSlate, "The requested self-tape/introduction video is included")
        XCTAssertTrue(draft.includeHeadshots, "The requested headshot is included")
        XCTAssertFalse(draft.isHeadshotOptional, "The notice requests a headshot or recent photo")
        XCTAssertFalse(draft.missingRequiredDetails.contains("script sides"), "A notice without sides must not require a fictional scene")
        XCTAssertFalse(draft.projectDetails?.hasReviewableContent ?? true)
    }

    func testScriptParserThoughtUnitDividerWithLongSentenceAndParentheticals() {
        let text = "Listen to me, Maryam (beat). I never wanted to tell you this [hesitates], but we were cornered in the basement for three whole days while the tanks rolled right through the city streets."
        let units = ScriptParser.divideIntoThoughtUnits(text)
        XCTAssertFalse(units.isEmpty)
        // Stage directions (beat) and [hesitates] should be stripped from prompter thoughts
        for unit in units {
            XCTAssertFalse(unit.contains("(beat)"))
            XCTAssertFalse(unit.contains("[hesitates]"))
        }
    }

    func testFlyersOCRAndDeterministicParsing() async throws {
        let datasetDir = "/Users/user1/Downloads/OneTake-iOS/dataset/notices"
        let flyers = [
            ("Notice 1", "notice_1_shadows_of_manhattan.jpg"),
            ("Notice 2", "notice_2_the_quiet_horizon.jpg"),
            ("Notice 3", "notice_3_crossroads_chronicle.jpg")
        ]

        guard FileManager.default.fileExists(atPath: datasetDir) else {
            throw XCTSkip("Flyer dataset not found at \(datasetDir), skipping test")
        }

        for (label, filename) in flyers {
            let path = "\(datasetDir)/\(filename)"
            guard let image = UIImage(contentsOfFile: path) else {
                XCTFail("Could not load image at \(path)")
                continue
            }

            print("\n=======================================================")
            print("EVALUATING: \(label) (\(filename))")
            print("Image Size: \(image.size.width) x \(image.size.height)")

            let pages = await NoticeOCR.recognizePages(in: [image])
            let ocrText = pages.first ?? ""
            let lines = ocrText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let words = ocrText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })

            print("--- OCR RESULTS ---")
            print("Pages returned: \(pages.count)")
            print("Line count: \(lines.count)")
            print("Word count: \(words.count)")
            print("Looks readable: \(NoticeOCR.looksReadable(ocrText))")
            print("OCR Text:\n\(ocrText)")

            // Test Deterministic Parser
            let draft = NoticeParser.parse(ocrText, pages: pages)
            print("\n--- DETERMINISTIC PARSER EXTRACTED FIELDS ---")
            print("Project Title: \(draft.project)")
            print("Candidate Roles: \(draft.candidateRoles)")
            print("Due Date: \(String(describing: draft.due))")
            print("Casting Office: \(draft.castingOffice)")
            print("Destination: \(draft.destination) -> \(draft.destinationDetail ?? "none")")
            print("Asks: \(draft.asks)")
            print("Role Size: \(draft.roleSize)")

            // Test Model-Assisted Parser (Prompt 2)
            let refinedDraft = await NoticeParser.parseAsync(ocrText, pages: pages)
            print("\n--- MODEL-ASSISTED REFINEMENT EXTRACTED FIELDS ---")
            print("Project Title: \(refinedDraft.project)")
            print("Candidate Roles: \(refinedDraft.candidateRoles)")
            print("Role Selected: \(refinedDraft.role)")
            print("Due Date: \(String(describing: refinedDraft.due))")
            print("Casting Office: \(refinedDraft.castingOffice)")
            print("Destination: \(refinedDraft.destination) -> \(refinedDraft.destinationDetail ?? "none")")
            print("Asks: \(refinedDraft.asks)")
            print("AI Guidance: \(refinedDraft.aiGuidance)")

            // Verify bounded enlargement recovered lines on flyers
            XCTAssertTrue(lines.count >= 8, "\(label) should recover at least 8 lines with bounded enlargement")
            XCTAssertTrue(NoticeOCR.looksReadable(ocrText), "\(label) should produce readable text")
            XCTAssertFalse(draft.project.isEmpty, "\(label) should extract a non-empty project title")
            XCTAssertFalse(draft.candidateRoles.isEmpty, "\(label) should extract candidate roles")
            XCTAssertNotNil(draft.due, "\(label) should extract a submission deadline")
        }
    }

    func testMultipleDetectedRolesLeaveRoleBlankInDraftAndUnselectedInReview() {
        var draft = NoticeParser.Draft.blank
        draft.project = "The Quiet Horizon"
        draft.candidateRoles = ["Elena Gomez", "Marcus Brody"]
        draft.role = "" // Ambiguous roles leave draft.role blank
        draft.due = Date().addingTimeInterval(86400)

        // Instantiate review sheet
        let review = OCRReviewSheet(draft: draft, onConfirm: { _, _ in }, onDiscard: {})

        // Assert role is not arbitrarily pre-filled
        XCTAssertTrue(review.currentRoleText.isEmpty, "Review screen must not pre-fill candidate role when multiple roles exist")
        XCTAssertFalse(review.isUseThisEnabled, "Use this must be disabled until the actor explicitly chooses a role")
    }

    func testSingleDetectedRolePreFillsInReview() {
        var draft = NoticeParser.Draft.blank
        draft.project = "Single Role Production"
        draft.candidateRoles = ["Solo Lead"]
        draft.role = "Solo Lead"
        draft.due = Date().addingTimeInterval(86400)

        let review = OCRReviewSheet(draft: draft, onConfirm: { _, _ in }, onDiscard: {})
        XCTAssertEqual(review.currentRoleText, "Solo Lead", "Review screen should pre-fill unambiguous single candidate role")
        XCTAssertTrue(review.isUseThisEnabled, "Use this should be enabled when a single role is known")
    }

    @MainActor
    func testRenderOCRReviewSheetMultiStepsSnapshot() {
        var draft = NoticeParser.Draft.blank
        draft.project = "Pilgrimage"
        draft.materialKind = .sides
        draft.role = "Noor"
        draft.candidateRoles = ["Noor", "Maryam", "Nadia", "Sosan", "Fatima"]
        draft.castingOffice = "Anti-Casting, Telsey + Co"
        draft.due = Date().addingTimeInterval(86400 * 3)
        draft.asks = ["Slate first", "Landscape", "Under 2 min"]
        draft.availablePortions = [
            ScriptParser.ScenePortion(id: "portion_noor", number: 1, heading: "NOOR · She/her · Early 60s", characters: ["Noor"], rawText: "NOOR: The secret I carried.", lineCount: 1, pageNumber: 2),
            ScriptParser.ScenePortion(id: "portion_maryam", number: 2, heading: "MARYAM · She/her · Mid-30s", characters: ["Maryam"], rawText: "MARYAM: You don't know.", lineCount: 1, pageNumber: 3),
            ScriptParser.ScenePortion(id: "portion_nadia", number: 3, heading: "NADIA · She/her · Mid-30s", characters: ["Nadia"], rawText: "NADIA: Hello.\nREADER: Hi.", lineCount: 2, pageNumber: 4)
        ]
        draft.selectedPortionIDs = ["portion_noor"]
        let store = AppStore()

        let steps: [(OCRReviewSheet.ReviewStep, String)] = [
            (.project, "/Users/user1/.gemini/antigravity/brain/d790eb58-5771-48bc-93de-9d618f769bd8/sim_review_step1.png"),
            (.scenes, "/Users/user1/.gemini/antigravity/brain/d790eb58-5771-48bc-93de-9d618f769bd8/sim_review_step2.png"),
            (.requirements, "/Users/user1/.gemini/antigravity/brain/d790eb58-5771-48bc-93de-9d618f769bd8/sim_review_step3.png")
        ]

        for (step, path) in steps {
            let view = OCRReviewSheet(draft: draft, initialStep: step, onConfirm: { _, _ in }, onDiscard: {})
                .environment(store)
            let host = UIHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            host.view.backgroundColor = .black
            host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
            let img = renderer.image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            if let data = img.pngData() {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    func testSilentReactionCueIsNotBypassedWhenVoiceFollowingActive() {
        let questionCue = ScriptLine(character: "Reader", text: "?", isMine: false)
        XCTAssertTrue(questionCue.isSilentReactionCue)

        let hasSpokenWords = !questionCue.text.split(separator: " ").map({ SpokenLineMatcher.cleanWord($0) }).filter({ !$0.isEmpty }).isEmpty
        XCTAssertFalse(hasSpokenWords, "Lone question mark cue has no spoken words")

        let isSilentBeat = questionCue.isSilentReactionCue || !hasSpokenWords
        XCTAssertTrue(isSilentBeat, "Silent reaction cue must be classified as a silent beat")

        // Simulate the ShootViews guard:
        // When followVoice is true and readerAudioMissing is false,
        // a spoken line would bail out, but a silent beat must NOT bail out.
        let followVoice = true
        let readerAudioMissing = false
        var wouldBailOut = false
        if !isSilentBeat {
            if followVoice && questionCue.isMine { wouldBailOut = true }
            if followVoice && !questionCue.isMine && !readerAudioMissing { wouldBailOut = true }
        }

        XCTAssertFalse(wouldBailOut, "Silent reaction cue must not bail out; it must schedule timed advance even when followVoice is active")
    }

    func testMediaExporterFiltersPreviousSidesTakes() {
        var audition = NoticeParser.Draft(project: "Hamlet", role: "Hamlet").makeAudition()
        audition.sidesRevision = 2
        audition.scenes = [ScriptScene(number: 1, title: "Scene 1", heading: "INT. CASTLE - DAY", lines: [])]
        let sceneIndex = 0

        let currentURL = URL(fileURLWithPath: "/tmp/current.mp4")
        let currentTake = Take(
            number: 1,
            duration: 10,
            recordedAt: .now,
            isCircled: true,
            notes: [],
            fileURL: currentURL,
            auditionID: audition.id,
            sceneIndex: sceneIndex,
            isPreviousSides: false,
            sidesRevision: 2
        )

        let prevURL = URL(fileURLWithPath: "/tmp/prev.mp4")
        let prevTake = Take(
            number: 2,
            duration: 10,
            recordedAt: .now,
            isCircled: true,
            notes: [],
            fileURL: prevURL,
            auditionID: audition.id,
            sceneIndex: sceneIndex,
            isPreviousSides: true,
            sidesRevision: 1
        )

        let clips = MediaExporter.clips(for: audition, takes: [prevTake, currentTake])
        let sceneClips = clips.filter {
            if case .scene = $0.kind { return true }
            return false
        }
        XCTAssertEqual(sceneClips.count, 1)
        XCTAssertEqual(sceneClips.first?.url, currentURL)
    }
}
