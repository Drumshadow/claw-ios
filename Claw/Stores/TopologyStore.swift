import Foundation

// MARK: - TopologyStore
//
// Manages the live infrastructure graph (InfraGraph) from the gateway.
//
// Gateway API expectations:
//   Request:  { method: "topology.snapshot" } → payload: InfraGraph JSON
//   Request:  { method: "topology.subscribe" } → starts event stream
//   Event:    "topology.snapshot"  — full graph replacement
//   Event:    "topology.node.updated"  — partial node patch { id, health, metrics... }
//   Event:    "topology.incident.opened"  — InfraIncident JSON
//   Event:    "topology.incident.closed"  — { id: String }
//   Event:    "topology.deployment.updated" — DeploymentEvent JSON
//
// When the gateway doesn't support topology, the store falls back to
// InfraGraph.preview so the UI always has something useful to display.

@Observable
@MainActor
final class TopologyStore {

    // MARK: - Published state

    private(set) var graph: InfraGraph = .preview
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?
    private(set) var isLive: Bool = false      // true when receiving real gateway data
    private(set) var lastRefreshedAt: Date?

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    nonisolated(unsafe) private var refreshTask: Task<Void, Never>?
    private static let refreshInterval: TimeInterval = 30

    private let decoder = JSONDecoder()

    init(client: GatewayClient) {
        self.client = client
    }

    deinit {
        eventTask?.cancel()
        refreshTask?.cancel()
    }

    // MARK: - Public API

    /// Kick off the initial load and start the event/refresh loop.
    func start() async {
        await loadSnapshot()
        startEventSubscription()
        startAutoRefresh()
    }

    /// Force a one-shot refresh from the gateway.
    func refresh() async {
        await loadSnapshot()
    }

    // MARK: - Snapshot loading

    private func loadSnapshot() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let payload = try await client.send(
                method: GatewayMethod.topologySnapshot,
                params: EmptyParams()
            )
            if let parsed = parseGraph(from: payload) {
                graph = parsed
                isLive = true
                lastRefreshedAt = Date()
            }
        } catch {
            // Non-fatal: fall back to preview / retain last known graph
            lastError = error.localizedDescription
            if !isLive {
                // First load failed — use preview so the UI isn't empty
                graph = .preview
            }
        }
    }

    // MARK: - Event subscription

    private func startEventSubscription() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.client.events()
            for await event in stream {
                await self.handleEvent(event)
                if Task.isCancelled { break }
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {
        case GatewayEventName.topologySnapshot:
            if let g = parseGraph(from: event.payload) {
                graph = g
                isLive = true
                lastRefreshedAt = Date()
            }

        case GatewayEventName.topologyNodeUpdated:
            applyNodePatch(event.payload)

        case GatewayEventName.topologyIncidentOpened:
            if let incident = parseIncident(from: event.payload) {
                var updated = graph
                updated.incidents.removeAll { $0.id == incident.id }
                updated.incidents.append(incident)
                graph = updated
            }

        case GatewayEventName.topologyIncidentClosed:
            if let id = event.payload["id"]?.stringValue {
                var updated = graph
                if let idx = updated.incidents.firstIndex(where: { $0.id == id }) {
                    updated.incidents[idx].resolvedAt = Date()
                }
                graph = updated
            }

        case GatewayEventName.topologyDeploymentUpdated:
            if let deploy = parseDeployment(from: event.payload) {
                var updated = graph
                updated.deployments.removeAll { $0.id == deploy.id }
                updated.deployments.insert(deploy, at: 0)
                // Keep the last 20 deployments
                if updated.deployments.count > 20 {
                    updated.deployments = Array(updated.deployments.prefix(20))
                }
                graph = updated
            }

        default:
            break
        }
    }

    // MARK: - Auto-refresh timer

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.loadSnapshot()
            }
        }
    }

    // MARK: - Node patch

    private func applyNodePatch(_ payload: [String: JSONValue]) {
        guard let id = payload["id"]?.stringValue else { return }
        guard let idx = graph.nodes.firstIndex(where: { $0.id == id }) else { return }

        var node = graph.nodes[idx]

        if let h = payload["health"]?.stringValue {
            node.health = InfraHealth(rawValue: h) ?? node.health
        }
        if let v = payload["cpuPercent"] { node.cpuPercent = doubleFrom(v) }
        if let v = payload["memPercent"] { node.memPercent = doubleFrom(v) }
        if let v = payload["errorRate"]  { node.errorRate  = doubleFrom(v) }
        if let v = payload["requestRate"]{ node.requestRate = doubleFrom(v) }
        if let v = payload["queueDepth"] { node.queueDepth = intFrom(v) }
        if let v = payload["instanceCount"] { node.instanceCount = intFrom(v) }
        if let v = payload["incidentCount"] { node.incidentCount = intFrom(v) ?? node.incidentCount }

        var updated = graph
        updated.nodes[idx] = node
        graph = updated
    }

    // MARK: - JSON parsing

    private func parseGraph(from payload: [String: JSONValue]) -> InfraGraph? {
        guard !payload.isEmpty else { return nil }
        // Re-encode the payload dict back to Data, then decode InfraGraph
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload),
              let g = try? decoder.decode(InfraGraph.self, from: data) else {
            return nil
        }
        return g
    }

    private func parseIncident(from payload: [String: JSONValue]) -> InfraIncident? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload),
              let inc = try? decoder.decode(InfraIncident.self, from: data) else {
            return nil
        }
        return inc
    }

    private func parseDeployment(from payload: [String: JSONValue]) -> DeploymentEvent? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload),
              let dep = try? decoder.decode(DeploymentEvent.self, from: data) else {
            return nil
        }
        return dep
    }

    private func doubleFrom(_ v: JSONValue) -> Double? {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }

    private func intFrom(_ v: JSONValue) -> Int? {
        switch v {
        case .int(let i):    return i
        case .double(let d): return Int(d)
        default:             return nil
        }
    }
}

// MARK: - Empty params helper

private struct EmptyParams: Encodable {}
