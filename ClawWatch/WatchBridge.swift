import WatchConnectivity
import WatchKit
import SwiftUI

// WatchBridge: handles WCSession communication between iPhone and Watch.
// Receives all message types from PhoneWatchBridge (iPhone-side) and
// maintains observable state for the Watch UI.
@Observable
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    // MARK: - Observable state

    private(set) var pendingApprovals:  [WatchApprovalRequest] = []
    private(set) var recentAlerts:      [WatchAlert] = []
    private(set) var deploymentEvents:  [WatchDeploymentItem] = []
    private(set) var incidents:         [WatchIncidentItem] = []
    private(set) var isConnected:       Bool = false
    private(set) var quickMetrics:      WatchMetrics = WatchMetrics()

    // MARK: - Models

    struct WatchApprovalRequest: Identifiable, Codable {
        let id: String
        let toolName: String
        let description: String
        let riskLevel: String    // "info" | "caution" | "danger" | "critical"
        let environment: String
        let timestamp: Date

        var riskColor: Color {
            switch riskLevel {
            case "critical": return .red
            case "danger":   return .orange
            case "caution":  return .yellow
            default:         return .green
            }
        }
    }

    struct WatchAlert: Identifiable, Codable {
        let id: String
        let title: String
        let body: String
        let severity: String     // "info" | "warning" | "critical"
        let timestamp: Date

        var severityColor: Color {
            switch severity {
            case "critical": return .red
            case "warning":  return .yellow
            default:         return .green
            }
        }
    }

    struct WatchMetrics: Codable {
        var activeSessions:   Int = 0
        var runningAgents:    Int = 0
        var pendingApprovals: Int = 0
        var lastUpdate:       Date = Date()
    }

    struct WatchDeploymentItem: Identifiable, Codable {
        let id: String
        let service: String
        let version: String
        let environment: String
        let status: String       // "started" | "succeeded" | "failed" | "rolled_back"
        let timestamp: Date
        let rollbackAvailable: Bool

        var statusColor: Color {
            switch status {
            case "succeeded": return .green
            case "failed":    return .red
            case "rolled_back": return .orange
            default: return .yellow
            }
        }

        var statusIcon: String {
            switch status {
            case "succeeded":   return "checkmark.circle.fill"
            case "failed":      return "xmark.circle.fill"
            case "rolled_back": return "arrow.uturn.backward.circle.fill"
            default:            return "arrow.up.circle.fill"
            }
        }
    }

    struct WatchIncidentItem: Identifiable, Codable {
        let id: String
        let title: String
        let severity: String     // "info" | "warning" | "critical"
        let environment: String
        let affectedServices: [String]
        let summary: String
        let startedAt: Date
        var resolvedAt: Date?
        let actionRequired: Bool

        var isOngoing: Bool { resolvedAt == nil }

        var severityColor: Color {
            switch severity {
            case "critical": return .red
            case "warning":  return .yellow
            default:         return .green
            }
        }
    }

    // MARK: - Init

    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Actions

    func sendApproval(id: String, approved: Bool) {
        guard WCSession.default.isReachable else {
            // Try transferUserInfo as fallback
            WCSession.default.transferUserInfo([
                "type": "approval_response", "id": id, "approved": approved
            ])
            pendingApprovals.removeAll { $0.id == id }
            return
        }
        WCSession.default.sendMessage(
            ["type": "approval_response", "id": id, "approved": approved],
            replyHandler: nil,
            errorHandler: { error in
                #if DEBUG
                print("WatchBridge: sendApproval error: \(error)")
                #endif
            }
        )
        pendingApprovals.removeAll { $0.id == id }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in isConnected = activationState == .activated }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in handleIncomingMessage(message) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in handleIncomingMessage(userInfo) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in handleIncomingMessage(applicationContext) }
    }

    // MARK: - Message routing

    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "approval_request":
            handleApprovalRequest(message)

        case "approval_resolved":
            if let id = message["id"] as? String {
                pendingApprovals.removeAll { $0.id == id }
            }

        case "alert":
            handleAlert(message)

        case "metrics":
            handleMetrics(message)

        case "deployment":
            handleDeployment(message)

        case "incident":
            handleIncident(message)

        default:
            break
        }
    }

    private func handleApprovalRequest(_ message: [String: Any]) {
        let id          = message["id"]          as? String ?? UUID().uuidString
        let toolName    = message["toolName"]    as? String ?? "Unknown"
        let description = message["description"] as? String ?? ""
        let riskLevel   = message["riskLevel"]   as? String ?? "caution"
        let environment = message["environment"] as? String ?? "unknown"
        let timestamp   = ISO8601DateFormatter().date(from: message["timestamp"] as? String ?? "") ?? Date()

        let request = WatchApprovalRequest(
            id: id,
            toolName: toolName,
            description: description,
            riskLevel: riskLevel,
            environment: environment,
            timestamp: timestamp
        )

        // Avoid duplicates
        guard !pendingApprovals.contains(where: { $0.id == id }) else { return }
        pendingApprovals.append(request)

        let haptic: WKHapticType = riskLevel == "critical" ? .directionUp : .notification
        WKInterfaceDevice.current().play(haptic)
    }

    private func handleAlert(_ message: [String: Any]) {
        let id        = message["id"]        as? String ?? UUID().uuidString
        let title     = message["title"]     as? String ?? "Alert"
        let body      = message["body"]      as? String ?? ""
        let severity  = message["severity"]  as? String ?? "info"
        let timestamp = ISO8601DateFormatter().date(from: message["timestamp"] as? String ?? "") ?? Date()

        let alert = WatchAlert(id: id, title: title, body: body, severity: severity, timestamp: timestamp)

        if !recentAlerts.contains(where: { $0.id == id }) {
            recentAlerts.insert(alert, at: 0)
            if recentAlerts.count > 30 { recentAlerts.removeLast() }
        }

        let haptic: WKHapticType = severity == "critical" ? .failure : .notification
        WKInterfaceDevice.current().play(haptic)
    }

    private func handleMetrics(_ message: [String: Any]) {
        let activeSessions   = message["activeSessions"]   as? Int ?? 0
        let runningAgents    = message["runningAgents"]    as? Int ?? 0
        let pendingApprovals = message["pendingApprovals"] as? Int ?? 0
        let lastUpdate = ISO8601DateFormatter().date(from: message["lastUpdate"] as? String ?? "") ?? Date()

        quickMetrics = WatchMetrics(
            activeSessions: activeSessions,
            runningAgents: runningAgents,
            pendingApprovals: pendingApprovals,
            lastUpdate: lastUpdate
        )
    }

    private func handleDeployment(_ message: [String: Any]) {
        guard let base64 = message["eventData"] as? String,
              let data = Data(base64Encoded: base64),
              let event = try? JSONDecoder().decode(WatchDeploymentItem.self, from: data)
        else { return }

        if !deploymentEvents.contains(where: { $0.id == event.id }) {
            deploymentEvents.insert(event, at: 0)
            if deploymentEvents.count > 20 { deploymentEvents.removeLast() }
        }

        let haptic: WKHapticType = event.status == "failed" ? .failure : .success
        WKInterfaceDevice.current().play(haptic)
    }

    private func handleIncident(_ message: [String: Any]) {
        guard let base64 = message["incidentData"] as? String,
              let data = Data(base64Encoded: base64),
              let incident = try? JSONDecoder().decode(WatchIncidentItem.self, from: data)
        else { return }

        if let idx = incidents.firstIndex(where: { $0.id == incident.id }) {
            incidents[idx] = incident
        } else {
            incidents.insert(incident, at: 0)
            if incidents.count > 10 { incidents.removeLast() }
        }

        if incident.actionRequired || incident.isOngoing {
            WKInterfaceDevice.current().play(incident.severity == "critical" ? .directionUp : .notification)
        }
    }
}
