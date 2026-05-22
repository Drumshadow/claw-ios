import Foundation

enum RiskLevel: String, Codable, Comparable, CaseIterable {
    case info      // green  - read operations, status checks
    case caution   // amber  - restarts, config changes
    case danger    // red    - deploys, data mutations
    case critical  // red+biometric - prod DB writes, deletions, destroy

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.info, .caution, .danger, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    var color: String {  // return hex string for use in SwiftUI Color(hex:)
        switch self {
        case .info: return "22c55e"
        case .caution: return "f59e0b"
        case .danger: return "ef4444"
        case .critical: return "ef4444"
        }
    }

    var requiresBiometric: Bool { self == .critical }
    var displayLabel: String { rawValue.capitalized }
}

struct ApprovalPolicy: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var environment: String     // "production", "staging", "dev", "*"
    var toolPattern: String     // glob: "docker restart *", "db.delete *", "*"
    var riskLevel: RiskLevel
    var autoApprove: Bool       // skip approval UI for this rule
    var requireBiometric: Bool  // force biometric even if riskLevel doesn't
    var timeoutSeconds: Int     // auto-deny after N seconds (0 = no timeout)
    var isEnabled: Bool

    // Returns true if this policy matches a given tool name + environment
    func matches(tool: String, environment: String) -> Bool {
        guard isEnabled else { return false }

        // Check environment match
        let envMatches = self.environment == "*" ||
                        self.environment.lowercased() == environment.lowercased()
        guard envMatches else { return false }

        // Convert glob pattern to regex
        let pattern = toolPattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")

        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: .caseInsensitive) else {
            return false
        }

        let range = NSRange(tool.startIndex..<tool.endIndex, in: tool)
        return regex.firstMatch(in: tool, range: range) != nil
    }
}

// Evaluates which policy applies to a given tool call
struct PolicyEngine {
    let policies: [ApprovalPolicy]

    // Returns the highest-risk matching policy, or a default .caution policy
    func evaluate(tool: String, environment: String) -> (policy: ApprovalPolicy?, risk: RiskLevel) {
        let matchingPolicies = policies.filter { $0.matches(tool: tool, environment: environment) }

        // Return highest risk policy
        if let highestRiskPolicy = matchingPolicies.max(by: { $0.riskLevel < $1.riskLevel }) {
            return (highestRiskPolicy, highestRiskPolicy.riskLevel)
        }

        // No policy matched - use heuristics
        let inferredRisk = PolicyEngine.inferRisk(from: tool)
        return (nil, inferredRisk)
    }

    // Built-in heuristics when no policy matches:
    // - "db.delete", "drop", "truncate" → .critical
    // - "deploy", "push", "rollback" → .danger
    // - "restart", "stop", "config" → .caution
    // - "read", "list", "get", "status" → .info
    static func inferRisk(from toolName: String) -> RiskLevel {
        let lowercased = toolName.lowercased()

        // Critical operations
        if lowercased.contains("delete") ||
           lowercased.contains("drop") ||
           lowercased.contains("truncate") ||
           lowercased.contains("destroy") ||
           lowercased.contains("remove") ||
           lowercased.contains("db.") && (lowercased.contains("write") || lowercased.contains("update")) {
            return .critical
        }

        // Danger operations
        if lowercased.contains("deploy") ||
           lowercased.contains("push") ||
           lowercased.contains("rollback") ||
           lowercased.contains("migrate") ||
           lowercased.contains("write") ||
           lowercased.contains("update") ||
           lowercased.contains("create") {
            return .danger
        }

        // Caution operations
        if lowercased.contains("restart") ||
           lowercased.contains("stop") ||
           lowercased.contains("start") ||
           lowercased.contains("config") ||
           lowercased.contains("set") ||
           lowercased.contains("modify") {
            return .caution
        }

        // Info operations (safe reads)
        if lowercased.contains("read") ||
           lowercased.contains("list") ||
           lowercased.contains("get") ||
           lowercased.contains("status") ||
           lowercased.contains("show") ||
           lowercased.contains("view") ||
           lowercased.contains("fetch") ||
           lowercased.contains("query") {
            return .info
        }

        // Default to caution for unknown operations
        return .caution
    }
}
