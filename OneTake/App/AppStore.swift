import SwiftUI
import Observation
import AVFoundation

/// Every pushed screen in the app. One enum keeps the flow testable and mirrors the Figma prototype keys.
enum Route: Hashable {
    case auditionDetail(Audition.ID)
    case prepare(Audition.ID, sceneIndex: Int)
    case runLines(Audition.ID, sceneIndex: Int)
    case reader(Audition.ID, sceneIndex: Int)
    case recordReader(Audition.ID, sceneIndex: Int)
    /// `scene` picks which scene the camera opens on; nil lets it pick the next one still to shoot.
    case shootSetup(Audition.ID, scene: Int? = nil)
    case takes(Audition.ID)
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
    /// Practice's Quick Drills: First-Letter Prompts and Mask & Reveal Lines (Audio Gap reuses `.runLines`).
    case lineDrill(Audition.ID, sceneIndex: Int, mode: LineLearningMode)
    /// Hands-Free Audio Walk — the one drill with its own screen.
    case audioWalk(Audition.ID, sceneIndex: Int)
}

/// The camera flow runs full-screen and outside the tab navigation, like the system Camera.
enum CameraFlow: Identifiable, Hashable {
    case shoot(Audition.ID, scene: Int? = nil)  // camera check → slate → full length → scene → take saved
    case headshot                    // front → left → right → crop
    case scanSides
    case practiceTake

    var id: String {
        switch self {
        case .shoot(let id, _): "shoot-\(id)"
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
    /// Set when an audition is saved; once the Add sheet has gone, the app continues straight into
    /// that audition's first step instead of stopping on its overview.
    var continueAfterAdd: Audition.ID?
    /// A notice shared from another app, waiting for Add audition to read it.
    var incomingShare: ShareInbox.Item?

    // Send state
    var sendProgress: Double = 0

    // MARK: Persistence

    private var saveTask: Task<Void, Never>?
    /// True while `init` is still applying a loaded snapshot, so that pass doesn't immediately
    /// re-trigger its own save.
    private var isLoading = false

    init() {
        isLoading = true
        if let saved = Persistence.load() {
            auditions = saved.auditions.map { a in
                var a = a
                a.slateVideoURL = MediaStore.rebased(a.slateVideoURL)
                a.fullLengthVideoURL = MediaStore.rebased(a.fullLengthVideoURL)
                a.exportedFileURL = MediaStore.rebased(a.exportedFileURL)
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
        }
        isLoading = false
    }

    /// Debounced so rapid edits (typing in a text field) don't hit disk on every keystroke.
    private func persist() {
        guard !isLoading else { return }
        saveTask?.cancel()
        let snapshot = PersistedState(auditions: auditions, takes: takes, practice: practice, slate: slate, isOnboarded: isOnboarded, account: account)
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            Persistence.save(snapshot)
            // Same debounce: reminders, widgets and the Live Activity follow due dates, progress,
            // status and deletions.
            Reminders.reschedule(snapshot.auditions)
            WidgetSync.update(snapshot.auditions)
            await LiveActivitySync.update(snapshot.auditions)
        }
    }

    // MARK: Account

    func signOut() {
        AccountAuth.signOut(account)
        account = nil
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
        if let export = audition.exportedFileURL,
           !auditions.contains(where: { $0.id != id && $0.exportedFileURL == export }) {
            try? fm.removeItem(at: export)
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
    func replaceSides(of id: Audition.ID, with scenes: [ScriptScene]) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].scenes = scenes
        auditions[i].pieces.removeAll { $0.kind == .scene }
        auditions[i].pieces += scenes.map { Piece(kind: .scene, title: $0.title, detail: "Revised sides", isDone: false) }
        if auditions[i].status == .ready { auditions[i].status = .due }
        for p in practice.indices where practice[p].auditionID == id {
            guard let s = practice[p].sceneIndex, scenes.indices.contains(s) else { continue }
            practice[p].scene = scenes[s]
            practice[p].linesTotal = scenes[s].lines.filter(\.isMine).count
            practice[p].linesLearned = min(practice[p].linesLearned, practice[p].linesTotal)
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

    func setFullLengthVideo(_ url: URL, for id: Audition.ID) {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return }
        auditions[i].fullLengthVideoURL = url
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
           !takes.contains(where: { $0.auditionID == id && $0.sceneIndex == scene }) {
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

    /// Push a route on the currently selected tab's stack.
    func push(_ route: Route) {
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
            guard let i = path.lastIndex(of: route) else { return false }
            path.removeSubrange(path.index(after: i)...)
            return true
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

    func popToRoot() {
        switch tab {
        case .auditions: auditionsPath.removeAll()
        case .search:    searchPath.removeAll()
        case .practice:  practicePath.removeAll()
        case .profile:   profilePath.removeAll()
        }
    }
}
