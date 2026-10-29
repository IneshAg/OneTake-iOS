import XCTest
@testable import OneTake

final class TapeCheckFilterTests: XCTestCase {
    private var auditionID: UUID!
    private var audition: Audition!

    override func setUp() {
        super.setUp()
        auditionID = UUID()
        let scene1 = ScriptScene(number: 1, title: "Scene 1", heading: "INT. DINER", lines: [], estimatedSeconds: 30)
        let scene2 = ScriptScene(number: 2, title: "Scene 2", heading: "EXT. ALLEY", lines: [], estimatedSeconds: 40)
        let scene3 = ScriptScene(number: 3, title: "Scene 3", heading: "INT. MOTEL", lines: [], estimatedSeconds: 20)

        audition = Audition(
            id: auditionID,
            project: "Noir",
            projectType: "Feature",
            role: "Detective",
            roleSize: "Lead",
            castingOffice: "Warner Bros",
            due: .now,
            asks: [],
            pieces: [],
            scenes: [scene1, scene2, scene3],
            destination: .actorsAccess,
            status: .due
        )
    }

    func testOnlyCircledTakesAreIncludedForTapeAnalysis() {
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")

        // Scene 0: Take 1 (uncircled), Take 2 (circled)
        let s0Take1 = Take(number: 1, duration: 30, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)
        let s0Take2 = Take(number: 2, duration: 31, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)

        // Scene 1: Take 1 (circled), Take 2 (uncircled)
        let s1Take1 = Take(number: 1, duration: 40, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 1)
        let s1Take2 = Take(number: 2, duration: 42, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 1)

        // Scene 2: Take 1 (uncircled), Take 2 (uncircled) - no circled takes
        let s2Take1 = Take(number: 1, duration: 20, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 2)
        let s2Take2 = Take(number: 2, duration: 22, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 2)

        let allTakes = [s0Take1, s0Take2, s1Take1, s1Take2, s2Take1, s2Take2]

        // Tape Check filter rule: store.takes.filter { $0.auditionID == auditionID && $0.isCircled }
        let finalizedTakes = allTakes.filter { $0.auditionID == auditionID && $0.isCircled }

        XCTAssertEqual(finalizedTakes.count, 2, "Only circled takes should be in finalizedTakes")
        XCTAssertTrue(finalizedTakes.contains(where: { $0.id == s0Take2.id }), "Scene 0 Take 2 must be included")
        XCTAssertTrue(finalizedTakes.contains(where: { $0.id == s1Take1.id }), "Scene 1 Take 1 must be included")

        // Clips generated from finalizedTakes must only contain the circled takes
        let clips = MediaExporter.clips(for: audition, takes: finalizedTakes, slateAtStart: true)
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].label, "Scene 1 · Take 2")
        XCTAssertEqual(clips[1].label, "Scene 2 · Take 1")
    }

    func testUncircledTakesAreStrictlyExcludedFromTapeCheck() {
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")

        // An audition with several takes, but NONE of them circled
        let take1 = Take(number: 1, duration: 25, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)
        let take2 = Take(number: 2, duration: 26, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)
        let take3 = Take(number: 1, duration: 35, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 1)

        let allTakes = [take1, take2, take3]
        let finalizedTakes = allTakes.filter { $0.auditionID == auditionID && $0.isCircled }

        XCTAssertTrue(finalizedTakes.isEmpty, "Finalized takes list must be empty when no takes are circled")

        let clips = MediaExporter.clips(for: audition, takes: finalizedTakes, slateAtStart: true)
        XCTAssertTrue(clips.isEmpty, "No scene clips should be generated when takes are not circled")
    }

    func testForeignAuditionCircledTakesAreExcluded() {
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")
        let foreignAuditionID = UUID()

        // Foreign audition take with isCircled = true
        let foreignTake = Take(number: 1, duration: 30, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: foreignAuditionID, sceneIndex: 0)

        // Target audition take with isCircled = true
        let targetTake = Take(number: 1, duration: 25, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)

        let storeTakes = [foreignTake, targetTake]
        let finalizedTakes = storeTakes.filter { $0.auditionID == auditionID && $0.isCircled }

        XCTAssertEqual(finalizedTakes.count, 1)
        XCTAssertEqual(finalizedTakes.first?.id, targetTake.id)
        XCTAssertFalse(finalizedTakes.contains(where: { $0.auditionID == foreignAuditionID }))
    }

    @MainActor
    func testAppStoreCircleOnlyReplacesPreviousCircledTakeForSameScene() {
        let store = AppStore()
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")

        let take1 = Take(number: 1, duration: 20, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)
        let take2 = Take(number: 2, duration: 22, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)

        store.takes = [take1, take2]

        // Circle take 2
        store.circleOnly(take2)

        let updatedTake1 = store.takes.first { $0.id == take1.id }
        let updatedTake2 = store.takes.first { $0.id == take2.id }

        XCTAssertFalse(updatedTake1?.isCircled ?? true, "Previous take must be uncircled")
        XCTAssertTrue(updatedTake2?.isCircled ?? false, "Target take must now be circled")

        let finalized = store.takes.filter { $0.auditionID == auditionID && $0.isCircled }
        XCTAssertEqual(finalized.count, 1)
        XCTAssertEqual(finalized.first?.id, take2.id)
    }

    func testStressMixedTakesAcrossMultipleScenesNeverIncludesUncircledInClips() {
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")
        let foreignID1 = UUID()
        let foreignID2 = UUID()

        var allTakes: [Take] = []

        // Scene 0: 5 takes, only take 2 is circled
        for i in 1...5 {
            allTakes.append(Take(number: i, duration: 20 + Double(i), recordedAt: .now, isCircled: (i == 2), notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0))
        }

        // Scene 1: 3 takes, NONE circled
        for i in 1...3 {
            allTakes.append(Take(number: i, duration: 30 + Double(i), recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 1))
        }

        // Scene 2: 4 takes, only take 3 is circled
        for i in 1...4 {
            allTakes.append(Take(number: i, duration: 25 + Double(i), recordedAt: .now, isCircled: (i == 3), notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 2))
        }

        // Scene 3: 0 takes (empty)

        // Scene 4 (add to audition so we have 5 scenes): 2 takes, only take 2 is circled
        let scene4 = ScriptScene(number: 4, title: "Scene 4", heading: "INT. OFFICE", lines: [], estimatedSeconds: 15)
        let scene5 = ScriptScene(number: 5, title: "Scene 5", heading: "EXT. ROOFTOP", lines: [], estimatedSeconds: 25)
        var extendedAudition = audition!
        extendedAudition.scenes.append(contentsOf: [scene4, scene5])

        for i in 1...2 {
            allTakes.append(Take(number: i, duration: 15 + Double(i), recordedAt: .now, isCircled: (i == 2), notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 4))
        }

        // Add 10 foreign audition takes (some circled, some uncircled)
        for i in 1...5 {
            allTakes.append(Take(number: i, duration: 40, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: foreignID1, sceneIndex: 0))
            allTakes.append(Take(number: i, duration: 45, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: foreignID2, sceneIndex: 1))
        }

        // Apply Tape Check filtering rule:
        let finalizedTakes = allTakes.filter { $0.auditionID == auditionID && $0.isCircled }

        // Must strictly contain only the 3 circled takes belonging to auditionID
        XCTAssertEqual(finalizedTakes.count, 3, "Only the 3 circled takes for this audition should be finalized")
        for take in finalizedTakes {
            XCTAssertEqual(take.auditionID, auditionID, "Finalized take must belong to target audition")
            XCTAssertTrue(take.isCircled, "Finalized take must be circled")
        }

        // Generate clips from finalizedTakes
        let clips = MediaExporter.clips(for: extendedAudition, takes: finalizedTakes, slateAtStart: true)
        XCTAssertEqual(clips.count, 3, "Clips count must match number of scenes with circled takes")
        XCTAssertEqual(clips[0].label, "Scene 1 · Take 2")
        XCTAssertEqual(clips[1].label, "Scene 3 · Take 3")
        XCTAssertEqual(clips[2].label, "Scene 5 · Take 2")

        // Uncircled takes from Scene 1, Scene 3, and other uncircled takes must NEVER appear in clips
        for clip in clips {
            XCTAssertFalse(clip.label.contains("Scene 2"), "Scene 2 (no circled take) must not appear in clips")
            XCTAssertFalse(clip.label.contains("Scene 4"), "Scene 4 (no takes recorded) must not appear in clips")
        }
    }

    func testStressAllUncircledTakesYieldsZeroClipsAndZeroReportClips() async {
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")
        let foreignID = UUID()

        var allTakes: [Take] = []
        // 10 scenes, 3 uncircled takes per scene = 30 uncircled takes
        for s in 0..<10 {
            for t in 1...3 {
                allTakes.append(Take(number: t, duration: 20, recordedAt: .now, isCircled: false, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: s))
            }
        }
        // Foreign takes that are circled
        for s in 0..<3 {
            allTakes.append(Take(number: 1, duration: 20, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: foreignID, sceneIndex: s))
        }

        let finalizedTakes = allTakes.filter { $0.auditionID == auditionID && $0.isCircled }
        XCTAssertTrue(finalizedTakes.isEmpty, "Finalized takes must be strictly empty when all takes are uncircled")

        let clips = MediaExporter.clips(for: audition, takes: finalizedTakes, slateAtStart: true)
        XCTAssertTrue(clips.isEmpty, "Clips must be strictly empty when finalized takes is empty")

        let report = await TapeAnalyzer.analyze(audition, takes: finalizedTakes)
        XCTAssertEqual(report.clipCount, 0, "TapeAnalyzer report must report 0 clips when all takes are uncircled")
    }

    func testStressEmptyTakesListYieldsZeroClipsAndZeroReportClips() async {
        let emptyTakes: [Take] = []
        let finalizedTakes = emptyTakes.filter { $0.auditionID == auditionID && $0.isCircled }
        XCTAssertTrue(finalizedTakes.isEmpty)

        let clips = MediaExporter.clips(for: audition, takes: finalizedTakes, slateAtStart: true)
        XCTAssertTrue(clips.isEmpty)

        let report = await TapeAnalyzer.analyze(audition, takes: finalizedTakes)
        XCTAssertEqual(report.clipCount, 0)
    }

    func testStressForeignAuditionTakesIsolationUnderAdversarialCollisions() {
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")
        let foreignID = UUID()

        // Foreign take and target take with identical sceneIndex=0, number=1, isCircled=true
        let foreignTake = Take(number: 1, duration: 30, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: foreignID, sceneIndex: 0)
        let targetTake = Take(number: 1, duration: 25, recordedAt: .now, isCircled: true, notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: 0)

        let takes = [foreignTake, targetTake]
        let finalizedTakes = takes.filter { $0.auditionID == auditionID && $0.isCircled }

        XCTAssertEqual(finalizedTakes.count, 1)
        XCTAssertEqual(finalizedTakes.first?.id, targetTake.id)
        XCTAssertEqual(finalizedTakes.first?.duration, 25)

        let clips = MediaExporter.clips(for: audition, takes: finalizedTakes)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips.first?.label, "Scene 1 · Take 1")
    }

    @MainActor
    func testStressCircleOnlyRapidSwitchingMaintainsSingleCircledInvariantPerScene() {
        let store = AppStore()
        let dummyURL = URL(fileURLWithPath: "/tmp/take.mov")

        // 3 scenes, 4 takes each
        var takes: [Take] = []
        for s in 0..<3 {
            for t in 1...4 {
                takes.append(Take(number: t, duration: Double(t * 10), recordedAt: .now, isCircled: (t == 1), notes: [], fileURL: dummyURL, auditionID: auditionID, sceneIndex: s))
            }
        }
        store.takes = takes

        // For scene 0: switch circle from take 1 to take 2 to take 3 to take 4 to take 1
        for targetTakeNumber in [2, 3, 4, 1] {
            let targetTake = store.takes.first { $0.auditionID == auditionID && $0.sceneIndex == 0 && $0.number == targetTakeNumber }!
            store.circleOnly(targetTake)

            // Verify invariant: exactly 1 take is circled for scene 0
            let scene0Circled = store.takes.filter { $0.auditionID == auditionID && $0.sceneIndex == 0 && $0.isCircled }
            XCTAssertEqual(scene0Circled.count, 1, "Scene 0 must have exactly 1 circled take")
            XCTAssertEqual(scene0Circled.first?.number, targetTakeNumber)

            // Verify other scenes were not disturbed
            let scene1Circled = store.takes.filter { $0.auditionID == auditionID && $0.sceneIndex == 1 && $0.isCircled }
            XCTAssertEqual(scene1Circled.count, 1, "Scene 1 circled take must remain intact")
            XCTAssertEqual(scene1Circled.first?.number, 1)
        }
    }
}

