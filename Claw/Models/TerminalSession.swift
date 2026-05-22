import Foundation

// MARK: - TerminalSessionStatus

enum TerminalSessionStatus: String, Codable, Equatable, Hashable {
    case active     // live streaming output
    case idle       // connected, no recent output
    case ended      // process exited; history is available
    case error      // connection/process error

    var displayLabel: String {
        switch self {
        case .active: return "Live"
        case .idle:   return "Idle"
        case .ended:  return "Ended"
        case .error:  return "Error"
        }
    }

    var isLive: Bool { self == .active || self == .idle }
}

// MARK: - TerminalSession

/// Represents a terminal session managed by the gateway.
/// Maps to the `terminal.sessions.list` and `terminal.output` gateway contracts.
struct TerminalSession: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var title: String
    var nodeId: String?         // runner node hosting this session
    var nodeName: String?       // human-readable node label
    var status: TerminalSessionStatus
    var startedAt: Date
    var endedAt: Date?
    var exitCode: Int?
    var isReplay: Bool          // viewing archived history (not live)
    var pid: Int?               // process ID, if known

    // MARK: - Helpers

    var duration: TimeInterval? {
        guard let end = endedAt else {
            guard status.isLive else { return nil }
            return Date().timeIntervalSince(startedAt)
        }
        return end.timeIntervalSince(startedAt)
    }

    var formattedDuration: String? {
        guard let d = duration else { return nil }
        let mins = Int(d) / 60
        let secs = Int(d) % 60
        if mins > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }
}

// MARK: - TerminalSessionPayload (gateway wire type)

/// Raw payload decoded from gateway responses/events for terminal sessions.
struct TerminalSessionPayload: Codable {
    let id: String
    let title: String
    let nodeId: String?
    let nodeName: String?
    let status: String
    let startedAt: Double      // Unix timestamp
    let endedAt: Double?
    let exitCode: Int?
    let pid: Int?

    func toTerminalSession() -> TerminalSession {
        TerminalSession(
            id: id,
            title: title,
            nodeId: nodeId,
            nodeName: nodeName,
            status: TerminalSessionStatus(rawValue: status) ?? .idle,
            startedAt: Date(timeIntervalSince1970: startedAt),
            endedAt: endedAt.map { Date(timeIntervalSince1970: $0) },
            exitCode: exitCode,
            isReplay: (TerminalSessionStatus(rawValue: status) ?? .idle) == .ended,
            pid: pid
        )
    }
}

// MARK: - TerminalHistoryLinePayload (gateway wire type)

/// A single historical terminal line from `terminal.session.history`.
struct TerminalHistoryLinePayload: Codable {
    let data: String
    let timestamp: Double   // Unix timestamp

    var date: Date { Date(timeIntervalSince1970: timestamp) }
}

// MARK: - Sample data for previews

extension TerminalSession {
    static let sampleSessions: [TerminalSession] = [
        TerminalSession(
            id: "ts-001",
            title: "Deploy Pipeline",
            nodeId: "node-prod",
            nodeName: "prod-runner",
            status: .active,
            startedAt: Date().addingTimeInterval(-62),
            endedAt: nil,
            exitCode: nil,
            isReplay: false,
            pid: 14823
        ),
        TerminalSession(
            id: "ts-002",
            title: "Health Check — api.openclaw.dev",
            nodeId: "node-prod",
            nodeName: "prod-runner",
            status: .idle,
            startedAt: Date().addingTimeInterval(-320),
            endedAt: nil,
            exitCode: nil,
            isReplay: false,
            pid: 14800
        ),
        TerminalSession(
            id: "ts-003",
            title: "npm run build",
            nodeId: "node-staging",
            nodeName: "staging-runner",
            status: .ended,
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date().addingTimeInterval(-1680),
            exitCode: 0,
            isReplay: true,
            pid: nil
        ),
        TerminalSession(
            id: "ts-004",
            title: "Database Migration",
            nodeId: "node-prod",
            nodeName: "prod-runner",
            status: .error,
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date().addingTimeInterval(-895),
            exitCode: 1,
            isReplay: true,
            pid: nil
        ),
    ]
}
