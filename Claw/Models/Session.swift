import Foundation

// MARK: - ClawSession

struct ClawSession: Identifiable, Hashable, Codable {
    let id: String           // session key from gateway
    var title: String
    var lastMessage: String?
    var lastMessageAt: Date?
    var agentStatus: AgentStatus
    var unreadCount: Int
    var model: String?
    var totalTokens: Int?
    var estimatedCostUsd: Double?
    var childSessionKeys: [String] = []
    var isPinned: Bool = false

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClawSession, rhs: ClawSession) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AgentStatus

enum AgentStatus: String, Codable {
    case idle
    case thinking
    case running

    /// Display text shown in the UI.
    var displayText: String? {
        switch self {
        case .idle: return nil
        case .thinking: return "Thinking…"
        case .running: return "Running…"
        }
    }

    /// Color used for the status dot in session list rows.
    var dotColorName: String {
        switch self {
        case .idle: return "gray"
        case .thinking: return "yellow"
        case .running: return "green"
        }
    }

    init(rawString: String) {
        switch rawString.lowercased() {
        case "thinking": self = .thinking
        case "running": self = .running
        default: self = .idle
        }
    }
}
