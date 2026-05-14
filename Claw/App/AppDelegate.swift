import UIKit
import UserNotifications
import BackgroundTasks

// MARK: - AppDelegate

/// UIApplicationDelegate wired via @UIApplicationDelegateAdaptor.
/// Handles APNs token delivery and notification delegate setup.
final class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Shared push manager reference
    // Injected by ClawApp after the delegate is initialized.
    var pushManager: PushManager?

    // MARK: - Notification delegate
    private let notificationDelegate = NotificationDelegate()

    // MARK: - App launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // Register BGTaskScheduler handler for SSH health checks.
        HealthCheckScheduler.registerBackgroundTask()
        return true
    }

    // MARK: - APNs token registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            pushManager?.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
        #endif
    }

    // MARK: - Background fetch / silent push

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Forward to PushManager for presence heartbeat
        Task { @MainActor in
            if let client = pushManager?.gatewayClient {
                await pushManager?.handleBackgroundWake(client: client)
            }
            completionHandler(.noData)
        }
    }
}
