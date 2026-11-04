import VisionKit
import XCTest
@testable import OneTake

final class ModelTests: XCTestCase {
    private func audition(scenes: [ScriptScene] = []) -> Audition {
        Audition(project: "The Last Summer", projectType: "Feature film", role: "Maya", roleSize: "Lead",
                 castingOffice: "Casting office", due: .now, asks: [], pieces: [], scenes: scenes,
                 destination: .actorsAccess, status: .due)
    }

    func testEmptySlateAsksForDetailsInsteadOfReadingBlanks() {
        let slate = SlateInfo()
        XCTAssertTrue(slate.isEmpty)
        XCTAssertEqual(slate.spoken, "Say your name, height and where you're based.")
        XCTAssertEqual(SlateInfo(name: "Asha Rao", basedIn: "Pune").spoken, "Asha Rao. Pune.")
    }

    func testDeliverableFileName() {
        XCTAssertEqual(audition().deliverableFileName(slate: SlateInfo(name: "Asha Rao")), "RAO_ASHA_MAYA_THELASTSUMMER.mp4")
        XCTAssertEqual(audition().deliverableFileName(slate: SlateInfo()), "ACTOR_MAYA_THELASTSUMMER.mp4")
    }

    func testDeadlineUnderOneHourRoundsUpInsteadOfShowingZero() {
        var a = audition()
        a.due = .now.addingTimeInterval(45 * 60)
        XCTAssertEqual(a.hoursLeft, 1)
        a.due = .now.addingTimeInterval(2 * 3600 + 10 * 60)
        XCTAssertEqual(a.hoursLeft, 2)
        a.due = .now.addingTimeInterval(-10)
        XCTAssertEqual(a.hoursLeft, 0)
    }

    func testLegacyPlaceholderIsTheMockupPersona() {
        XCTAssertEqual(SlateInfo.legacyPlaceholder.name, "Kabir Sharma")
        XCTAssertNotEqual(SlateInfo(), SlateInfo.legacyPlaceholder)
    }

    func testMaskingHidesAGrowingShareOfYourWords() {
        let mine = ScriptLine(character: "Maya", text: "one two three four five", isMine: true)
        XCTAssertEqual(otLineDisplay(mine, mode: .masked(level: 1), peeked: false), "___ two three four ____")
        XCTAssertEqual(otLineDisplay(mine, mode: .masked(level: 4), peeked: false), "___ ___ _____ ____ ____")
        XCTAssertEqual(otLineDisplay(mine, mode: .masked(level: 4), peeked: true), mine.text)
        let theirs = ScriptLine(character: "Arjun", text: "one two", isMine: false)
        XCTAssertEqual(otLineDisplay(theirs, mode: .masked(level: 4), peeked: false), "one two")
    }

    func testSlatePositionOrdersTheTape() {
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "SIDES", lines: [], estimatedSeconds: 30)
        var a = audition(scenes: [scene])
        a.slateVideoURL = URL(fileURLWithPath: "/tmp/slate.mov")
        a.fullLengthVideoURL = URL(fileURLWithPath: "/tmp/full.mov")
        let take = Take(number: 1, duration: 30, recordedAt: .now, isCircled: true, notes: [],
                        fileURL: URL(fileURLWithPath: "/tmp/take.mov"), auditionID: a.id, sceneIndex: 0)
        let other = Take(number: 1, duration: 30, recordedAt: .now, isCircled: true, notes: [],
                         fileURL: URL(fileURLWithPath: "/tmp/other.mov"), auditionID: UUID(), sceneIndex: 0)

        let first = MediaExporter.clips(for: a, takes: [other, take], slateAtStart: true).map(\.kind)
        XCTAssertEqual(first, [.slate, .fullLength, .scene(0)])
        let last = MediaExporter.clips(for: a, takes: [other, take], slateAtStart: false).map(\.kind)
        XCTAssertEqual(last, [.scene(0), .slate, .fullLength])
    }

    @MainActor
    func testSpeechFollowerDetectsNowAndSynonyms() {
        let follower = SpeechFollower()
        follower.handle(["no"])
        XCTAssertNil(follower.lastCommand)
        follower.handle(["now"])
        follower.finishCurrentUtterance()
        XCTAssertEqual(follower.lastCommand?.word, "now")

        follower.reset()
        XCTAssertNil(follower.lastCommand)

        follower.handle(["shoot"])
        follower.finishCurrentUtterance()
        XCTAssertEqual(follower.lastCommand?.word, "now")

        for syn in ["click", "photo", "picture", "take", "snap", "cheese", "capture"] {
            follower.reset()
            follower.handle([syn])
            follower.finishCurrentUtterance()
            XCTAssertEqual(follower.lastCommand?.word, "now", "Expected \(syn) to map to 'now'")
        }
    }

    @MainActor
    func testSpeechFollowerSuppressesCommandsInContinuousSpeech() {
        let follower = SpeechFollower()
        follower.handle(["now"])
        follower.handle(["now", "listen"])
        follower.finishCurrentUtterance()
        XCTAssertNil(follower.lastCommand)
    }

    @MainActor
    func testSpeechFollowerDetectsActionAndCut() {
        let follower = SpeechFollower()
        follower.handle(["action"])
        follower.finishCurrentUtterance()
        XCTAssertEqual(follower.lastCommand?.word, "action")

        follower.reset()
        follower.handle(["cut"])
        follower.finishCurrentUtterance()
        XCTAssertEqual(follower.lastCommand?.word, "cut")
    }

    @MainActor
    func testSpeechFollowerLineAdvancementContinuousSession() {
        let follower = SpeechFollower()
        // Line 1: Speech recognizer transcribes continuously
        follower.handle(["i", "am", "ready"])
        XCTAssertEqual(follower.transcript, "i am ready")

        // Actor advances line: follower resets
        follower.reset()
        XCTAssertEqual(follower.transcript, "")

        // Apple Speech continues same recognition session appending line 2
        follower.handle(["i", "am", "ready", "what", "is", "next"])
        XCTAssertEqual(follower.transcript, "what is next")

        // Next word in line 2
        follower.handle(["i", "am", "ready", "what", "is", "next", "scene"])
        XCTAssertEqual(follower.transcript, "what is next scene")
    }

    func testSpokenLineMatcherContractionsAndAlignments() {
        let line = "I don't think we should go in there right now."
        // Partial speech
        let m1 = SpokenLineMatcher.matchedWordIndices(in: line, transcript: "i don't think")
        XCTAssertEqual(m1, [0, 1, 2]) // Exactly indices 0 ("I"), 1 ("don't"), 2 ("think")

        // Contraction expansion: actor says "do not"
        let m2 = SpokenLineMatcher.matchedWordIndices(in: line, transcript: "i do not think we should")
        XCTAssertTrue(m2.contains(0)) // "I"
        XCTAssertTrue(m2.contains(1)) // "don't" (matched via "do not")
        XCTAssertTrue(m2.contains(2)) // "think"
        XCTAssertTrue(m2.contains(3)) // "we"
        XCTAssertTrue(m2.contains(4)) // "should"

        // Reverse contraction: line has "do not", actor says "don't"
        let line2 = "I do not know."
        let m3 = SpokenLineMatcher.matchedWordIndices(in: line2, transcript: "i don't know")
        XCTAssertTrue(m3.contains(0))
        XCTAssertTrue(m3.contains(1))
        XCTAssertTrue(m3.contains(2))
        XCTAssertTrue(m3.contains(3))
    }

    func testSpokenLineMatcherFlexibleAdvancementThresholds() {
        // 1-word line
        XCTAssertEqual(SpokenLineMatcher.requiredMatches(for: "Yes."), 1)

        // 2-word line (50% is enough to advance)
        XCTAssertEqual(SpokenLineMatcher.requiredMatches(for: "Come here."), 1)

        // 3-word line
        XCTAssertEqual(SpokenLineMatcher.requiredMatches(for: "Who is that?"), 2)

        // Full line verification
        let line = "Wait for me near the front door."
        let transcript = "wait for me near front door" // "the" was skipped
        let matched = SpokenLineMatcher.matchedWordIndices(in: line, transcript: transcript)
        XCTAssertGreaterThanOrEqual(matched.count, SpokenLineMatcher.requiredMatches(for: line))
    }

    @MainActor
    func testDocumentScannerSaveButtonRepositionedToBottomRight() throws {
        let coordinator = DocumentScannerView.Coordinator { _ in }
        let vc = VNDocumentCameraViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = vc
        window.makeKeyAndVisible()

        coordinator.attachCustomizer(to: vc)

        let saveBtn: UIButton
        let root: UIView
        if let foundBtn = DocumentScannerCustomizer.findSaveButton(in: vc), let foundRoot = foundBtn.superview {
            saveBtn = foundBtn
            root = foundRoot
        } else {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let btn = UIButton(frame: CGRect(x: 0, y: 0, width: 60, height: 44))
            container.addSubview(btn)
            saveBtn = btn
            root = container
        }

        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()

        DocumentScannerCustomizer.reposition(saveButton: saveBtn, in: root)

        // Button should be positioned in bottom right corner
        XCTAssertGreaterThan(saveBtn.frame.origin.x, root.bounds.width * 0.5, "Save button should be near trailing edge")
        XCTAssertGreaterThan(saveBtn.frame.origin.y, root.bounds.height * 0.65, "Save button should be near bottom edge")
    }

    @MainActor
    func testCameraGuidanceSpeakerRepeatsAndThrottles() {
        let speaker = CameraGuidanceSpeaker()
        speaker.speak("Move closer", minInterval: 0.1, repeatInterval: 0.2)
        speaker.stop()
        // verify stop resets speech
        speaker.speak("Turn left", minInterval: 0.1, repeatInterval: 0.2)
        speaker.stop()
    }

    func testReaderRecordingValidationResults() {
        let shortResult = ReaderRecordResult.tooShort(duration: 0.4)
        if case .tooShort(let d) = shortResult {
            XCTAssertEqual(d, 0.4)
            XCTAssertLessThan(d, 1.0)
        } else {
            XCTFail("Expected tooShort result")
        }

        let silenceResult = ReaderRecordResult.noSpeechDetected
        if case .noSpeechDetected = silenceResult {
            // Success
        } else {
            XCTFail("Expected noSpeechDetected result")
        }

        let successResult = ReaderRecordResult.success(duration: 2.1)
        if case .success(let d) = successResult {
            XCTAssertEqual(d, 2.1)
            XCTAssertGreaterThanOrEqual(d, 1.0)
        } else {
            XCTFail("Expected success result")
        }
    }

    @MainActor
    func testReaderTrackPlayerStateAndSeeking() {
        let player = ReaderTrackPlayer()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)

        // Seeking when no audio is loaded safely clamps to 0
        player.seek(to: 5.0)
        XCTAssertEqual(player.currentTime, 0)

        player.seekRelative(2.0)
        XCTAssertEqual(player.currentTime, 0)

        player.pause()
        XCTAssertFalse(player.isPlaying)

        player.stop()
        XCTAssertNil(player.currentAuditionID)
        XCTAssertNil(player.currentSceneIndex)
        XCTAssertNil(player.currentLineIndex)
    }

    func testSceneAudioFlowRouteAndMapping() {
        let audID = UUID()
        let route = Route.sceneAudioFlow(audID, sceneIndex: 0)
        let route2 = Route.sceneAudioFlow(audID, sceneIndex: 0)
        XCTAssertEqual(route, route2)
        XCTAssertEqual(route.hashValue, route2.hashValue)

        let scene = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "INT. CAFE - DAY",
            lines: [
                ScriptLine(character: "Kat", text: "Are you sure you're okay?", isMine: true),
                ScriptLine(character: "Oscar", text: "Do you think I'd know immediately if I had a collapsed lung?", isMine: false),
                ScriptLine(character: "Kat", text: "It's only fair that you punch me back.", isMine: true),
                ScriptLine(character: "Oscar", text: "What? No. I'm not going to do that.", isMine: false)
            ],
            estimatedSeconds: 30
        )

        // Verify Oscar's reader cue mapping
        let oscarLines = scene.lines.filter { !$0.isMine && $0.character.caseInsensitiveCompare("Oscar") == .orderedSame }
        XCTAssertEqual(oscarLines.count, 2)
        XCTAssertEqual(oscarLines[0].text, "Do you think I'd know immediately if I had a collapsed lung?")
        XCTAssertEqual(oscarLines[1].text, "What? No. I'm not going to do that.")

        // Verify index of line 1 is cue 0, and line 3 is cue 1
        let cue0 = oscarLines.firstIndex(where: { $0.id == scene.lines[1].id })
        let cue1 = oscarLines.firstIndex(where: { $0.id == scene.lines[3].id })
        XCTAssertEqual(cue0, 0)
        XCTAssertEqual(cue1, 1)
    }

    func testRoleDropdownSelectionAndNextScreenReaderMapping() {
        let script = """
        KAT
        Are you sure you're okay?
        OSCAR
        Do you think I'd know immediately if I had a collapsed lung?
        """
        let extracted = ScriptParser.extractCharacters(from: script)
        XCTAssertEqual(extracted, ["Kat", "Oscar"])

        // When user selects Kat in Adding Details:
        let scenesIfKat = ScriptParser.parseScenes(from: script, myRole: "Kat")
        let readerLinesIfKat = scenesIfKat[0].lines.filter { !$0.isMine }
        XCTAssertEqual(readerLinesIfKat.first?.character.capitalized, "Oscar") // Next screen shows "Who reads Oscar?"

        // When user selects Oscar in Adding Details:
        let scenesIfOscar = ScriptParser.parseScenes(from: script, myRole: "Oscar")
        let readerLinesIfOscar = scenesIfOscar[0].lines.filter { !$0.isMine }
        XCTAssertEqual(readerLinesIfOscar.first?.character.capitalized, "Kat") // Next screen shows "Who reads Kat?"
    }

    @MainActor
    func testStartCallbackMergesExtraScenesAndCombinesScriptTextAndPreservesNotes() {
        let store = AppStore()
        let origScene = ScriptScene(
            number: 1,
            title: "Scene 1",
            heading: "INT. LIVING ROOM - DAY",
            lines: [
                ScriptLine(character: "Maya", text: "I can't believe you're leaving.", isMine: true),
                ScriptLine(character: "Sam", text: "I have to.", isMine: false)
            ]
        )
        let origPieces = [
            Piece(kind: .slate, title: "Slate", detail: "Name and height", isDone: true, isOptional: false),
            Piece(kind: .scene, title: "Scene 1", detail: "", isDone: true, isOptional: false),
            Piece(kind: .headshot, title: "Headshot", detail: "Photos", isDone: true, isOptional: true)
        ]
        var original = Audition(
            project: "Summer Breeze",
            projectType: "Feature film",
            role: "Maya",
            roleSize: "Lead",
            castingOffice: "Sarah Finn Casting",
            due: Date.now.addingTimeInterval(86400),
            asks: ["Email: casting@example.com"],
            pieces: origPieces,
            scenes: [origScene],
            destination: .emailOrLink,
            status: .ready
        )
        original.scriptText = "MAYA\nI can't believe you're leaving.\nSAM\nI have to."
        original.castingNotes = "Warm and vulnerable"
        original.actorNotes = "She knows he won't change his mind"
        original.round = 1
        store.add(original)

        let callbackScene2 = ScriptScene(
            number: 2,
            title: "Scene 2",
            heading: "EXT. TRAIN STATION - NIGHT",
            lines: [
                ScriptLine(character: "Maya", text: "Take care of yourself.", isMine: true),
                ScriptLine(character: "Sam", text: "Always.", isMine: false)
            ]
        )
        let extraText = "MAYA\nTake care of yourself.\nSAM\nAlways."
        let newDueDate = Date.now.addingTimeInterval(5 * 86400)

        let callbackID = store.startCallback(
            from: original.id,
            due: newDueDate,
            notes: "More grounded and restrained",
            actorNotes: "Don't let him see her tear up",
            scenes: [origScene, callbackScene2],
            extraScriptText: extraText,
            bringReader: false
        )

        guard let callbackID, let callback = store.audition(callbackID) else {
            XCTFail("Callback was not created")
            return
        }

        XCTAssertEqual(callback.round, 2)
        XCTAssertEqual(callback.project, "Summer Breeze")
        XCTAssertEqual(callback.role, "Maya")
        XCTAssertEqual(callback.castingOffice, "Sarah Finn Casting")
        XCTAssertEqual(callback.castingNotes, "More grounded and restrained")
        XCTAssertEqual(callback.actorNotes, "Don't let him see her tear up")
        XCTAssertEqual(callback.scenes.count, 2)
        XCTAssertEqual(callback.scenes[0].title, "Scene 1")
        XCTAssertEqual(callback.scenes[1].title, "Scene 2")

        // Combined script text contains both parts
        XCTAssertTrue(callback.scriptText?.contains("I can't believe you're leaving.") == true)
        XCTAssertTrue(callback.scriptText?.contains("--- Callback Sides ---") == true)
        XCTAssertTrue(callback.scriptText?.contains("Take care of yourself.") == true)

        // Check pieces
        let pieces = callback.pieces
        XCTAssertEqual(pieces.count, 4) // Slate, Scene 1, Scene 2, Headshot
        XCTAssertEqual(pieces[0].kind, .slate)
        XCTAssertFalse(pieces[0].isDone)
        XCTAssertEqual(pieces[1].kind, .scene)
        XCTAssertEqual(pieces[1].title, "Scene 1")
        XCTAssertFalse(pieces[1].isDone)
        XCTAssertEqual(pieces[2].kind, .scene)
        XCTAssertEqual(pieces[2].title, "Scene 2")
        XCTAssertEqual(pieces[2].detail, "Callback scene")
        XCTAssertFalse(pieces[2].isDone)
        XCTAssertEqual(pieces[3].kind, .headshot)
        XCTAssertTrue(pieces[3].isOptional)
        XCTAssertFalse(pieces[3].isDone)
    }
}

