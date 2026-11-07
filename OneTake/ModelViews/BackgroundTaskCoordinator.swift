import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Abstraction for managing platform background execution tasks, decoupling UIKit from AppStore business logic
/// and enabling deterministic unit testing of background task lifecycle, race conditions, and expiration.
protocol BackgroundTaskManaging: AnyObject, Sendable {
    func beginBackgroundTask(name: String, expirationHandler: (@Sendable () -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

#if canImport(UIKit)
final class UIKitBackgroundTaskManager: BackgroundTaskManaging {
    static let shared = UIKitBackgroundTaskManager()

    func beginBackgroundTask(name: String, expirationHandler: (@Sendable () -> Void)?) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expirationHandler)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
#else
final class UIKitBackgroundTaskManager: BackgroundTaskManaging {
    static let shared = UIKitBackgroundTaskManager()
    func beginBackgroundTask(name: String, expirationHandler: (@Sendable () -> Void)?) -> UIBackgroundTaskIdentifier { .invalid }
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
}
#endif

/// A thread-safe token ensuring background execution assertions are ended exactly once across
/// normal completion, errors, cancellation, and expiration callbacks.
final class BackgroundTaskToken: @unchecked Sendable {
    private let lock = NSLock()
    private var identifier: UIBackgroundTaskIdentifier
    private let manager: BackgroundTaskManaging
    private var isEnded = false

    init(manager: BackgroundTaskManaging, name: String, expirationHandler: (@Sendable () -> Void)?) {
        self.manager = manager
        self.identifier = manager.beginBackgroundTask(name: name, expirationHandler: expirationHandler)
    }

    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return identifier != .invalid && !isEnded
    }

    func end() {
        lock.lock()
        defer { lock.unlock() }
        guard !isEnded, identifier != .invalid else { return }
        isEnded = true
        let id = identifier
        identifier = .invalid
        manager.endBackgroundTask(id)
    }
}
