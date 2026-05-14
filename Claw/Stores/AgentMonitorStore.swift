import Foundation

// MARK: - AgentMonitorStatus

enum AgentMonitorStatus {
    case running, completed, error

    var label: String {
        switch self {
        case .running:   return "Running"
        case .completed: return "Done"
        case .error:     return "Error"
        }
    }

    var isActive: Bool {
        self == .running
    }
}

// MARK: - AgentMonitorSession

struct AgentMonitorSession: Identifiable {
    let id: String
    var title: String
    var status: AgentMonitorStatus
    var lastMessage: String?
    var model: String?
    var updatedAt: Date?
    var startedAt: Date?
    var parentSessionKey: String?
    var agentId: String?
}

// MARK: - AgentMonitorStore

@Observable
@MainActor
final class AgentMonitorStore {

    var sessions: [AgentMonitorSession] = []
    var isLoading: Bool = false

    var runningCount: Int {
        sessions.filter(\.status.isActive).count
    }

    private let client: GatewayClient
    nonisolated(unsafe) var pollTask: Task<Void, Never>?
    nonisolated(unsafe) var eventTask: Task<Void, Never>?
    nonisolated(unsafe) private var reloadDebounceTask: Task<Void, Never>?

    init(client: GatewayClient) {
        self.client = client
        startEventSubscription()
    }

    deinit {
        pollTask?.cancel()
        eventTask?.cancel()
        reloadDebounceTask?.cancel()
    }

    // MARK: - Load

    func load() async {
        struct MonitorListParams: Encodable {
            let activeMinutes: Int = 180
            let includeDerivedTitles: Bool = true
            let includeLastMessage: Bool = true
        }

        guard let payload = try? await client.send(method: GatewayMethod.sessionsList, params: MonitorListParams()) else { return }

        guard let sessionsValue = payload["sessions"],
              case .array(let arr) = sessionsValue else {
            sessions = []
            return
        }

        var result: [AgentMonitorSession] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            if let session = parseMonitorSession(obj: obj) {
                result.append(session)
            }
        }

        sessions = result.sorted { a, b in
            if a.status.isActive != b.status.isActive { return a.status.isActive }
            return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
        }
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        await load()
        isLoading = false
    }

    // MARK: - Polling

    func startPollingIfNeeded() {
        guard runningCount > 0 else { return }
        guard pollTask == nil || pollTask?.isCancelled == true else { return }
        pollTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await self.load()
                if await self.runningCount == 0 {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Event subscription

    func startEventSubscription() {
        eventTask = Task { [weak self, client] in
            for await event in await client.events() {
                guard let self else { return }
                await self.handleMonitorEvent(event)
            }
        }
    }

    private func handleMonitorEvent(_ event: GatewayEvent) {
        switch event.name {
        case "sessions.changed":
            // Debounce: a burst of changed events should produce one reload,
            // not one request per event.
            reloadDebounceTask?.cancel()
            reloadDebounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.load()
            }

        case "session.updated":
            guard let parsed = parseMonitorSession(obj: event.payload) else { return }
            if let idx = sessions.firstIndex(where: { $0.id == parsed.id }) {
                sessions[idx] = parsed
                sessions.sort { a, b in
                    if a.status.isActive != b.status.isActive { return a.status.isActive }
                    return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
                }
            }

        default:
            break
        }
    }

    // MARK: - Parse

    private func parseMonitorSession(obj: [String: JSONValue]) -> AgentMonitorSession? {
        guard let keyValue = obj["key"], case .string(let key) = keyValue else { return nil }

        let parentSessionKey: String?
        if let v = obj["parentSessionKey"], case .string(let s) = v, !s.isEmpty {
            parentSessionKey = s
        } else {
            parentSessionKey = nil
        }

        guard parentSessionKey != nil else { return nil }

        let title: String
        if let v = obj["displayName"], case .string(let s) = v, !s.isEmpty {
            title = s
        } else if let v = obj["derivedTitle"], case .string(let s) = v, !s.isEmpty {
            title = s
        } else if let v = obj["label"], case .string(let s) = v, !s.isEmpty {
            title = s
        } else {
            title = String(key.prefix(12))
        }

        let status: AgentMonitorStatus
        if let v = obj["hasActiveRun"], case .bool(let active) = v, active {
            status = .running
        } else if let v = obj["status"], case .string(let s) = v {
            switch s.lowercased() {
            case "running": status = .running
            case "error":   status = .error
            default:        status = .completed
            }
        } else {
            status = .completed
        }

        let lastMessage: String?
        if let v = obj["lastMessagePreview"], case .string(let s) = v, !s.isEmpty {
            lastMessage = s
        } else {
            lastMessage = nil
        }

        let model: String?
        if let v = obj["model"], case .string(let s) = v, !s.isEmpty {
            model = s
        } else {
            model = nil
        }

        let updatedAt: Date?
        if let v = obj["updatedAt"] {
            updatedAt = dateFromMs(v)
        } else {
            updatedAt = nil
        }

        let startedAt: Date?
        if let v = obj["startedAt"] {
            startedAt = dateFromMs(v)
        } else {
            startedAt = nil
        }

        let agentId: String?
        if let v = obj["agentId"], case .string(let s) = v, !s.isEmpty {
            agentId = s
        } else {
            agentId = nil
        }

        return AgentMonitorSession(
            id: key,
            title: title,
            status: status,
            lastMessage: lastMessage,
            model: model,
            updatedAt: updatedAt,
            startedAt: startedAt,
            parentSessionKey: parentSessionKey,
            agentId: agentId
        )
    }

    private func dateFromMs(_ value: JSONValue) -> Date? {
        switch value {
        case .int(let ms):    return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        case .double(let ms): return Date(timeIntervalSince1970: ms / 1000.0)
        default:              return nil
        }
    }
}
