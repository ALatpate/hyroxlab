import Foundation
import UserNotifications
import LumaCore

/// Hands Luma's reminders to iOS. What is due, and when, is worked out in LumaCore from the athlete's
/// own numbers (`ReminderPlanner`); this only keeps the system's pending list equal to that plan.
/// Everything stays on the phone: these are local notifications.
private let lumaReminderPrefix = "luma.reminder."

@MainActor
enum LumaReminders {
    /// What was last handed over, so an unchanged plan costs nothing. Nil until the first plan.
    private static var last: [String]?

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Shows one notification now, if the athlete has given leave for notifications. Used for a result
    /// that has just come in (Luma Doctor's weekly check); a second one with the same id replaces the first.
    static func post(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = "luma.doctor"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    /// Makes the pending reminders equal to `planned`. A reminder keeps its id from one plan to the
    /// next, so planning again replaces it; one whose reason has gone is no longer in the plan and is removed.
    static func sync(_ planned: [PlannedReminder]) {
        let signature = planned.map { "\($0.id)|\(LNum.int($0.at.timeIntervalSince1970))|\($0.title)|\($0.body)" }
        guard signature != last else { return }
        last = signature
        let center = UNUserNotificationCenter.current()
        let keep = Set(planned.map { $0.id })
        center.getPendingNotificationRequests { pending in
            let stale = pending.map { $0.identifier }.filter { $0.hasPrefix(lumaReminderPrefix) && !keep.contains($0) }
            if !stale.isEmpty { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale) }
        }
        for reminder in planned {
            let wait = reminder.at.timeIntervalSinceNow
            guard wait > 5 else { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "luma.reminders"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
