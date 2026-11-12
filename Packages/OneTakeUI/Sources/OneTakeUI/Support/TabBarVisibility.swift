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

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hidesBottomBarWhenPushed = true
            parent?.hidesBottomBarWhenPushed = true
            var responder: UIResponder? = view
            while let r = responder {
                if let vc = r as? UIViewController, vc !== self {
                    vc.hidesBottomBarWhenPushed = true
                }
                responder = r.next
            }
            hideTabBar(animated: animated)
        }

        private func findTabBarController() -> UITabBarController? {
            if let tbc = tabBarController { return tbc }
            if let tbc = navigationController?.tabBarController { return tbc }
            var responder: UIResponder? = view
            while let r = responder {
                if let tbc = r as? UITabBarController { return tbc }
                if let vc = r as? UIViewController, let tbc = vc.tabBarController { return tbc }
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
    public let isVisible: Bool

    public init(isVisible: Bool = true) {
        self.isVisible = isVisible
    }

    public func makeUIViewController(context: Context) -> ShowerController {
        let vc = ShowerController()
        vc.desiredVisibility = isVisible
        return vc
    }

    public func updateUIViewController(_ uiViewController: ShowerController, context: Context) {
        uiViewController.desiredVisibility = isVisible
        if isVisible {
            uiViewController.showTabBar(animated: false)
        } else {
            uiViewController.hideTabBar(animated: false)
        }
    }

    public final class ShowerController: UIViewController {
        var desiredVisibility: Bool = true

        public override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if desiredVisibility {
                showTabBar(animated: animated)
            } else {
                hideTabBar(animated: animated)
            }
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if desiredVisibility {
                showTabBar(animated: false)
            } else {
                hideTabBar(animated: false)
            }
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

        func showTabBar(animated: Bool) {
            guard desiredVisibility else {
                hideTabBar(animated: animated)
                return
            }
            guard isTopOrVisible() else {
                hideTabBar(animated: animated)
                return
            }
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
            guard let nav = findNavigationController() else {
                if let tbc = findTabBarController(), let sel = tbc.selectedViewController {
                    if let nav = sel as? UINavigationController ?? sel.children.compactMap({ $0 as? UINavigationController }).first {
                        return nav.viewControllers.count <= 1
                    }
                }
                return true
            }
            return nav.viewControllers.count <= 1
        }

        private func findNavigationController() -> UINavigationController? {
            if let nav = navigationController { return nav }
            var responder: UIResponder? = view
            while let r = responder {
                if let vc = r as? UIViewController, vc !== self {
                    if let nav = vc as? UINavigationController ?? vc.navigationController {
                        return nav
                    }
                }
                responder = r.next
            }
            if let root = view.window?.rootViewController {
                if let nav = root as? UINavigationController { return nav }
                if let tbc = root as? UITabBarController, let sel = tbc.selectedViewController {
                    if let nav = sel as? UINavigationController { return nav }
                    for child in sel.children {
                        if let nav = child as? UINavigationController { return nav }
                    }
                }
            }
            return nil
        }

        private func findTabBarController() -> UITabBarController? {
            if let tbc = tabBarController { return tbc }
            if let tbc = navigationController?.tabBarController { return tbc }
            var responder: UIResponder? = view
            while let r = responder {
                if let tbc = r as? UITabBarController { return tbc }
                if let vc = r as? UIViewController, let tbc = vc.tabBarController { return tbc }
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
