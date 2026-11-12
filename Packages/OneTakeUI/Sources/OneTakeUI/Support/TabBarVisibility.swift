import SwiftUI
import UIKit

// MARK: - Tab Bar Visibility Controller Bridges

/// Ensures the enclosing UITabBarController hides its tab bar when this view appears.
public struct TabBarHider: UIViewControllerRepresentable {
    public init() {}

    public func makeUIViewController(context: Context) -> HiderController {
        HiderController()
    }

    public func updateUIViewController(_ uiViewController: HiderController, context: Context) {
        uiViewController.hideTabBar(animated: false)
    }

    public final class HiderController: UIViewController {
        public override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hidesBottomBarWhenPushed = true
            parent?.hidesBottomBarWhenPushed = true
            hideTabBar(animated: animated)
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hideTabBar(animated: false)
        }

        func hideTabBar(animated: Bool) {
            guard let tbc = findTabBarController() else { return }
            if #available(iOS 18.0, *) {
                if !tbc.isTabBarHidden {
                    tbc.setTabBarHidden(true, animated: animated)
                }
            } else {
                tbc.tabBar.isHidden = true
            }
        }

        private func findTabBarController() -> UITabBarController? {
            if let tbc = tabBarController { return tbc }
            if let tbc = navigationController?.tabBarController { return tbc }
            var current: UIViewController? = self
            while let p = current?.parent {
                if let tbc = p as? UITabBarController ?? p.tabBarController { return tbc }
                current = p
            }
            var responder: UIResponder? = self
            while let r = responder {
                if let tbc = r as? UITabBarController { return tbc }
                responder = r.next
            }
            if let root = view.window?.rootViewController {
                if let tbc = root as? UITabBarController { return tbc }
                for child in root.children {
                    if let tbc = child as? UITabBarController { return tbc }
                }
            }
            return nil
        }
    }
}

/// Ensures the enclosing UITabBarController shows its tab bar when this root view appears.
public struct TabBarShower: UIViewControllerRepresentable {
    public init() {}

    public func makeUIViewController(context: Context) -> ShowerController {
        ShowerController()
    }

    public func updateUIViewController(_ uiViewController: ShowerController, context: Context) {
        uiViewController.showTabBar(animated: false)
    }

    public final class ShowerController: UIViewController {
        public override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            showTabBar(animated: animated)
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            showTabBar(animated: false)
        }

        func showTabBar(animated: Bool) {
            guard isTopOrVisible() else { return }
            guard let tbc = findTabBarController() else { return }
            if #available(iOS 18.0, *) {
                if tbc.isTabBarHidden {
                    tbc.setTabBarHidden(false, animated: animated)
                }
            } else {
                tbc.tabBar.isHidden = false
            }
        }

        private func isTopOrVisible() -> Bool {
            guard let nav = findNavigationController() else { return true }
            if nav.viewControllers.count > 1 {
                if nav.topViewController !== self && nav.topViewController !== parent {
                    return false
                }
            }
            return true
        }

        private func findNavigationController() -> UINavigationController? {
            if let nav = navigationController { return nav }
            var current: UIViewController? = self
            while let p = current?.parent {
                if let nav = p as? UINavigationController ?? p.navigationController { return nav }
                current = p
            }
            return nil
        }

        private func findTabBarController() -> UITabBarController? {
            if let tbc = tabBarController { return tbc }
            if let tbc = navigationController?.tabBarController { return tbc }
            var current: UIViewController? = self
            while let p = current?.parent {
                if let tbc = p as? UITabBarController ?? p.tabBarController { return tbc }
                current = p
            }
            var responder: UIResponder? = self
            while let r = responder {
                if let tbc = r as? UITabBarController { return tbc }
                responder = r.next
            }
            if let root = view.window?.rootViewController {
                if let tbc = root as? UITabBarController { return tbc }
                for child in root.children {
                    if let tbc = child as? UITabBarController { return tbc }
                }
            }
            return nil
        }
    }
}
