import Foundation
import UIKit
import UserNotifications

// MARK: - PushManager

/// Manages APNs registration, gateway push token registration, and local notification scheduling.
@Observable
@MainActor
final class PushManager {

    // MARK: - Observable state

    private(set) var apnsToken: String?
    private(set) var isRegisteredWithGateway: Bool = false
    private(set) var registrationError: Error?

    // MARK: - Dependencies

    /// Set by AppState when a valid client is available.
    var gatewayClient: GatewayClient?

    // MARK: - Request authorization

    /// Requests notification authorization from the system.
    /// Returns true if the user granted permission.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Register for remote notifications

    /// Registers the app for remote (APNs) notifications.
    /// Must be called on the MainActor.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Handle device token

    /// Converts the raw APNs token data to a hex string, persists it, and registers it with the gateway.
    func handleDeviceToken(_ tokenData: Data) {
        let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
        apnsToken = hexToken

        // Persist to Keychain for reference
        if let data = hexToken.data(using: .utf8) {
            try? KeychainStore.save(key: "claw.push.apnsToken", data: data)
        }

        // Register with gateway if client is available
        Task {
            await registerWithGateway()
        }
    }

    // MARK: - Register with gateway

    /// Sends the APNs token to the gateway via the `push.apns.register` method.
    func registerWithGateway() async {
        guard let token = apnsToken, let client = gatewayClient else { return }

        #if DEBUG
        let env = "development"
        #else
        let env = "production"
        #endif
        let params = APNSRegisterParams(
            token: token,
            environment: env,
            bundleId: "ai.clawos.app"
        )

        do {
            _ = try await client.send(method: "push.apns.register", params: params)
            isRegisteredWithGateway = true
            registrationError = nil
        } catch {
            isRegisteredWithGateway = false
            registrationError = error
        }
    }

    // MARK: - Handle background wake

    /// Called when the app wakes from a background push. Attempts a reconnect if disconnected,
    /// then sends a presence alive event to update lastSeenAt on the gateway.
    func handleBackgroundWake(client: GatewayClient) async {
        // Send a lightweight presence event to satisfy gateway lastSeenAt tracking
        let params = NodeEventParams(event: "node.presence.alive")
        _ = try? await client.send(method: "node.event", params: params)
    }

    // MARK: - Schedule local notification

    /// Schedules an immediate local notification banner. Used when a message arrives while backgrounded.
    func scheduleLocalNotification(title: String, body: String, sessionKey: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let key = sessionKey {
            content.userInfo = ["sessionKey": key]
        }

        // Immediate delivery: nil trigger fires right away
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                #if DEBUG
                print("[PushManager] Failed to schedule local notification: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Request param types

private struct APNSRegisterParams: Encodable {
    let token: String
    let environment: String
    let bundleId: String
}

private struct NodeEventParams: Encodable {
    let event: String
}
