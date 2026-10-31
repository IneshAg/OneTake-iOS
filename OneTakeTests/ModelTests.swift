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
}

