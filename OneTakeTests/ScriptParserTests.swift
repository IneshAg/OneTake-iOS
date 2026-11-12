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

    func testDialogueDividedByCharacterTurns() {
        let script = """
        JAKE
        I think we should wait for Sarah before opening this.

        AUSTIN
        Sarah is twenty minutes late. We open it now.

        SARAH
        Don't touch that without me.

        JAKE
        See? I told you she was coming.

        SARAH
        Give me the keys, Austin.
        """
        let scenes = ScriptParser.parseScenes(from: script, myRole: "Sarah")
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.count, 5)
        XCTAssertEqual(scenes[0].lines.map(\.character), ["Jake", "Austin", "Sarah", "Jake", "Sarah"])
        XCTAssertEqual(scenes[0].lines.map(\.isMine), [false, false, true, false, true])
        XCTAssertEqual(scenes[0].lines[0].text, "I think we should wait for Sarah before opening this.")
        XCTAssertEqual(scenes[0].lines[1].text, "Sarah is twenty minutes late. We open it now.")
        XCTAssertEqual(scenes[0].lines[2].text, "Don't touch that without me.")
        XCTAssertEqual(scenes[0].lines[3].text, "See? I told you she was coming.")
        XCTAssertEqual(scenes[0].lines[4].text, "Give me the keys, Austin.")
    }

    func testMonologueUnderCharacterRemainsUnderCharacter() {
        let monologue = """
        NOOR
        You know I've called you my miracle child, Maryam. I had such trouble conceiving.
        I thought it was my fault, that I was the cause. But I wasn't.
        Right after the Russians invaded Afghanistan, they were rounding up anyone who
        was not a communist sympathizer.
        """
        let scenes = ScriptParser.parseScenes(from: monologue, myRole: "Noor")
        XCTAssertEqual(scenes.count, 1)
        // All lines under Noor belong strictly to Noor without arbitrary fragmentation
        XCTAssertEqual(scenes[0].lines.count, 1)
        XCTAssertEqual(scenes[0].lines[0].character, "Noor")
        XCTAssertTrue(scenes[0].lines[0].isMine)
        XCTAssertTrue(scenes[0].lines[0].text.contains("miracle child"))
        XCTAssertTrue(scenes[0].lines[0].text.contains("communist sympathizer"))
    }

    func testDivideIntoThoughtUnitsUtility() {
        let text = "You know I've called you my miracle child, Maryam. I had such trouble conceiving. I thought it was my fault, that I was the cause. But I wasn't."
        let units = ScriptParser.divideIntoThoughtUnits(text)
        XCTAssertGreaterThan(units.count, 1)
        for unit in units {
            let count = unit.split(separator: " ").count
            XCTAssertLessThanOrEqual(count, 25)
        }
    }

    func testProtectedAbbreviationsDoNotSplitSentences() {
        let text = "Dr. Stone met with Lt. Col. Davis at 6 p.m. in the U.S. capital."
        let units = ScriptParser.divideIntoThoughtUnits(text)
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0], "Dr. Stone met with Lt. Col. Davis at 6 p.m. in the U.S. capital.")
    }

    func testPilgrimageMultiRoleSidesPacket() {
        let pilgrimageDocument = """
        PILGRIMAGE
        CASTING SIDES
        Humaira Ghilzai & Bridgette Dutta Portman
        Director: Khaled Abol Naga (Kal)
        The Lab at Georgetown University · November 2026

        HOW TO USE THESE SIDES
        Each side has been selected to reveal character, range, and presence within 1–2 minutes of screen time.
        Please read all instructions on your character's page before recording.
        Slate first. At the top of your video, look directly into the camera and state your name, pronouns, the role you are reading for, and your city.
        Submit your tape via the link at: kalnaga.com/pilgrimage/casting.html

        THE CHARACTERS IN THIS DOCUMENT
        NOOR — Page 2
        MARYAM — Page 3
        NADIA — Page 4
        SOSAN — Page 5
        FATIMA — Page 6

        NOOR · She/her · Early 60s · Afghan American
        Director note: What I'm looking for: the weight of a woman who has carried this secret for decades.
        SLATE INSTRUCTION Before beginning, look directly into camera and state: your full name · your pronouns · the role you are reading for (NOOR).
        THE SIDE — Noor's Confession (Act II, Scene 4)
        Setting: At the Kaaba, Mecca. Noor addresses Maryam directly for the first time.
        You know I've called you my miracle child, Maryam. I had such trouble conceiving.
        I thought it was my fault, that I was the cause. But I wasn't.
        Right after the Russians invaded Afghanistan, they were rounding up anyone who was not a communist sympathizer.

        MARYAM · She/her · Mid-30s · Afghan American
        Director note: Maryam's comedy and devastation are the same instrument.
        SLATE INSTRUCTION Before beginning, look directly into camera and state: role you are reading for (MARYAM).
        SIDE A — The Phone Call (Act I, Scene 5)
        Setting: Hotel lobby, on the phone with Candace.
        [speaking on phone]
        Candace, I'm about to embark on a journey that Prophet Muhammad made in 632 to retake Mecca.
        Tell their lawyers that I'm in the state of Ihram and can't be bothered with earthly problems.

        SIDE B — The Aftermath (Act II, Scene 4)
        Setting: After Noor's confession at the Kaaba.
        I can't talk to her right now.
        I can't believe this. She's been lying all her life.

        NADIA · She/her · Mid-30s · Afghan American
        SLATE INSTRUCTION Before beginning, look directly into camera and state: role (NADIA).
        SIDE A — Boo-hoo + The Reveal (Act II, Scene 4)
        Setting: At the Kaaba.
        Boo-hoo, the poor misunderstood millionaire. I may not be famous, but my life is stressful too.
        I'm in love with Fatima.

        SIDE B — You Missed Her Funeral (Act I, Scene 2)
        Setting: Hotel room in Medina. Nadia confronts Sosan.
        NADIA
        You missed her funeral.
        SOSAN
        I had work in Nigeria.
        NADIA
        You stole my chance to grieve.
        """

        // 1. Archetype check
        XCTAssertEqual(ScriptParser.detectArchetype(in: pilgrimageDocument), .multiRolePacket)

        // 2. Candidate roles detection
        let characters = ScriptParser.extractCharacters(from: pilgrimageDocument)
        XCTAssertTrue(characters.contains("Noor"))
        XCTAssertTrue(characters.contains("Maryam"))
        XCTAssertTrue(characters.contains("Nadia"))
        XCTAssertFalse(characters.contains("Setting"))
        XCTAssertFalse(characters.contains("Director Note"))

        // 3. Parsing for Noor
        let noorScenes = ScriptParser.parseScenes(from: pilgrimageDocument, myRole: "Noor")
        XCTAssertEqual(noorScenes.count, 1)
        XCTAssertTrue(noorScenes[0].heading.contains("Noor's Confession"))
        XCTAssertTrue(noorScenes[0].lines.allSatisfy { $0.character == "Noor" && $0.isMine })
        XCTAssertTrue(noorScenes[0].lines.contains { $0.text.contains("miracle child") })

        // 4. Parsing for Maryam: Side A and Side B should become 2 distinct scenes
        let maryamScenes = ScriptParser.parseScenes(from: pilgrimageDocument, myRole: "Maryam")
        XCTAssertEqual(maryamScenes.count, 2)
        XCTAssertTrue(maryamScenes[0].heading.contains("The Phone Call"))
        XCTAssertTrue(maryamScenes[1].heading.contains("The Aftermath"))
        XCTAssertTrue(maryamScenes[0].lines.allSatisfy { $0.character == "Maryam" && $0.isMine })

        // 5. Parsing for Nadia: Dialogue in Side B should mark Nadia as mine and Sosan as reader
        let nadiaScenes = ScriptParser.parseScenes(from: pilgrimageDocument, myRole: "Nadia")
        XCTAssertEqual(nadiaScenes.count, 2)
        let funeralScene = nadiaScenes[1]
        XCTAssertTrue(funeralScene.lines.contains { $0.character == "Nadia" && $0.isMine })
        XCTAssertTrue(funeralScene.lines.contains { $0.character == "Sosan" && !$0.isMine })
    }

    func testStagePlayPeriodCues() {
        let play = """
        ACT I, SCENE II
        Elsinore. A platform before the castle.

        HAMLET. To be, or not to be, that is the question:
        Whether 'tis nobler in the mind to suffer
        The slings and arrows of outrageous fortune.

        HORATIO. (Approaching slowly)
        My lord, the watch is set.

        HAMLET. Not a mouse stirring.
        """
        XCTAssertEqual(ScriptParser.detectArchetype(in: play), .stagePlay)
        let scenes = ScriptParser.parseScenes(from: play, myRole: "Hamlet")
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.filter(\.isMine).count, 2)
        XCTAssertEqual(scenes[0].lines[0].character, "Hamlet")
        XCTAssertTrue(scenes[0].lines[0].text.contains("To be, or not to be"))
        XCTAssertEqual(scenes[0].lines[1].character, "Horatio")
        XCTAssertFalse(scenes[0].lines[1].isMine)
        XCTAssertEqual(scenes[0].lines[1].text, "My lord, the watch is set.")
    }

    func testCommercialCopyAudioVideoParsing() {
        let commercial = """
        COMMERCIAL COPY — 30 SEC
        CLIENT: ACME MOTORS

        VIDEO: Hero shot of sleek vehicle accelerating on open mountain highway.
        AUDIO: ANNCR: The morning commute just got an upgrade.

        VIDEO: Cut to driver smiling, tapping digital dashboard.
        AUDIO: MAN: Set destination home.

        AUDIO: ANNCR: Drive into the future today.
        """
        XCTAssertEqual(ScriptParser.detectArchetype(in: commercial), .commercial)
        let scenes = ScriptParser.parseScenes(from: commercial, myRole: "Anncr")
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.count, 3)
        XCTAssertEqual(scenes[0].lines[0].character, "Anncr")
        XCTAssertTrue(scenes[0].lines[0].isMine)
        XCTAssertEqual(scenes[0].lines[0].text, "The morning commute just got an upgrade.")
        XCTAssertEqual(scenes[0].lines[1].character, "Man")
        XCTAssertFalse(scenes[0].lines[1].isMine)
    }

    func testFormattingDialogueWithFullStopsAndCommas() {
        // Physical wrapped lines with missing space after commas/periods and missing final period
        let rawInput = """
        Candace,I'm about to embark on a journey that Prophet Muhammad,Peace Be
        Upon Him,made in 632 to retake Mecca.So,tell their lawyers that I'm in the state
        of Ihram and can't be bothered with earthly problems
        """
        let formatted = ScriptParser.formatDialogueText(rawInput)

        // Line wraps unwrapped into continuous prose
        XCTAssertFalse(formatted.contains("\n"))

        // Commas and full stops properly preserved with clean spacing
        XCTAssertTrue(formatted.contains("Candace, I'm about"))
        XCTAssertTrue(formatted.contains("Prophet Muhammad, Peace Be Upon Him, made"))
        XCTAssertTrue(formatted.contains("Mecca. So, tell"))

        // Final full stop added
        XCTAssertTrue(formatted.hasSuffix("earthly problems."))
    }

    func testNonStandardCuesAndMultiLineParentheticals() {
        let sides = """
        [HAMLET]
        (leaning close to the audience,
         pausing for dramatic breath)
        To be, or not to be.

        CLAUDIUS - CONT'D
        What does he mean?
        """
        let scenes = ScriptParser.parseScenes(from: sides, myRole: "Hamlet")
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.count, 2)
        XCTAssertEqual(scenes[0].lines[0].character, "Hamlet")
        XCTAssertTrue(scenes[0].lines[0].isMine)
        XCTAssertEqual(scenes[0].lines[0].text, "To be, or not to be.")
        XCTAssertEqual(scenes[0].lines[1].character, "Claudius")
        XCTAssertEqual(scenes[0].lines[1].text, "What does he mean?")
    }

    func testIdentifyScenePortionsAndHierarchicalChunking() {
        let multiSceneScript = """
        ACT ONE SCENE SIX
        SANDY:
        Do a split, give a yell!
        DANNY:
        Hiya, Sandy.

        ACT TWO SCENE FIVE
        SANDY:
        Look at me, I'm Sandra Dee.
        """

        let portions = ScriptParser.identifyScenePortions(from: multiSceneScript)
        XCTAssertEqual(portions.count, 2)
        XCTAssertEqual(portions[0].heading, "ACT ONE SCENE SIX")
        XCTAssertTrue(portions[0].characters.contains("SANDY"))
        XCTAssertTrue(portions[0].characters.contains("DANNY"))

        XCTAssertEqual(portions[1].heading, "ACT TWO SCENE FIVE")
        XCTAssertTrue(portions[1].characters.contains("SANDY"))

        // Pass 2: User selects only Scene 2 (ACT TWO SCENE FIVE)
        let selectedPortion = [portions[1]]
        let parsed = ScriptParser.parseSelectedPortions(selectedPortion, myRole: "Sandy")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].title, "Scene 1")
        XCTAssertEqual(parsed[0].lines.count, 1)
        XCTAssertEqual(parsed[0].lines[0].character, "Sandy")
        XCTAssertEqual(parsed[0].lines[0].text, "Look at me, I'm Sandra Dee.")
    }

    func testCastingFlyerPayAndUsageLabelsAreNotDialogueOrScenes() {
        // Layout and wording are based on a public two-page casting flyer. This fixture uses
        // short synthetic text rather than reproducing the notice's role copy.
        let flyer = """
        CASTING CALL — COMMERCIAL
        Seeking local adult actors for an internal training video.

        RATE OF PAY: PRINCIPAL ROLE $1,500/DAY, SECONDARY ROLE $800/DAY + agency fee.
        VIDEO USAGE: Internal training only. No broadcast. Location: Buffalo, NY.

        Submit a self-tape by email. Include a headshot and resume.
        """

        XCTAssertTrue(ScriptParser.extractCharacters(from: flyer).isEmpty)
        XCTAssertTrue(ScriptParser.parseScenes(from: flyer, myRole: "").isEmpty)
        XCTAssertTrue(ScriptParser.identifyScenePortions(from: flyer).isEmpty)
    }

    func testBPETokenizerEncodingDecoding() {
        let tokenizer = BPETokenizer.shared
        let original = "{\"project\": \"Grease\", \"role\": \"Sandy\"}"

        let tokens = tokenizer.encode(text: original)
        XCTAssertFalse(tokens.isEmpty)

        let decoded = tokenizer.decode(tokens: tokens)
        XCTAssertEqual(decoded, original)

        let chatTokens = tokenizer.applyChatTemplate(system: "System prompt", user: "User notice text")
        XCTAssertTrue(chatTokens.contains(tokenizer.imStartTokenID))
        XCTAssertTrue(chatTokens.contains(tokenizer.imEndTokenID))
    }
    func testBPETokenizerQwenParityTokenIDs() {
        let tokenizer = BPETokenizer.shared

        // 1. "Project: Grease" -> [7849, 25, 13532, 519]
        let greaseTokens = tokenizer.encode(text: "Project: Grease")
        XCTAssertEqual(greaseTokens, [7849, 25, 13532, 519])
        XCTAssertEqual(tokenizer.decode(tokens: greaseTokens), "Project: Grease")

        // 2. "Role: Sandy" -> [9030, 25, 38385]
        let sandyTokens = tokenizer.encode(text: "Role: Sandy")
        XCTAssertEqual(sandyTokens, [9030, 25, 38385])
        XCTAssertEqual(tokenizer.decode(tokens: sandyTokens), "Role: Sandy")

        // 3. "{"project": "Hamlet", "role": "Ophelia"}" -> [4913, 4987, 788, 330, 39941, 1149, 497, 330, 5778, 788, 330, 46, 759, 35929, 9207]
        let hamletJSON = "{\"project\": \"Hamlet\", \"role\": \"Ophelia\"}"
        let hamletTokens = tokenizer.encode(text: hamletJSON)
        XCTAssertEqual(hamletTokens, [4913, 4987, 788, 330, 39941, 1149, 497, 330, 5778, 788, 330, 46, 759, 35929, 9207])
        XCTAssertEqual(tokenizer.decode(tokens: hamletTokens), hamletJSON)
    }

    func testCoreMLScriptElementClassifierAccuracy() async {
        let runner = CoreMLScriptParserRunner.shared
        XCTAssertTrue(runner.isAvailable, "ScriptElementClassifier model should be available on device or test host.")

        let testCases: [(String, ScriptElementClass)] = [
            // Headings / Sluglines
            ("INT. COFFEE SHOP - DAY", .sceneHeading),
            ("EXT. STREET CORNER - NIGHT", .sceneHeading),
            ("SCENE 1", .sceneHeading),
            ("ACT I", .sceneHeading),
            ("INT./EXT. CAR - MOVING", .sceneHeading),

            // Character Cues
            ("MAYA", .characterCue),
            ("ARJUN (CONT'D)", .characterCue),
            ("DANNY:", .characterCue),
            ("SARAH (O.S.)", .characterCue),
            ("DETECTIVE MILLER (V.O.)", .characterCue),
            ("\t\tMAYA", .characterCue),
            ("    JOHN", .characterCue),

            // Dialogue
            ("Where were you last night?", .dialogue),
            ("I didn't think you'd come.", .dialogue),
            ("Look at me.", .dialogue),
            ("I told you everything I know.", .dialogue),
            ("Not here. We can't talk here.", .dialogue),
            ("Why did you do it?", .dialogue),

            // Parentheticals
            ("(whispering)", .parenthetical),
            ("(beat)", .parenthetical),
            ("(to Arjun)", .parenthetical),
            ("(laughing)", .parenthetical),
            ("(pauses)", .parenthetical),
            ("(under her breath)", .parenthetical),
            ("(firmly)", .parenthetical),
            ("(hesitates)", .parenthetical),

            // Action
            ("Maya paces across the room, clutching her phone.", .action),
            ("He glances out the rain-streaked window.", .action),
            ("Silence hangs in the cold air.", .action),
            ("She slams the door shut.", .action),
            ("They exchange uneasy glances.", .action),

            // Metadata
            ("CONFIDENTIAL", .metadata),
            ("PAGE 4 OF 12", .metadata),
            ("AUDITION SIDES ONLY", .metadata),
            ("FINAL SHOOTING DRAFT", .metadata)
        ]

        for (line, expectedClass) in testCases {
            let syncResult = runner.classifySync(line: line)
            XCTAssertEqual(
                syncResult,
                expectedClass,
                "Sync classification failed for '\(line)': expected \(expectedClass.rawValue), got \(syncResult?.rawValue ?? "nil")"
            )

            let asyncResult = await runner.classify(line: line)
            XCTAssertEqual(
                asyncResult,
                expectedClass,
                "Async classification failed for '\(line)': expected \(expectedClass.rawValue), got \(asyncResult?.rawValue ?? "nil")"
            )
        }

        // Batch prediction check
        let sampleLines = testCases.map(\.0)
        let batchResults = await runner.classify(lines: sampleLines)
        XCTAssertEqual(batchResults.count, testCases.count)
        for (idx, expectedClass) in testCases.map(\.1).enumerated() {
            XCTAssertEqual(batchResults[idx], expectedClass)
        }
    }

    func testIndentedCharacterCuesWithTabsAndSpaces() {
        let sides = """
        INT. COFFEE SHOP - DAY

        Maya sits alone at a corner table stirring her tea.

        \t\tMAYA
        \t(whispering)
        I didn't think you'd come.

            JOHN
        (sitting across from her)
        You asked me to.

        He reaches into his jacket and pulls out an envelope.

        \t\tMaya
        Is that what I think it is?
        """
        let scenes = ScriptParser.parseScenes(from: sides, myRole: "Maya")
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].lines.count, 3)
        XCTAssertEqual(scenes[0].lines[0].character, "Maya")
        XCTAssertEqual(scenes[0].lines[0].text, "I didn't think you'd come.")
        XCTAssertTrue(scenes[0].lines[0].isMine)

        XCTAssertEqual(scenes[0].lines[1].character, "John")
        XCTAssertEqual(scenes[0].lines[1].text, "You asked me to.")
        XCTAssertFalse(scenes[0].lines[1].isMine)

        XCTAssertEqual(scenes[0].lines[2].character, "Maya")
        XCTAssertEqual(scenes[0].lines[2].text, "Is that what I think it is?")
        XCTAssertTrue(scenes[0].lines[2].isMine)
    }

    func testCoreMLScriptParserParsesScenes() {
        let multiSceneScript = """
        INT. APARTMENT - DAY

        MAYA
        Where were you last night?

        JOHN
        Working late at the archives.

        EXT. ALLEY - NIGHT

        Rain falls heavily onto the asphalt.

        JOHN
        Don't follow me, Maya.

        MAYA
        (stepping forward)
        I'm not leaving you behind.
        """
        let scenes = ScriptParser.parseScenes(from: multiSceneScript, myRole: "Maya")
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[0].heading, "INT. APARTMENT - DAY")
        XCTAssertEqual(scenes[0].lines.count, 2)
        XCTAssertEqual(scenes[0].lines[0].character, "Maya")
        XCTAssertEqual(scenes[0].lines[0].text, "Where were you last night?")
        XCTAssertTrue(scenes[0].lines[0].isMine)
        XCTAssertEqual(scenes[0].lines[1].character, "John")
        XCTAssertEqual(scenes[0].lines[1].text, "Working late at the archives.")
        XCTAssertFalse(scenes[0].lines[1].isMine)

        XCTAssertEqual(scenes[1].heading, "EXT. ALLEY - NIGHT")
        XCTAssertEqual(scenes[1].lines.count, 2)
        XCTAssertEqual(scenes[1].lines[0].character, "John")
        XCTAssertEqual(scenes[1].lines[0].text, "Don't follow me, Maya.")
        XCTAssertFalse(scenes[1].lines[0].isMine)
        XCTAssertEqual(scenes[1].lines[1].character, "Maya")
        XCTAssertEqual(scenes[1].lines[1].text, "I'm not leaving you behind.")
        XCTAssertTrue(scenes[1].lines[1].isMine)
    }
}
