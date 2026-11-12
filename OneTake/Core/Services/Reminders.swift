import Foundation
import UserNotifications

/// Handles notification presentation so alerts show banner and sound in the foreground too.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
}

/// Local reminders, scheduled on this iPhone — no server. Rebuilt from the auditions whenever they
/// change, so a moved due date, a sent tape or a deleted audition never leaves a stale alert behind.
/// Which ones are on is the Notifications screen's toggles (`n.*` in UserDefaults).
enum Reminders {
    private static let prefix = "onetake."

    private static func isOn(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "OneTake Deadline Reminder"
        content.body = "Your reminders are active. You’ll hear from OneTake when an audition is due."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "\(prefix)test.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    struct PlannedReminder: Equatable {
        let id: String
        let title: String
        let body: String
        let date: Date
    }

    static func plannedReminders(
        for auditions: [Audition],
        now: Date = .now,
        morning: Bool = isOn("n.morning", default: true),
        twoHours: Bool = isOn("n.twoHours", default: true)
    ) -> [PlannedReminder] {
        let upcoming = auditions.filter { $0.status != .sent && $0.due > now }
        let minSeparation: TimeInterval = 2 * 3600
        var result: [PlannedReminder] = []

        for a in upcoming {
            let dueTime = a.due.formatted(date: .omitted, time: .shortened)
            let twoBefore = a.due.addingTimeInterval(-2 * 3600)
            let willScheduleTwoHours = twoHours && twoBefore > now

            if morning,
               let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: a.due),
               nine > now,
               nine < a.due {
                // Suppress morning reminder if the 2-hour reminder will fire on the same day within 2 hours of it
                // (e.g. deadline is 11:08 AM -> twoBefore is 9:08 AM, only 8 minutes after 9:00 AM).
                let collidesWithTwoHours = willScheduleTwoHours && (twoBefore <= nine || twoBefore.timeIntervalSince(nine) < minSeparation)
                if !collidesWithTwoHours {
                    result.append(PlannedReminder(
                        id: "\(prefix)morning.\(a.id)",
                        title: "\(a.project) is due today",
                        body: "Due \(dueTime). Next: \(a.nextAction).",
                        date: nine
                    ))
                }
            }

            if willScheduleTwoHours {
                result.append(PlannedReminder(
                    id: "\(prefix)twohours.\(a.id)",
                    title: "Two hours left · \(a.project)",
                    body: "Due \(dueTime). Next: \(a.nextAction).",
                    date: twoBefore
                ))
            }
        }

        return result
    }

    static func reschedule(_ auditions: [Audition]) {
        let morning = isOn("n.morning", default: true)
        let twoHours = isOn("n.twoHours", default: true)
        let practice = isOn("n.practice", default: false)
        let now = Date.now
        let upcoming = auditions.filter { $0.status != .sent && $0.due > now }

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

            let reminders = plannedReminders(for: auditions, now: now, morning: morning, twoHours: twoHours)
            for r in reminders {
                add(center, id: r.id, title: r.title, body: r.body, at: r.date)
            }

            // One gentle daily nudge at 6 pm toward the soonest audition that has sides to learn.
            if practice, let next = upcoming.filter({ !$0.scenes.isEmpty }).min(by: { $0.due < $1.due }) {
                let content = UNMutableNotificationContent()
                content.title = "Run your lines"
                content.body = "\(next.role) in \(next.project) — five minutes is enough."
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 18, minute: 0), repeats: true)
                center.add(UNNotificationRequest(identifier: "\(prefix)practice", content: content, trigger: trigger))
            }
        }
    }

    /// Immediate alert, for something that finished while the actor was out of the app.
    static func notifyNow(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(prefix)now.\(UUID().uuidString)", content: content, trigger: nil))
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
}
