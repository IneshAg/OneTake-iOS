// xcode: set sdk=iOS

import SwiftUI
import UIKit
import GoogleSignIn

@main
struct OneTakeApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    /// Profile → Appearance: "system" follows the iPhone; "light" / "dark" pin it. Every colour token
    /// has both a light and a dark value, so either works throughout.
    @AppStorage("appearance") private var appearance = "system"

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isOnboarded {
                    RootTabView()
                } else {
                    OnboardingFlow()
                }
            }
            .environment(store)
            .tint(OT.accent)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .task {
                if ProcessInfo.processInfo.arguments.contains("-loadSampleAudition") {
                    store.loadSampleAudition()
                }
                if ProcessInfo.processInfo.arguments.contains("-openProfile") {
                    store.showProfile = true
                }
                if ProcessInfo.processInfo.arguments.contains("-openFirstAudition"), let first = store.auditions.first {
                    store.auditionsPath = [.auditionDetail(first.id)]
                }
                await store.validateAccount()
            }
            // Widgets and the Live Activity open "onetake://audition/<id>".
            .onOpenURL { url in
                // Google's sign-in redirect comes back through here too.
                if GIDSignIn.sharedInstance.handle(url) { return }
                if url.scheme == "onetake", url.host == "tab" {
                    if url.lastPathComponent == "auditions" { store.tab = .auditions }
                    else if url.lastPathComponent == "practice" { store.tab = .practice }
                    return
                }
                if url.scheme == "onetake", url.host == "headshot" {
                    store.camera = .headshot
                    return
                }
                if url.scheme == "onetake", url.host == "add" {
                    store.showAddAudition = true
                    return
                }
                if url.scheme == "onetake", url.host == "profile" {
                    store.showProfile = true
                    return
                }
                guard url.scheme == "onetake", url.host == "audition",
                      let id = UUID(uuidString: url.lastPathComponent), store.audition(id) != nil else { return }
                store.showProfile = false
                store.camera = nil
                store.tab = .auditions
                store.auditionsPath = [.auditionDetail(id)]
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                store.flushPersistence()
            }
            // Countdowns move on while the app is closed; refresh them whenever it comes back.
            guard phase == .active else { return }
            WidgetSync.update(store.auditions)
            LiveActivitySync.update(store.auditions)
            // Anything shared to OneTake while it was closed opens Add audition with it — unless the
            // actor is mid-shoot or already adding one; it waits in the inbox until next time.
            if store.isOnboarded, store.camera == nil, !store.showAddAudition, store.incomingShare == nil,
               let shared = ShareInbox.next() {
                store.incomingShare = shared
                store.tab = .auditions
                store.showAddAudition = true
            }
        }
    }
}

struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"

    /// Search is useful once there are auditions or standalone practice pieces to query.
    private var isSearchAvailable: Bool {
        !store.auditions.isEmpty || !store.practice.isEmpty
    }

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("Auditions", systemImage: "movieclapper.fill", value: AppTab.auditions) {
                NavigationStack(path: $store.auditionsPath) {
                    AuditionsView()
                        .showSystemTabBar()
                        .withRoutes()
                }
            }

            Tab("Practice", systemImage: "theatermasks.fill", value: AppTab.practice) {
                NavigationStack(path: $store.practicePath) {
                    PracticeView()
                        .showSystemTabBar()
                        .withRoutes()
                }
            }

            if isSearchAvailable {
                if #available(iOS 27.0, *) {
                    // Keep Search as the distinct third control. iOS 27's prominent role
                    // prevents it from being folded into the two destination tabs.
                    Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .prominent) {
                        NavigationStack(path: $store.searchPath) {
                            SearchView()
                                .showSystemTabBar()
                                .withRoutes()
                        }
                    }
                } else {
                    // Earlier iOS versions still get the native dedicated Search tab role.
                    Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                        NavigationStack(path: $store.searchPath) {
                            SearchView()
                                .showSystemTabBar()
                                .withRoutes()
                        }
                    }
                }
            }
        }
        .applySearchTabActivation()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OT.bgCanvas.ignoresSafeArea())
        .onChange(of: isSearchAvailable) { _, available in
            if !available && store.tab == .search {
                store.tab = .auditions
            }
        }
        .sheet(isPresented: $store.showProfile, onDismiss: {
            store.profilePath.removeAll()
        }) {
            NavigationStack(path: $store.profilePath) {
                ProfileView()
                    .withRoutes()
            }
            .presentationDragIndicator(.visible)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .sheet(isPresented: $store.showAddAudition, onDismiss: {
            if let pending = store.pendingRouteAfterAdd {
                store.pendingRouteAfterAdd = nil
                store.push(pending)
            } else if let id = store.continueAfterAdd {
                store.continueAfterAdd = nil
                store.continueAudition(id)
            }
        }) {
            AddAuditionFlow()
                .presentationDetents([.height(315)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .fullScreenCover(item: $store.camera) { flow in
            switch flow {
            case .shoot(let id, let scene, let start): ShootFlow(auditionID: id, initialScene: scene, initialStage: start)
            case .headshot(let auditionID): HeadshotFlow(auditionID: auditionID)
            case .scanSides:      DocumentScannerView { _ in store.camera = nil }.ignoresSafeArea()
            case .practiceTake(let pieceID, let displayMode, let recordMode):
                PracticeTakeView(pieceID: pieceID, initialDisplayMode: displayMode, initialRecordMode: recordMode)
            }
        }
    }
}

// MARK: - Route table

private struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            destination(for: route)
                .hideSystemBars()
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .auditionDetail(let id):            AuditionDetailView(auditionID: id)
        case .prepare(let id, let scene):        PrepareView(auditionID: id, sceneIndex: scene)
        case .runLines(let id, let scene):       RunLinesView(auditionID: id, sceneIndex: scene)
        case .reader(let id, let scene):         ReaderView(auditionID: id, sceneIndex: scene)
        case .recordReader(let id, let scene, let initialLine, let readerChar): RecordReaderView(auditionID: id, sceneIndex: scene, initialLineIndex: initialLine, readerCharacter: readerChar)
        case .sceneAudioFlow(let id, let scene): SceneAudioFlowView(auditionID: id, sceneIndex: scene)
        case .shootSetup(let id, let scene):     ShootSetupView(auditionID: id, scene: scene)
        case .takes(let id, let sceneIndex):     TakesView(auditionID: id, initialScene: sceneIndex)
        case .tapeCheck(let id):                 TapeCheckView(auditionID: id)
        case .package(let id):                   PackageView(auditionID: id)
        case .preview(let id):                   TapePreviewView(auditionID: id)
        case .elementReview(let id, let element): AuditionElementReviewView(auditionID: id, element: element)
        case .profile:                           ProfileView()
        case .headshots(let id):                 HeadshotsView(auditionID: id)
        case .editSlate:                         EditSlateView()
        case .privacy:                           PrivacyView()
        case .notifications:                     NotificationSettingsView()
        case .practiceSetup:                     PracticeSetupView()
        case .practiceOptions(let id, let scene): PracticeOptionsView(auditionID: id, sceneIndex: scene)
        case .standalonePractice(let id):        StandalonePracticeView(pieceID: id)
        case .practiceSample:                    StandalonePracticeView(pieceID: nil, isSample: true)
        case .lineDrill(let id, let scene, let mode): LineDrillView(auditionID: id, sceneIndex: scene, mode: mode)
        case .audioWalk(let id, let scene):      AudioWalkView(auditionID: id, sceneIndex: scene)
        case .missingDetails:                    MissingDetailsView()
        case .noticeReview:                      NoticeReviewView()
        case .testSides:                         AddDraftSidesSheet(draft: .constant(NoticeParser.Draft(project: "Hamlet", role: "Ophelia", due: .now.addingTimeInterval(86400))))
        }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }

    @ViewBuilder
    func hideSystemBars() -> some View {
        self
            .toolbarVisibility(.hidden, for: .tabBar)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .background(TabBarHider())
    }

    @ViewBuilder
    func showSystemTabBar() -> some View {
        self
            .toolbarVisibility(.visible, for: .tabBar)
            .toolbar(.visible, for: .tabBar)
            .background(TabBarShower())
    }

    @ViewBuilder
    func applySearch(enabled: Bool, text: Binding<String>) -> some View {
        if enabled {
            self.searchable(text: text, prompt: "Search auditions, sides, practice...")
                .applySearchTabActivation()
        } else {
            self
        }
    }

    @ViewBuilder
    func applySearchTabActivation() -> some View {
        // `#available` only guards the runtime; the API also has to exist in the SDK being built
        // with (Xcode 26+). Older toolchains, like CI's Xcode 16, skip it entirely.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabViewSearchActivation(.searchTabSelection)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
