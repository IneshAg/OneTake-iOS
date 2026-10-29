import XCTest
@testable import OneTake

final class MediaExporterTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        MediaStore.deleteAll(["headshots", "Exports"])
        HeadshotStore.clearCache()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MediaExporterTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        MediaStore.deleteAll(["headshots", "Exports"])
        HeadshotStore.clearCache()
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeAudition(
        role: String = "Maya",
        project: String = "The Last Summer",
        scenes: [ScriptScene] = []
    ) -> Audition {
        Audition(
            project: project,
            projectType: "Feature film",
            role: role,
            roleSize: "Lead",
            castingOffice: "Paramount",
            due: .now,
            asks: [],
            pieces: [],
            scenes: scenes,
            destination: .actorsAccess,
            status: .due
        )
    }

    // MARK: - Deliverable File Name Formatting

    func testDeliverableFileNameFormatting() {
        let audition = makeAudition(role: "Maya", project: "The Last Summer")

        // Standard two-word name
        let slate = SlateInfo(name: "Asha Rao")
        XCTAssertEqual(audition.deliverableFileName(slate: slate), "RAO_ASHA_MAYA_THELASTSUMMER.mp4")

        // Empty slate falls back to ACTOR prefix
        let emptySlate = SlateInfo()
        XCTAssertEqual(audition.deliverableFileName(slate: emptySlate), "ACTOR_MAYA_THELASTSUMMER.mp4")

        // Single name
        let singleNameSlate = SlateInfo(name: "Cher")
        XCTAssertEqual(audition.deliverableFileName(slate: singleNameSlate), "CHER_MAYA_THELASTSUMMER.mp4")

        // Three-word name: last word becomes last name, first word becomes first name
        let threePartSlate = SlateInfo(name: "Mary Jane Watson")
        XCTAssertEqual(audition.deliverableFileName(slate: threePartSlate), "WATSON_MARY_MAYA_THELASTSUMMER.mp4")

        // Special characters and punctuation in role and project sanitized to uppercase letters
        let complexAudition = makeAudition(role: "Det. O'Connor-Smith", project: "Law & Order: SVU!")
        let sanitized = complexAudition.deliverableFileName(slate: slate)
        XCTAssertEqual(sanitized, "RAO_ASHA_DETOCONNORSMITH_LAWORDERSVU.mp4")
    }

    // MARK: - Clip Ordering (slateAtStart = true / false)

    func testClipOrderingSlateAtStartTrue() {
        let scene1 = ScriptScene(number: 1, title: "Scene 1", heading: "INT. COFFEE SHOP", lines: [], estimatedSeconds: 30)
        let scene2 = ScriptScene(number: 2, title: "Scene 2", heading: "EXT. PARK", lines: [], estimatedSeconds: 45)
        var audition = makeAudition(scenes: [scene1, scene2])

        let slateFile = tempDirectory.appendingPathComponent("slate.mov")
        let fullFile = tempDirectory.appendingPathComponent("full.mov")
        let take1File = tempDirectory.appendingPathComponent("scene1_take1.mov")
        let take2File = tempDirectory.appendingPathComponent("scene2_take1.mov")

        audition.slateVideoURL = slateFile
        audition.fullLengthVideoURL = fullFile

        let take1 = Take(number: 1, duration: 30, recordedAt: .now, isCircled: true, notes: [], fileURL: take1File, auditionID: audition.id, sceneIndex: 0)
        let take2 = Take(number: 1, duration: 45, recordedAt: .now, isCircled: true, notes: [], fileURL: take2File, auditionID: audition.id, sceneIndex: 1)

        let clips = MediaExporter.clips(for: audition, takes: [take1, take2], slateAtStart: true)
        let kinds = clips.map(\.kind)

        XCTAssertEqual(kinds, [.slate, .fullLength, .scene(0), .scene(1)], "Clips must start with slate and full length when slateAtStart is true")
    }

    func testClipOrderingSlateAtStartFalse() {
        let scene1 = ScriptScene(number: 1, title: "Scene 1", heading: "INT. OFFICE", lines: [], estimatedSeconds: 20)
        var audition = makeAudition(scenes: [scene1])

        let slateFile = tempDirectory.appendingPathComponent("slate.mov")
        let fullFile = tempDirectory.appendingPathComponent("full.mov")
        let takeFile = tempDirectory.appendingPathComponent("take1.mov")

        audition.slateVideoURL = slateFile
        audition.fullLengthVideoURL = fullFile

        let take = Take(number: 1, duration: 20, recordedAt: .now, isCircled: true, notes: [], fileURL: takeFile, auditionID: audition.id, sceneIndex: 0)

        let clips = MediaExporter.clips(for: audition, takes: [take], slateAtStart: false)
        let kinds = clips.map(\.kind)

        XCTAssertEqual(kinds, [.scene(0), .slate, .fullLength], "Clips must place scenes before slate and full length when slateAtStart is false")
    }

    func testClipOrderingSelectsCircledTakeOverUncircled() {
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "ROOM", lines: [], estimatedSeconds: 15)
        let audition = makeAudition(scenes: [scene])

        let take1 = Take(number: 1, duration: 15, recordedAt: .now, isCircled: false, notes: [], fileURL: tempDirectory.appendingPathComponent("take1.mov"), auditionID: audition.id, sceneIndex: 0)
        let take2 = Take(number: 2, duration: 15, recordedAt: .now, isCircled: true, notes: [], fileURL: tempDirectory.appendingPathComponent("take2.mov"), auditionID: audition.id, sceneIndex: 0)
        let take3 = Take(number: 3, duration: 15, recordedAt: .now, isCircled: false, notes: [], fileURL: tempDirectory.appendingPathComponent("take3.mov"), auditionID: audition.id, sceneIndex: 0)

        let clips = MediaExporter.clips(for: audition, takes: [take1, take2, take3], slateAtStart: true)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips.first?.label, "Scene 1 · Take 2", "MediaExporter must select circled take 2 instead of earlier uncircled takes")
    }

    func testClipOrderingExcludesTakesFromForeignAuditions() {
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "ROOM", lines: [], estimatedSeconds: 15)
        let audition = makeAudition(scenes: [scene])
        let foreignID = UUID()

        let foreignTake = Take(number: 1, duration: 15, recordedAt: .now, isCircled: true, notes: [], fileURL: tempDirectory.appendingPathComponent("foreign.mov"), auditionID: foreignID, sceneIndex: 0)
        let clips = MediaExporter.clips(for: audition, takes: [foreignTake], slateAtStart: true)

        XCTAssertTrue(clips.isEmpty, "MediaExporter must strictly exclude takes belonging to other auditions")
    }

    // MARK: - Separate ZIP Archive Generation

    func testMakeSeparateArchiveCreatesZipWithVideos() throws {
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "STAGE", lines: [], estimatedSeconds: 25)
        var audition = makeAudition(role: "Maya", project: "The Last Summer", scenes: [scene])

        // Create dummy video files on disk so Data(contentsOf:) succeeds
        let slateURL = tempDirectory.appendingPathComponent("slate.mov")
        let fullURL = tempDirectory.appendingPathComponent("full.mov")
        let takeURL = tempDirectory.appendingPathComponent("take1.mov")

        let slateBytes = Data("DUMMY SLATE MOVIE DATA".utf8)
        let fullBytes = Data("DUMMY FULL LENGTH MOVIE DATA".utf8)
        let takeBytes = Data("DUMMY TAKE 1 MOVIE DATA".utf8)

        try slateBytes.write(to: slateURL)
        try fullBytes.write(to: fullURL)
        try takeBytes.write(to: takeURL)

        audition.slateVideoURL = slateURL
        audition.fullLengthVideoURL = fullURL

        let take = Take(number: 1, duration: 25, recordedAt: .now, isCircled: true, notes: [], fileURL: takeURL, auditionID: audition.id, sceneIndex: 0)
        let slate = SlateInfo(name: "Asha Rao")

        let archiveURL = try MediaExporter.makeSeparateArchive(audition, takes: [take], slate: slate)

        XCTAssertTrue(archiveURL.lastPathComponent.hasSuffix("_SEPARATE.zip"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let zipData = try Data(contentsOf: archiveURL)
        XCTAssertGreaterThan(zipData.count, 0)

        // Verify the ZIP archive structure contains Videos/ entries
        let fileContentString = String(decoding: zipData, as: UTF8.self)
        XCTAssertTrue(fileContentString.contains("Videos/Slate.mov") || fileContentString.contains("Videos/Slate"))
        XCTAssertTrue(fileContentString.contains("Videos/Full_length.mov") || fileContentString.contains("Videos/Full_length"))
        XCTAssertTrue(fileContentString.contains("Videos/Scene_1_-_Take_1.mov"))

        // Clean up exported archive
        try? FileManager.default.removeItem(at: archiveURL)
    }

    func testMakeSeparateArchiveThrowsOnNothingToExport() {
        let audition = makeAudition()
        let slate = SlateInfo()

        XCTAssertThrowsError(try MediaExporter.makeSeparateArchive(audition, takes: [], slate: slate)) { error in
            guard let exportError = error as? MediaExporter.ExportError else {
                XCTFail("Expected MediaExporter.ExportError but received \(error)")
                return
            }
            XCTAssertEqual(exportError, .nothingToExport)
        }
    }

    func testMakeSeparateArchiveWithHeadshotsAndTakesStructure() throws {
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "STAGE", lines: [], estimatedSeconds: 25)
        var audition = makeAudition(role: "Maya", project: "The Last Summer", scenes: [scene])

        // Save a mock front headshot image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160))
        let mockImage = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
        HeadshotStore.save(mockImage, key: "front")

        let slateURL = tempDirectory.appendingPathComponent("slate.mov")
        let fullURL = tempDirectory.appendingPathComponent("full.mov")
        let takeURL = tempDirectory.appendingPathComponent("take1.mov")

        try Data("SLATE".utf8).write(to: slateURL)
        try Data("FULL".utf8).write(to: fullURL)
        try Data("TAKE1".utf8).write(to: takeURL)

        audition.slateVideoURL = slateURL
        audition.fullLengthVideoURL = fullURL

        let take = Take(number: 1, duration: 25, recordedAt: .now, isCircled: true, notes: [], fileURL: takeURL, auditionID: audition.id, sceneIndex: 0)
        let slate = SlateInfo(name: "Asha Rao")

        let archiveURL = try MediaExporter.makeSeparateArchive(audition, takes: [take], slate: slate)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let zipData = try Data(contentsOf: archiveURL)
        let contentString = String(decoding: zipData, as: UTF8.self)

        // Must contain both Videos/ and Headshots/ structures
        XCTAssertTrue(contentString.contains("Videos/Slate.mov"), "Archive must contain Videos/Slate.mov")
        XCTAssertTrue(contentString.contains("Videos/Full_length.mov"), "Archive must contain Videos/Full_length.mov")
        XCTAssertTrue(contentString.contains("Videos/Scene_1_-_Take_1.mov"), "Archive must contain Videos/Scene_1_-_Take_1.mov")
        XCTAssertTrue(contentString.contains("Headshots/RAO_ASHA_MAYA_THELASTSUMMER_HEADSHOT_FRONT.jpg"), "Archive must contain Headshots/<baseName>_HEADSHOT_FRONT.jpg")
    }

    func testMakeSeparateArchiveClipOrderingSlateAtStartTrueVsFalse() throws {
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "STAGE", lines: [], estimatedSeconds: 20)
        var audition = makeAudition(role: "Maya", project: "Ordering Test", scenes: [scene])

        let slateURL = tempDirectory.appendingPathComponent("slate_ord.mov")
        let takeURL = tempDirectory.appendingPathComponent("take1_ord.mov")
        try Data("SLATE_ORD".utf8).write(to: slateURL)
        try Data("TAKE_ORD".utf8).write(to: takeURL)

        audition.slateVideoURL = slateURL
        let take = Take(number: 1, duration: 20, recordedAt: .now, isCircled: true, notes: [], fileURL: takeURL, auditionID: audition.id, sceneIndex: 0)
        let slate = SlateInfo(name: "Asha Rao")

        // 1. Test slateAtStart = true
        UserDefaults.standard.set(true, forKey: "slateAtStart")
        let archiveURLTrue = try MediaExporter.makeSeparateArchive(audition, takes: [take], slate: slate)
        let dataTrue = try Data(contentsOf: archiveURLTrue)
        let strTrue = String(decoding: dataTrue, as: UTF8.self)

        let slateRangeTrue = strTrue.range(of: "Videos/Slate.mov")
        let sceneRangeTrue = strTrue.range(of: "Videos/Scene_1_-_Take_1.mov")
        XCTAssertNotNil(slateRangeTrue)
        XCTAssertNotNil(sceneRangeTrue)
        if let s = slateRangeTrue, let t = sceneRangeTrue {
            XCTAssertLessThan(s.lowerBound, t.lowerBound, "When slateAtStart is true, Slate.mov must precede Scene_1 in the archive")
        }

        // 2. Test slateAtStart = false
        UserDefaults.standard.set(false, forKey: "slateAtStart")
        let archiveURLFalse = try MediaExporter.makeSeparateArchive(audition, takes: [take], slate: slate)
        let dataFalse = try Data(contentsOf: archiveURLFalse)
        let strFalse = String(decoding: dataFalse, as: UTF8.self)

        let slateRangeFalse = strFalse.range(of: "Videos/Slate.mov")
        let sceneRangeFalse = strFalse.range(of: "Videos/Scene_1_-_Take_1.mov")
        XCTAssertNotNil(slateRangeFalse)
        XCTAssertNotNil(sceneRangeFalse)
        if let s = slateRangeFalse, let t = sceneRangeFalse {
            XCTAssertLessThan(t.lowerBound, s.lowerBound, "When slateAtStart is false, Scene_1 must precede Slate.mov in the archive")
        }

        // Clean up preference
        UserDefaults.standard.removeObject(forKey: "slateAtStart")
    }

    func testMakeSeparateArchiveWithOnlyHeadshots() throws {
        let audition = makeAudition(role: "Maya", project: "Headshots Only")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 100))
        let mockImage = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 100))
        }
        HeadshotStore.save(mockImage, key: "front")

        let slate = SlateInfo(name: "Asha Rao")
        let archiveURL = try MediaExporter.makeSeparateArchive(audition, takes: [], slate: slate)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let zipData = try Data(contentsOf: archiveURL)
        let contentString = String(decoding: zipData, as: UTF8.self)
        XCTAssertTrue(contentString.contains("Headshots/"), "Archive with only headshots must include Headshots/")
        XCTAssertFalse(contentString.contains("Videos/"), "Archive with only headshots must not include Videos/")
    }
}
