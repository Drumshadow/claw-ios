import Foundation

// MARK: - CommandSimulation result

struct CommandSimulation {
    let toolName: String
    let input: [String: JSONValue]
    let environment: String

    // What would happen
    var simulatedOutput: String
    var wouldModify: [String]          // Resources that would be modified
    var estimatedDuration: String?
    var riskAssessment: String
    var riskLevel: RiskLevel
    var requiresSnapshot: Bool

    // Diff representation for mutations
    var diffLines: [DiffLine]

    struct DiffLine: Identifiable {
        enum Kind { case added, removed, context }
        let id: UUID = UUID()
        let kind: Kind
        let content: String
    }
}

// MARK: - CommandSimulatorError

enum CommandSimulatorError: Error, LocalizedError {
    case toolNotSupported(String)
    case gatewayUnavailable
    case simulationFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotSupported(let name): return "Simulation not supported for \(name)"
        case .gatewayUnavailable:         return "Gateway unavailable for simulation"
        case .simulationFailed(let msg):  return "Simulation failed: \(msg)"
        }
    }
}

// MARK: - CommandSimulator
//
// Sends a dry-run / simulation request to the gateway and returns a
// structured CommandSimulation result.
//
// Gateway contract (expected):
//   method: tools.simulate
//   params: { toolName: String, toolInput: JSON, environment: String }
//   response: {
//     simulatedOutput: String,
//     wouldModify: [String],
//     estimatedDurationMs: Int?,
//     riskAssessment: String,
//     riskLevel: String,
//     requiresSnapshot: Bool,
//     diffLines: [{ kind: "added"|"removed"|"context", content: String }]
//   }
//
// Falls back to client-side heuristic simulation when gateway is unavailable.

struct CommandSimulator {

    let client: GatewayClient?

    // MARK: - Simulate

    func simulate(
        toolName: String,
        input: [String: JSONValue],
        environment: String
    ) async throws -> CommandSimulation {
        // If we have a gateway, prefer server-side simulation
        if let client {
            return try await remoteSimulate(toolName: toolName, input: input, environment: environment, client: client)
        }
        // Fall back to client-side heuristics
        return clientSimulate(toolName: toolName, input: input, environment: environment)
    }

    // MARK: - Remote simulation

    private func remoteSimulate(
        toolName: String,
        input: [String: JSONValue],
        environment: String,
        client: GatewayClient
    ) async throws -> CommandSimulation {
        struct SimulateParams: Encodable {
            let toolName: String
            let toolInput: JSONValue
            let environment: String
        }

        let inputValue = JSONValue.object(input)
        let params = SimulateParams(toolName: toolName, toolInput: inputValue, environment: environment)

        let response = try await client.send(method: GatewayMethod.toolsSimulate, params: params)

        let simulatedOutput   = response["simulatedOutput"]?.stringValue ?? "(no output)"
        let wouldModify       = response["wouldModify"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let riskAssessmentStr = response["riskAssessment"]?.stringValue ?? "Unable to assess risk."
        let riskLevelStr      = response["riskLevel"]?.stringValue ?? "caution"
        let riskLevel         = RiskLevel(rawValue: riskLevelStr) ?? PolicyEngine.inferRisk(from: toolName)
        let requiresSnapshot  = response["requiresSnapshot"]?.boolValue ?? (riskLevel >= .danger)

        let durationMs = response["estimatedDurationMs"]?.intValue
        let durationStr = durationMs.map { ms in
            ms < 1000 ? "\(ms)ms" : String(format: "~%.1fs", Double(ms) / 1000.0)
        }

        let rawDiff = response["diffLines"]?.arrayValue ?? []
        let diffLines: [CommandSimulation.DiffLine] = rawDiff.compactMap { item in
            guard let obj = item.objectValue,
                  let kindStr = obj["kind"]?.stringValue,
                  let content = obj["content"]?.stringValue else { return nil }
            let kind: CommandSimulation.DiffLine.Kind
            switch kindStr {
            case "added":   kind = .added
            case "removed": kind = .removed
            default:        kind = .context
            }
            return CommandSimulation.DiffLine(kind: kind, content: content)
        }

        return CommandSimulation(
            toolName: toolName,
            input: input,
            environment: environment,
            simulatedOutput: simulatedOutput,
            wouldModify: wouldModify,
            estimatedDuration: durationStr,
            riskAssessment: riskAssessmentStr,
            riskLevel: riskLevel,
            requiresSnapshot: requiresSnapshot,
            diffLines: diffLines
        )
    }

    // MARK: - Client-side heuristic simulation (offline fallback)

    private func clientSimulate(
        toolName: String,
        input: [String: JSONValue],
        environment: String
    ) -> CommandSimulation {
        let risk = PolicyEngine.inferRisk(from: toolName)
        let inputSummary = input.map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        let (description, modifies, output) = heuristicDescription(toolName: toolName, input: input, environment: environment)

        return CommandSimulation(
            toolName: toolName,
            input: input,
            environment: environment,
            simulatedOutput: output,
            wouldModify: modifies,
            estimatedDuration: nil,
            riskAssessment: description,
            riskLevel: risk,
            requiresSnapshot: risk >= .danger,
            diffLines: heuristicDiff(toolName: toolName, input: input)
        )
    }

    private func heuristicDescription(
        toolName: String,
        input: [String: JSONValue],
        environment: String
    ) -> (assessment: String, modifies: [String], output: String) {
        let lower = toolName.lowercased()

        if lower.contains("delete") || lower.contains("drop") || lower.contains("truncate") {
            let table = input["table"]?.stringValue ?? input["resource"]?.stringValue ?? "unknown"
            return (
                "This operation permanently removes data from \(table) in \(environment). " +
                "This cannot be undone without a snapshot rollback.",
                ["\(environment)/\(table) (DELETE)"],
                "[DRY RUN] Would delete records from \(table). Snapshot recommended before proceeding."
            )
        }

        if lower.contains("deploy") || lower.contains("rollout") {
            let service = input["service"]?.stringValue ?? "service"
            let version = input["version"]?.stringValue ?? "unknown"
            return (
                "Deploys \(service) to version \(version) in \(environment). " +
                "Current version will be replaced. Rollback available if snapshot is captured.",
                ["\(environment)/\(service) (DEPLOY \(version))"],
                "[DRY RUN] Would deploy \(service):\(version) to \(environment)."
            )
        }

        if lower.contains("migrate") {
            return (
                "Runs database migration in \(environment). " +
                "Schema changes may be irreversible.",
                ["\(environment)/database (MIGRATE)"],
                "[DRY RUN] Would run migration. Review SQL statements before proceeding."
            )
        }

        if lower.contains("restart") || lower.contains("stop") {
            let service = input["service"]?.stringValue ?? input["container"]?.stringValue ?? "service"
            return (
                "Restarts \(service) in \(environment). " +
                "Brief downtime expected.",
                ["\(environment)/\(service) (RESTART)"],
                "[DRY RUN] Would restart \(service). Brief downtime of ~5-30s."
            )
        }

        return (
            "Simulated (offline). Review parameters carefully before approving.",
            [],
            "[DRY RUN] (offline simulation) \(toolName) would execute with: \(input.keys.joined(separator: ", "))"
        )
    }

    private func heuristicDiff(
        toolName: String,
        input: [String: JSONValue]
    ) -> [CommandSimulation.DiffLine] {
        let lower = toolName.lowercased()
        guard lower.contains("config") || lower.contains("patch") || lower.contains("update") else {
            return []
        }
        // For config/patch operations, show a synthetic diff of the input params
        var lines: [CommandSimulation.DiffLine] = []
        for (key, value) in input.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(kind: .removed, content: "- \(key): <current>"))
            lines.append(.init(kind: .added,   content: "+ \(key): \(value)"))
        }
        return lines
    }
}
