import Foundation
import BackgroundTasks
import UserNotifications

// MARK: - HealthCheckScheduler

/// Manages BGTaskScheduler registration and handling for periodic SSH health checks.
final class HealthCheckScheduler {

    static let taskIdentifier = "ai.clawos.health-check"

    // MARK: - Registration

    /// Register the background task handler. Call from AppDelegate.didFinishLaunching.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                // Retrieve stores from shared singletons via notification or
                // use a stored reference set by ClawApp at launch.
                await HealthCheckScheduler.handleBackgroundTask(refreshTask)
            }
        }
    }

    // MARK: - Scheduling

    /// Schedule the next BGAppRefreshTask to fire after `intervalSeconds`.
    static func scheduleNextCheck(after intervalSeconds: Int) {
        guard intervalSeconds > 0 else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalSeconds))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[HealthCheckScheduler] Failed to schedule background task: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Background Fetch Handling

    /// Called by the OS when the background task fires.
    /// Runs health checks for all instances that have credentials and a non-zero interval.
    @MainActor
    static func handleBackgroundFetch(
        store: InstanceSSHStore,
        remoteOpsStore: RemoteOpsStore
    ) async {
        for instance in remoteOpsStore.ec2Instances {
            guard store.hasCredential(for: instance.id) else { continue }

            let config = store.loadHealthConfig(for: instance.id)
            guard config.intervalSeconds > 0 else { continue }

            let result = await store.runHealthCheck(for: instance)

            if !result.success {
                await postFailureNotification(for: instance, result: result)
            }

            // Reschedule with this instance's interval (use the smallest non-zero
            // interval across all configured instances for the next wake).
            scheduleNextCheck(after: config.intervalSeconds)
        }
    }

    // MARK: - Private

    @MainActor
    private static func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // Provide a cancellation handler so iOS can terminate us gracefully.
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Create fresh store instances for background work.
        // All SSH credentials and configs are persisted in Keychain, so a fresh
        // InstanceSSHStore has full access to the same data as the foreground UI.
        let store = InstanceSSHStore()
        let opsStore = RemoteOpsStore()

        // Refresh EC2 instances so we know which to check.
        await opsStore.refresh()

        await handleBackgroundFetch(store: store, remoteOpsStore: opsStore)
        task.setTaskCompleted(success: true)
    }

    private static func postFailureNotification(for instance: EC2Instance, result: HealthCheckResult) async {
        let content = UNMutableNotificationContent()
        content.title = "Health check failed: \(instance.name)"
        content.body = result.output.isEmpty ? "Command returned an error." : String(result.output.prefix(200))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "health-fail-\(instance.id)-\(result.id.uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            #if DEBUG
            print("[HealthCheckScheduler] Failed to post notification: \(error.localizedDescription)")
            #endif
        }
    }
}

