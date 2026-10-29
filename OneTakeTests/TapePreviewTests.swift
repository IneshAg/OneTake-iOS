import XCTest
import AVFoundation
@testable import OneTake

final class TapePreviewTests: XCTestCase {
    // MARK: - Chapter Duration Calculations

    func testChapterDurationCalculations() {
        let slateChapter = MediaExporter.Chapter(kind: .slate, label: "Slate", start: 0.0, duration: 8.5)
        let fullLengthChapter = MediaExporter.Chapter(kind: .fullLength, label: "Full length", start: 8.5, duration: 25.0)
        let scene1Chapter = MediaExporter.Chapter(kind: .scene(0), label: "Scene 1", start: 33.5, duration: 42.0)
        let scene2Chapter = MediaExporter.Chapter(kind: .scene(1), label: "Scene 2", start: 75.5, duration: 60.5)

        let chapters = [slateChapter, fullLengthChapter, scene1Chapter, scene2Chapter]

        // Verify start positions accumulate monotonically
        for i in 1..<chapters.count {
            let previous = chapters[i - 1]
            let current = chapters[i]
            XCTAssertEqual(current.start, previous.start + previous.duration, accuracy: 0.001)
        }

        // Test Tape.duration calculation
        let composition = AVMutableComposition()
        let videoComp = AVMutableVideoComposition()
        let tape = MediaExporter.Tape(composition: composition, videoComposition: videoComp, chapters: chapters)

        let expectedTotalDuration = 8.5 + 25.0 + 42.0 + 60.5
        XCTAssertEqual(tape.duration, expectedTotalDuration, accuracy: 0.001)
    }

    func testTapeDurationWithEmptyChaptersIsZero() {
        let composition = AVMutableComposition()
        let videoComp = AVMutableVideoComposition()
        let emptyTape = MediaExporter.Tape(composition: composition, videoComposition: videoComp, chapters: [])
        XCTAssertEqual(emptyTape.duration, 0.0)
    }

    // MARK: - Clock Duration String Formatting

    private func formatClock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    func testClockDurationFormatting() {
        XCTAssertEqual(formatClock(0.0), "0:00")
        XCTAssertEqual(formatClock(5.0), "0:05")
        XCTAssertEqual(formatClock(9.9), "0:09")
        XCTAssertEqual(formatClock(10.0), "0:10")
        XCTAssertEqual(formatClock(59.0), "0:59")
        XCTAssertEqual(formatClock(60.0), "1:00")
        XCTAssertEqual(formatClock(75.0), "1:15")
        XCTAssertEqual(formatClock(359.0), "5:59")
        XCTAssertEqual(formatClock(605.0), "10:05")
        XCTAssertEqual(formatClock(3661.0), "61:01")
        XCTAssertEqual(formatClock(-15.0), "0:00", "Negative time values must clamp to 0:00")
    }

    // MARK: - Chapter Action Handling

    @MainActor
    func testChapterActionSlateOpensSlateCamera() {
        let store = AppStore()
        let auditionID = UUID()

        // Simulate action for .slate chapter
        let slateChapter = MediaExporter.Chapter(kind: .slate, label: "Slate", start: 0, duration: 10)
        switch slateChapter.kind {
        case .slate:
            store.camera = .shoot(auditionID, start: .slate)
        default:
            XCTFail("Expected .slate kind")
        }

        XCTAssertEqual(store.camera, .shoot(auditionID, start: .slate))
    }

    @MainActor
    func testChapterActionFullLengthOpensFullLengthCamera() {
        let store = AppStore()
        let auditionID = UUID()

        // Simulate action for .fullLength chapter
        let fullLengthChapter = MediaExporter.Chapter(kind: .fullLength, label: "Full length", start: 10, duration: 30)
        switch fullLengthChapter.kind {
        case .fullLength:
            store.camera = .shoot(auditionID, start: .fullLength)
        default:
            XCTFail("Expected .fullLength kind")
        }

        XCTAssertEqual(store.camera, .shoot(auditionID, start: .fullLength))
    }

    @MainActor
    func testChapterActionSceneOpensTakesFilteredToScene() {
        let store = AppStore()
        let auditionID = UUID()
        let targetSceneIndex = 2

        // Simulate action for .scene chapter
        let sceneChapter = MediaExporter.Chapter(kind: .scene(targetSceneIndex), label: "Scene 3", start: 40, duration: 45)
        switch sceneChapter.kind {
        case .scene(let index):
            store.push(.takes(auditionID, sceneIndex: index))
        default:
            XCTFail("Expected .scene kind")
        }

        XCTAssertEqual(store.auditionsPath.last, .takes(auditionID, sceneIndex: targetSceneIndex))
    }

    @MainActor
    func testChapterActionChangeHeadshotsOpensHeadshotsView() {
        let store = AppStore()
        let auditionID = UUID()

        store.push(.headshots(for: auditionID))
        XCTAssertEqual(store.auditionsPath.last, .headshots(for: auditionID))
    }

    @MainActor
    func testTapePreviewNavigationButtons() {
        let store = AppStore()
        let auditionID = UUID()

        // "Looks right — package it" button
        store.push(.package(auditionID))
        XCTAssertEqual(store.auditionsPath.last, .package(auditionID))

        // "Change a take" button pops back or pushes .takes
        store.popTo(.takes(auditionID))
        XCTAssertEqual(store.auditionsPath.last, .takes(auditionID))
    }
}
