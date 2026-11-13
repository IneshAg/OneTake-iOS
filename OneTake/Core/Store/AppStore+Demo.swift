import Foundation
import SwiftUI

// MARK: - AppStore Demo Mode Extension

extension AppStore {
    static let demoEnabledKey = "demo.enabled"
    private static let demoSeededSlateKey = "demo.seededSlate"
    private static let demoSeededHeadshotKeysKey = "demo.seededHeadshotKeys"

    var isDemoModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.demoEnabledKey)
    }

    var demoAuditionCount: Int {
        auditions.filter(DemoModeCatalog.isDemoAudition).count
    }

    var demoTakeCount: Int {
        takes.filter(DemoModeCatalog.isDemoTake).count
    }

    var demoPracticeCount: Int {
        practice.filter(DemoModeCatalog.isDemoPractice).count
    }

    /// Turns full Demo Mode ON: seeds realistic demo auditions across Due / Ready / Exported / Sent,
    /// playable demo takes + slate videos, reader audio cues, standalone practice scenes, and
    /// placeholder slate/headshots when empty, without touching existing real user data.
    func enableDemoMode(generateMediaAsync: Bool = true) {
        UserDefaults.standard.set(true, forKey: Self.demoEnabledKey)
        UserDefaults.standard.set(true, forKey: "practice.showSample")
        isOnboarded = true

        seedDemoSlateAndHeadshotsIfEmpty()
        insertMissingDemoRecords()
        syncPieces()
        persist()

        if generateMediaAsync {
            scheduleDemoMediaGeneration()
        }
    }

    /// Restores all demo auditions, takes, practice pieces, and playable demo media to a fresh state
    /// while leaving any real user auditions, takes, practice pieces, slate, and headshots intact.
    func resetDemoData(generateMediaAsync: Bool = true) {
        removeDemoRecordsAndFiles(clearSeededProfile: false)
        enableDemoMode(generateMediaAsync: generateMediaAsync)
    }

    /// Turns Demo Mode OFF and deletes all seeded demo records, demo video/audio files, standalone
    /// sample pieces, and any slate/headshots that were created solely by Demo Mode.
    func disableDemoMode() {
        demoMediaTask?.cancel()
        demoMediaTask = nil
        isPreparingDemoMedia = false

        UserDefaults.standard.set(false, forKey: Self.demoEnabledKey)
        removeDemoRecordsAndFiles(clearSeededProfile: true)
        removeSampleData()
        persist()
    }

    /// Loads a realistic multi-role casting notice draft and navigates straight to Notice Review
    /// so testing or demonstrating notice parsing + review takes one tap from Profile.
    func launchDemoNoticeReview() {
        if !isDemoModeEnabled {
            enableDemoMode(generateMediaAsync: true)
        }
        auditionDraft = DemoModeCatalog.sampleNoticeDraft()
        showProfile = false
        tab = .auditions
        if showAddAudition {
            showAddAudition = false
            pendingRouteAfterAdd = .noticeReview
        } else {
            auditionsPath = [.noticeReview]
        }
    }

    /// Opens the pre-built Ready demo audition ("Midnight Dispatch") on the Auditions tab for fast demos.
    func openDemoReadyAudition() {
        if !isDemoModeEnabled || audition(DemoModeCatalog.midnightDispatchID) == nil {
            enableDemoMode(generateMediaAsync: true)
        }
        showProfile = false
        tab = .auditions
        auditionsPath = [.auditionDetail(DemoModeCatalog.midnightDispatchID)]
    }

    @MainActor
    func ensureDemoMediaIfNeeded() async {
        guard isDemoModeEnabled else { return }
        if !auditions.contains(where: DemoModeCatalog.isDemoAudition) {
            insertMissingDemoRecords()
            syncPieces()
        }
        let specs = demoVideoSpecs()
        let audioSpecs = demoReaderAudioSpecs()
        let missingMedia = specs.contains { !FileManager.default.fileExists(atPath: $0.destinationURL.path) }
            || audioSpecs.contains { !FileManager.default.fileExists(atPath: $0.destinationURL.path) }
        guard missingMedia else { return }
        await generateDemoMediaAssets()
    }

    // MARK: - Internal Seeding & Cleanup Helpers

    private func seedDemoSlateAndHeadshotsIfEmpty() {
        if slate.isEmpty {
            slate = DemoModeCatalog.defaultDemoSlate
            UserDefaults.standard.set(true, forKey: Self.demoSeededSlateKey)
        }

        var seededKeys = Set(UserDefaults.standard.stringArray(forKey: Self.demoSeededHeadshotKeysKey) ?? [])
        var addedAnyHeadshot = false
        for angle in HeadshotStore.angles where !HeadshotStore.exists(key: angle.key) {
            let image = DemoMediaGenerator.renderHeadshotImage(angle: angle.key)
            HeadshotStore.save(image, key: angle.key)
            seededKeys.insert(angle.key)
            addedAnyHeadshot = true
        }
        if addedAnyHeadshot {
            UserDefaults.standard.set(Array(seededKeys).sorted(), forKey: Self.demoSeededHeadshotKeysKey)
            headshotVersion += 1
        }
    }

    private func insertMissingDemoRecords() {
        let now = Date()
        let existingAuditionIDs = Set(auditions.map(\.id))
        let demoAuditions = DemoModeCatalog.makeDemoAuditions(now: now)
        for demo in demoAuditions.reversed() where !existingAuditionIDs.contains(demo.id) {
            auditions.insert(demo, at: 0)
        }

        let existingTakeIDs = Set(takes.map(\.id))
        for demoTake in DemoModeCatalog.makeDemoTakes(now: now) where !existingTakeIDs.contains(demoTake.id) {
            takes.append(demoTake)
        }

        let existingPracticeIDs = Set(practice.map(\.id))
        for demoPiece in DemoModeCatalog.makeDemoPracticePieces().reversed() where !existingPracticeIDs.contains(demoPiece.id) {
            practice.insert(demoPiece, at: 0)
        }
    }

    private func removeDemoRecordsAndFiles(clearSeededProfile: Bool) {
        let fm = FileManager.default
        let exportsDir = MediaStore.directory("Exports")

        for audition in auditions where DemoModeCatalog.isDemoAudition(audition) {
            HeadshotStore.removeAuditionHeadshots(for: audition.id)
            try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("audition-\(audition.id.uuidString)", isDirectory: true))
            try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(audition.id.uuidString)", isDirectory: true))
            if let export = audition.exportedFileURL {
                try? fm.removeItem(at: export)
            }
            if let zip = audition.separateArchiveURL {
                try? fm.removeItem(at: zip)
            }
        }
        try? fm.removeItem(at: exportsDir.appendingPathComponent("DEMO_VANCE_RUNNER1_ATLAS.mp4"))

        for piece in practice where DemoModeCatalog.isDemoPractice(piece) {
            try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("practice-\(piece.id.uuidString)", isDirectory: true))
        }

        auditions.removeAll(where: DemoModeCatalog.isDemoAudition)
        takes.removeAll(where: DemoModeCatalog.isDemoTake)
        practice.removeAll(where: DemoModeCatalog.isDemoPractice)

        auditionsPath.removeAll(where: routeReferencesDemo)
        practicePath.removeAll(where: routeReferencesDemo)
        searchPath.removeAll(where: routeReferencesDemo)
        if let pending = pendingRouteAfterAdd, routeReferencesDemo(pending) {
            pendingRouteAfterAdd = nil
        }
        if cameraReferencesDemo(camera) {
            camera = nil
        }

        if clearSeededProfile {
            if UserDefaults.standard.bool(forKey: Self.demoSeededSlateKey) {
                if slate == DemoModeCatalog.defaultDemoSlate {
                    slate = SlateInfo()
                }
                UserDefaults.standard.removeObject(forKey: Self.demoSeededSlateKey)
            }

            let seededKeys = UserDefaults.standard.stringArray(forKey: Self.demoSeededHeadshotKeysKey) ?? []
            if !seededKeys.isEmpty {
                for key in seededKeys {
                    HeadshotStore.remove(key: key)
                }
                UserDefaults.standard.removeObject(forKey: Self.demoSeededHeadshotKeysKey)
                headshotVersion += 1
            }
        }

        readerTracksDidChange()
    }

    private func scheduleDemoMediaGeneration() {
        demoMediaTask?.cancel()
        demoMediaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.generateDemoMediaAssets()
        }
    }

    @MainActor
    func generateDemoMediaAssets() async {
        guard isDemoModeEnabled else { return }
        isPreparingDemoMedia = true
        defer { isPreparingDemoMedia = false }

        let videoSpecs = demoVideoSpecs()
        let audioSpecs = demoReaderAudioSpecs()

        for spec in videoSpecs {
            if Task.isCancelled || !isDemoModeEnabled { return }
            if !FileManager.default.fileExists(atPath: spec.destinationURL.path) {
                await DemoMediaGenerator.writeVideoClip(spec)
            }
        }

        for spec in audioSpecs {
            if Task.isCancelled || !isDemoModeEnabled { return }
            if !FileManager.default.fileExists(atPath: spec.destinationURL.path) {
                await DemoMediaGenerator.writeAudioCue(spec)
            }
        }

        guard !Task.isCancelled, isDemoModeEnabled else { return }
        syncPieces()
        readerTracksDidChange()
        persist()
    }

    private func demoVideoSpecs() -> [DemoMediaGenerator.VideoClipSpec] {
        let dispatchDir = MediaStore.directory("audition-\(DemoModeCatalog.midnightDispatchID.uuidString)")
        let atlasDir = MediaStore.directory("audition-\(DemoModeCatalog.atlasRunningID.uuidString)")
        let exportsDir = MediaStore.directory("Exports")

        return [
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: dispatchDir.appendingPathComponent("demo-dispatch-slate.mp4"),
                headline: "Avery Vance — Slate",
                subheadline: "Midnight Dispatch · Detective Reyes · 5′10″",
                badge: "Demo Slate",
                accentRGB: (0.92, 0.35, 0.30),
                durationSeconds: 2.0
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: dispatchDir.appendingPathComponent("demo-dispatch-s1-t1.mp4"),
                headline: "Scene 1 — Take 1",
                subheadline: "INT. Precinct Corridor · Faster pacing",
                badge: "Midnight Dispatch",
                accentRGB: (0.35, 0.62, 0.96),
                durationSeconds: 2.5
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: dispatchDir.appendingPathComponent("demo-dispatch-s1-t2.mp4"),
                headline: "Scene 1 — Take 2 ★ Circled",
                subheadline: "INT. Precinct Corridor · Selected beat",
                badge: "Midnight Dispatch",
                accentRGB: (0.28, 0.78, 0.56),
                durationSeconds: 2.5
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: dispatchDir.appendingPathComponent("demo-dispatch-s1-t3.mp4"),
                headline: "Scene 1 — Take 3",
                subheadline: "INT. Precinct Corridor · Alternate warmth",
                badge: "Midnight Dispatch",
                accentRGB: (0.68, 0.52, 0.96),
                durationSeconds: 2.5
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: dispatchDir.appendingPathComponent("demo-dispatch-s2-t1.mp4"),
                headline: "Scene 2 — Take 1 ★ Circled",
                subheadline: "INT. Interrogation B · Confrontation",
                badge: "Midnight Dispatch",
                accentRGB: (0.28, 0.78, 0.56),
                durationSeconds: 2.5
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: atlasDir.appendingPathComponent("demo-atlas-slate.mp4"),
                headline: "Avery Vance — Slate",
                subheadline: "Atlas Running · Launch Anthem",
                badge: "Demo Commercial Slate",
                accentRGB: (0.95, 0.60, 0.24),
                durationSeconds: 2.0
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: atlasDir.appendingPathComponent("demo-atlas-fullbody.mp4"),
                headline: "Full-Body Profile Shot",
                subheadline: "Atlas Running · Principal Runner #1",
                badge: "Demo Full-Body",
                accentRGB: (0.95, 0.60, 0.24),
                durationSeconds: 2.0
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: atlasDir.appendingPathComponent("demo-atlas-movement-t1.mp4"),
                headline: "Movement Reel — Take 1",
                subheadline: "EXT. City Track · Golden Hour",
                badge: "Atlas Running",
                accentRGB: (0.28, 0.78, 0.56),
                durationSeconds: 2.5
            ),
            DemoMediaGenerator.VideoClipSpec(
                destinationURL: exportsDir.appendingPathComponent("DEMO_VANCE_RUNNER1_ATLAS.mp4"),
                headline: "Exported Deliverable (1080p)",
                subheadline: "Atlas Running — Combined Slate + Movement",
                badge: "Ready to Submit",
                accentRGB: (0.28, 0.78, 0.56),
                durationSeconds: 3.0
            )
        ]
    }

    private func demoReaderAudioSpecs() -> [DemoMediaGenerator.AudioCueSpec] {
        [
            DemoMediaGenerator.AudioCueSpec(
                destinationURL: ReaderTrackPlayer.url(auditionID: DemoModeCatalog.quietHorizonID, sceneIndex: 0, line: 0),
                frequencyHz: 440,
                durationSeconds: 1.4
            ),
            DemoMediaGenerator.AudioCueSpec(
                destinationURL: ReaderTrackPlayer.url(auditionID: DemoModeCatalog.quietHorizonID, sceneIndex: 0, line: 2),
                frequencyHz: 493.88,
                durationSeconds: 1.2
            ),
            DemoMediaGenerator.AudioCueSpec(
                destinationURL: ReaderTrackPlayer.url(auditionID: DemoModeCatalog.quietHorizonID, sceneIndex: 0, line: 4),
                frequencyHz: 523.25,
                durationSeconds: 1.3
            ),
            DemoMediaGenerator.AudioCueSpec(
                destinationURL: ReaderTrackPlayer.url(auditionID: DemoModeCatalog.quietHorizonID, sceneIndex: 1, line: 0),
                frequencyHz: 440,
                durationSeconds: 1.5
            ),
            DemoMediaGenerator.AudioCueSpec(
                destinationURL: ReaderTrackPlayer.url(auditionID: DemoModeCatalog.quietHorizonID, sceneIndex: 1, line: 2),
                frequencyHz: 523.25,
                durationSeconds: 1.4
            )
        ]
    }

    private func routeReferencesDemo(_ route: Route) -> Bool {
        switch route {
        case .practiceSample:
            return true
        case .standalonePractice(let pid):
            return DemoModeCatalog.allDemoPracticeIDs.contains(pid)
        case .headshots(let forID):
            return forID.map(DemoModeCatalog.allDemoAuditionIDs.contains) ?? false
        case .auditionDetail(let id),
             .prepare(let id, _),
             .runLines(let id, _),
             .reader(let id, _),
             .recordReader(let id, _, _, _),
             .sceneAudioFlow(let id, _),
             .shootSetup(let id, _),
             .takes(let id, _),
             .tapeCheck(let id),
             .package(let id),
             .preview(let id),
             .elementReview(let id, _),
             .practiceOptions(let id, _),
             .lineDrill(let id, _, _),
             .audioWalk(let id, _):
            return DemoModeCatalog.allDemoAuditionIDs.contains(id)
        case .profile, .editSlate, .privacy, .notifications, .practiceSetup, .missingDetails, .noticeReview, .testSides:
            return false
        }
    }

    private func cameraReferencesDemo(_ flow: CameraFlow?) -> Bool {
        guard let flow else { return false }
        switch flow {
        case .shoot(let id, _, _):
            return DemoModeCatalog.allDemoAuditionIDs.contains(id)
        case .headshot(let auditionID):
            return auditionID.map(DemoModeCatalog.allDemoAuditionIDs.contains) ?? false
        case .practiceTake(let pieceID, _, _):
            return pieceID.map(DemoModeCatalog.allDemoPracticeIDs.contains) ?? false
        case .scanSides:
            return false
        }
    }
}
