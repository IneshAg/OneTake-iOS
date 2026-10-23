import SwiftUI
import Observation

/// Every pushed screen in the app. One enum keeps the flow testable and mirrors the Figma prototype keys.
enum Route: Hashable {
    case auditionDetail(Audition.ID)
    case prepare(Audition.ID, sceneIndex: Int)
    case runLines(Audition.ID, sceneIndex: Int)
    case reader(Audition.ID)
    case recordReader(Audition.ID)
    case shootSetup(Audition.ID)
    case takes(Audition.ID)
    case tapeCheck(Audition.ID)
    case package(Audition.ID)
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
    case shoot(Audition.ID)          // camera check → slate → full length → scene → take saved
    case headshot                    // front → left → right → crop
    case scanSides
    case practiceTake

    var id: String {
        switch self {
        case .shoot(let id): "shoot-\(id)"
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
    var isOnboarded = false { didSet { persist() } }
    /// Guest by default — OneTake works fully offline without an account. Sign-in only ever
    /// happens at a real persistence boundary (e.g. a cross-device share link), never to unlock
    /// recording or export.
    var isSignedIn = false { didSet { persist() } }
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
            slate = saved.slate
            isOnboarded = saved.isOnboarded
            isSignedIn = saved.isSignedIn
        }
        isLoading = false
    }

    /// Debounced so rapid edits (typing in a text field) don't hit disk on every keystroke.
    private func persist() {
        guard !isLoading else { return }
        saveTask?.cancel()
        let snapshot = PersistedState(auditions: auditions, takes: takes, practice: practice, slate: slate, isOnboarded: isOnboarded, isSignedIn: isSignedIn)
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            Persistence.save(snapshot)
        }
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
        for i in auditions.indices where auditions[i].status != .sent {
            for j in auditions[i].pieces.indices where auditions[i].pieces[j].kind == .headshot {
                auditions[i].pieces[j].isDone = true
            }
            if auditions[i].nextPiece == nil, auditions[i].status == .due { auditions[i].status = .ready }
        }
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

    /// Push a route on the currently selected tab's stack.
    func push(_ route: Route) {
        switch tab {
        case .auditions: auditionsPath.append(route)
        case .search:    searchPath.append(route)
        case .practice:  practicePath.append(route)
        case .profile:   profilePath.append(route)
        }
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
