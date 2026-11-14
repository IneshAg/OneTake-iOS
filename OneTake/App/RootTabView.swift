import SwiftUI

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
                        .withRoutes()
                }
                .toolbarVisibility(store.auditionsPath.isEmpty ? .visible : .hidden, for: .tabBar)
                .background(TabBarShower(isVisible: store.auditionsPath.isEmpty))
            }

            Tab("Practice", systemImage: "theatermasks.fill", value: AppTab.practice) {
                NavigationStack(path: $store.practicePath) {
                    PracticeView()
                        .withRoutes()
                }
                .toolbarVisibility(store.practicePath.isEmpty ? .visible : .hidden, for: .tabBar)
                .background(TabBarShower(isVisible: store.practicePath.isEmpty))
            }

            if #available(iOS 27.0, *) {
                // Keep Search as the distinct third control. iOS 27's prominent role
                // prevents it from being folded into the two destination tabs.
                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .prominent) {
                    NavigationStack(path: $store.searchPath) {
                        SearchView()
                            .withRoutes()
                    }
                    .toolbarVisibility(store.searchPath.isEmpty ? .visible : .hidden, for: .tabBar)
                    .background(TabBarShower(isVisible: store.searchPath.isEmpty))
                }
            } else {
                // Earlier iOS versions still get the native dedicated Search tab role.
                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    NavigationStack(path: $store.searchPath) {
                        SearchView()
                            .withRoutes()
                    }
                    .toolbarVisibility(store.searchPath.isEmpty ? .visible : .hidden, for: .tabBar)
                    .background(TabBarShower(isVisible: store.searchPath.isEmpty))
                }
            }
        }
        .applySearchTabActivation()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OT.bgCanvas.ignoresSafeArea())
        .sheet(isPresented: $store.showProfile, onDismiss: {
            store.profilePath.removeAll()
        }) {
            NavigationStack(path: $store.profilePath) {
                ProfileView()
                    .withRoutes()
            }
            .environment(\.otInSheet, true)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .sheet(isPresented: $store.showAddAudition, onDismiss: {
            if let pending = store.pendingRouteAfterAdd {
                store.pendingRouteAfterAdd = nil
                if store.auditionsPath.last != pending {
                    Task { @MainActor in
                        store.push(pending)
                    }
                }
            } else if let id = store.continueAfterAdd {
                store.continueAfterAdd = nil
                Task { @MainActor in
                    store.continueAudition(id)
                }
            }
        }) {
            AddAuditionFlow()
                .presentationDetents([.height(315)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .fullScreenCover(item: $store.camera) { flow in
            switch flow {
            case .shoot(let id, let scene, let start):
                ShootWithSlateSetup(auditionID: id, scene: scene, start: start)
            case .headshot(let auditionID): HeadshotFlow(auditionID: auditionID)
            case .scanSides:      DocumentScannerView { _ in store.camera = nil }.ignoresSafeArea()
            case .practiceTake(let pieceID, let displayMode, let recordMode):
                PracticeTakeView(pieceID: pieceID, initialDisplayMode: displayMode, initialRecordMode: recordMode)
            }
        }
    }
}

/// Offers slate details before the camera opens for a pending required slate.
private struct ShootWithSlateSetup: View {
    let auditionID: Audition.ID
    let scene: Int?
    let start: CameraFlow.ShootStart

    @Environment(AppStore.self) private var store
    @AppStorage("slate.hasSeenSetup") private var hasSeenSetup = false

    var body: some View {
        if !hasSeenSetup,
           store.slate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let audition = store.audition(auditionID),
           audition.pieces.contains(where: { $0.kind == .slate && !$0.isOptional && !$0.isDone }) {
            NavigationStack {
                SlateDetailsView(onContinue: { hasSeenSetup = true })
                    .navigationTitle("Set up your slate")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { store.camera = nil }
                        }
                    }
            }
        } else {
            ShootFlow(auditionID: auditionID, initialScene: scene, initialStage: start)
        }
    }
}
