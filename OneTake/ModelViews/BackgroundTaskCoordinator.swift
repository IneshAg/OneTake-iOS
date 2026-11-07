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


/// Explicit, synchronized operation lifecycle managing background persistence flush execution,
/// ensuring that only one terminal outcome (completed, failed, or expired) can win, and preventing
/// delayed expiration callbacks from overwriting successful flush commits.
final class FlushOperation: @unchecked Sendable {
    enum Outcome: Equatable {
        case running
        case completed
        case failed(String)
        case expired
    }

    let sequence: Int
    private let lock = NSLock()
    private(set) var outcome: Outcome = .running
    private let token: BackgroundTaskToken

    init(sequence: Int, token: BackgroundTaskToken) {
        self.sequence = sequence
        self.token = token
    }

    /// Attempts to transition to `.completed`. Returns true if this transition won.
    @discardableResult
    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard outcome == .running else { return false }
        outcome = .completed
        token.end()
        return true
    }

    /// Attempts to transition to `.failed`. Returns true if this transition won.
    @discardableResult
    func markFailed(_ error: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard outcome == .running else { return false }
        outcome = .failed(error)
        token.end()
        return true
    }

    /// Attempts to transition to `.expired`. Returns true if this transition won.
    @discardableResult
    func markExpired() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard outcome == .running else { return false }
        outcome = .expired
        token.end()
        return true
    }

    var isTerminal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return outcome != .running
    }

    func currentOutcome() -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }
}
