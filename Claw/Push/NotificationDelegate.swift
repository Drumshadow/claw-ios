import Foundation
import UserNotifications

// MARK: - NotificationDelegate

/// UNUserNotificationCenterDelegate that handles foreground banner display and tap routing.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Foreground presentation

    /// Show banners and play sound even when the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Tap handling

    /// Handle a notification tap. If the notification carries a `sessionKey` in its userInfo,
    /// post a named notification so the app can navigate to that session.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let sessionKey = userInfo["sessionKey"] as? String {
            NotificationCenter.default.post(
                name: Notification.Name("claw.notification.tapped"),
                object: nil,
                userInfo: ["sessionKey": sessionKey]
            )
        }

        completionHandler()
    }
}
