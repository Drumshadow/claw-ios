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

    /// Observer token for Watch-originated approve/deny responses.
    nonisolated(unsafe) private var watchResponseObserver: NSObjectProtocol?

    /// Approval ids already resolved from any source (phone UI, Watch, auto-approve, or a
    /// gateway/other-client resolution). Guards against double-resolving the same approval —
    /// which mutates gateway state — on re-delivery or concurrent multi-client use.
    private var resolvedIds: Set<String> = []

    /// `exec.approval.resolve` decision strings understood by the gateway.
    private static let decisionAllowOnce = "allow-once"
    private static let decisionDeny = "deny"

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
        if AppReviewSampleData.isEnabled {
            loadAppReviewSampleData()
        } else {
            startEventSubscription()
            observeWatchResponses()
        }
    }

    deinit {
        eventTask?.cancel()
        if let watchResponseObserver {
            NotificationCenter.default.removeObserver(watchResponseObserver)
        }
    }

    // MARK: - Approve / Deny

    func approve(id: String) {
        if AppReviewSampleData.isEnabled {
            pendingApprovals.removeAll { $0.id == id }
            return
        }
        // Mark any associated snapshot as executed before clearing the request.
        if pendingApprovals.first(where: { $0.id == id })?.snapshotId != nil {
            RollbackSnapshotStore.shared.markExecuted(id)
        }
        pendingApprovals.removeAll { $0.id == id }
        resolveAndDismiss(id: id, decision: Self.decisionAllowOnce, approved: true)
    }

    func deny(id: String) {
        pendingApprovals.removeAll { $0.id == id }
        guard !AppReviewSampleData.isEnabled else { return }
        resolveAndDismiss(id: id, decision: Self.decisionDeny, approved: false)
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

    // MARK: - App Review sample data

    func loadAppReviewSampleData() {
        eventTask?.cancel()
        eventTask = nil
        pendingApprovals = AppReviewSampleData.approvals
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
        // Current gateway emits exec.approval.requested; "tool.approval_required" is the
        // legacy event name, kept so older gateways keep working.
        case GatewayEventName.execApprovalRequested, "tool.approval_required":
            handleApprovalRequired(event.payload)

        // The gateway (or another client, e.g. desktop) resolved an approval — clear it
        // locally and dismiss any stale Watch prompt so multiple clients stay in sync.
        case GatewayEventName.execApprovalResolved:
            handleApprovalResolved(event.payload)

        case GatewayEventName.snapshotCaptured:
            handleSnapshotCaptured(event.payload)

        case GatewayEventName.rollbackCompleted:
            handleRollbackCompleted(event.payload)

        default:
            break
        }
    }

    private func handleApprovalRequired(_ payload: [String: JSONValue]) {
        // exec.approval.requested nests the details in a `request` object and carries the
        // approval id at the top level; the legacy tool.approval_required event is flat.
        // Read from `request` first, then fall back to the top level so both shapes work.
        let details = payload["request"]?.objectValue ?? payload

        guard let approvalId = payload["id"]?.stringValue ?? payload["approvalId"]?.stringValue,
              !approvalId.isEmpty else { return }

        // Skip re-delivered or already-resolved approvals (gateway resend / multi-client).
        guard !resolvedIds.contains(approvalId),
              !pendingApprovals.contains(where: { $0.id == approvalId }) else { return }

        // Tool label: exec approvals expose toolName/command/label; legacy uses toolName.
        let toolName = details["toolName"]?.stringValue
            ?? details["command"]?.stringValue
            ?? details["label"]?.stringValue
            ?? payload["toolName"]?.stringValue
            ?? "command"

        let sessionKey = details["sessionKey"]?.stringValue
            ?? payload["sessionKey"]?.stringValue
            ?? ""

        // Structured input: legacy carries `toolInput`; exec carries command/argv/cwd in
        // the `request` object, so surface that object when no explicit input is present.
        let toolInput: [String: JSONValue]
        if let explicit = payload["toolInput"]?.objectValue {
            toolInput = explicit
        } else {
            toolInput = details
        }

        let nodeId = (details["nodeId"]?.stringValue ?? payload["nodeId"]?.stringValue)
            .flatMap { $0.isEmpty ? nil : $0 }

        let isDestructive = payload["isDestructive"]?.boolValue
            ?? details["isDestructive"]?.boolValue
            ?? false

        // NB: the exec request's `env` is the process env-var MAP (an object), not an
        // environment NAME, so it is intentionally not consulted here — only an explicit
        // environment name is honored, otherwise policies match against "unknown"/wildcard.
        let environment = details["environment"]?.stringValue
            ?? payload["environment"]?.stringValue
            ?? "unknown"

        // Evaluate via PolicyEngine before any bypass decisions so stored
        // allowlists cannot silently skip destructive or biometric-gated flows.
        let engine = PolicyStore.shared.engine
        let (matchedPolicy, riskLevel) = engine.evaluate(tool: toolName, environment: environment)
        let requiresUserAuth = isDestructive
            || riskLevel.requiresBiometric
            || (matchedPolicy?.requireBiometric == true)

        // Auto-approve if tool is in always-allow list, but never bypass a
        // destructive request or a policy/risk level that requires device auth.
        if isAlwaysAllowed(toolName), !requiresUserAuth {
            sendResolution(id: approvalId, decision: Self.decisionAllowOnce)
            return
        }

        // Auto-approve if policy says so, unless the request still needs an
        // explicit destructive/biometric confirmation.
        if let policy = matchedPolicy, policy.autoApprove, !requiresUserAuth {
            sendResolution(id: approvalId, decision: Self.decisionAllowOnce)
            return
        }

        // Register rollback snapshot for danger/critical operations
        var snapshotId: UUID? = nil
        if riskLevel >= .danger {
            let inputSummary = redactedInputSummary(toolInput)
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

    // MARK: - Private: resolution + Watch round-trip

    /// Resolve an approval on the gateway and dismiss the matching Watch prompt.
    private func resolveAndDismiss(id: String, decision: String, approved: Bool) {
        PhoneWatchBridge.shared.sendApprovalResolved(id: id, approved: approved)
        sendResolution(id: id, decision: decision)
    }

    /// Send `exec.approval.resolve` to the gateway, at most once per approval id.
    private func sendResolution(id: String, decision: String) {
        guard resolvedIds.insert(id).inserted else { return }
        Task { [weak self, client] in
            struct ResolveParams: Encodable {
                let id: String
                let decision: String
            }
            do {
                _ = try await client.send(
                    method: GatewayMethod.execApprovalResolve,
                    params: ResolveParams(id: id, decision: decision)
                )
            } catch {
                // The resolution never reached the gateway — drop the dedup marker so a
                // re-delivered exec.approval.requested can be resolved again instead of
                // being silently swallowed (which would lose an intended allow/deny).
                await self?.unmarkResolved(id)
            }
        }
    }

    private func unmarkResolved(_ id: String) {
        resolvedIds.remove(id)
    }

    /// Apply a resolution that originated off-device (the gateway or another client) so this
    /// client's pending list and the Watch stay in sync. Does not re-resolve on the gateway.
    private func handleApprovalResolved(_ payload: [String: JSONValue]) {
        let request = payload["request"]?.objectValue ?? payload
        guard let id = payload["id"]?.stringValue
                ?? payload["approvalId"]?.stringValue
                ?? request["id"]?.stringValue,
              !id.isEmpty else { return }
        resolvedIds.insert(id)
        pendingApprovals.removeAll { $0.id == id }
        let approved = (payload["decision"]?.stringValue ?? request["decision"]?.stringValue)
            .map { $0.hasPrefix("allow") } ?? (payload["approved"]?.boolValue ?? false)
        PhoneWatchBridge.shared.sendApprovalResolved(id: id, approved: approved)
    }

    /// Route Watch-originated approve/deny taps to the resolution path, with an auth gate.
    private func observeWatchResponses() {
        watchResponseObserver = NotificationCenter.default.addObserver(
            forName: .watchApprovalResponse,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let approvalId = note.userInfo?["approvalId"] as? String,
                  let approved = note.userInfo?["approved"] as? Bool else { return }
            Task { @MainActor in
                self?.handleWatchResponse(id: approvalId, approved: approved)
            }
        }
    }

    /// Apply an approve/deny that originated on the Watch.
    ///
    /// Denials are always honored. Approvals are honored only for requests that do NOT
    /// require an on-device auth gate: a Watch tap must never approve a destructive /
    /// critical / biometric-gated command, because the Face ID / passcode confirmation the
    /// phone enforces (ToolApprovalSheet) cannot be performed from the wrist. Such an
    /// approval is ignored and the request is left pending, so the phone sheet — already
    /// presented while the request is pending — drives the biometric confirmation.
    private func handleWatchResponse(id: String, approved: Bool) {
        guard approved else { deny(id: id); return }
        guard let request = pendingApprovals.first(where: { $0.id == id }) else { return }
        let requiresUserAuth = request.isDestructive
            || request.riskLevel.requiresBiometric
            || (request.matchedPolicy?.requireBiometric == true)
        guard !requiresUserAuth else { return }   // must be confirmed on the phone with biometrics
        approve(id: id)
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

    private func redactedInputSummary(_ input: [String: JSONValue]) -> String {
        input.prefix(3)
            .map { key, value in "\(key)=\(redactedValue(for: key, value: value))" }
            .joined(separator: ", ")
    }

    private func redactedValue(for key: String, value: JSONValue) -> String {
        let sensitiveTerms = ["token", "secret", "password", "passwd", "authorization", "credential", "privatekey", "api_key", "apikey"]
        let normalizedKey = key.replacingOccurrences(of: "_", with: "").lowercased()
        if sensitiveTerms.contains(where: { normalizedKey.contains($0) }) {
            return "<redacted>"
        }

        switch value {
        case .null:
            return "null"
        case .bool(let bool):
            return String(bool)
        case .int(let int):
            return String(int)
        case .double(let double):
            return String(double)
        case .string(let string):
            return String(string.prefix(160))
        case .array(let array):
            return "[\(array.count) items]"
        case .object(let object):
            return "{\(object.count) fields}"
        }
    }
}
