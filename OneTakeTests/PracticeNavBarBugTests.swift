import XCTest
import SwiftUI
@testable import OneTake

@MainActor
final class PracticeNavBarBugTests: XCTestCase {
    private func findTBC(host vc: UIViewController?) -> UITabBarController? {
        guard let vc else { return nil }
        if let tbc = vc as? UITabBarController { return tbc }
        for child in vc.children {
            if let found = findTBC(host: child) { return found }
        }
        return nil
    }

    func testTabBarRemainsVisibleAfterDisablingSampleSceneInProfileSheet() throws {
        UserDefaults.standard.set(true, forKey: "practice.showSample")
        defer { UserDefaults.standard.removeObject(forKey: "practice.showSample") }

        let store = AppStore()
        store.auditions = []
        store.practice = [
            PracticePiece(title: "A late goodbye", detail: "Sample · not saved", linesLearned: 0, linesTotal: 3, character: "MAYA", scene: nil)
        ]
        store.takes = []
        store.isOnboarded = true
        store.tab = .practice

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: RootTabView().environment(store))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let tbc = try XCTUnwrap(findTBC(host: host))

        if #available(iOS 18.0, *) {
            XCTAssertFalse(tbc.isTabBarHidden, "Tab bar should start visible on Practice root")
        }
        XCTAssertFalse(tbc.tabBar.isHidden, "UITabBar should start visible")

        // 1. Open and close Profile sheet without changing sample toggle.
        store.showProfile = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        store.showProfile = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        if #available(iOS 18.0, *) {
            XCTAssertFalse(tbc.isTabBarHidden, "Dismissing Profile sheet must not hide tab bar")
        }
        XCTAssertFalse(tbc.tabBar.isHidden, "UITabBar must stay visible after closing Profile sheet")

        // 2. Open Profile sheet, disable Show sample scene, purge sample data, and close sheet.
        store.showProfile = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        UserDefaults.standard.set(false, forKey: "practice.showSample")
        store.removeSampleData()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        store.showProfile = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        if #available(iOS 18.0, *) {
            XCTAssertFalse(tbc.isTabBarHidden, "Disabling Show sample scene in Profile sheet must not hide tab bar")
        }
        XCTAssertFalse(tbc.tabBar.isHidden, "UITabBar must stay visible after disabling Show sample scene")

        // 3. Pushed routes inside the tab still hide the tab bar and popping restores it.
        store.push(.practiceSetup)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        if #available(iOS 18.0, *) {
            XCTAssertTrue(tbc.isTabBarHidden, "Pushing a child screen should hide the tab bar")
        }

        store.pop()
        let deadline = Date().addingTimeInterval(2.0)
        while tbc.tabBar.isHidden && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        if #available(iOS 18.0, *) {
            XCTAssertFalse(tbc.isTabBarHidden, "Popping back to Practice root should restore the tab bar")
        }
        XCTAssertFalse(tbc.tabBar.isHidden)
    }

    func testEmptyPracticeViewHasNoActionWhenSampleDisabled() {
        XCTAssertEqual(EmptyPracticeView(showSample: true).buttonAction?.title, "Try a sample scene")
        XCTAssertNil(EmptyPracticeView(showSample: false).buttonAction)
    }
}
