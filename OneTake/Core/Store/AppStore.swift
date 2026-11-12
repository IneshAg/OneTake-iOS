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

    /// Loads a complete sample audition ("The Quiet Horizon", role "Maya") with sides, reader cues,
    /// and required Scene 1, allowing actors to immediately explore rehearsal, filming, and export.
    func loadSampleAudition() {
        let sampleSides = """
        INT. STATION — NIGHT

        MAYA
        I know the train leaves at six. I just didn't think you'd come.

        READER
        You asked me to.

        MAYA
        I asked you to say goodbye.

        READER
        Is that all you want?

        MAYA
        No. But it's all I know how to ask for.
        """
        var draft = NoticeParser.Draft()
        draft.project = "The Quiet Horizon"
        draft.projectType = "Feature Film"
        draft.role = "Maya"
        draft.roleSize = "Lead"
        draft.castingOffice = "Sarah Finn Casting"
        draft.due = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        draft.asks = ["Scene 1 required", "Headshot (optional)"]
        draft.sourceText = sampleSides
        draft.destination = .email
        draft.destinationDetail = "submissions@sarahfinncasting.com"
        draft.destinationWasDetected = true
        draft.isHeadshotOptional = true
        draft.includeHeadshots = true
        draft.includeSlate = false
        draft.customScenes = ScriptParser.parseScenes(from: sampleSides, myRole: "Maya")
        draft.scenes = 1

        let audition = draft.makeAudition()
        add(audition)
        isOnboarded = true
        tab = .auditions
        auditionsPath = [.auditionDetail(audition.id)]
    }

    // Send state
    var sendProgress: Double = 0

    // MARK: Persistence

    private var saveTask: Task<Void, Never>?
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
        if ProcessInfo.processInfo.arguments.contains("-testAuditionHeadshots") {
            isOnboarded = true
            let audition: Audition
            if let first = auditions.first {
                audition = first
            } else {
                var draft = NoticeParser.Draft(project: "The Crown", role: "Diana", due: .now.addingTimeInterval(86400))
                let newAudition = draft.makeAudition()
                auditions.append(newAudition)
                audition = newAudition
            }
            auditionsPath = [.auditionDetail(audition.id), .headshots(for: audition.id)]
            let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000)).image { ctx in
                UIColor.systemPink.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
                UIColor.systemYellow.setFill()
                ctx.fill(CGRect(x: 250, y: 200, width: 300, height: 400))
            }
            if !HeadshotStore.exists(key: "front", auditionID: audition.id) {
                HeadshotStore.save(img, key: "front", auditionID: audition.id)
            }
            if !HeadshotStore.exists(key: "left", auditionID: audition.id) {
                HeadshotStore.save(img, key: "left", auditionID: audition.id)
            }
            if !HeadshotStore.exists(key: "right", auditionID: audition.id) {
                HeadshotStore.save(img, key: "right", auditionID: audition.id)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-testAuditionDetail") {
            isOnboarded = true
            let audition: Audition
            if let first = auditions.first {
                audition = first
            } else {
                var draft = NoticeParser.Draft(project: "The Crown", role: "Diana", due: .now.addingTimeInterval(86400))
                let newAudition = draft.makeAudition()
                auditions.append(newAudition)
                audition = newAudition
            }
            auditionsPath = [.auditionDetail(audition.id)]
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
    func persist() {
        guard !isLoading else { return }
        saveTask?.cancel()
        let snapshot = PersistedState(auditions: auditions, takes: takes, practice: practice, slate: slate, isOnboarded: isOnboarded, account: account)
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                Self.writeSnapshot(snapshot)
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
        let snapshot = PersistedState(auditions: auditions, takes: takes, practice: practice, slate: slate, isOnboarded: isOnboarded, account: account)
        Self.writeSnapshot(snapshot)
        Task.detached(priority: .utility) {
            await LiveActivitySync.update(snapshot.auditions)
        }
    }

    @MainActor
    private static func writeSnapshot(_ snapshot: PersistedState) {
        Persistence.save(snapshot)
        // Reminders and widgets follow due dates, progress, status and deletions.
        Reminders.reschedule(snapshot.auditions)
        WidgetSync.update(snapshot.auditions)
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

    // MARK: Reset & Clear

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
