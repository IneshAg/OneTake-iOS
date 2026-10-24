import SwiftUI

@main
struct OneTakeApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    /// Profile → Appearance: "system" follows the iPhone; "light" / "dark" pin it. Every colour token
    /// has both a light and a dark value, so either works throughout.
    @AppStorage("appearance") private var appearance = "system"

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
            // Widgets and the Live Activity open "onetake://audition/<id>".
            .onOpenURL { url in
                guard url.scheme == "onetake", url.host == "audition",
                      let id = UUID(uuidString: url.lastPathComponent), store.audition(id) != nil else { return }
                store.camera = nil
                store.tab = .auditions
                store.auditionsPath = [.auditionDetail(id)]
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Countdowns move on while the app is closed; refresh them whenever it comes back.
            guard phase == .active else { return }
            WidgetSync.update(store.auditions)
            LiveActivitySync.update(store.auditions)
        }
    }
}

struct RootTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("Auditions", systemImage: "movieclapper.fill", value: AppTab.auditions) {
                NavigationStack(path: $store.auditionsPath) {
                    AuditionsView().withRoutes()
                }
            }
            Tab("Practice", systemImage: "theatermasks.fill", value: AppTab.practice) {
                NavigationStack(path: $store.practicePath) {
                    PracticeView().withRoutes()
                }
            }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                NavigationStack(path: $store.profilePath) {
                    ProfileView().withRoutes()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $store.searchPath) {
                    SearchView().withRoutes()
                }
            }
        }
        .searchable(text: $store.searchQuery, prompt: "Search auditions, practice, profile...")
        .applySearchTabActivation()
        .sheet(isPresented: $store.showAddAudition, onDismiss: {
            // Presenting the next screen only after the sheet is fully gone (a camera cover can't
            // present over a sheet that's still dismissing).
            guard let id = store.continueAfterAdd else { return }
            store.continueAfterAdd = nil
            store.continueAudition(id)
        }) {
            AddAuditionFlow()
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $store.camera) { flow in
            switch flow {
            case .shoot(let id):  ShootFlow(auditionID: id)
            case .headshot:       HeadshotFlow()
            case .scanSides:      DocumentScannerView { _ in store.camera = nil }.ignoresSafeArea()
            case .practiceTake:   PracticeTakeView()
            }
        }
    }
}

// MARK: - Route table

private struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case .auditionDetail(let id):            AuditionDetailView(auditionID: id)
            case .prepare(let id, let scene):        PrepareView(auditionID: id, sceneIndex: scene)
            case .runLines(let id, let scene):       RunLinesView(auditionID: id, sceneIndex: scene)
            case .reader(let id):                    ReaderView(auditionID: id)
            case .recordReader(let id):              RecordReaderView(auditionID: id)
            case .shootSetup(let id):                ShootSetupView(auditionID: id)
            case .takes(let id):                     TakesView(auditionID: id)
            case .tapeCheck(let id):                 TapeCheckView(auditionID: id)
            case .package(let id):                   PackageView(auditionID: id)
            case .preview(let id):                   TapePreviewView(auditionID: id)
            case .headshots(let id):                 HeadshotsView(auditionID: id)
            case .editSlate:                         EditSlateView()
            case .privacy:                           PrivacyView()
            case .notifications:                     NotificationSettingsView()
            case .practiceSetup:                     PracticeSetupView()
            case .lineDrill(let id, let scene, let mode): LineDrillView(auditionID: id, sceneIndex: scene, mode: mode)
            case .audioWalk(let id, let scene):      AudioWalkView(auditionID: id, sceneIndex: scene)
            }
        }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }

    @ViewBuilder
    func applySearchTabActivation() -> some View {
        if #available(iOS 26.0, *) {
            self.tabViewSearchActivation(.searchTabSelection)
        } else {
            self
        }
    }
}
