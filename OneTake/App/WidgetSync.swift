import ActivityKit
import Foundation
import WidgetKit

// MARK: - Widgets

extension WidgetSnapshot {
    /// The widgets' view of the app: unsent, not-yet-due auditions, soonest first, with each piece
    /// marked done / next / to do in tape order.
    init(auditions: [Audition], now: Date = .now) {
        upcoming = auditions
            .filter { $0.status != .sent && $0.due > now }
            .sorted { $0.due < $1.due }
            .prefix(3)
            .map { Item(id: $0.id, project: $0.project, role: $0.role, due: $0.due, pieces: Self.pieces(for: $0)) }
    }

    static func pieces(for audition: Audition) -> [Piece] {
        let nextID = audition.nextPiece?.id
        return audition.pieces.map { piece in
            Piece(title: piece.title, status: piece.isDone ? .done : piece.id == nextID ? .next : .todo)
        }
    }
}

enum WidgetSync {
    /// Writes the snapshot and asks WidgetKit to redraw — only when what the widgets show has
    /// changed. Called with every (debounced) save, and WidgetKit budgets reloads: most saves (a
    /// note, a circled take, a trim) don't touch the widgets at all.
    static func update(_ auditions: [Audition]) {
        let snapshot = WidgetSnapshot(auditions: auditions)
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Live Activity

/// Keeps one Live Activity running for the audition that's due next — once it's within a day of
/// its deadline — and ends it when that audition is sent, deleted, or past due. Also carries the
/// upload progress of a tape being sent as a link.
@MainActor
enum LiveActivitySync {
    /// Only start the countdown when the deadline is close enough to matter.
    private static let window: TimeInterval = 24 * 3600
    private static var isEnabled: Bool { UserDefaults.standard.object(forKey: "n.liveActivity") as? Bool ?? true }

    static func update(_ auditions: [Audition]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date.now
        let target = isEnabled
            ? auditions.filter { $0.status != .sent && $0.due > now && $0.due.timeIntervalSince(now) < window }.min { $0.due < $1.due }
            : nil
        let running = Activity<AuditionActivityAttributes>.activities

        // End anything that's no longer the audition to count down (unless it's mid-upload).
        for activity in running where activity.attributes.auditionID != target?.id && activity.content.state.uploadProgress == nil {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard let target else { return }
        let state = AuditionActivityAttributes.ContentState(pieces: WidgetSnapshot.pieces(for: target), uploadProgress: nil)
        if let existing = running.first(where: { $0.attributes.auditionID == target.id }) {
            guard existing.content.state.uploadProgress == nil, existing.content.state != state else { return }
            Task { await existing.update(ActivityContent(state: state, staleDate: target.due)) }
        } else {
            start(target, state: state)
        }
    }

    /// Upload progress for a link send (0…1), or nil when it's finished. Starts an activity for that
    /// audition if there isn't one, so the actor can leave the app while it uploads.
    static func setUploadProgress(_ progress: Double?, for audition: Audition) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = AuditionActivityAttributes.ContentState(pieces: WidgetSnapshot.pieces(for: audition), uploadProgress: progress)
        if let existing = Activity<AuditionActivityAttributes>.activities.first(where: { $0.attributes.auditionID == audition.id }) {
            if progress == nil, audition.status == .sent {
                Task { await existing.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default) }
            } else {
                Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
            }
        } else if progress != nil {
            start(audition, state: state)
        }
    }

    private static func start(_ audition: Audition, state: AuditionActivityAttributes.ContentState) {
        let attributes = AuditionActivityAttributes(auditionID: audition.id, project: audition.project, role: audition.role, due: audition.due)
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: audition.due))
    }
}
