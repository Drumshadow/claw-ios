import WatchConnectivity
import WatchKit
import Foundation

// WatchBridge: handles WCSession communication between iPhone and Watch
@Observable
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private(set) var pendingApprovals: [WatchApprovalRequest] = []
    private(set) var recentAlerts: [WatchAlert] = []
    private(set) var isConnected: Bool = false
    private(set) var quickMetrics: WatchMetrics = WatchMetrics()

    struct WatchApprovalRequest: Identifiable, Codable {
        let id: String
        let toolName: String
        let description: String
        let riskLevel: String    // "info" | "caution" | "danger" | "critical"
        let timestamp: Date
    }

    struct WatchAlert: Identifiable, Codable {
        let id: String
        let title: String
        let body: String
        let severity: String     // "info" | "warning" | "critical"
        let timestamp: Date
    }

    struct WatchMetrics: Codable {
        var activeSessions: Int = 0
        var runningAgents: Int = 0
        var pendingApprovals: Int = 0
        var lastUpdate: Date = Date()
    }

    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendApproval(id: String, approved: Bool) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["type": "approval_response", "id": id, "approved": approved],
            replyHandler: nil
        )
        pendingApprovals.removeAll { $0.id == id }
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in isConnected = activationState == .activated }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in handleIncomingMessage(message) }
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "approval_request":
            if let data = try? JSONSerialization.data(withJSONObject: message),
               let request = try? JSONDecoder().decode(WatchApprovalRequest.self, from: data) {
                pendingApprovals.append(request)
                WKInterfaceDevice.current().play(.notification)
            }
        case "alert":
            if let data = try? JSONSerialization.data(withJSONObject: message),
               let alert = try? JSONDecoder().decode(WatchAlert.self, from: data) {
                recentAlerts.insert(alert, at: 0)
                if recentAlerts.count > 20 { recentAlerts.removeLast() }
            }
        case "metrics":
            if let data = try? JSONSerialization.data(withJSONObject: message),
               let metrics = try? JSONDecoder().decode(WatchMetrics.self, from: data) {
                quickMetrics = metrics
            }
        default: break
        }
    }
}
