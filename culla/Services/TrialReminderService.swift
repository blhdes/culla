import Foundation
import UserNotifications

/// Schedules a single local notification 24h before the Culla Pro trial expires.
/// Silently no-ops if the user denies notification permission or the trial has already ended.
enum TrialReminderService {
    private static let identifier = "culla.trial.expiring"
    private static let leadTime: TimeInterval = 24 * 60 * 60

    static func scheduleReminder(for expirationDate: Date) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        cancelReminder()

        let fireDate = expirationDate.addingTimeInterval(-leadTime)
        let interval = fireDate.timeIntervalSinceNow
        // If we're already inside the 24h window, fire in 5s so the user still gets a heads-up.
        let finalInterval = max(interval, 5)
        guard expirationDate.timeIntervalSinceNow > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your Culla Pro trial ends soon")
        content.body = String(localized: "Cancel anytime in Settings to avoid being charged.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: finalInterval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
