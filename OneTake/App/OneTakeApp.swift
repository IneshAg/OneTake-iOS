// xcode: set sdk=iOS

import SwiftUI
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
