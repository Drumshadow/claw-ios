import Foundation

// MARK: - NodeStore errors

enum NodeStoreError: Error, LocalizedError {
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let detail): return "Malformed nodes response: \(detail)"
        }
    }
}

// MARK: - NodeStore

/// Loads and maintains the list of paired and pending nodes, reacting to gateway events in real time.
@Observable
@MainActor
final class NodeStore {

    // MARK: - Observable state

    private(set) var nodes: [ClawNode] = []
    private(set) var pendingNodes: [ClawNode] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?
    private(set) var mutationError: Error?

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    nonisolated(unsafe) private var silentReloadTask: Task<Void, Never>?

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
        startEventSubscription()
    }

    deinit {
        eventTask?.cancel()
        silentReloadTask?.cancel()
    }

    // MARK: - Load

    func load() async throws {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            async let listPayload = client.send(method: GatewayMethod.nodesList, params: EmptyParams())
            async let pendingPayload = client.send(method: GatewayMethod.nodesPending, params: EmptyParams())

            let list = try await listPayload
            let pending = try await pendingPayload
            applyNodesList(payload: list)
            applyPendingList(payload: pending)
        } catch {
            loadError = error
            throw error
        }
    }

    private func silentReload() {
        silentReloadTask?.cancel()
        silentReloadTask = Task { [weak self, client] in
            async let listFetch = try? client.send(method: GatewayMethod.nodesList, params: EmptyParams())
            async let pendingFetch = try? client.send(method: GatewayMethod.nodesPending, params: EmptyParams())
            let list = await listFetch
            let pending = await pendingFetch
            guard !Task.isCancelled, let self else { return }
            if let list { self.applyNodesList(payload: list) }
            if let pending { self.applyPendingList(payload: pending) }
        }
    }

    // MARK: - Approve

    /// Approves a pending node. Optimistically moves it from pending to paired list;
    /// the matching `node.connected` event will populate any missing fields.
    func approve(_ nodeId: String) async throws {
        mutationError = nil
        guard let idx = pendingNodes.firstIndex(where: { $0.id == nodeId }) else {
            // Still send the request even if not in our local cache (it might be stale).
            do {
                _ = try await client.send(method: GatewayMethod.nodesApprove, params: NodeIdParams(nodeId: nodeId))
                silentReload()
                return
            } catch {
                mutationError = error
                throw error
            }
        }

        var promoted = pendingNodes.remove(at: idx)
        promoted.isPending = false
        promoted.paired = true
        promoted.approvedAt = Date()
        if !nodes.contains(where: { $0.id == promoted.id }) {
            nodes.insert(promoted, at: 0)
        }

        do {
            _ = try await client.send(method: GatewayMethod.nodesApprove, params: NodeIdParams(nodeId: nodeId))
        } catch {
            // Restore on failure.
            nodes.removeAll { $0.id == promoted.id }
            promoted.isPending = true
            promoted.paired = false
            promoted.approvedAt = nil
            pendingNodes.insert(promoted, at: min(idx, pendingNodes.count))
            mutationError = error
            throw error
        }
    }

    // MARK: - Reject

    /// Rejects a pending node, removing it from the list. Restores on error.
    func reject(_ nodeId: String) async throws {
        mutationError = nil
        guard let idx = pendingNodes.firstIndex(where: { $0.id == nodeId }) else {
            do {
                _ = try await client.send(method: GatewayMethod.nodesReject, params: NodeIdParams(nodeId: nodeId))
                return
            } catch {
                mutationError = error
                throw error
            }
        }

        let removed = pendingNodes.remove(at: idx)
        do {
            _ = try await client.send(method: GatewayMethod.nodesReject, params: NodeIdParams(nodeId: nodeId))
        } catch {
            let insertAt = min(idx, pendingNodes.count)
            pendingNodes.insert(removed, at: insertAt)
            mutationError = error
            throw error
        }
    }

    // MARK: - Notify

    /// Sends a push notification to a paired node.
    func sendNotification(to nodeId: String, title: String, body: String) async throws {
        mutationError = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return }

        let params = NodeNotifyParams(nodeId: nodeId, title: trimmedTitle, body: trimmedBody)
        do {
            _ = try await client.send(method: GatewayMethod.nodesNotify, params: params)
        } catch {
            mutationError = error
            throw error
        }
    }

    // MARK: - Private: parse responses

    private func applyNodesList(payload: [String: JSONValue]) {
        let arr = extractNodesArray(from: payload)
        var result: [ClawNode] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            if let node = parseNode(obj: obj, isPending: false) {
                result.append(node)
            }
        }
        nodes = result.sorted { lhs, rhs in
            if lhs.connected != rhs.connected { return lhs.connected }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func applyPendingList(payload: [String: JSONValue]) {
        let arr = extractNodesArray(from: payload)
        var result: [ClawNode] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            if let node = parseNode(obj: obj, isPending: true) {
                result.append(node)
            }
        }
        pendingNodes = result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func extractNodesArray(from payload: [String: JSONValue]) -> [JSONValue] {
        if let nodesVal = payload["nodes"], case .array(let arr) = nodesVal {
            return arr
        }
        if let pendingVal = payload["pending"], case .array(let arr) = pendingVal {
            return arr
        }
        return []
    }

    private func parseNode(obj: [String: JSONValue], isPending: Bool) -> ClawNode? {
        guard let idVal = obj["nodeId"], case .string(let nodeId) = idVal, !nodeId.isEmpty else { return nil }

        let displayName: String
        if let v = obj["displayName"], case .string(let s) = v, !s.isEmpty {
            displayName = s
        } else {
            displayName = String(nodeId.prefix(12))
        }

        let platform: String
        if let v = obj["platform"], case .string(let s) = v {
            platform = s
        } else {
            platform = ""
        }

        let connected: Bool
        if let v = obj["connected"], case .bool(let b) = v {
            connected = b
        } else {
            connected = false
        }

        let paired: Bool
        if let v = obj["paired"], case .bool(let b) = v {
            paired = b
        } else {
            paired = !isPending
        }

        let approvedAt: Date?
        if let v = obj["approvedAtMs"] {
            approvedAt = dateFromJSONValue(v)
        } else {
            approvedAt = nil
        }

        var caps: [String] = []
        if let v = obj["caps"], case .array(let arr) = v {
            caps = arr.compactMap {
                if case .string(let s) = $0 { return s }
                return nil
            }
        }

        return ClawNode(
            id: nodeId,
            displayName: displayName,
            platform: platform,
            connected: connected,
            paired: paired,
            approvedAt: approvedAt,
            caps: caps,
            isPending: isPending
        )
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

        case GatewayEventName.nodeConnected:
            guard let nodeId = nodeIdFromPayload(event.payload) else { return }
            if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[idx].connected = true
                // Merge any additional fields the event carries.
                if let updated = parseNode(obj: event.payload, isPending: false) {
                    nodes[idx] = updated
                }
            } else if let node = parseNode(obj: event.payload, isPending: false) {
                nodes.insert(node, at: 0)
            } else {
                silentReload()
            }

        case GatewayEventName.nodeDisconnected:
            guard let nodeId = nodeIdFromPayload(event.payload) else { return }
            if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[idx].connected = false
            }

        case GatewayEventName.nodePending:
            if let node = parseNode(obj: event.payload, isPending: true) {
                if let idx = pendingNodes.firstIndex(where: { $0.id == node.id }) {
                    pendingNodes[idx] = node
                } else {
                    pendingNodes.append(node)
                }
            } else {
                silentReload()
            }

        default:
            break
        }
    }

    // MARK: - Private: helpers

    private func nodeIdFromPayload(_ payload: [String: JSONValue]) -> String? {
        if let v = payload["nodeId"], case .string(let s) = v, !s.isEmpty { return s }
        return nil
    }

    private func dateFromJSONValue(_ value: JSONValue) -> Date? {
        switch value {
        case .int(let ms):
            return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        case .double(let ms):
            return Date(timeIntervalSince1970: ms / 1000.0)
        default:
            return nil
        }
    }
}

// MARK: - Request param types

private struct NodeIdParams: Encodable {
    let nodeId: String
}

private struct NodeNotifyParams: Encodable {
    let nodeId: String
    let title: String
    let body: String
}

private struct EmptyParams: Encodable {}
