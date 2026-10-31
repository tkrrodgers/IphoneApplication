import Foundation
import UserNotifications

/// The daily reminder to log (FR-25), at the user's chosen time.
enum Reminders {
    static let id = "daily-review"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ settings: AppSettings) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard settings.remindersOn else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your one-minute review"
        content.body = "Log today's prospects, expenses, miles and time — or tell HERB."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: settings.reminderTime, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
