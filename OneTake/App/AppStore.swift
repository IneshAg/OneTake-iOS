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
    case headshots
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
    // Session
    var isOnboarded = false
    /// Guest by default — OneTake works fully offline without an account. Sign-in only ever
    /// happens at a real persistence boundary (e.g. a cross-device share link), never to unlock
    /// recording or export.
    var isSignedIn = false
    var slate = SlateInfo()

    // Data
    var auditions: [Audition] = SampleData.auditions
    var takes: [Take] = SampleData.takes
    var practice: [PracticePiece] = SampleData.practice

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

    // Send state
    var sendProgress: Double = 0

    // MARK: Lookup

    func audition(_ id: Audition.ID) -> Audition? { auditions.first { $0.id == id } }

    func binding(for id: Audition.ID) -> Binding<Audition>? {
        guard let i = auditions.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { self.auditions[i] }, set: { self.auditions[i] = $0 })
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

    func circle(_ take: Take) {
        for i in takes.indices { takes[i].isCircled = takes[i].id == take.id }
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
