import WatchConnectivity
import Foundation

// MARK: - PhoneWatchBridge
//
// iPhone-side WatchConnectivity manager.
// Pushes approval requests, metrics updates, alerts, and deployment
// events to the companion Apple Watch app via WCSession.
//
// Use PhoneWatchBridge.shared to access the singleton.
// Call PhoneWatchBridge.activate() once at app startup (e.g. in AppDelegate).

@Observable
@MainActor
final class PhoneWatchBridge: NSObject {

    static let shared = PhoneWatchBridge()

    // MARK: - Observable state

    private(set) var isWatchReachable: Bool = false
    private(set) var isWatchPaired:    Bool = false
    private(set) var isWatchAppInstalled: Bool = false
    private(set) var lastSyncDate: Date? = nil

    // MARK: - Queued messages (sent when Watch reconnects)

    private var queuedApprovals: [ToolApprovalRequest] = []

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Activation

    /// Call once at app launch — safe to call multiple times.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
    }

    // MARK: - Send to Watch

    /// Push a pending approval to the Watch.
    func sendApprovalRequest(_ approval: ToolApprovalRequest) {
        let payload: [String: Any] = [
            "type":        "approval_request",
            "id":          approval.id,
            "toolName":    approval.toolName,
            "description": formatInputSummary(approval.toolInput),
            "riskLevel":   approval.riskLevel.rawValue,
            "environment": approval.environment,
            "timestamp":   ISO8601DateFormatter().string(from: Date())
        ]
        sendMessage(payload) { [weak self] in
            self?.queuedApprovals.append(approval)
        }
    }

    /// Push an alert (incident, error, warning) to the Watch.
    func sendAlert(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        severity: WatchAlertSeverity
    ) {
        let payload: [String: Any] = [
            "type":      "alert",
            "id":        id,
            "title":     title,
            "body":      body,
            "severity":  severity.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendMessage(payload)
    }

    /// Push a metrics snapshot to the Watch.
    func sendMetrics(activeSessions: Int, runningAgents: Int, pendingApprovals: Int) {
        let payload: [String: Any] = [
            "type":             "metrics",
            "activeSessions":   activeSessions,
            "runningAgents":    runningAgents,
            "pendingApprovals": pendingApprovals,
            "lastUpdate":       ISO8601DateFormatter().string(from: Date())
        ]
        // Use updateApplicationContext for metrics — it's best-effort and merges with last state.
        updateContext(payload)
    }

    /// Push a deployment event to the Watch.
    func sendDeploymentEvent(_ event: WatchDeploymentEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        let payload: [String: Any] = [
            "type":           "deployment",
            "eventData":      data.base64EncodedString(),
            "timestamp":      ISO8601DateFormatter().string(from: Date())
        ]
        sendMessage(payload)
    }

    /// Push an incident summary to the Watch.
    func sendIncidentSummary(_ incident: WatchIncidentSummary) {
        guard let data = try? JSONEncoder().encode(incident) else { return }
        let payload: [String: Any] = [
            "type":       "incident",
            "incidentData": data.base64EncodedString(),
            "timestamp":  ISO8601DateFormatter().string(from: Date())
        ]
        sendMessage(payload)
    }

    /// Notify Watch that an approval was resolved (to dismiss the prompt).
    func sendApprovalResolved(id: String, approved: Bool) {
        let payload: [String: Any] = [
            "type":     "approval_resolved",
            "id":       id,
            "approved": approved,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendMessage(payload)
        queuedApprovals.removeAll { $0.id == id }
    }

    // MARK: - Private: WCSession send helpers

    private func sendMessage(_ payload: [String: Any], onFail: (() -> Void)? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        guard session.activationState == .activated else {
            onFail?()
            return
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] _ in
                Task { @MainActor in self?.lastSyncDate = Date() }
            }, errorHandler: { [weak self] error in
                #if DEBUG
                print("PhoneWatchBridge: sendMessage error: \(error)")
                #endif
                onFail?()
                _ = self
            })
        } else {
            // Transfer via user info — guaranteed delivery, FIFO
            session.transferUserInfo(payload)
            Task { @MainActor in lastSyncDate = Date() }
        }
    }

    private func updateContext(_ payload: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(payload)
        Task { @MainActor in lastSyncDate = Date() }
    }

    // MARK: - Private: utilities

    private func formatInputSummary(_ input: [String: JSONValue]) -> String {
        input.prefix(3)
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }
}

// MARK: - WCSessionDelegate

extension PhoneWatchBridge: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isWatchPaired       = session.isPaired
            isWatchAppInstalled = session.isWatchAppInstalled
            isWatchReachable    = session.isReachable
            if activationState == .activated {
                flushQueuedApprovals()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
            if session.isReachable { flushQueuedApprovals() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in isWatchReachable = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS — reactivate to pick up watch pairing changes
        WCSession.default.activate()
    }

    // Handle messages from Watch (e.g. approval responses)
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in handleWatchMessage(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in handleWatchMessage(userInfo) }
    }

    @MainActor
    private func handleWatchMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "approval_response":
            guard let id = message["id"] as? String,
                  let approved = message["approved"] as? Bool else { return }
            // Post notification for ToolApprovalStore to pick up
            NotificationCenter.default.post(
                name: .watchApprovalResponse,
                object: nil,
                userInfo: ["approvalId": id, "approved": approved]
            )

        default:
            break
        }
    }

    @MainActor
    private func flushQueuedApprovals() {
        guard !queuedApprovals.isEmpty else { return }
        let toFlush = queuedApprovals
        queuedApprovals.removeAll()
        for approval in toFlush {
            sendApprovalRequest(approval)
        }
    }
}

// MARK: - Watch data models (shared message contracts)

enum WatchAlertSeverity: String, Codable {
    case info     = "info"
    case warning  = "warning"
    case critical = "critical"
}

struct WatchDeploymentEvent: Codable, Identifiable {
    var id: String = UUID().uuidString
    let service: String
    let version: String
    let environment: String
    let status: DeploymentStatus
    let initiatedBy: String?
    let timestamp: Date
    let durationSeconds: Int?
    let rollbackAvailable: Bool

    enum DeploymentStatus: String, Codable {
        case started    = "started"
        case succeeded  = "succeeded"
        case failed     = "failed"
        case rolledBack = "rolled_back"

        var displayLabel: String {
            switch self {
            case .started:    return "Deploying"
            case .succeeded:  return "Deployed"
            case .failed:     return "Failed"
            case .rolledBack: return "Rolled Back"
            }
        }
    }
}

struct WatchIncidentSummary: Codable, Identifiable {
    var id: String = UUID().uuidString
    let title: String
    let severity: WatchAlertSeverity
    let environment: String
    let affectedServices: [String]
    let summary: String
    let startedAt: Date
    var resolvedAt: Date?
    let impactDescription: String?
    let actionRequired: Bool

    var isOngoing: Bool { resolvedAt == nil }

    var durationDescription: String {
        let end = resolvedAt ?? Date()
        let delta = end.timeIntervalSince(startedAt)
        if delta < 60  { return "\(Int(delta))s" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        return "\(Int(delta / 3600))h \(Int((delta.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let watchApprovalResponse = Notification.Name("ai.clawos.watchApprovalResponse")
}
