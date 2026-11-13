import AVFoundation
import XCTest
@testable import OneTake

@MainActor
final class DemoModeTests: XCTestCase {
    private var savedAuditions: [Audition] = []
    private var savedTakes: [Take] = []
    private var savedPractice: [PracticePiece] = []
    private var savedSlate = SlateInfo()
    private var savedDemoEnabled = false

    override func setUp() {
        super.setUp()
        savedDemoEnabled = UserDefaults.standard.bool(forKey: AppStore.demoEnabledKey)
        UserDefaults.standard.set(false, forKey: AppStore.demoEnabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedDemoEnabled, forKey: AppStore.demoEnabledKey)
        super.tearDown()
    }

    func testEnableAndDisableDemoModePreservesRealUserData() {
        let store = AppStore()
        savedAuditions = store.auditions
        savedTakes = store.takes
        savedPractice = store.practice
        savedSlate = store.slate

        defer {
            store.disableDemoMode()
            store.auditions = savedAuditions
            store.takes = savedTakes
            store.practice = savedPractice
            store.slate = savedSlate
            store.persist()
        }

        store.disableDemoMode()
        store.slate = SlateInfo(name: "Real Actor", height: "5′ 9″", basedIn: "Toronto", representation: "Real Agency")
        var realDraft = NoticeParser.Draft(project: "Real Project", role: "Real Role", due: Date().addingTimeInterval(7_200))
        let realAudition = realDraft.makeAudition()
        store.add(realAudition)

        store.enableDemoMode(generateMediaAsync: false)

        XCTAssertTrue(store.isDemoModeEnabled)
        XCTAssertEqual(store.demoAuditionCount, 4)
        XCTAssertEqual(store.demoTakeCount, 5)
        XCTAssertEqual(store.demoPracticeCount, 3)
        XCTAssertTrue(store.auditions.contains { $0.id == realAudition.id })
        XCTAssertEqual(store.slate.name, "Real Actor")

        let statuses = Set(store.auditions.filter(DemoModeCatalog.isDemoAudition).map(\.status))
        XCTAssertEqual(statuses, [.due, .ready, .exported, .sent])

        store.disableDemoMode()

        XCTAssertFalse(store.isDemoModeEnabled)
        XCTAssertEqual(store.demoAuditionCount, 0)
        XCTAssertEqual(store.demoTakeCount, 0)
        XCTAssertEqual(store.demoPracticeCount, 0)
        XCTAssertTrue(store.auditions.contains { $0.id == realAudition.id })
        XCTAssertEqual(store.slate.name, "Real Actor")
    }

    func testDisableDemoModeCleansSeededEmptySlateAndHeadshots() {
        let store = AppStore()
        savedAuditions = store.auditions
        savedTakes = store.takes
        savedPractice = store.practice
        savedSlate = store.slate

        let hadFront = HeadshotStore.exists(key: "front")
        let hadLeft = HeadshotStore.exists(key: "left")
        let hadRight = HeadshotStore.exists(key: "right")

        defer {
            store.disableDemoMode()
            store.auditions = savedAuditions
            store.takes = savedTakes
            store.practice = savedPractice
            store.slate = savedSlate
            store.persist()
        }

        store.disableDemoMode()
        store.slate = SlateInfo()
        for angle in HeadshotStore.angles {
            HeadshotStore.remove(key: angle.key)
        }

        store.enableDemoMode(generateMediaAsync: false)
        XCTAssertEqual(store.slate.name, DemoModeCatalog.defaultDemoSlate.name)
        XCTAssertTrue(HeadshotStore.isComplete())

        store.disableDemoMode()
        XCTAssertTrue(store.slate.isEmpty)
        XCTAssertFalse(hadFront && HeadshotStore.exists(key: "front"))
        XCTAssertFalse(hadLeft && HeadshotStore.exists(key: "left"))
        XCTAssertFalse(hadRight && HeadshotStore.exists(key: "right"))
        XCTAssertFalse(HeadshotStore.exists(key: "front"))
    }

    func testLaunchDemoNoticeReviewPopulatesDraftAndRoutes() {
        let store = AppStore()
        savedAuditions = store.auditions
        savedTakes = store.takes
        savedPractice = store.practice
        savedSlate = store.slate

        defer {
            store.disableDemoMode()
            store.auditions = savedAuditions
            store.takes = savedTakes
            store.practice = savedPractice
            store.slate = savedSlate
            store.persist()
        }

        store.launchDemoNoticeReview()
        XCTAssertEqual(store.auditionDraft.project, "The Glass Lighthouse")
        XCTAssertEqual(store.auditionDraft.role, "Nora")
        XCTAssertEqual(store.tab, .auditions)
        XCTAssertFalse(store.showProfile)
        XCTAssertEqual(store.auditionsPath.last, .noticeReview)
    }

    func testDemoMediaGeneratorProducesPlayableVideoAndAudioFiles() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneTakeDemoMediaTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoURL = tempDir.appendingPathComponent("sample-clip.mp4")
        let audioURL = tempDir.appendingPathComponent("sample-cue.m4a")

        let videoOK = await DemoMediaGenerator.writeVideoClip(.init(
            destinationURL: videoURL,
            headline: "Demo Clip",
            subheadline: "Unit Test",
            badge: "Test",
            accentRGB: (0.2, 0.7, 0.5),
            durationSeconds: 1.0
        ))
        let audioOK = await DemoMediaGenerator.writeAudioCue(.init(
            destinationURL: audioURL,
            frequencyHz: 440,
            durationSeconds: 0.8
        ))

        XCTAssertTrue(videoOK)
        XCTAssertTrue(audioOK)

        let videoAsset = AVURLAsset(url: videoURL)
        let videoDuration = try? await videoAsset.load(.duration).seconds
        let videoTracks = try? await videoAsset.loadTracks(withMediaType: .video)
        XCTAssertGreaterThan(videoDuration ?? 0, 0.5)
        XCTAssertEqual(videoTracks?.count, 1)

        let audioAsset = AVURLAsset(url: audioURL)
        let audioTracks = try? await audioAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks?.count, 1)
    }
}
