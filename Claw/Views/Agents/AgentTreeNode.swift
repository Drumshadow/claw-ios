import Foundation

// Represents one node in the agent relationship tree
struct AgentTreeNode: Identifiable {
    let id: String          // session ID
    let title: String
    let agentType: String?  // "main", "claude", etc.
    let status: AgentNodeStatus
    let depth: Int          // 0 = root, 1 = child, 2 = grandchild
    let children: [AgentTreeNode]
    let startedAt: Date?
    let tokenCount: Int?
    let model: String?

    enum AgentNodeStatus {
        case idle, running, thinking, completed, failed

        var color: String {
            switch self {
            case .idle: return "838387"
            case .running: return "22c55e"
            case .thinking: return "14b8a6"
            case .completed: return "3b82f6"
            case .failed: return "ef4444"
            }
        }

        var systemImage: String {
            switch self {
            case .idle: return "circle"
            case .running: return "cpu"
            case .thinking: return "brain"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        // Map from ClawSession.AgentStatus
        static func from(_ agentStatus: AgentStatus, hasMessages: Bool) -> AgentNodeStatus {
            switch agentStatus {
            case .idle:
                return hasMessages ? .completed : .idle
            case .thinking:
                return .thinking
            case .running:
                return .running
            }
        }
    }

    // Build a tree from flat session list using childSessionKeys
    static func buildTree(from sessions: [ClawSession], rootId: String) -> AgentTreeNode? {
        // Create a lookup dictionary for fast access
        let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        guard let rootSession = sessionMap[rootId] else {
            return nil
        }

        // Track visited nodes to prevent cycles
        var visited = Set<String>()

        func buildNode(sessionId: String, currentDepth: Int) -> AgentTreeNode? {
            // Prevent cycles and limit depth
            guard currentDepth < 8 else { return nil }
            guard !visited.contains(sessionId) else { return nil }
            guard let session = sessionMap[sessionId] else { return nil }

            visited.insert(sessionId)

            // Determine status
            let hasMessages = session.lastMessage != nil && !(session.lastMessage?.isEmpty ?? true)
            let nodeStatus = AgentNodeStatus.from(session.agentStatus, hasMessages: hasMessages)

            // Recursively build children
            let childNodes = session.childSessionKeys.compactMap { childId in
                buildNode(sessionId: childId, currentDepth: currentDepth + 1)
            }

            return AgentTreeNode(
                id: session.id,
                title: session.title,
                agentType: extractAgentType(from: session.title),
                status: nodeStatus,
                depth: currentDepth,
                children: childNodes,
                startedAt: session.lastMessageAt,
                tokenCount: session.totalTokens,
                model: session.model
            )
        }

        return buildNode(sessionId: rootId, currentDepth: 0)
    }

    // Extract agent type from session title (e.g., "claude", "explore", "general-purpose")
    private static func extractAgentType(from title: String) -> String? {
        let lower = title.lowercased()
        if lower.contains("claude") { return "claude" }
        if lower.contains("explore") { return "explore" }
        if lower.contains("plan") { return "plan" }
        if lower.contains("general") { return "general-purpose" }
        return nil
    }

    // Flatten the tree into a list for stats/search
    func flatten() -> [AgentTreeNode] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.flatten())
        }
        return result
    }
}
