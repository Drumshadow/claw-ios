import Foundation

// MARK: - ToolApprovalRequest

struct ToolApprovalRequest: Identifiable {
    let id: String         // approvalId from gateway payload
    let sessionKey: String
    let toolName: String
    let toolInput: [String: JSONValue]
    let nodeId: String?
    let isDestructive: Bool
}

// MARK: - ToolApprovalStore

/// Listens for tool.approval_required events and manages pending approvals.
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
        guard event.name == "tool.approval_required" else { return }
        let payload = event.payload

        guard let idVal = payload["approvalId"], case .string(let approvalId) = idVal, !approvalId.isEmpty,
              let skVal = payload["sessionKey"], case .string(let sessionKey) = skVal,
              let tnVal = payload["toolName"], case .string(let toolName) = tnVal
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

        // Auto-approve if tool is in always-allow list
        if isAlwaysAllowed(toolName) {
            Task {
                struct ApproveParams: Encodable { let approvalId: String }
                _ = try? await client.send(method: GatewayMethod.toolsApprove, params: ApproveParams(approvalId: approvalId))
            }
            return
        }

        let request = ToolApprovalRequest(
            id: approvalId,
            sessionKey: sessionKey,
            toolName: toolName,
            toolInput: toolInput,
            nodeId: nodeId,
            isDestructive: isDestructive
        )
        pendingApprovals.append(request)
    }
}
