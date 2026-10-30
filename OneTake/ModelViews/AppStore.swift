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
    case recordReader(Audition.ID, sceneIndex: Int)
    /// `scene` picks which scene the camera opens on; nil lets it pick the next one still to shoot.
    case shootSetup(Audition.ID, scene: Int? = nil)
    case takes(Audition.ID, sceneIndex: Int? = nil)
    case tapeCheck(Audition.ID)
    case package(Audition.ID)
    /// 20.0 — the whole tape with chapters, after Tape Check and before Package.
    case preview(Audition.ID)
    /// Headshots, optionally opened from an audition's checklist so it can offer "Next" afterwards.
    case headshots(for: Audition.ID?)
    case editSlate
    case privacy
    case notifications
    case practiceSetup
    case standalonePractice(PracticePiece.ID)
    case practiceSample
    /// Practice's Quick Drills: First-Letter Prompts and Mask & Reveal Lines (Audio Gap reuses `.runLines`).
    case lineDrill(Audition.ID, sceneIndex: Int, mode: LineLearningMode)
    /// Hands-Free Audio Walk — the one drill with its own screen.
    case audioWalk(Audition.ID, sceneIndex: Int)
    case missingDetails
    case noticeReview
}

/// The camera flow runs full-screen and outside the tab navigation, like the system Camera.
enum CameraFlow: Identifiable, Hashable {
    enum ShootStart: String, Hashable {
        case check, slate, fullLength
    }

    case shoot(Audition.ID, scene: Int? = nil, start: ShootStart = .check)  // camera check → slate → full length → scene → take saved
    case headshot                    // front → left → right → crop
    case scanSides
    case practiceTake

    var id: String {
        switch self {
        case .shoot(let id, _, let start): "shoot-\(id)-\(start.rawValue)"
        case .headshot:      "headshot"
        case .scanSides:     "scan"
        case .practiceTake:  "practice"
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
        if let saved = Persistence.load() {
            auditions = saved.auditions.map { a in
                var a = a
                a.slateVideoURL = MediaStore.rebased(a.slateVideoURL)
                a.slateOriginalVideoURL = MediaStore.rebased(a.slateOriginalVideoURL)
                a.fullLengthVideoURL = MediaStore.rebased(a.fullLengthVideoURL)
                a.exportedFileURL = MediaStore.rebased(a.exportedFileURL)
                a.separateArchiveURL = MediaStore.rebased(a.separateArchiveURL)
                return a
            }
            takes = saved.takes.map { t in
                var t = t
                t.fileURL = MediaStore.rebased(t.fileURL)
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
        isLoading = false
        if removedLegacyDemoData { persist() }
    }

    /// Debounced so rapid edits (typing in a text field) don't hit disk on every keystroke.
    private func persist() {
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
        syncHeadshotPieces()
    }

    /// Headshots belong to the actor, not one audition: once a real front headshot exists, every
    /// unsent audition's headshot piece is done.
    func syncHeadshotPieces() {
        guard HeadshotStore.exists(key: "front") else { return }
        // Only writes when something actually changes — every write persists and re-renders.
        for i in auditions.indices where auditions[i].status != .sent {
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .headshot && !auditions[i].pieces[j].isDone {
                auditions[i].pieces[j].isDone = true
            }
            if auditions[i].nextPiece == nil, auditions[i].status == .due { auditions[i].status = .ready }
        }
    }

    func readerTracksDidChange() { readerTrackVersion += 1 }

    /// Replaces local app data from an explicitly selected offline backup. Account credentials stay
    /// on this device and are never restored from an archive.
    func restoreLocalBackup(_ state: PersistedState) {
        auditions = state.auditions.map { audition in
            var audition = audition
            audition.slateVideoURL = MediaStore.rebased(audition.slateVideoURL)
            audition.slateOriginalVideoURL = MediaStore.rebased(audition.slateOriginalVideoURL)
            audition.fullLengthVideoURL = MediaStore.rebased(audition.fullLengthVideoURL)
            audition.exportedFileURL = MediaStore.rebased(audition.exportedFileURL)
            audition.separateArchiveURL = MediaStore.rebased(audition.separateArchiveURL)
            return audition
        }
        takes = state.takes.map { take in
            var take = take
            take.fileURL = MediaStore.rebased(take.fileURL)
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
        if let i = a.scenes.indices.first(where: { i in !takes.contains { $0.auditionID == id && $0.sceneIndex == i } }) { return i }
        return 0
    }

    /// The scene a checklist piece is about (scene pieces share their scene's title).
    func sceneIndex(for piece: Piece, in id: Audition.ID) -> Int {
        audition(id)?.scenes.firstIndex { $0.title == piece.title } ?? sceneToShoot(id)
    }

    /// The one "Next" action used everywhere an audition offers to continue: opens whatever its next
    /// unfinished piece needs, or the package once everything is in.
    func continueAudition(_ id: Audition.ID) {
        syncHeadshotPieces()
        guard let a = audition(id) else { return }
        guard let next = a.nextPiece else { push(.package(id)); return }
        switch next.kind {
        case .headshot:                   push(.headshots(for: id))
        case .slate, .fullLength, .scene: camera = .shoot(id)
        }
    }

    /// Removes an audition and everything recorded for it on this iPhone: takes, slate and full
    /// length, reader tracks, practice pieces made from its scenes, and its exported tape. The iCloud
    /// copy behind a sent link is left alone — casting may still be using that link.
    func deleteAudition(_ id: Audition.ID) {
        guard let audition = audition(id) else { return }
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
        auditions[i].pieces.removeAll { $0.kind == .scene }
        auditions[i].pieces += scenes.map { Piece(kind: .scene, title: $0.title, detail: hadScenes ? "Revised sides" : "", isDone: false) }
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

    func reclassifyRole(for id: Audition.ID) {
        guard let index = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let scriptText = auditions[index].scriptText, !scriptText.isEmpty {
            auditions[index].scenes = ScriptParser.parseScenes(from: scriptText, myRole: auditions[index].role)
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
    func startCallback(from id: Audition.ID, due: Date, notes: String, bringReader: Bool) -> Audition.ID? {
        guard let original = audition(id) else { return nil }
        var callback = Audition(project: original.project, projectType: original.projectType, role: original.role,
                                roleSize: original.roleSize, castingOffice: original.castingOffice, due: due,
                                asks: original.asks,
                                pieces: original.pieces.map { Piece(kind: $0.kind, title: $0.title, detail: $0.detail, isDone: false) },
                                scenes: original.scenes, destination: original.destination, status: .due)
        callback.round = (original.round ?? 1) + 1
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        callback.castingNotes = trimmed.isEmpty ? nil : trimmed
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
        if auditions[i].nextPiece == nil { auditions[i].status = .ready }
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
    }

    func setSlateVideo(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].slateVideoURL = url
    }

    func keepOriginalSlate(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        if let previous = auditions[i].slateVideoURL, previous != url { try? FileManager.default.removeItem(at: previous) }
        if let backup = auditions[i].slateOriginalVideoURL, backup != url { try? FileManager.default.removeItem(at: backup) }
        auditions[i].slateVideoURL = url
        auditions[i].slateOriginalVideoURL = nil
        invalidateExport(for: id)
    }

    func acceptSlateTrim(_ trimmed: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }),
              let original = auditions[i].slateOriginalVideoURL ?? auditions[i].slateVideoURL,
              let replacement = moveEditedClip(trimmed, beside: original, stem: "slate-auto-trimmed") else { return }
        auditions[i].slateOriginalVideoURL = original
        auditions[i].slateVideoURL = replacement
        invalidateExport(for: id)
    }

    func restoreOriginalSlate(for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let original = auditions[i].slateOriginalVideoURL else { return }
        if let current = auditions[i].slateVideoURL, current != original { try? FileManager.default.removeItem(at: current) }
        auditions[i].slateVideoURL = original
        auditions[i].slateOriginalVideoURL = nil
        invalidateExport(for: id)
    }

    func setFullLengthVideo(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].fullLengthVideoURL = url
    }

    func replaceSlateVideo(for id: Audition.ID, with edited: URL) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let old = auditions[i].slateVideoURL,
              let replacement = moveEditedClip(edited, beside: old, stem: "slate") else { return }
        try? FileManager.default.removeItem(at: old)
        auditions[i].slateVideoURL = replacement
        invalidateExport(for: id)
    }

    func replaceFullLengthVideo(for id: Audition.ID, with edited: URL) {
        guard let i = auditions.firstIndex(where: { $0.id == id }), let old = auditions[i].fullLengthVideoURL,
              let replacement = moveEditedClip(edited, beside: old, stem: "full-length") else { return }
        try? FileManager.default.removeItem(at: old)
        auditions[i].fullLengthVideoURL = replacement
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
    }

    /// Swaps a take's file for its trimmed version. The new file gets a new name, so thumbnails and
    /// Tape Check (which key off the URL) pick up the change.
    func replaceTakeFile(_ id: Take.ID, with edited: URL) {
        guard let i = takes.firstIndex(where: { $0.id == id }), let old = takes[i].fileURL else { return }
        let dest = old.deletingLastPathComponent().appendingPathComponent("take-\(takes[i].number)-\(UUID().uuidString).mov")
        do { try FileManager.default.moveItem(at: edited, to: dest) } catch { return }
        try? FileManager.default.removeItem(at: old)
        takes[i].fileURL = dest
        if let auditionID = takes[i].auditionID { invalidateExport(for: auditionID) }
        Task { @MainActor in
            guard let seconds = try? await AVURLAsset(url: dest).load(.duration).seconds,
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
        practice[index].linesLearned = min(linesOnYourOwn, practice[index].linesTotal)
        promotePracticePiece(pieceID)
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
        updated.linesLearned = min(linesOnYourOwn, updated.linesTotal)
        practice.remove(at: i)
        practice.insert(updated, at: 0)
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
                if case let (.takes(existingID, _), .takes(targetID, _)) = (existing, route) {
                    return existingID == targetID
                }
                return false
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
