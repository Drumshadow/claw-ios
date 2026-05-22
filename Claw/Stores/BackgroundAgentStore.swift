import Foundation

// MARK: - BackgroundAgentStore
//
// Manages background watchers, incidents, and remediation proposals.
// Subscribes to gateway events for live updates.
//
// Backend expectations:
//   methods: background.agents.list, background.agent.create,
//            background.agent.delete, background.agent.toggle,
//            incidents.list, incident.acknowledge, incident.resolve,
//            proposals.list, proposal.approve, proposal.reject
//   events:  background.agent.alert, incident.created, incident.updated,
//            proposal.created

@Observable
@MainActor
final class BackgroundAgentStore {

    // MARK: - Observable State

    private(set) var watchers: [BackgroundWatcher] = []
    private(set) var incidents: [Incident] = []
    private(set) var proposals: [AnomalyProposal] = []
    private(set) var isLoadingWatchers: Bool = false
    private(set) var isLoadingIncidents: Bool = false
    private(set) var loadError: Error?

    // MARK: - Computed

    var activeIncidents: [Incident] { incidents.filter { $0.status.isActive } }
    var enabledWatchers: [BackgroundWatcher] { watchers.filter { $0.isEnabled } }
    var pendingProposals: [AnomalyProposal] { proposals.filter { $0.status == .pending } }

    var totalActiveCount: Int { activeIncidents.count }
    var criticalCount: Int {
        activeIncidents.filter { $0.severity == .critical || $0.severity == .emergency }.count
    }

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    nonisolated(unsafe) private var reloadDebounce: Task<Void, Never>?

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
        startEventSubscription()
    }

    deinit {
        eventTask?.cancel()
        reloadDebounce?.cancel()
    }

    // MARK: - Load

    func loadAll() async {
        async let watchersResult: Void = loadWatchers()
        async let incidentsResult: Void = loadIncidents()
        async let proposalsResult: Void = loadProposals()
        _ = await (watchersResult, incidentsResult, proposalsResult)
    }

    func loadWatchers() async {
        isLoadingWatchers = true
        defer { isLoadingWatchers = false }

        guard let payload = try? await client.send(
            method: GatewayMethod.backgroundAgentsList,
            params: EmptyParams()
        ) else {
            // Backend not available — load preview data
            watchers = BackgroundWatcher.previewWatchers
            return
        }

        if let arr = payload["watchers"], case .array(let items) = arr {
            watchers = items.compactMap { parseWatcher($0) }
        }
    }

    func loadIncidents() async {
        isLoadingIncidents = true
        defer { isLoadingIncidents = false }

        guard let payload = try? await client.send(
            method: GatewayMethod.incidentsList,
            params: EmptyParams()
        ) else {
            incidents = Incident.previewIncidents
            return
        }

        if let arr = payload["incidents"], case .array(let items) = arr {
            incidents = items.compactMap { parseIncident($0) }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    func loadProposals() async {
        guard let payload = try? await client.send(
            method: GatewayMethod.proposalsList,
            params: EmptyParams()
        ) else { return }

        if let arr = payload["proposals"], case .array(let items) = arr {
            proposals = items.compactMap { parseProposal($0) }
        }
    }

    // MARK: - Watcher CRUD

    func toggleWatcher(_ id: String) async {
        guard let idx = watchers.firstIndex(where: { $0.id == id }) else { return }
        let newEnabled = !watchers[idx].isEnabled
        watchers[idx].isEnabled = newEnabled

        struct ToggleParams: Encodable { let id: String; let enabled: Bool }
        _ = try? await client.send(
            method: GatewayMethod.backgroundAgentToggle,
            params: ToggleParams(id: id, enabled: newEnabled)
        )
    }

    func deleteWatcher(_ id: String) async {
        watchers.removeAll { $0.id == id }
        struct IdParams: Encodable { let id: String }
        _ = try? await client.send(
            method: GatewayMethod.backgroundAgentDelete,
            params: IdParams(id: id)
        )
    }

    // MARK: - Incident Actions

    func acknowledgeIncident(_ id: String) async {
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[idx].status = .acknowledged
        incidents[idx].acknowledgedAt = Date()

        struct IdParams: Encodable { let id: String }
        _ = try? await client.send(
            method: GatewayMethod.incidentAcknowledge,
            params: IdParams(id: id)
        )
    }

    func resolveIncident(_ id: String, resolution: String) async {
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[idx].status = .resolved
        incidents[idx].resolvedAt = Date()

        struct ResolveParams: Encodable { let id: String; let resolution: String }
        _ = try? await client.send(
            method: GatewayMethod.incidentResolve,
            params: ResolveParams(id: id, resolution: resolution)
        )
    }

    // MARK: - Proposal Actions

    func approveProposal(_ id: String) async {
        guard let idx = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[idx].status = .approved
        proposals[idx].reviewedAt = Date()

        struct IdParams: Encodable { let id: String }
        _ = try? await client.send(
            method: GatewayMethod.proposalApprove,
            params: IdParams(id: id)
        )
    }

    func rejectProposal(_ id: String, reason: String?) async {
        guard let idx = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[idx].status = .rejected
        proposals[idx].reviewedAt = Date()

        struct RejectParams: Encodable { let id: String; let reason: String? }
        _ = try? await client.send(
            method: GatewayMethod.proposalReject,
            params: RejectParams(id: id, reason: reason)
        )
    }

    // MARK: - Event Subscription

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
        case GatewayEventName.backgroundAgentAlert:
            // A watcher fired — debounce reload
            scheduleReload()

        case GatewayEventName.incidentCreated:
            if let incident = parseIncident(event.payload.asJSONValue) {
                incidents.insert(incident, at: 0)
            } else {
                scheduleReload()
            }

        case GatewayEventName.incidentUpdated:
            if let incident = parseIncident(event.payload.asJSONValue) {
                if let idx = incidents.firstIndex(where: { $0.id == incident.id }) {
                    incidents[idx] = incident
                } else {
                    incidents.insert(incident, at: 0)
                }
            }

        case GatewayEventName.proposalCreated:
            if let proposal = parseProposal(event.payload.asJSONValue) {
                proposals.insert(proposal, at: 0)
            }

        default:
            break
        }
    }

    private func scheduleReload() {
        reloadDebounce?.cancel()
        reloadDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.loadIncidents()
        }
    }

    // MARK: - Parsing

    private func parseWatcher(_ value: JSONValue) -> BackgroundWatcher? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal else { return nil }

        let name: String
        if let v = obj["name"], case .string(let s) = v { name = s } else { name = id }

        let description: String
        if let v = obj["description"], case .string(let s) = v { description = s } else { description = "" }

        let isEnabled: Bool
        if let v = obj["enabled"], case .bool(let b) = v { isEnabled = b } else { isEnabled = true }

        let triggerType: WatcherTriggerType
        if let v = obj["triggerType"], case .string(let s) = v {
            triggerType = WatcherTriggerType(rawValue: s) ?? .scheduled
        } else {
            triggerType = .scheduled
        }

        let condition: String
        if let v = obj["condition"], case .string(let s) = v { condition = s } else { condition = "" }

        let remediationEnabled: Bool
        if let v = obj["remediationEnabled"], case .bool(let b) = v { remediationEnabled = b } else { remediationEnabled = false }

        return BackgroundWatcher(
            id: id,
            name: name,
            description: description,
            isEnabled: isEnabled,
            triggerType: triggerType,
            condition: condition,
            schedule: nil,
            eventSourceIds: [],
            assignedAgentId: nil,
            lastTriggeredAt: dateFromMs(obj["lastTriggeredAt"]),
            lastResult: nil,
            createdAt: dateFromMs(obj["createdAt"]) ?? Date(),
            escalationPolicy: nil,
            remediationEnabled: remediationEnabled,
            incidentGroupTag: nil
        )
    }

    private func parseIncident(_ value: JSONValue) -> Incident? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal else { return nil }

        let title: String
        if let v = obj["title"], case .string(let s) = v { title = s } else { title = "Incident \(id.prefix(8))" }

        let description: String
        if let v = obj["description"], case .string(let s) = v { description = s } else { description = "" }

        let severity: IncidentSeverity
        if let v = obj["severity"], case .string(let s) = v {
            severity = IncidentSeverity(rawValue: s) ?? .warning
        } else {
            severity = .warning
        }

        let status: IncidentStatus
        if let v = obj["status"], case .string(let s) = v {
            status = IncidentStatus(rawValue: s) ?? .open
        } else {
            status = .open
        }

        return Incident(
            id: id,
            title: title,
            description: description,
            severity: severity,
            status: status,
            watcherIds: [],
            proposalIds: [],
            relatedSessionIds: [],
            timeline: [],
            createdAt: dateFromMs(obj["createdAt"]) ?? Date(),
            resolvedAt: dateFromMs(obj["resolvedAt"]),
            acknowledgedAt: dateFromMs(obj["acknowledgedAt"]),
            tags: []
        )
    }

    private func parseProposal(_ value: JSONValue) -> AnomalyProposal? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal,
              let incVal = obj["incidentId"], case .string(let incidentId) = incVal else { return nil }

        let title: String
        if let v = obj["title"], case .string(let s) = v { title = s } else { title = "Proposal \(id.prefix(8))" }

        let description: String
        if let v = obj["description"], case .string(let s) = v { description = s } else { description = "" }

        let status: RemediationStatus
        if let v = obj["status"], case .string(let s) = v {
            status = RemediationStatus(rawValue: s) ?? .pending
        } else {
            status = .pending
        }

        let riskLevel: ProposalRiskLevel
        if let v = obj["riskLevel"], case .string(let s) = v {
            riskLevel = ProposalRiskLevel(rawValue: s) ?? .medium
        } else {
            riskLevel = .medium
        }

        return AnomalyProposal(
            id: id,
            incidentId: incidentId,
            watcherId: nil,
            sessionId: nil,
            title: title,
            description: description,
            proposedActions: [],
            status: status,
            riskLevel: riskLevel,
            estimatedImpact: "",
            createdAt: dateFromMs(obj["createdAt"]) ?? Date(),
            reviewedAt: dateFromMs(obj["reviewedAt"]),
            executedAt: dateFromMs(obj["executedAt"]),
            tokenCost: nil
        )
    }

    private func dateFromMs(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }
        switch value {
        case .int(let ms):    return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        case .double(let ms): return Date(timeIntervalSince1970: ms / 1000.0)
        default:              return nil
        }
    }
}

// MARK: - Helpers

private struct EmptyParams: Encodable {}

private extension [String: JSONValue] {
    var asJSONValue: JSONValue { .object(self) }
}
