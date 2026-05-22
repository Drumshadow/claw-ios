import Foundation

// MARK: - ToolApprovalRequest

struct ToolApprovalRequest: Identifiable {
    let id: String         // approvalId from gateway payload
    let sessionKey: String
    let toolName: String
    let toolInput: [String: JSONValue]
    let nodeId: String?
    let isDestructive: Bool
    let environment: String

    // Evaluated by PolicyEngine when request arrives
    let matchedPolicy: ApprovalPolicy?
    let riskLevel: RiskLevel

    // Associated rollback snapshot (registered on creation when risk >= .danger)
    let snapshotId: UUID?
}

// MARK: - ToolApprovalStore

/// Listens for tool.approval_required events and manages pending approvals.
/// Integrates with PolicyStore for risk evaluation, RollbackSnapshotStore
/// for pre-execution checkpoints, and WatchConnectivity via PhoneWatchBridge.
@Observable
@MainActor
final class ToolApprovalStore {

    // MARK: - Observable state

    private(set) var pendingApprovals: [ToolApprovalRequest] = []

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    /// Keychain key for the always-allow list.
    /// Stored in Keychain (not UserDefaults) because this list controls which tool
    /// invocations bypass the user approval prompt. An attacker with UserDefaults write
    /// access could otherwise pre-allow destructive tools without user interaction.
    private static let alwaysAllowKeychainKey = "claw.toolAlwaysAllow"

    /// Cached always-allow set. Avoids a Keychain read + JSON decode on every
    /// incoming approval event. Invalidated on any mutation.
    private var alwaysAllowCache: Set<String>?

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
        startEventSubscription()
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Approve / Deny

    func approve(id: String) {
        // Mark any associated snapshot as executed
        if let approval = pendingApprovals.first(where: { $0.id == id }),
           let snapshotId = approval.snapshotId {
            RollbackSnapshotStore.shared.markExecuted(id)
            _ = snapshotId // referenced to avoid warning — snapshot tracking by approvalId
        }
        pendingApprovals.removeAll { $0.id == id }
        Task {
            struct ApproveParams: Encodable { let approvalId: String }
            _ = try? await client.send(method: GatewayMethod.toolsApprove, params: ApproveParams(approvalId: id))
        }
    }

    func deny(id: String) {
        pendingApprovals.removeAll { $0.id == id }
        Task {
            struct DenyParams: Encodable { let approvalId: String }
            _ = try? await client.send(method: GatewayMethod.toolsDeny, params: DenyParams(approvalId: id))
        }
    }

    // MARK: - Rollback

    func rollback(approvalId: String) {
        guard let approval = pendingApprovals.first(where: { $0.id == approvalId }) ??
              nil else { return }
        // Find the snapshot for this approval
        let snapshot = RollbackSnapshotStore.shared.snapshots.first { $0.approvalId == approvalId }
        guard let snapshot else { return }
        RollbackSnapshotStore.shared.requestRollback(snapshot, client: client)
    }

    // MARK: - Always Allow

    func alwaysAllow(toolName: String) {
        var set = ensureAlwaysAllowCache()
        guard !set.contains(toolName) else { return }
        set.insert(toolName)
        saveAlwaysAllowList(set)
    }

    func revokeAlwaysAllow(toolName: String) {
        var set = ensureAlwaysAllowCache()
        guard set.remove(toolName) != nil else { return }
        saveAlwaysAllowList(set)
    }

    func isAlwaysAllowed(_ toolName: String) -> Bool {
        ensureAlwaysAllowCache().contains(toolName)
    }

    var alwaysAllowedTools: [String] {
        Array(ensureAlwaysAllowCache()).sorted()
    }

    // MARK: - Private: Keychain-backed always-allow persistence

    /// Returns the cached always-allow set, populating it from Keychain on first access.
    private func ensureAlwaysAllowCache() -> Set<String> {
        if let cache = alwaysAllowCache { return cache }
        let list: [String]
        if let data = try? KeychainStore.load(key: Self.alwaysAllowKeychainKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            list = decoded
        } else {
            list = []
        }
        let set = Set(list)
        alwaysAllowCache = set
        return set
    }

    private func saveAlwaysAllowList(_ set: Set<String>) {
        alwaysAllowCache = set
        guard let data = try? JSONEncoder().encode(Array(set)) else { return }
        try? KeychainStore.save(key: Self.alwaysAllowKeychainKey, data: data)
    }

    // MARK: - Private: event subscription

    private func startEventSubscription() {
        eventTask = Task { [weak self, client] in
            for await event in await client.events() {
                guard let self else { return }
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {
        case "tool.approval_required":
            handleApprovalRequired(event.payload)

        case GatewayEventName.snapshotCaptured:
            handleSnapshotCaptured(event.payload)

        case GatewayEventName.rollbackCompleted:
            handleRollbackCompleted(event.payload)

        default:
            break
        }
    }

    private func handleApprovalRequired(_ payload: [String: JSONValue]) {
        guard let idVal  = payload["approvalId"], case .string(let approvalId) = idVal, !approvalId.isEmpty,
              let skVal  = payload["sessionKey"],  case .string(let sessionKey) = skVal,
              let tnVal  = payload["toolName"],    case .string(let toolName) = tnVal
        else { return }

        let toolInput: [String: JSONValue]
        if let inputVal = payload["toolInput"], case .object(let obj) = inputVal {
            toolInput = obj
        } else {
            toolInput = [:]
        }

        let nodeId: String?
        if let nidVal = payload["nodeId"], case .string(let nid) = nidVal, !nid.isEmpty {
            nodeId = nid
        } else {
            nodeId = nil
        }

        let isDestructive: Bool
        if let dVal = payload["isDestructive"], case .bool(let d) = dVal {
            isDestructive = d
        } else {
            isDestructive = false
        }

        let environment: String
        if let envVal = payload["environment"], case .string(let env) = envVal, !env.isEmpty {
            environment = env
        } else {
            environment = "unknown"
        }

        // Auto-approve if tool is in always-allow list
        if isAlwaysAllowed(toolName) {
            Task {
                struct ApproveParams: Encodable { let approvalId: String }
                _ = try? await client.send(method: GatewayMethod.toolsApprove, params: ApproveParams(approvalId: approvalId))
            }
            return
        }

        // Evaluate via PolicyEngine
        let engine = PolicyStore.shared.engine
        let (matchedPolicy, riskLevel) = engine.evaluate(tool: toolName, environment: environment)

        // Auto-approve if policy says so (and not destructive override)
        if let policy = matchedPolicy, policy.autoApprove, !isDestructive {
            Task {
                struct ApproveParams: Encodable { let approvalId: String }
                _ = try? await client.send(method: GatewayMethod.toolsApprove, params: ApproveParams(approvalId: approvalId))
            }
            return
        }

        // Register rollback snapshot for danger/critical operations
        var snapshotId: UUID? = nil
        if riskLevel >= .danger {
            let inputSummary = toolInput.prefix(3).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            let snapshot = RollbackSnapshotStore.shared.register(
                approvalId: approvalId,
                sessionKey: sessionKey,
                toolName: toolName,
                toolInputSummary: inputSummary,
                environment: environment,
                ttlSeconds: matchedPolicy.flatMap { $0.timeoutSeconds > 0 ? $0.timeoutSeconds * 10 : nil } ?? 3600
            )
            snapshotId = snapshot.id
        }

        let request = ToolApprovalRequest(
            id: approvalId,
            sessionKey: sessionKey,
            toolName: toolName,
            toolInput: toolInput,
            nodeId: nodeId,
            isDestructive: isDestructive,
            environment: environment,
            matchedPolicy: matchedPolicy,
            riskLevel: riskLevel,
            snapshotId: snapshotId
        )
        pendingApprovals.append(request)

        // Push to Watch
        PhoneWatchBridge.shared.sendApprovalRequest(request)
    }

    private func handleSnapshotCaptured(_ payload: [String: JSONValue]) {
        guard let approvalId = payload["approvalId"]?.stringValue,
              let serverRef  = payload["snapshotRef"]?.stringValue
        else { return }

        let resources = payload["resources"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let impact    = payload["impactSummary"]?.stringValue

        // Find our local snapshot record
        if let snapshot = RollbackSnapshotStore.shared.snapshots.first(where: { $0.approvalId == approvalId }) {
            RollbackSnapshotStore.shared.markCaptured(snapshot.id, serverRef: serverRef, resources: resources, impact: impact)
        }
    }

    private func handleRollbackCompleted(_ payload: [String: JSONValue]) {
        guard let approvalId = payload["approvalId"]?.stringValue else { return }
        let notes = payload["notes"]?.stringValue
        if let snapshot = RollbackSnapshotStore.shared.snapshots.first(where: { $0.approvalId == approvalId }) {
            RollbackSnapshotStore.shared.markRolledBack(snapshot.id, notes: notes)
        }
    }
}
