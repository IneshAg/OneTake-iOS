import SwiftUI
import Observation
import AVFoundation

/// Every pushed screen in the app. One enum keeps the flow testable and mirrors the Figma prototype keys.
enum Route: Hashable {
    case auditionDetail(Audition.ID)
    case profile
    case prepare(Audition.ID, sceneIndex: Int)
    case runLines(Audition.ID, sceneIndex: Int)
    case reader(Audition.ID, sceneIndex: Int)
    case recordReader(Audition.ID, sceneIndex: Int, initialLineIndex: Int? = nil, readerCharacter: String? = nil)
    case sceneAudioFlow(Audition.ID, sceneIndex: Int)
    /// `scene` picks which scene the camera opens on; nil lets it pick the next one still to shoot.
    case shootSetup(Audition.ID, scene: Int? = nil)
    case takes(Audition.ID, sceneIndex: Int? = nil)
    case tapeCheck(Audition.ID)
    case package(Audition.ID)
    /// 20.0 — the whole tape with chapters, after Tape Check and before Package.
    case preview(Audition.ID)
    /// A focused review of one recorded part, separated from the whole-tape preview.
    case elementReview(Audition.ID, element: AuditionReviewElement)
    /// Headshots, optionally opened from an audition's checklist so it can offer "Next" afterwards.
    case headshots(for: Audition.ID?)
    case editSlate
    case privacy
    case notifications
    case practiceSetup
    case practiceOptions(Audition.ID, sceneIndex: Int)
    case standalonePractice(PracticePiece.ID)
    case practiceSample
    /// Practice's Quick Drills: First-Letter Prompts and Mask & Reveal Lines (Audio Gap reuses `.runLines`).
    case lineDrill(Audition.ID, sceneIndex: Int, mode: LineLearningMode)
    /// Hands-Free Audio Walk — the one drill with its own screen.
    case audioWalk(Audition.ID, sceneIndex: Int)
    case missingDetails
    case noticeReview
    case testSides
}

enum AuditionReviewElement: Hashable {
    case slate
    case fullLength
    case scene(Int)

    var title: String {
        switch self {
        case .slate: "Slate"
        case .fullLength: "Full-body shot"
        case .scene(let index): "Scene \(index + 1)"
        }
    }
}

/// The camera flow runs full-screen and outside the tab navigation, like the system Camera.
enum CameraFlow: Identifiable, Hashable {
    enum ShootStart: String, Hashable {
        case check, slate, fullLength
    }

    case shoot(Audition.ID, scene: Int? = nil, start: ShootStart = .check)  // camera check → slate → requested full-body shot → scenes → take saved
    case headshot(auditionID: Audition.ID? = nil)                           // front → left → right → crop
    case scanSides
    case practiceTake(pieceID: PracticePiece.ID? = nil, initialDisplayMode: StandaloneDisplay = .full, initialRecordMode: PracticeRecordMode = .camera)

    static var headshot: CameraFlow { .headshot(auditionID: nil) }
    static var practiceTake: CameraFlow { .practiceTake(pieceID: nil) }

    var id: String {
        switch self {
        case .shoot(let id, _, let start):  "shoot-\(id)-\(start.rawValue)"
        case .headshot(let auditionID):     "headshot-\(auditionID?.uuidString ?? "profile")"
        case .scanSides:                    "scan"
        case .practiceTake(let pieceID, let mode, let rec): "practice-\(pieceID?.uuidString ?? "default")-\(mode.rawValue)-\(rec.rawValue)"
        }
    }
}

enum AppTab: Hashable { case auditions, practice, profile, search }

@Observable
final class AppStore {
    // Session — didSet persists to disk (debounced) so none of this is lost on relaunch.
    /// Bumped whenever a headshot file is saved or removed, so views that draw headshots from disk
    /// (which SwiftUI can't observe) refresh.
    var headshotVersion = 0
    /// Bumped after reader audio changes so screens backed by files refresh their recording status.
    var readerTrackVersion = 0
    var isOnboarded = false { didSet { persist() } }
    /// Guest by default — OneTake works fully offline without an account. Sign-in only ever
    /// happens at a real persistence boundary (e.g. a cross-device share link), never to unlock
    /// recording or export.
    var account: Account? { didSet { persist() } }
    var isSignedIn: Bool { account != nil }
    var slate = SlateInfo() { didSet { persist() } }

    // Data
    var auditions: [Audition] = [] { didSet { persist() } }
    var takes: [Take] = [] { didSet { persist() } }
    var practice: [PracticePiece] = [] { didSet { persist() } }

    // Navigation
    var tab: AppTab = .auditions {
        didSet {
            if tab != .search {
                lastActiveTab = tab
            }
        }
    }
    var lastActiveTab: AppTab = .auditions
    var auditionsPath: [Route] = []
    var practicePath: [Route] = []
    var profilePath: [Route] = []
    var searchPath: [Route] = []
    var searchQuery: String = ""

    var currentPath: [Route] {
        if showProfile { return profilePath }
        switch tab {
        case .auditions: return auditionsPath
        case .search:    return searchPath
        case .practice:  return practicePath
        case .profile:   return profilePath
        }
    }
    var camera: CameraFlow?
    var showAddAudition = false
    var showProfile = false
    var showTestSidesSheet = false
    /// Set when an audition is saved; once the Add sheet has gone, the app continues straight into
    /// that audition's first step instead of stopping on its overview.
    var continueAfterAdd: Audition.ID?
    /// A notice shared from another app, waiting for Add audition to read it.
    var incomingShare: ShareInbox.Item?
    /// The draft audition currently being created or reviewed.
    var auditionDraft = NoticeParser.Draft.blank
    /// Pushed onto auditionsPath once the Add sheet has dismissed.
    var pendingRouteAfterAdd: Route?

    func startAuditionDraft(_ draft: NoticeParser.Draft) {
        auditionDraft = draft
        showAddAudition = false
        pendingRouteAfterAdd = draft.missingRequiredDetails.isEmpty ? .noticeReview : .missingDetails
    }

    /// Commits a confirmed draft directly into a persistent Audition, skipping redundant review screens
    /// and navigating directly to the Audition Detail or Reader recording.
    func commitAuditionDraft(_ draft: NoticeParser.Draft, readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .later) {
        let audition = draft.makeAudition()
        add(audition)
        auditionDraft = .blank
        showAddAudition = false
        tab = .auditions
        if readerAudioPlan == .recordNow,
           let firstScene = audition.scenes.indices.first(where: { !audition.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
            pendingRouteAfterAdd = .reader(audition.id, sceneIndex: firstScene)
        } else {
            pendingRouteAfterAdd = .auditionDetail(audition.id)
            continueAfterAdd = audition.id
        }
    }

    // Send state
    var sendProgress: Double = 0

    // MARK: Persistence

    private var saveTask: Task<Void, Never>?
    /// Monotonically increasing counter ensuring older async snapshots never overwrite newer ones.
    private var saveSequence: Int = 0
    /// Surface persistent write errors to the UI
    @Published var persistenceError: String? = nil
    @Published var lastSaveSucceeded: Bool = true
    /// True while `init` is still applying a loaded snapshot, so that pass doesn't immediately
    /// re-trigger its own save.
    private var isLoading = false

    init() {
        isLoading = true
        var removedLegacyDemoData = false
        var reorderedLegacyPieces = false
        if let saved = Persistence.load() {
            auditions = saved.auditions.map { a in
                var a = a
                a.slateVideoURL = MediaStore.rebased(a.slateVideoURL)
                a.slateOriginalVideoURL = MediaStore.rebased(a.slateOriginalVideoURL)
                a.fullLengthVideoURL = MediaStore.rebased(a.fullLengthVideoURL)
                a.fullLengthOriginalVideoURL = MediaStore.rebased(a.fullLengthOriginalVideoURL)
                a.exportedFileURL = MediaStore.rebased(a.exportedFileURL)
                a.separateArchiveURL = MediaStore.rebased(a.separateArchiveURL)
                return a
            }
            let flowOrderMigrationKey = "migration.auditionPieces.headshotsSlateScenes.v1"
            if !UserDefaults.standard.bool(forKey: flowOrderMigrationKey) {
                for index in auditions.indices {
                    let ordered = Piece.defaultFlowOrder(auditions[index].pieces)
                    if ordered != auditions[index].pieces {
                        auditions[index].pieces = ordered
                        reorderedLegacyPieces = true
                    }
                }
                UserDefaults.standard.set(true, forKey: flowOrderMigrationKey)
            }
            let fullBodyLabelMigrationKey = "migration.auditionPieces.fullBodyTerminology.v1"
            if !UserDefaults.standard.bool(forKey: fullBodyLabelMigrationKey) {
                for index in auditions.indices {
                    if let pieceIndex = auditions[index].pieces.firstIndex(where: { $0.kind == .fullLength }) {
                        if auditions[index].pieces[pieceIndex].title.localizedCaseInsensitiveContains("full length") {
                            auditions[index].pieces[pieceIndex].title = "Full-body shot"
                            auditions[index].pieces[pieceIndex].detail = "Separate head-to-toe video, as requested"
                            reorderedLegacyPieces = true
                        }
                    } else if auditions[index].asks.contains("Full length") {
                        auditions[index].pieces.append(Piece(
                            kind: .fullLength,
                            title: "Full-body shot",
                            detail: "Separate head-to-toe video, as requested",
                            isDone: auditions[index].fullLengthVideoURL != nil
                        ))
                        auditions[index].pieces = Piece.defaultFlowOrder(auditions[index].pieces)
                        reorderedLegacyPieces = true
                    }
                }
                UserDefaults.standard.set(true, forKey: fullBodyLabelMigrationKey)
            }
            takes = saved.takes.map { t in
                var t = t
                t.fileURL = MediaStore.rebased(t.fileURL)
                t.originalFileURL = MediaStore.rebased(t.originalFileURL)
                return t
            }
            practice = saved.practice
            slate = saved.slate == SlateInfo.legacyPlaceholder ? SlateInfo() : saved.slate
            isOnboarded = saved.isOnboarded
            account = saved.account

            // Remove the old generic simulator fixture without touching other saved auditions.
            // This exact fingerprint came from the demo profile shown in early builds.
            let isDemoProfile = slate.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Jane Actor") == .orderedSame
            let demoAuditions = auditions.filter {
                $0.project.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Hamlet") == .orderedSame
                    && $0.projectType.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Theatre") == .orderedSame
                    && $0.role.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Ophelia") == .orderedSame
            }
            if isDemoProfile, !demoAuditions.isEmpty {
                let demoIDs = Set(demoAuditions.map(\.id))
                let demoTakes = takes.filter { $0.auditionID.map(demoIDs.contains) ?? false }
                for url in demoTakes.compactMap(\.fileURL)
                    + demoAuditions.flatMap({ [$0.slateVideoURL, $0.fullLengthVideoURL, $0.exportedFileURL, $0.separateArchiveURL].compactMap { $0 } }) {
                    try? FileManager.default.removeItem(at: MediaStore.rebased(url) ?? url)
                }
                for id in demoIDs { MediaStore.deleteAll(["audition-\(id.uuidString)", "practice-\(id.uuidString)"]) }
                auditions.removeAll { demoIDs.contains($0.id) }
                takes.removeAll { $0.auditionID.map(demoIDs.contains) ?? false }
                practice.removeAll { $0.auditionID.map(demoIDs.contains) ?? false }
                slate = SlateInfo()
                HeadshotStore.clearCache()
                MediaStore.deleteAll(["headshots"])
                removedLegacyDemoData = true
            }
        }
        // If the user previously turned off "Show sample scene", purge any persisted sample pieces.
        if UserDefaults.standard.object(forKey: "practice.showSample") as? Bool == false {
            let samples = practice.filter { isSamplePiece($0) }
            if !samples.isEmpty {
                let dirs = samples.map { "practice-\($0.id.uuidString)" }
                MediaStore.deleteAll(dirs)
                practice.removeAll { isSamplePiece($0) }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-practice") {
            tab = .practice
        }
        if ProcessInfo.processInfo.arguments.contains("-onboarded") {
            isOnboarded = true
        }
        if ProcessInfo.processInfo.arguments.contains("-headshot") {
            isOnboarded = true
            camera = .headshot
        }
        if ProcessInfo.processInfo.arguments.contains("-missingDetails") {
            isOnboarded = true
            auditionDraft = NoticeParser.Draft(project: "", role: "", due: nil)
            auditionsPath = [.missingDetails]
        }
        if ProcessInfo.processInfo.arguments.contains("-noticeReview") {
            isOnboarded = true
            auditionDraft = NoticeParser.Draft(project: "Hamlet", role: "Ophelia", due: .now.addingTimeInterval(86400))
            auditionsPath = [.noticeReview]
        }
        if ProcessInfo.processInfo.arguments.contains("-auditionDetail"), let firstAudition = auditions.first {
            isOnboarded = true
            auditionsPath = [.auditionDetail(firstAudition.id)]
        }
        if ProcessInfo.processInfo.arguments.contains("-editSlate") {
            isOnboarded = true
            showProfile = true
            profilePath = [.editSlate]
        }
        if ProcessInfo.processInfo.arguments.contains("-testHeadshots") {
            isOnboarded = true
            showProfile = true
            profilePath = [.headshots(for: nil)]
            if !HeadshotStore.exists(key: "front") {
                let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000)).image { ctx in
                    UIColor.systemIndigo.setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
                    UIColor.systemOrange.setFill()
                    ctx.fill(CGRect(x: 250, y: 200, width: 300, height: 400))
                }
                HeadshotStore.save(img, key: "front")
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-search") {
            isOnboarded = true
            tab = .search
        }
        if ProcessInfo.processInfo.arguments.contains("-testAddSides") {
            isOnboarded = true
            auditionDraft = NoticeParser.Draft(project: "Hamlet", role: "Ophelia", due: .now.addingTimeInterval(86400))
            auditionsPath = [.testSides]
        }
        if ProcessInfo.processInfo.arguments.contains("-testVoiceRehearsal"), let first = auditions.first {
            isOnboarded = true
            let piece = practicePiece(for: first.id, sceneIndex: 0)
            camera = .practiceTake(pieceID: piece.id, initialDisplayMode: .full, initialRecordMode: .voiceOnly)
        }
        if ProcessInfo.processInfo.arguments.contains("-testCameraRehearsal"), let first = auditions.first {
            isOnboarded = true
            let piece = practicePiece(for: first.id, sceneIndex: 0)
            camera = .practiceTake(pieceID: piece.id, initialDisplayMode: .full, initialRecordMode: .camera)
        }
        isLoading = false
        syncPieces()
        if removedLegacyDemoData || reorderedLegacyPieces { persist() }
    }

    /// Debounced so rapid edits (typing in a text field) don't hit disk on every keystroke.
    /// Offloads JSON serialization and disk writing completely off @MainActor to StateStorage.
    private func persist() {
        guard !isLoading else { return }
        saveSequence += 1
        let currentSeq = saveSequence
        saveTask?.cancel()
        let snapshot = PersistedState(auditions: auditions, takes: takes, practice: practice, slate: slate, isOnboarded: isOnboarded, account: account)
        saveTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let committed = try await StateStorage.shared.writeSnapshot(snapshot, sequence: currentSeq)
                if committed {
                    await MainActor.run {
                        self?.persistenceError = nil
                        self?.lastSaveSucceeded = true
                        Reminders.reschedule(snapshot.auditions)
                        WidgetSync.update(snapshot.auditions)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.persistenceError = error.localizedDescription
                    self?.lastSaveSucceeded = false
                }
            }
            await LiveActivitySync.update(snapshot.auditions)
        }
    }

    /// Commits the current value immediately when iOS is about to suspend the app.
    @MainActor
    func flushPersistence() {
        guard !isLoading else { return }
        saveTask?.cancel()
        saveTask = nil
        saveSequence += 1
        let currentSeq = saveSequence
        let snapshot = PersistedState(auditions: auditions, takes: takes, practice: practice, slate: slate, isOnboarded: isOnboarded, account: account)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let committed = try await StateStorage.shared.writeSnapshot(snapshot, sequence: currentSeq)
                if committed {
                    await MainActor.run {
                        self?.persistenceError = nil
                        self?.lastSaveSucceeded = true
                        Reminders.reschedule(snapshot.auditions)
                        WidgetSync.update(snapshot.auditions)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.persistenceError = error.localizedDescription
                    self?.lastSaveSucceeded = false
                }
            }
            await LiveActivitySync.update(snapshot.auditions)
        }
    }

    @MainActor
    static func writeSnapshot(_ snapshot: PersistedState) {
        do {
            try Persistence.save(snapshot)
            Reminders.reschedule(snapshot.auditions)
            WidgetSync.update(snapshot.auditions)
        } catch {
            #if DEBUG
            print("[AppStore] Synchronous writeSnapshot failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: Account

    func signOut() {
        AccountAuth.signOut(account)
        account = nil
    }

    func deleteAccount() {
        AccountAuth.deleteAccount(account)
        account = nil
        persist()
    }

    /// Drops an Apple account the person has revoked from Settings since last launch.
    @MainActor
    func validateAccount() async {
        guard let account, !(await AccountAuth.isStillValid(account)) else { return }
        self.account = nil
    }

    // MARK: Lookup

    func audition(_ id: Audition.ID) -> Audition? { auditions.first { $0.id == id } }

    /// Looks the audition up by ID on every get/set — capturing its index would go stale (editing the
    /// wrong audition, or crashing) as soon as `add` inserts at the top or one is removed.
    func binding(for id: Audition.ID) -> Binding<Audition>? {
        guard let initial = audition(id) else { return nil }
        return Binding(
            get: { self.audition(id) ?? initial },
            set: { newValue in
                guard let i = self.auditions.firstIndex(where: { $0.id == id }) else { return }
                self.auditions[i] = newValue
            }
        )
    }

    /// The audition Home should push the actor toward: soonest due, not sent.
    var nextPriority: Audition? {
        auditions.filter { $0.status != .sent }.min { $0.due < $1.due }
    }

    var active: [Audition] { auditions.filter { $0.status != .sent }.sorted { $0.due < $1.due } }
    var sent: [Audition] { auditions.filter { $0.status == .sent } }

    // MARK: Mutations

    func add(_ audition: Audition) {
        auditions.insert(audition, at: 0)
        syncPieces()
    }

    /// Audition headshots are independent from the profile default headshot. Each audition's headshot
    /// piece is marked done only if that specific audition has a headshot attached.
    func syncHeadshotPieces() {
        syncPieces()
    }

    /// Synchronizes checklist piece status (scenes, slate, full length, headshots) with real disk recordings and takes.
    func syncPieces() {
        for i in auditions.indices where auditions[i].status != .sent {
            let id = auditions[i].id
            // Headshots
            let hasAuditionHeadshot = !HeadshotStore.taken(auditionID: id).isEmpty
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .headshot {
                if hasAuditionHeadshot {
                    auditions[i].pieces[j].isDone = true
                } else if !auditions[i].pieces[j].isOptional {
                    auditions[i].pieces[j].isDone = false
                }
            }
            // Slate
            let hasSlate = auditions[i].slateVideoURL != nil
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .slate {
                if hasSlate {
                    auditions[i].pieces[j].isDone = true
                } else if !auditions[i].pieces[j].isOptional {
                    auditions[i].pieces[j].isDone = false
                }
            }
            // Full length
            let hasFullLength = auditions[i].fullLengthVideoURL != nil
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .fullLength {
                if hasFullLength {
                    auditions[i].pieces[j].isDone = true
                } else if !auditions[i].pieces[j].isOptional {
                    auditions[i].pieces[j].isDone = false
                }
            }
            // Scenes: if an audition has recorded takes for a scene, that scene is done!
            let auditionTakes = takes.filter { $0.auditionID == id }
            let sceneTitles = !auditions[i].scenes.isEmpty
                ? auditions[i].scenes.map(\.title)
                : auditions[i].pieces.filter { $0.kind == .scene }.map(\.title)
            for (sceneIndex, title) in sceneTitles.enumerated() {
                let hasTake = auditionTakes.contains { ($0.sceneIndex ?? 0) == sceneIndex }
                for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .scene && auditions[i].pieces[j].title == title {
                    if hasTake {
                        auditions[i].pieces[j].isDone = true
                    } else if !auditions[i].pieces[j].isOptional {
                        // Preserve an explicit skip for optional scenes. Required scenes only
                        // count as complete when a take exists.
                        auditions[i].pieces[j].isDone = false
                    }
                }
            }
            if auditions[i].status != .sent {
                auditions[i].status = auditions[i].isPackageReady ? .ready : .due
            }
        }
    }

    func readerTracksDidChange() { readerTrackVersion += 1 }

    // MARK: Sample Data

    /// Returns `true` when `piece` is the built-in sample ("A late goodbye" / "Sample scene").
    /// Standalone pieces tied to no real audition and carrying the sample fingerprint are matched.
    func isSamplePiece(_ piece: PracticePiece) -> Bool {
        guard piece.auditionID == nil else { return false }
        return piece.title.caseInsensitiveCompare("A late goodbye") == .orderedSame
            || piece.detail.localizedCaseInsensitiveContains("sample")
    }

    /// Removes sample practice pieces and their associated disk folders.
    /// Call when the user turns off "Show sample scene" in Settings.
    func removeSampleData() {
        let samples = practice.filter { isSamplePiece($0) }
        guard !samples.isEmpty else { return }
        let dirs = samples.map { "practice-\($0.id.uuidString)" }
        MediaStore.deleteAll(dirs)
        practice.removeAll { isSamplePiece($0) }
        // Clear practice navigation if it points into a now-deleted piece.
        practicePath.removeAll { route in
            if case .practiceSample = route { return true }
            return false
        }
        if case .practiceTake(let pieceID, _, _) = camera,
           let pid = pieceID, samples.contains(where: { $0.id == pid }) {
            camera = nil
        }
        persist()
    }

    /// Cleans all practice pieces, progress, active practice navigation, and associated practice takes.
    func clearPracticeData() {
        let practiceDirs = practice.map { "practice-\($0.id.uuidString)" }
        let allPracticeFolders = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path))?.filter { $0.hasPrefix("practice-") } ?? []
        MediaStore.deleteAll([ReaderTrackPlayer.folder] + practiceDirs + allPracticeFolders)
        practice.removeAll()
        practicePath.removeAll()
        readerTracksDidChange()
        if case .practiceTake = camera {
            camera = nil
        }
        persist()
    }

    /// Cleans all local data on this iPhone: takes, headshots, reader tracks, exports, and practice pieces.
    func clearAllLocalData() {
        let practiceDirs = practice.map { "practice-\($0.id.uuidString)" }
        let auditionDirs = auditions.map { "audition-\($0.id.uuidString)" }
        let allPracticeFolders = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path))?.filter { $0.hasPrefix("practice-") } ?? []
        MediaStore.deleteAll(["headshots", "takes", "Exports", ReaderTrackPlayer.folder] + auditionDirs + practiceDirs + allPracticeFolders)
        HeadshotStore.clearCache()
        headshotVersion += 1
        readerTracksDidChange()
        takes.removeAll()
        for i in auditions.indices {
            auditions[i].slateVideoURL = nil
            auditions[i].slateOriginalVideoURL = nil
            auditions[i].fullLengthVideoURL = nil
            auditions[i].fullLengthOriginalVideoURL = nil
            auditions[i].exportedFileURL = nil
            guard auditions[i].status != .sent else { continue }
            for j in auditions[i].pieces.indices { auditions[i].pieces[j].isDone = false }
            auditions[i].status = .due
        }
        practice.removeAll()
        practicePath.removeAll()
        if case .practiceTake = camera {
            camera = nil
        }
        persist()
    }

    /// Development reset: removes every OneTake record and preference, then returns the running
    /// app to the same first-launch state a fresh install would show.
    @MainActor
    func resetAppForTesting() {
        saveTask?.cancel()
        camera = nil
        auditionsPath.removeAll()
        practicePath.removeAll()
        profilePath.removeAll()
        searchPath.removeAll()
        incomingShare = nil

        let manager = FileManager.default
        let documentContents = (try? manager.contentsOfDirectory(at: MediaStore.documentsURL, includingPropertiesForKeys: nil)) ?? []
        for url in documentContents { try? manager.removeItem(at: url) }
        HeadshotStore.clearCache()
        AccountAuth.deleteAccount(account)

        auditions.removeAll()
        takes.removeAll()
        practice.removeAll()
        slate = SlateInfo()
        account = nil
        headshotVersion += 1
        readerTracksDidChange()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        isOnboarded = false
        tab = .auditions
        flushPersistence()
    }

    /// Replaces local app data from an explicitly selected offline backup. Account credentials stay
    /// on this device and are never restored from an archive.
    func restoreLocalBackup(_ state: PersistedState) {
        auditions = state.auditions.map { audition in
            var audition = audition
            audition.slateVideoURL = MediaStore.rebased(audition.slateVideoURL)
            audition.slateOriginalVideoURL = MediaStore.rebased(audition.slateOriginalVideoURL)
            audition.fullLengthVideoURL = MediaStore.rebased(audition.fullLengthVideoURL)
            audition.fullLengthOriginalVideoURL = MediaStore.rebased(audition.fullLengthOriginalVideoURL)
            audition.exportedFileURL = MediaStore.rebased(audition.exportedFileURL)
            audition.separateArchiveURL = MediaStore.rebased(audition.separateArchiveURL)
            return audition
        }
        takes = state.takes.map { take in
            var take = take
            take.fileURL = MediaStore.rebased(take.fileURL)
            take.originalFileURL = MediaStore.rebased(take.originalFileURL)
            return take
        }
        practice = state.practice
        slate = state.slate
        isOnboarded = state.isOnboarded
        HeadshotStore.clearCache()
        headshotVersion += 1
        readerTrackVersion += 1
    }

    /// The scene the camera should open on: the first one whose checklist piece isn't done, else the
    /// first with no takes yet, else the first.
    func sceneToShoot(_ id: Audition.ID) -> Int {
        guard let a = audition(id), !a.scenes.isEmpty else { return 0 }
        let undone = Set(a.pieces.filter { $0.kind == .scene && !$0.isDone }.map(\.title))
        if let i = a.scenes.indices.first(where: { undone.contains(a.scenes[$0].title) }) { return i }
        if let i = a.scenes.indices.first(where: { i in !takes.contains { $0.auditionID == id && ($0.sceneIndex ?? 0) == i } }) { return i }
        return 0
    }

    /// The scene a checklist piece is about (scene pieces share their scene's title).
    func sceneIndex(for piece: Piece, in id: Audition.ID) -> Int {
        audition(id)?.scenes.firstIndex { $0.title == piece.title } ?? sceneToShoot(id)
    }

    /// The one "Next" action used everywhere an audition offers to continue: opens whatever its next
    /// unfinished piece needs in the audition flow (slate, scenes, headshots).
    func continueAudition(_ id: Audition.ID) {
        syncPieces()
        guard let a = audition(id) else { return }
        guard let next = a.nextPiece else {
            push(.preview(id))
            return
        }
        switch next.kind {
        case .slate:
            camera = .shoot(id, start: .slate)
        case .fullLength:
            camera = .shoot(id, start: .fullLength)
        case .scene:
            let idx = sceneIndex(for: next, in: id)
            camera = .shoot(id, scene: idx)
        case .headshot:
            push(.headshots(for: id))
        }
    }

    /// Removes an audition and everything recorded for it on this iPhone: takes, slate and full
    /// length, reader tracks, practice pieces made from its scenes, its exported tape, and its
    /// audition-specific headshots. Profile default headshots are left untouched.
    func deleteAudition(_ id: Audition.ID) {
        if let target = audition(id), (target.shareLink != nil || target.shareUbiquityFolderURL != nil) {
            let link = target.shareLink
            let folder = target.shareUbiquityFolderURL
            Task.detached(priority: .background) {
                try? await CloudLink.revoke(url: link, ubiquityFolderURL: folder)
            }
        }
        guard let audition = audition(id) else { return }
        HeadshotStore.removeAuditionHeadshots(for: id)
        let fm = FileManager.default
        try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("audition-\(id.uuidString)", isDirectory: true))
        try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)", isDirectory: true))
        // Export file names come from role + project, so two auditions can share one; keep it if so.
        let otherAuditions = auditions.filter { $0.id != id }
        if let export = audition.exportedFileURL,
           !otherAuditions.contains(where: { $0.exportedFileURL?.standardizedFileURL == export.standardizedFileURL }) {
            try? fm.removeItem(at: export)
        }
        let exports = MediaStore.directory("Exports")
        let archiveURL = audition.separateArchiveURL ?? exports.appendingPathComponent(
            "\((audition.deliverableFileName(slate: slate) as NSString).deletingPathExtension)_SEPARATE.zip"
        )
        let archiveBase = archiveURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_SEPARATE", with: "")
        let sameNamedExportStillUsed = otherAuditions.contains { other in
            let otherArchive = other.separateArchiveURL ?? exports.appendingPathComponent(
                "\((other.deliverableFileName(slate: slate) as NSString).deletingPathExtension)_SEPARATE.zip"
            )
            return otherArchive.standardizedFileURL == archiveURL.standardizedFileURL
        }
        if !sameNamedExportStillUsed {
            try? fm.removeItem(at: archiveURL)
            for angle in HeadshotStore.angles {
                try? fm.removeItem(at: exports.appendingPathComponent("\(archiveBase)_HEADSHOT_\(angle.key.uppercased()).jpg"))
            }
        }
        for piece in practice where piece.auditionID == id {
            try? fm.removeItem(at: MediaStore.documentsURL.appendingPathComponent("practice-\(piece.id.uuidString)", isDirectory: true))
        }
        practice.removeAll { $0.auditionID == id }
        takes.removeAll { $0.auditionID == id }
        auditions.removeAll { $0.id == id }
    }

    /// Revised sides: swaps in the new scenes and resets the scene pieces (the old takes stay, but the
    /// new pages need shooting). Practice pieces for this audition follow the new text.
    func replaceSides(of id: Audition.ID, with scenes: [ScriptScene], sourceText: String? = nil) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        let hadScenes = !auditions[i].scenes.isEmpty
        auditions[i].scenes = scenes
        auditions[i].scriptText = sourceText
        if auditions[i].castingNotes == nil, let sourceText {
            auditions[i].castingNotes = NoticeParser.extractCharacterDescription(for: auditions[i].role, in: sourceText)
        }
        auditions[i].pieces.removeAll { $0.kind == .scene }
        auditions[i].pieces += scenes.map {
            let isOpt = NoticeParser.isSceneOptional(scene: $0, in: sourceText ?? "")
            return Piece(kind: .scene, title: $0.title, detail: hadScenes ? "Revised sides" : "", isDone: false, isOptional: isOpt)
        }
        if auditions[i].status == .ready { auditions[i].status = .due }
        // Existing recordings remain available to watch, but can no longer be selected for the
        // revised script until the actor explicitly circles a take from this round.
        for index in takes.indices where takes[index].auditionID == id {
            takes[index].isCircled = false
        }
        for p in practice.indices where practice[p].auditionID == id {
            guard let s = practice[p].sceneIndex, scenes.indices.contains(s) else { continue }
            practice[p].scene = scenes[s]
            practice[p].linesTotal = scenes[s].lines.filter(\.isMine).count
            practice[p].linesLearned = min(practice[p].linesLearned, practice[p].linesTotal)
        }
    }

    /// Adjusts the total number of scenes for an audition directly (e.g. from Edit Details).
    /// Adding scenes inserts new checklist pieces and empty scene containers ready for shooting or sides.
    func updateSceneCount(for id: Audition.ID, count: Int) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        let target = max(1, count)
        let currentScenes = auditions[i].scenes
        let currentScenePieces = auditions[i].pieces.filter { $0.kind == .scene }
        let currentCount = max(currentScenes.count, currentScenePieces.count)

        guard target != currentCount else { return }

        if target > currentCount {
            if auditions[i].scenes.isEmpty && currentCount > 0 {
                for n in 1...currentCount {
                    auditions[i].scenes.append(ScriptScene(number: n, title: "Scene \(n)", heading: "SCENE \(n)", lines: [], estimatedSeconds: 60))
                }
            }
            for n in (currentCount + 1)...target {
                let newScene = ScriptScene(
                    number: n,
                    title: "Scene \(n)",
                    heading: "SCENE \(n)",
                    lines: [],
                    estimatedSeconds: 60
                )
                auditions[i].scenes.append(newScene)

                let newPiece = Piece(
                    kind: .scene,
                    title: "Scene \(n)",
                    detail: "",
                    isDone: false
                )
                if let lastSceneIdx = auditions[i].pieces.lastIndex(where: { $0.kind == .scene }) {
                    auditions[i].pieces.insert(newPiece, at: lastSceneIdx + 1)
                } else if let slateIdx = auditions[i].pieces.firstIndex(where: { $0.kind == .slate }) {
                    auditions[i].pieces.insert(newPiece, at: slateIdx + 1)
                } else {
                    auditions[i].pieces.append(newPiece)
                }
            }
        } else {
            let diff = currentCount - target
            for _ in 0..<diff {
                if auditions[i].scenes.count > target {
                    auditions[i].scenes.removeLast()
                }
                if let lastSceneIdx = auditions[i].pieces.lastIndex(where: { $0.kind == .scene }) {
                    auditions[i].pieces.remove(at: lastSceneIdx)
                }
            }
        }

        if auditions[i].status == .ready { auditions[i].status = .due }
    }

    func updateRole(for id: Audition.ID, to newRole: String) {
        guard let index = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[index].role = newRole
        reclassifyRole(for: id)
        readerTracksDidChange()
    }

    func reclassifyRole(for id: Audition.ID) {
        guard let index = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let scriptText = auditions[index].scriptText, !scriptText.isEmpty {
            auditions[index].scenes = ScriptParser.parseScenes(from: scriptText, myRole: auditions[index].role)
            if let notes = NoticeParser.extractCharacterDescription(for: auditions[index].role, in: scriptText) {
                auditions[index].castingNotes = notes
            }
        } else {
            auditions[index].scenes = ScriptParser.reclassify(auditions[index].scenes, myRole: auditions[index].role)
        }
        for practiceIndex in practice.indices where practice[practiceIndex].auditionID == id {
            guard let sceneIndex = practice[practiceIndex].sceneIndex,
                  auditions[index].scenes.indices.contains(sceneIndex) else { continue }
            let scene = auditions[index].scenes[sceneIndex]
            practice[practiceIndex].scene = scene
            practice[practiceIndex].linesTotal = scene.lines.filter(\.isMine).count
            practice[practiceIndex].linesLearned = min(practice[practiceIndex].linesLearned, practice[practiceIndex].linesTotal)
        }
    }

    /// A callback: a new audition for the next round of the same role, with casting's notes, its own
    /// due date and a fresh checklist. Reader recordings can come along so they needn't be re-recorded.
    @discardableResult
    func startCallback(
        from id: Audition.ID,
        due: Date,
        notes: String,
        actorNotes: String? = nil,
        scenes: [ScriptScene]? = nil,
        extraScriptText: String? = nil,
        bringReader: Bool
    ) -> Audition.ID? {
        guard let original = audition(id) else { return nil }
        let finalScenes = (scenes != nil && !scenes!.isEmpty) ? scenes! : original.scenes

        // Build fresh pieces:
        // 1. Slate (if original had slate)
        var newPieces: [Piece] = []
        if let origSlate = original.pieces.first(where: { $0.kind == .slate }) {
            newPieces.append(Piece(kind: .slate, title: origSlate.title, detail: origSlate.detail, isDone: false, isOptional: origSlate.isOptional))
        }

        // 2. Scenes
        for (idx, scene) in finalScenes.enumerated() {
            let isNew = idx >= original.scenes.count
            let detail = isNew ? "Callback scene" : ""
            let origScene = original.pieces.first { $0.kind == .scene && $0.title == scene.title }
            let isOpt = origScene?.isOptional ?? NoticeParser.isSceneOptional(scene: scene, in: original.scriptText ?? "")
            newPieces.append(Piece(kind: .scene, title: scene.title.isEmpty ? "Scene \(scene.number)" : scene.title, detail: detail, isDone: false, isOptional: isOpt))
        }

        // 3. Headshot / Full Length (if original had them)
        if let origHeadshot = original.pieces.first(where: { $0.kind == .headshot }) {
            newPieces.append(Piece(kind: .headshot, title: origHeadshot.title, detail: origHeadshot.detail, isDone: false, isOptional: origHeadshot.isOptional))
        }
        if let origFullLength = original.pieces.first(where: { $0.kind == .fullLength }) {
            newPieces.append(Piece(kind: .fullLength, title: origFullLength.title, detail: origFullLength.detail, isDone: false, isOptional: origFullLength.isOptional))
        }
        newPieces = Piece.defaultFlowOrder(newPieces)

        var callback = Audition(
            project: original.project,
            projectType: original.projectType,
            role: original.role,
            roleSize: original.roleSize,
            castingOffice: original.castingOffice,
            due: due,
            asks: original.asks,
            pieces: newPieces,
            scenes: finalScenes,
            destination: original.destination,
            status: .due
        )
        callback.destinationDetail = original.destinationDetail
        callback.round = (original.round ?? 1) + 1

        let trimmedCasting = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        callback.castingNotes = trimmedCasting.isEmpty ? original.castingNotes : trimmedCasting

        let trimmedActor = (actorNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        callback.actorNotes = trimmedActor.isEmpty ? original.actorNotes : trimmedActor

        // Combine script text
        let extra = (extraScriptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            if let orig = original.scriptText, !orig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                callback.scriptText = orig + "\n\n--- Callback Sides ---\n\n" + extra
            } else {
                callback.scriptText = extra
            }
        } else {
            callback.scriptText = original.scriptText
        }

        if bringReader {
            let from = MediaStore.documentsURL.appendingPathComponent("\(ReaderTrackPlayer.folder)/\(id.uuidString)", isDirectory: true)
            let to = MediaStore.directory(ReaderTrackPlayer.folder).appendingPathComponent(callback.id.uuidString, isDirectory: true)
            try? FileManager.default.copyItem(at: from, to: to)
            readerTracksDidChange()
        }
        add(callback)
        return callback.id
    }

    func markDone(_ kind: PieceKind, in id: Audition.ID, title: String? = nil) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let j = auditions[i].pieces.firstIndex(where: { $0.kind == kind && !$0.isDone && (title == nil || $0.title == title) }) {
            auditions[i].pieces[j].isDone = true
        }
        if auditions[i].isPackageReady { auditions[i].status = .ready }
    }

    func togglePieceOptional(for id: Audition.ID, pieceID: UUID) {
        guard let index = auditions.firstIndex(where: { $0.id == id }),
              let pieceIndex = auditions[index].pieces.firstIndex(where: { $0.id == pieceID }) else { return }
        auditions[index].pieces[pieceIndex].isOptional.toggle()
        let isOpt = auditions[index].pieces[pieceIndex].isOptional
        if auditions[index].pieces[pieceIndex].kind == .headshot {
            auditions[index].pieces[pieceIndex].title = isOpt ? "Headshot (Optional)" : "Headshot"
        } else if auditions[index].pieces[pieceIndex].kind == .slate {
            auditions[index].pieces[pieceIndex].title = isOpt ? "Slate (Optional)" : "Slate"
        }
        if auditions[index].status != .sent {
            auditions[index].status = auditions[index].isPackageReady ? .ready : .due
        }
    }

    func markPieceDone(_ id: Audition.ID, pieceID: UUID, isDone: Bool = true) {
        guard let index = auditions.firstIndex(where: { $0.id == id }),
              let pieceIndex = auditions[index].pieces.firstIndex(where: { $0.id == pieceID }) else { return }
        auditions[index].pieces[pieceIndex].isDone = isDone
        if auditions[index].status != .sent {
            auditions[index].status = auditions[index].isPackageReady ? .ready : .due
        }
    }

    func markSent(_ id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].status = .sent
        auditions[i].sentDate = .now
    }

    /// Circles `take` and un-circles every other take in the *same* audition+scene — scoped, so
    /// circling a take in one audition no longer silently un-circles another audition's send pick.
    func circleOnly(_ take: Take) {
        for i in takes.indices where takes[i].auditionID == take.auditionID && takes[i].sceneIndex == take.sceneIndex {
            takes[i].isCircled = takes[i].id == take.id
        }
        syncPieces()
    }

    func setSlateVideo(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].slateVideoURL = url
        syncPieces()
    }

    func keepOriginalSlate(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let previous = auditions[i].slateVideoURL, previous != url { try? FileManager.default.removeItem(at: previous) }
        if let backup = auditions[i].slateOriginalVideoURL, backup != url { try? FileManager.default.removeItem(at: backup) }
        auditions[i].slateVideoURL = url
        auditions[i].slateOriginalVideoURL = nil
        invalidateExport(for: id)
        syncPieces()
    }

    func acceptSlateTrim(_ trimmed: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }),
              let original = auditions[i].slateOriginalVideoURL ?? auditions[i].slateVideoURL,
              let replacement = moveEditedClip(trimmed, beside: original, stem: "slate-auto-trimmed") else { return }
        auditions[i].slateOriginalVideoURL = original
        auditions[i].slateVideoURL = replacement
        invalidateExport(for: id)
        syncPieces()
    }

    func restoreOriginalSlate(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let original = auditions[i].slateOriginalVideoURL else { return }
        if let current = auditions[i].slateVideoURL, current != original { try? FileManager.default.removeItem(at: current) }
        auditions[i].slateVideoURL = original
        auditions[i].slateOriginalVideoURL = nil
        invalidateExport(for: id)
        syncPieces()
    }

    func setFullLengthVideo(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let previous = auditions[i].fullLengthVideoURL, previous != url { try? FileManager.default.removeItem(at: previous) }
        if let original = auditions[i].fullLengthOriginalVideoURL, original != url { try? FileManager.default.removeItem(at: original) }
        auditions[i].fullLengthVideoURL = url
        auditions[i].fullLengthOriginalVideoURL = nil
        syncPieces()
    }

    func replaceSlateVideo(for id: Audition.ID, with edited: URL) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let old = auditions[i].slateVideoURL,
              let replacement = moveEditedClip(edited, beside: old, stem: "slate") else { return }
        if let original = auditions[i].slateOriginalVideoURL {
            if old != original { try? FileManager.default.removeItem(at: old) }
        } else {
            auditions[i].slateOriginalVideoURL = old
        }
        auditions[i].slateVideoURL = replacement
        invalidateExport(for: id)
    }

    func replaceFullLengthVideo(for id: Audition.ID, with edited: URL) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let old = auditions[i].fullLengthVideoURL,
              let replacement = moveEditedClip(edited, beside: old, stem: "full-length") else { return }
        if let original = auditions[i].fullLengthOriginalVideoURL {
            if old != original { try? FileManager.default.removeItem(at: old) }
        } else {
            auditions[i].fullLengthOriginalVideoURL = old
        }
        auditions[i].fullLengthVideoURL = replacement
        invalidateExport(for: id)
    }

    func restoreOriginalFullLengthVideo(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }),
              let original = auditions[i].fullLengthOriginalVideoURL,
              FileManager.default.fileExists(atPath: original.path) else { return }
        if let current = auditions[i].fullLengthVideoURL, current != original { try? FileManager.default.removeItem(at: current) }
        auditions[i].fullLengthVideoURL = original
        auditions[i].fullLengthOriginalVideoURL = nil
        invalidateExport(for: id)
    }

    private func moveEditedClip(_ edited: URL, beside original: URL, stem: String) -> URL? {
        let ext = edited.pathExtension.isEmpty ? (original.pathExtension.isEmpty ? "mov" : original.pathExtension) : edited.pathExtension
        let destination = original.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-trimmed-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: edited, to: destination)
            return destination
        } catch { return nil }
    }

    private func invalidateExport(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let url = auditions[i].exportedFileURL { try? FileManager.default.removeItem(at: url) }
        if let url = auditions[i].separateArchiveURL { try? FileManager.default.removeItem(at: url) }
        auditions[i].exportedFileURL = nil
        auditions[i].separateArchiveURL = nil
    }

    func setShareLink(_ link: CloudLink.Published, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].shareLink = link.url
        auditions[i].shareLinkExpires = link.expires
        auditions[i].shareUbiquityFolderURL = link.ubiquityFolderURL
    }

    func clearShareLink(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        let oldLink = auditions[i].shareLink
        let folder = auditions[i].shareUbiquityFolderURL
        auditions[i].shareLink = nil
        auditions[i].shareLinkExpires = nil
        auditions[i].shareUbiquityFolderURL = nil
        if oldLink != nil || folder != nil {
            Task.detached(priority: .background) {
                try? await CloudLink.revoke(url: oldLink, ubiquityFolderURL: folder)
            }
        }
    }

    /// Saves a custom filename template for this audition's deliverables.
    /// Supported tokens: `{name}`, `{firstName}`, `{lastName}`, `{role}`, `{project}`,
    /// `{side}`, `{scene}`, `{take}`, `{song}`.
    /// Pass `nil` to revert to the app default (`LAST_FIRST_ROLE_PROJECT.mp4`).
    func setFileNameTemplate(_ template: String?, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if auditions[i].submissionInstructions == nil {
            auditions[i].submissionInstructions = AuditionSubmissionInstructions()
        }
        let trimmed = template?.trimmingCharacters(in: .whitespacesAndNewlines)
        auditions[i].submissionInstructions?.fileNameTemplate = (trimmed?.isEmpty == false) ? trimmed : nil
        // Template change means old exports (which used the old name) are stale.
        invalidateExport(for: id)
    }

    func setExportedFile(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].exportedFileURL = url
    }

    func setSeparateArchive(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].separateArchiveURL = url
    }

    /// Next take number for a scene — one past the highest real take, so numbers never repeat even
    /// after a take is removed (a count-based number would collide with an existing take).
    func nextTakeNumber(auditionID: Audition.ID, sceneIndex: Int) -> Int {
        (takes.filter { $0.auditionID == auditionID && $0.sceneIndex == sceneIndex }.map(\.number).max() ?? 0) + 1
    }

    /// Appends a real take, circling it automatically if it's the first for that scene (so there's
    /// always a sensible send pick without the actor having to remember to circle one).
    func addTake(_ take: Take) {
        var take = take
        if let id = take.auditionID, let scene = take.sceneIndex,
           !takes.contains(where: { $0.auditionID == id && $0.sceneIndex == scene && $0.isCircled }) {
            take.isCircled = true
        }
        takes.append(take)
        syncPieces()
    }

    /// Swaps a take's file for its trimmed version. The new file gets a new name, so thumbnails and
    /// Tape Check (which key off the URL) pick up the change.
    func replaceTakeFile(_ id: Take.ID, with edited: URL) {
        guard let i = takes.firstIndex(where: { $0.id == id }), let old = takes[i].fileURL else { return }
        let ext = edited.pathExtension.isEmpty ? (old.pathExtension.isEmpty ? "mov" : old.pathExtension) : edited.pathExtension
        let dest = old.deletingLastPathComponent().appendingPathComponent("take-\(takes[i].number)-\(UUID().uuidString).\(ext)")
        do { try FileManager.default.moveItem(at: edited, to: dest) } catch { return }
        let original = takes[i].originalFileURL ?? old
        if old != original { try? FileManager.default.removeItem(at: old) }
        takes[i].fileURL = dest
        takes[i].originalFileURL = original
        if let auditionID = takes[i].auditionID { invalidateExport(for: auditionID) }
        Task { @MainActor in
            guard let seconds = try? await AVURLAsset(url: dest).load(.duration).seconds,
                  let j = self.takes.firstIndex(where: { $0.id == id }) else { return }
            self.takes[j].duration = seconds
        }
    }

    func restoreOriginalTakeFile(_ id: Take.ID) {
        guard let i = takes.firstIndex(where: { $0.id == id }),
              let original = takes[i].originalFileURL,
              FileManager.default.fileExists(atPath: original.path) else { return }
        let edited = takes[i].fileURL
        takes[i].fileURL = original
        takes[i].originalFileURL = nil
        if let edited, edited != original { try? FileManager.default.removeItem(at: edited) }
        if let auditionID = takes[i].auditionID { invalidateExport(for: auditionID) }
        Task { @MainActor in
            guard let seconds = try? await AVURLAsset(url: original).load(.duration).seconds,
                  let j = self.takes.firstIndex(where: { $0.id == id }) else { return }
            self.takes[j].duration = seconds
        }
    }

    /// A private note on a take — never sent, just for the actor.
    func addNote(_ note: String, to id: Take.ID) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = takes.firstIndex(where: { $0.id == id }) else { return }
        takes[i].notes.append(trimmed)
    }

    func incrementPracticeTakes(for id: PracticePiece.ID) {
        guard let i = practice.firstIndex(where: { $0.id == id }) else { return }
        practice[i].takesRecorded += 1
    }

    func addStandalonePracticePiece(title: String, character: String, scene: ScriptScene,
                                   detail: String = "Personal scene") -> PracticePiece {
        let piece = PracticePiece(title: title, detail: detail, linesLearned: 0,
                                  linesTotal: scene.lines.filter(\.isMine).count,
                                  character: character, scene: scene)
        practice.insert(piece, at: 0)
        return piece
    }

    func promotePracticePiece(_ id: PracticePiece.ID) {
        guard let index = practice.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let piece = practice.remove(at: index)
        practice.insert(piece, at: 0)
    }

    func recordStandaloneRun(pieceID: PracticePiece.ID, linesOnYourOwn: Int) {
        guard let index = practice.firstIndex(where: { $0.id == pieceID }) else { return }
        let clamped = max(0, min(linesOnYourOwn, practice[index].linesTotal))
        practice[index].linesLearned = clamped
        if let audID = practice[index].auditionID, let sIdx = practice[index].sceneIndex {
            recordRun(auditionID: audID, sceneIndex: sIdx, linesOnYourOwn: clamped)
        } else {
            promotePracticePiece(pieceID)
            persist()
        }
    }

    /// Finds or creates the `PracticePiece` for a given audition scene, so Quick Drills and the
    /// "pick up where you left off" card have something real to point at.
    @discardableResult
    func practicePiece(for auditionID: Audition.ID, sceneIndex: Int) -> PracticePiece {
        if let existing = practice.first(where: { $0.auditionID == auditionID && $0.sceneIndex == sceneIndex }) {
            return existing
        }
        guard let audition = audition(auditionID), audition.scenes.indices.contains(sceneIndex) else {
            let blank = PracticePiece(title: "Practice", detail: "", linesLearned: 0, linesTotal: 0)
            practice.append(blank)
            return blank
        }
        let scene = audition.scenes[sceneIndex]
        let mine = scene.lines.filter(\.isMine)
        let piece = PracticePiece(
            title: scene.title, detail: "\(audition.project) · \(audition.role)",
            linesLearned: 0, linesTotal: mine.count,
            character: audition.role, scene: scene,
            auditionID: auditionID, sceneIndex: sceneIndex
        )
        practice.insert(piece, at: 0)
        return piece
    }

    /// A Run Lines pass that reached the end: the lines said without a prompt become the scene's
    /// "lines learned", and its practice piece moves to the top as the one to pick up next.
    func recordRun(auditionID: Audition.ID, sceneIndex: Int, linesOnYourOwn: Int) {
        guard audition(auditionID)?.scenes.indices.contains(sceneIndex) == true else { return }
        let piece = practicePiece(for: auditionID, sceneIndex: sceneIndex)
        guard let i = practice.firstIndex(where: { $0.id == piece.id }) else { return }
        var updated = practice[i]
        updated.linesLearned = max(0, min(linesOnYourOwn, updated.linesTotal))
        practice.remove(at: i)
        practice.insert(updated, at: 0)
        persist()
    }

    /// Push a route on the currently selected tab's stack (or the profile sheet stack if open).
    func push(_ route: Route) {
        if showProfile {
            profilePath.append(route)
            return
        }
        switch tab {
        case .auditions: auditionsPath.append(route)
        case .search:    searchPath.append(route)
        case .practice:  practicePath.append(route)
        case .profile:   profilePath.append(route)
        }
    }

    /// Goes back to `route` if it's already on the current tab's stack (so "Change a take" returns to
    /// the Takes screen you came from instead of stacking a second one); pushes it otherwise.
    func popTo(_ route: Route) {
        func trim(_ path: inout [Route]) -> Bool {
            let exact = path.lastIndex(of: route)
            let match = exact ?? path.lastIndex { existing in
                switch (existing, route) {
                case let (.takes(existingID, _), .takes(targetID, _)):
                    return existingID == targetID
                case let (.preview(existingID), .preview(targetID)):
                    return existingID == targetID
                case let (.tapeCheck(existingID), .tapeCheck(targetID)):
                    return existingID == targetID
                case let (.package(existingID), .package(targetID)):
                    return existingID == targetID
                case let (.auditionDetail(existingID), .auditionDetail(targetID)):
                    return existingID == targetID
                case let (.headshots(existingID), .headshots(targetID)):
                    return existingID == targetID
                default:
                    return false
                }
            }
            guard let i = match else { return false }
            path.removeSubrange(path.index(after: i)...)
            return true
        }
        if showProfile {
            if !trim(&profilePath) { profilePath.append(route) }
            return
        }
        let found: Bool
        switch tab {
        case .auditions: found = trim(&auditionsPath)
        case .search:    found = trim(&searchPath)
        case .practice:  found = trim(&practicePath)
        case .profile:   found = trim(&profilePath)
        }
        if !found { push(route) }
    }

    /// Pops the top route from the active navigation stack.
    func pop() {
        if showProfile {
            if !profilePath.isEmpty { profilePath.removeLast() }
            return
        }
        switch tab {
        case .auditions: if !auditionsPath.isEmpty { auditionsPath.removeLast() }
        case .search:    if !searchPath.isEmpty { searchPath.removeLast() }
        case .practice:  if !practicePath.isEmpty { practicePath.removeLast() }
        case .profile:   if !profilePath.isEmpty { profilePath.removeLast() }
        }
    }

    func popToRoot() {
        if showProfile {
            profilePath.removeAll()
            return
        }
        switch tab {
        case .auditions: auditionsPath.removeAll()
        case .search:    searchPath.removeAll()
        case .practice:  practicePath.removeAll()
        case .profile:   profilePath.removeAll()
        }
    }
}


// MARK: - Autocomplete & Personal Suggestions for User Typing

extension AppStore {
    /// Personalized history-based project suggestions, most recent first.
    var projectSuggestions: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for a in auditions.reversed() {
            let p = a.project.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty && p.lowercased() != "untitled audition" && !seen.contains(p.lowercased()) {
                seen.insert(p.lowercased())
                list.append(p)
            }
        }
        return list
    }

    /// Personalized history-based role suggestions, most recent first.
    var roleSuggestions: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for r in auditionDraft.candidateRoles {
            let cleanR = r.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanR.isEmpty && !seen.contains(cleanR.lowercased()) {
                seen.insert(cleanR.lowercased())
                list.append(cleanR)
            }
        }
        for a in auditions.reversed() {
            let r = a.role.trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.isEmpty && r.lowercased() != "role" && !seen.contains(r.lowercased()) {
                seen.insert(r.lowercased())
                list.append(r)
            }
        }
        return list
    }

    /// Personalized history-based casting office suggestions, including industry agencies.
    var castingOfficeSuggestions: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for a in auditions.reversed() {
            let o = a.castingOffice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !o.isEmpty && !seen.contains(o.lowercased()) {
                seen.insert(o.lowercased())
                list.append(o)
            }
        }
        let common = ["Telsey + Company", "Casting Bay", "Mukesh Chhabra Casting Company (MCCC)", "Barden / Schnee", "Carmen Cuba", "Avy Kaufman"]
        for o in common where !seen.contains(o.lowercased()) {
            seen.insert(o.lowercased())
            list.append(o)
        }
        return list
    }
}
