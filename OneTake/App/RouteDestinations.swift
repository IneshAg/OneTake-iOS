import SwiftUI
import OneTakeUI

// MARK: - Route table

struct RouteDestinations: ViewModifier {
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
        case .testSides:                         AddDraftSidesSheet(draft: .constant(NoticeParser.Draft(project: "Hamlet", role: "Ophelia", due: .now.addingTimeInterval(86400))), isSheet: false)
        }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }

    @ViewBuilder
    func hideSystemBars() -> some View {
        self
            .toolbarVisibility(.hidden, for: .tabBar)
            .toolbar(.hidden, for: .tabBar)
            .background(TabBarHider())
    }

    @ViewBuilder
    func showSystemTabBar(isVisible: Bool = true) -> some View {
        self
            .toolbarVisibility(isVisible ? .visible : .hidden, for: .tabBar)
            .toolbar(isVisible ? .visible : .hidden, for: .tabBar)
            .background(TabBarShower(isVisible: isVisible))
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

/// Renders a root tab title inline on the leading side of the navigation bar without an iOS 26 glass pill.
struct OTInlineRootTitle: ToolbarContent {
    let title: String

    var body: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                titleLabel
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                titleLabel
            }
        }
        #else
        ToolbarItem(placement: .topBarLeading) {
            titleLabel
        }
        #endif
    }

    private var titleLabel: some View {
        Text(title)
            .font(.otLargeTitle)
            .foregroundStyle(OT.labelPrimary)
            .fixedSize()
    }
}

/// Inserts a fixed toolbar spacer on iOS 26+ so adjacent trailing toolbar buttons stay visually separate.
struct OTTrailingToolbarSpacer: ToolbarContent {
    var body: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        #endif
    }
}
