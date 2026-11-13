import Foundation

/// Deterministic fixtures for Demo Mode so toggling Demo Mode ON populates every workflow
/// (Auditions across Due/Ready/Exported/Sent, Practice drills, Search, Notice Review, Preview,
/// Package/Export, Slate & Headshots) and toggling OFF removes only demo-owned records.
enum DemoModeCatalog {
    // MARK: - Deterministic Demo IDs

    static let quietHorizonID = UUID(uuidString: "0000DE00-0001-4000-8000-000000000001")!
    static let midnightDispatchID = UUID(uuidString: "0000DE00-0001-4000-8000-000000000002")!
    static let atlasRunningID = UUID(uuidString: "0000DE00-0001-4000-8000-000000000003")!
    static let glassHarborID = UUID(uuidString: "0000DE00-0001-4000-8000-000000000004")!

    static let allDemoAuditionIDs: Set<UUID> = [
        quietHorizonID,
        midnightDispatchID,
        atlasRunningID,
        glassHarborID
    ]

    static let dispatchTake1ID = UUID(uuidString: "0000DE00-0002-4000-8000-000000000001")!
    static let dispatchTake2ID = UUID(uuidString: "0000DE00-0002-4000-8000-000000000002")!
    static let dispatchTake3ID = UUID(uuidString: "0000DE00-0002-4000-8000-000000000003")!
    static let dispatchScene2TakeID = UUID(uuidString: "0000DE00-0002-4000-8000-000000000004")!
    static let atlasTake1ID = UUID(uuidString: "0000DE00-0002-4000-8000-000000000005")!

    static let allDemoTakeIDs: Set<UUID> = [
        dispatchTake1ID,
        dispatchTake2ID,
        dispatchTake3ID,
        dispatchScene2TakeID,
        atlasTake1ID
    ]

    static let practiceGoodbyeID = UUID(uuidString: "0000DE00-0003-4000-8000-000000000001")!
    static let practiceCoffeeID = UUID(uuidString: "0000DE00-0003-4000-8000-000000000002")!
    static let practiceLearID = UUID(uuidString: "0000DE00-0003-4000-8000-000000000003")!

    static let allDemoPracticeIDs: Set<UUID> = [
        practiceGoodbyeID,
        practiceCoffeeID,
        practiceLearID
    ]

    static func isDemoAudition(_ audition: Audition) -> Bool {
        allDemoAuditionIDs.contains(audition.id)
    }

    static func isDemoTake(_ take: Take) -> Bool {
        allDemoTakeIDs.contains(take.id) || (take.auditionID.map(allDemoAuditionIDs.contains) ?? false)
    }

    static func isDemoPractice(_ piece: PracticePiece) -> Bool {
        allDemoPracticeIDs.contains(piece.id)
            || (piece.auditionID.map(allDemoAuditionIDs.contains) ?? false)
    }

    static let defaultDemoSlate = SlateInfo(
        name: "Avery Vance",
        height: "5′ 10″",
        basedIn: "London / New York",
        representation: "Bramwell Talent"
    )

    // MARK: - Demo Auditions

    static func makeDemoAuditions(now: Date = Date()) -> [Audition] {
        [
            makeMidnightDispatch(now: now),
            makeQuietHorizon(now: now),
            makeAtlasRunning(now: now),
            makeGlassHarbor(now: now)
        ]
    }

    static func makeDemoTakes(now: Date = Date()) -> [Take] {
        let dispatchDir = MediaStore.directory("audition-\(midnightDispatchID.uuidString)")
        let atlasDir = MediaStore.directory("audition-\(atlasRunningID.uuidString)")
        return [
            Take(
                id: dispatchTake1ID,
                number: 1,
                duration: 2.5,
                recordedAt: now.addingTimeInterval(-3_600 * 5),
                isCircled: false,
                notes: ["Slightly fast on the radio cue."],
                fileURL: dispatchDir.appendingPathComponent("demo-dispatch-s1-t1.mp4"),
                auditionID: midnightDispatchID,
                sceneIndex: 0
            ),
            Take(
                id: dispatchTake2ID,
                number: 2,
                duration: 2.5,
                recordedAt: now.addingTimeInterval(-3_600 * 3),
                isCircled: true,
                notes: ["Strong stillness before final line.", "Clean eyeline just left of lens."],
                fileURL: dispatchDir.appendingPathComponent("demo-dispatch-s1-t2.mp4"),
                auditionID: midnightDispatchID,
                sceneIndex: 0
            ),
            Take(
                id: dispatchTake3ID,
                number: 3,
                duration: 2.5,
                recordedAt: now.addingTimeInterval(-3_600 * 1.5),
                isCircled: false,
                notes: ["Warmer alternate take."],
                fileURL: dispatchDir.appendingPathComponent("demo-dispatch-s1-t3.mp4"),
                auditionID: midnightDispatchID,
                sceneIndex: 0
            ),
            Take(
                id: dispatchScene2TakeID,
                number: 1,
                duration: 2.5,
                recordedAt: now.addingTimeInterval(-3_600),
                isCircled: true,
                notes: ["Sharp pace for interrogation confrontation."],
                fileURL: dispatchDir.appendingPathComponent("demo-dispatch-s2-t1.mp4"),
                auditionID: midnightDispatchID,
                sceneIndex: 1
            ),
            Take(
                id: atlasTake1ID,
                number: 1,
                duration: 2.5,
                recordedAt: now.addingTimeInterval(-3_600 * 12),
                isCircled: true,
                notes: ["Wide horizontal framing · clean start & hold."],
                fileURL: atlasDir.appendingPathComponent("demo-atlas-movement-t1.mp4"),
                auditionID: atlasRunningID,
                sceneIndex: 0
            )
        ]
    }

    static func makeDemoPracticePieces() -> [PracticePiece] {
        let goodbyeScene = ScriptScene(
            number: 1,
            title: "Platform 4",
            heading: "INT. STATION — NIGHT",
            lines: [
                ScriptLine(character: "READER", text: "The 6:15 just pulled in.", isMine: false),
                ScriptLine(character: "MAYA", text: "I know the train leaves at six. I just didn't think you'd come.", isMine: true),
                ScriptLine(character: "READER", text: "You asked me to.", isMine: false),
                ScriptLine(character: "MAYA", text: "I asked you to say goodbye.", isMine: true),
                ScriptLine(character: "READER", text: "Is that all you want?", isMine: false),
                ScriptLine(character: "MAYA", text: "No. But it's all I know how to ask for.", isMine: true)
            ],
            estimatedSeconds: 38
        )

        let coffeeScene = ScriptScene(
            number: 1,
            title: "Morning Rush",
            heading: "INT. CORNER ESPRESSO BAR — MORNING",
            lines: [
                ScriptLine(character: "SAM", text: "Four oat cortados, zero foam, and please tell me the espresso machine isn't still smoking.", isMine: false),
                ScriptLine(character: "KATE", text: "It wasn't smoke, Sam. It was dramatic steam.", isMine: true),
                ScriptLine(character: "SAM", text: "The fire marshal literally asked for your autograph on a citation.", isMine: false),
                ScriptLine(character: "KATE", text: "Which proves my point. Nobody ignores theater.", isMine: true),
                ScriptLine(character: "SAM", text: "We open in eleven minutes.", isMine: false),
                ScriptLine(character: "KATE", text: "Then start grinding beans and stop stifling my process.", isMine: true)
            ],
            estimatedSeconds: 32
        )

        let learScene = ScriptScene(
            number: 1,
            title: "Storm Monologue",
            heading: "EXT. HEATH — NIGHT",
            lines: [
                ScriptLine(character: "LEAR", text: "Blow, winds, and crack your cheeks! Rage! Blow!", isMine: true),
                ScriptLine(character: "LEAR", text: "You cataracts and hurricanoes, spout till you have drenched our steeples.", isMine: true),
                ScriptLine(character: "LEAR", text: "Rumble thy bellyful! Spit, fire! Spout, rain!", isMine: true),
                ScriptLine(character: "LEAR", text: "I never gave you kingdom, called you children; you owe me no subscription.", isMine: true)
            ],
            estimatedSeconds: 45
        )

        return [
            PracticePiece(
                id: practiceGoodbyeID,
                title: "A late goodbye",
                detail: "2 scenes · Dramatic two-hander",
                linesLearned: 2,
                linesTotal: goodbyeScene.lines.filter(\.isMine).count,
                character: "MAYA",
                scene: goodbyeScene,
                takesRecorded: 0
            ),
            PracticePiece(
                id: practiceCoffeeID,
                title: "Morning Rush — Comedy",
                detail: "Demo drill · Fast timing two-hander",
                linesLearned: 2,
                linesTotal: coffeeScene.lines.filter(\.isMine).count,
                character: "KATE",
                scene: coffeeScene,
                takesRecorded: 1
            ),
            PracticePiece(
                id: practiceLearID,
                title: "King Lear — Act III",
                detail: "Demo monologue · Classical verse",
                linesLearned: 3,
                linesTotal: learScene.lines.filter(\.isMine).count,
                character: "LEAR",
                scene: learScene,
                takesRecorded: 2
            )
        ]
    }

    // MARK: - Individual Audition Fixtures

    private static func makeQuietHorizon(now: Date) -> Audition {
        let cal = Calendar.current
        let due = cal.date(byAdding: .day, value: 3, to: now) ?? now
        let callback = cal.date(byAdding: .day, value: 8, to: now) ?? due
        let shoot = cal.date(byAdding: .day, value: 24, to: now) ?? due

        let scene1 = ScriptScene(
            number: 1,
            title: "Scene 1 — Station Platform",
            heading: "INT. TRAIN STATION — NIGHT",
            lines: [
                ScriptLine(character: "READER", text: "You left your coat on the bench.", isMine: false),
                ScriptLine(character: "MAYA", text: "I know the train leaves at six. I just didn't think you'd come.", isMine: true),
                ScriptLine(character: "READER", text: "You asked me to.", isMine: false),
                ScriptLine(character: "MAYA", text: "I asked you to say goodbye.", isMine: true),
                ScriptLine(character: "READER", text: "Is that all you want?", isMine: false),
                ScriptLine(character: "MAYA", text: "(pause)", isMine: true),
                ScriptLine(character: "MAYA", text: "No. But it's all I know how to ask for.", isMine: true)
            ],
            estimatedSeconds: 50
        )
        let scene2 = ScriptScene(
            number: 2,
            title: "Scene 2 — Overpass Call",
            heading: "EXT. PEDESTRIAN OVERPASS — DAWN",
            lines: [
                ScriptLine(character: "READER", text: "The board already moved the departure window up.", isMine: false),
                ScriptLine(character: "MAYA", text: "Tell them I'm still three exits out, and I'm not turning around.", isMine: true),
                ScriptLine(character: "READER", text: "Maya, if you miss this window there isn't another.", isMine: false),
                ScriptLine(character: "MAYA", text: "Then tell them to hold the door.", isMine: true)
            ],
            estimatedSeconds: 36
        )

        return Audition(
            id: quietHorizonID,
            project: "The Quiet Horizon",
            projectType: "Feature Film",
            role: "Maya",
            roleSize: "Lead",
            castingOffice: "Sarah Finn Casting",
            due: due,
            asks: ["Slate at head", "Scene 1", "Scene 2", "Full-body shot (optional)"],
            pieces: [
                Piece(kind: .slate, title: "Slate", detail: "Name, height, city & rep", isDone: false),
                Piece(kind: .fullLength, title: "Full-body shot", detail: "Head-to-toe pan, optional", isDone: false, isOptional: true),
                Piece(kind: .scene, title: scene1.title, detail: "7 lines · Reader cues ready", isDone: false),
                Piece(kind: .scene, title: scene2.title, detail: "4 lines · Exterior dawn confrontation", isDone: false)
            ],
            scenes: [scene1, scene2],
            scriptText: """
            INT. TRAIN STATION — NIGHT

            MAYA
            I know the train leaves at six.
            """,
            destination: .email,
            destinationWasChosen: true,
            destinationDetail: "submissions@sarahfinncasting.com",
            packageDeliverable: .combinedVideo,
            status: .due,
            castingNotes: "Grounded, minimal vocal push. Let the camera read what she holds back before her last line.",
            actorNotes: "Objective: keep him from getting on that train without admitting it.",
            materialKind: .sides,
            projectDetails: AuditionProjectDetails(
                synopsis: "An air-traffic investigator discovers two passengers who boarded a flight that landed four hours early.",
                productionCompany: "Northlight Pictures",
                director: "Claire Callahan",
                payTerms: "SAG-AFTRA Schedule F",
                unionStatus: "SAG-AFTRA Theatrical",
                castingArea: "Los Angeles / Remote",
                productionLocation: "Vancouver, BC"
            ),
            importantDates: [
                AuditionDate(kind: .submissionDeadline, date: due, label: "Self-tape deadline"),
                AuditionDate(kind: .callback, date: callback, label: "Director chemistry callback"),
                AuditionDate(kind: .productionStart, date: shoot, label: "Principal photography")
            ],
            roleBreakdowns: [
                AuditionRoleBreakdown(
                    name: "MAYA",
                    description: "Sharp, fiercely controlled acoustic analyst hiding exhaustion beneath dry humour.",
                    ageRange: "26-34",
                    gender: "Female",
                    skills: ["British or neutral US accent"]
                )
            ],
            submissionInstructions: AuditionSubmissionInstructions(
                slateRequirements: ["Name, height, location & representation at the top"],
                videoOrientation: "1080p Horizontal (16:9)",
                maxTakes: 2,
                acceptedFormats: ["MP4 (H.264)"],
                fileNamingRule: "Lastname_Firstname_Maya_Scene",
                fileNameTemplate: "{lastName}_{firstName}_{role}_{scene}"
            )
        )
    }

    private static func makeMidnightDispatch(now: Date) -> Audition {
        let dir = MediaStore.directory("audition-\(midnightDispatchID.uuidString)")
        let due = Calendar.current.date(byAdding: .hour, value: 14, to: now) ?? now

        let scene1 = ScriptScene(
            number: 1,
            title: "Scene 1 — Precinct Hall",
            heading: "INT. PRECINCT CORRIDOR — 02:14 AM",
            lines: [
                ScriptLine(character: "READER", text: "Internal Affairs cleared the locker room ten minutes ago.", isMine: false),
                ScriptLine(character: "REYES", text: "Then someone signed the evidence log with my badge after midnight.", isMine: true),
                ScriptLine(character: "READER", text: "Careful how loudly you say that.", isMine: false),
                ScriptLine(character: "REYES", text: "I'm not saying it loudly. I'm saying it on record.", isMine: true)
            ],
            estimatedSeconds: 42
        )
        let scene2 = ScriptScene(
            number: 2,
            title: "Scene 2 — Interrogation Room B",
            heading: "INT. INTERROGATION B — CONTINUOUS",
            lines: [
                ScriptLine(character: "READER", text: "You don't have a warrant for this call log.", isMine: false),
                ScriptLine(character: "REYES", text: "Good thing it came from your own voicemail, Counselor.", isMine: true)
            ],
            estimatedSeconds: 28
        )

        return Audition(
            id: midnightDispatchID,
            project: "Midnight Dispatch",
            projectType: "Limited Series",
            role: "Detective Reyes",
            roleSize: "Recurring Guest Star",
            castingOffice: "Greenstein / Daniel Casting",
            due: due,
            asks: ["Slate", "Scene 1", "Scene 2"],
            pieces: [
                Piece(kind: .slate, title: "Slate", detail: "Ready to review", isDone: true),
                Piece(kind: .scene, title: scene1.title, detail: "3 takes recorded · Take 2 circled", isDone: true),
                Piece(kind: .scene, title: scene2.title, detail: "1 take recorded · Take 1 circled", isDone: true)
            ],
            scenes: [scene1, scene2],
            destination: .actorsAccess,
            destinationWasChosen: true,
            destinationDetail: "Actors Access · Eco Cast",
            packageDeliverable: .combinedVideo,
            status: .ready,
            slateVideoURL: dir.appendingPathComponent("demo-dispatch-slate.mp4"),
            castingNotes: "Keep both scenes wired and still — zero melodrama.",
            actorNotes: "Play Demo Tape Check & Preview to inspect chapters and export!",
            materialKind: .sides,
            submissionInstructions: AuditionSubmissionInstructions(
                slateRequirements: ["Frame from chest up, slate before Scene 1"],
                videoOrientation: "16:9 Horizontal",
                acceptedFormats: ["MP4"],
                fileNameTemplate: "{lastName}_{firstName}_{project}_{role}"
            )
        )
    }

    private static func makeAtlasRunning(now: Date) -> Audition {
        let dir = MediaStore.directory("audition-\(atlasRunningID.uuidString)")
        let exports = MediaStore.directory("Exports")
        let due = Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now

        let movementScene = ScriptScene(
            number: 1,
            title: "Movement & Slate",
            heading: "EXT. CITY TRACK — GOLDEN HOUR",
            lines: [
                ScriptLine(character: "RUNNER #1", text: "Smile direct to camera, jog three strides past lens, hold strong finish beat.", isMine: true)
            ],
            estimatedSeconds: 20
        )

        return Audition(
            id: atlasRunningID,
            project: "Atlas Running — Launch Anthem",
            projectType: "Commercial",
            role: "Runner #1",
            roleSize: "Principal",
            castingOffice: "House Casting",
            due: due,
            asks: ["Slate", "Movement clip", "Full-body shot"],
            pieces: [
                Piece(kind: .slate, title: "Slate", detail: "Personality + hands frame", isDone: true),
                Piece(kind: .fullLength, title: "Full-body shot", detail: "Athletic profile", isDone: true),
                Piece(kind: .scene, title: movementScene.title, detail: "Take 1 circled", isDone: true)
            ],
            scenes: [movementScene],
            destination: .castingNetworks,
            destinationWasChosen: true,
            destinationDetail: "Casting Networks",
            packageDeliverable: .combinedVideo,
            status: .exported,
            slateVideoURL: dir.appendingPathComponent("demo-atlas-slate.mp4"),
            fullLengthVideoURL: dir.appendingPathComponent("demo-atlas-fullbody.mp4"),
            exportedFileURL: exports.appendingPathComponent("DEMO_VANCE_RUNNER1_ATLAS.mp4"),
            castingNotes: "Natural athleticism, genuine grin, zero posing.",
            materialKind: .movement
        )
    }

    private static func makeGlassHarbor(now: Date) -> Audition {
        let sent = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        let due = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let expires = Calendar.current.date(byAdding: .day, value: 20, to: now) ?? now

        let scene1 = ScriptScene(
            number: 1,
            title: "Scene 1 — Harbor Lab",
            heading: "INT. MARINE LAB — NIGHT",
            lines: [
                ScriptLine(character: "READER", text: "Did the telemetry come back clean?", isMine: false),
                ScriptLine(character: "DR. NAIR", text: "Clean? Look at the depth curve at forty meters.", isMine: true)
            ],
            estimatedSeconds: 30
        )

        return Audition(
            id: glassHarborID,
            project: "Glass Harbor",
            projectType: "TV Drama",
            role: "Dr. Priya Nair",
            roleSize: "Series Regular",
            castingOffice: "Spotlight / BBC Drama",
            due: due,
            asks: ["Slate", "Scene 1"],
            pieces: [
                Piece(kind: .slate, title: "Slate", detail: "Submitted", isDone: true),
                Piece(kind: .scene, title: scene1.title, detail: "Submitted", isDone: true)
            ],
            scenes: [scene1],
            destination: .emailOrLink,
            destinationWasChosen: true,
            destinationDetail: "casting@glassharbor.co.uk",
            packageDeliverable: .combinedVideo,
            status: .sent,
            sentDate: sent,
            shareLink: URL(string: "https://onetake.example/demo/glass-harbor"),
            shareLinkExpires: expires,
            materialKind: .sides
        )
    }

    // MARK: - One-Tap Notice Review Demo Draft

    static func sampleNoticeDraft(now: Date = Date()) -> NoticeParser.Draft {
        let cal = Calendar.current
        let due = cal.date(byAdding: .day, value: 4, to: now) ?? now
        let callback = cal.date(byAdding: .day, value: 11, to: now) ?? due
        let filmStart = cal.date(byAdding: .day, value: 28, to: now) ?? due

        let rawNotice = """
        CASTING NOTICE — NORTHSTAR PICTURES
        Project: THE GLASS LIGHTHOUSE (Feature Film)
        Director: Elena Vance | Casting: Telsey + Company
        Submit to: submissions@telseycasting.example
        Self-Tape Deadline: \(due.formatted(date: .abbreviated, time: .omitted))
        Callbacks: \(callback.formatted(date: .abbreviated, time: .omitted))
        Shoot Window: \(filmStart.formatted(date: .abbreviated, time: .omitted))
        Notes: 1080p horizontal framing, slate at head, full-body shot optional. Name file {lastName}_{firstName}_{role}.

        ROLES:
        NORA (28-36, Female, Lead) — Coastal hydrographer who refuses to evacuate before the storm wall lands.
        GARRETT (32-42, Male, Supporting) — Harbourmaster with twenty years of unspoken debts.

        INT. LIGHTHOUSE WATCHROOM — NIGHT

        NORA
        The barometer dropped nine millibars since noon. Nobody leaves the pier.

        GARRETT
        You don't run the harbour, Nora. Take the last boat.

        NORA
        Then log me as missing, because I'm keeping the beam lit.
        """

        let sourceID = UUID()
        let parsedScenes = ScriptParser.parseScenes(from: rawNotice, myRole: "Nora")
        var draft = NoticeParser.Draft()
        draft.project = "The Glass Lighthouse"
        draft.projectType = "Feature Film"
        draft.role = "Nora"
        draft.candidateRoles = ["Nora", "Garrett"]
        draft.castingOffice = "Telsey + Company"
        draft.projectDetails = AuditionProjectDetails(
            synopsis: "A hydrographer stays behind in an automated storm beacon to prove an offshore fault triggered the blackout.",
            productionCompany: "Northstar Pictures",
            director: "Elena Vance",
            payTerms: "SAG-AFTRA Modified Low Budget",
            unionStatus: "SAG-AFTRA",
            castingArea: "New York / Remote"
        )
        draft.importantDates = [
            AuditionDate(kind: .submissionDeadline, date: due, label: "Self-tape deadline", sourceID: sourceID),
            AuditionDate(kind: .callback, date: callback, label: "Callbacks", sourceID: sourceID),
            AuditionDate(kind: .productionStart, date: filmStart, label: "Filming starts", sourceID: sourceID)
        ]
        draft.roleBreakdowns = [
            AuditionRoleBreakdown(
                name: "Nora",
                description: "Coastal hydrographer who refuses to evacuate before the storm wall lands.",
                ageRange: "28-36",
                gender: "Female"
            ),
            AuditionRoleBreakdown(
                name: "Garrett",
                description: "Harbourmaster with twenty years of unspoken debts.",
                ageRange: "32-42",
                gender: "Male"
            )
        ]
        draft.due = due
        draft.asks = ["Slate at head", "Scene 1", "Full-body shot (optional)"]
        draft.isFullBodyShotOptional = true
        draft.sourceText = rawNotice
        draft.destination = .email
        draft.destinationDetail = "submissions@telseycasting.example"
        draft.destinationWasDetected = true
        draft.customScenes = parsedScenes
        draft.scenes = max(1, parsedScenes.count)
        draft.castingNotes = "1080p horizontal framing, slate at head, full-body shot optional."
        draft.submissionInstructions = AuditionSubmissionInstructions(
            slateRequirements: ["Slate at head"],
            videoOrientation: "1080p Horizontal",
            acceptedFormats: ["MP4"],
            fileNamingRule: "Lastname_Firstname_Role",
            fileNameTemplate: "{lastName}_{firstName}_{role}"
        )
        draft.noticeSources = [
            AuditionSource(id: sourceID, name: "Demo Casting Notice.txt", kind: .castingNotice, pageNumber: 1, pageCount: 1)
        ]
        return draft
    }
}
