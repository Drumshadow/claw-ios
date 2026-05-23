import Foundation

// MARK: - TerminalSessionStore
//
// Manages the list of terminal sessions visible in the Ops tab.
// Subscribes to gateway events to keep the list live.
//
// Gateway contract:
//   terminal.sessions.list  → [TerminalSessionPayload]
//   Events: terminal.session.started  { session: TerminalSessionPayload }
//           terminal.session.ended    { sessionId: String, exitCode: Int? }

@Observable
@MainActor
final class TerminalSessionStore {

    // MARK: - Observable state

    private(set) var sessions: [TerminalSession] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// Active TerminalStore instances keyed by sessionId.
    /// Created lazily when the user opens a terminal session view.
    private(set) var activeStores: [String: TerminalStore] = [:]

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    private static let cacheKey = "claw.terminal.sessions.cache"

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
        sessions = AppReviewSampleData.isEnabled ? AppReviewSampleData.terminalSessions : loadCache()
        if !AppReviewSampleData.isEnabled { startEventSubscription() }
    }

    // MARK: - Load

    func load() async throws {
        if AppReviewSampleData.isEnabled {
            loadAppReviewSampleData()
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let response = try await client.send(
                method: GatewayMethod.terminalSessionsList,
                params: EmptyParams()
            )
            guard let sessionsVal = response["sessions"],
                  case .array(let arr) = sessionsVal else {
                sessions = TerminalSession.sampleSessions   // graceful fallback
                return
            }
            let decoder = JSONDecoder()
            let payloads: [TerminalSessionPayload] = arr.compactMap { item in
                guard case .object(let dict) = item else { return nil }
                if let data = try? JSONSerialization.data(withJSONObject: dict.asDictionary()),
                   let p = try? decoder.decode(TerminalSessionPayload.self, from: data) {
                    return p
                }
                return nil
            }
            sessions = payloads.map { $0.toTerminalSession() }
                .sorted { $0.startedAt > $1.startedAt }
            saveCache(sessions)
        } catch {
            loadError = error
            // Use cached data if gateway unavailable
            if sessions.isEmpty {
                sessions = TerminalSession.sampleSessions
            }
        }
    }

    // MARK: - App Review sample data

    func loadAppReviewSampleData() {
        eventTask?.cancel()
        eventTask = nil
        sessions = AppReviewSampleData.terminalSessions
        loadError = nil
    }

    // MARK: - TerminalStore lifecycle

    /// Returns (or creates) a TerminalStore for the given session.
    func store(for session: TerminalSession) -> TerminalStore {
        if let existing = activeStores[session.id] { return existing }
        let store = TerminalStore(sessionId: session.id, client: client)
        activeStores[session.id] = store
        return store
    }

    /// Tears down the TerminalStore for a session when the view is dismissed.
    func releaseStore(for sessionId: String) async {
        guard let store = activeStores[sessionId] else { return }
        await store.unsubscribe()
        activeStores.removeValue(forKey: sessionId)
    }

    // MARK: - Event subscription

    private func startEventSubscription() {
        eventTask = Task { [weak self, client] in
            for await event in await client.events() {
                guard let self, !Task.isCancelled else { break }
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {
        case GatewayEventName.terminalSessionStarted:
            if let sessionVal = event.payload["session"],
               case .object(let dict) = sessionVal,
               let data = try? JSONSerialization.data(withJSONObject: dict.asDictionary()),
               let payload = try? JSONDecoder().decode(TerminalSessionPayload.self, from: data) {
                let newSession = payload.toTerminalSession()
                if let idx = sessions.firstIndex(where: { $0.id == newSession.id }) {
                    sessions[idx] = newSession
                } else {
                    sessions.insert(newSession, at: 0)
                }
                saveCache(sessions)
            }

        case GatewayEventName.terminalSessionEnded:
            guard let sidVal = event.payload["sessionId"],
                  case .string(let sid) = sidVal else { return }
            if let idx = sessions.firstIndex(where: { $0.id == sid }) {
                var updated = sessions[idx]
                updated.status = .ended
                updated.endedAt = Date()
                if case .int(let code) = event.payload["exitCode"] {
                    updated.exitCode = code
                }
                updated.isReplay = true
                sessions[idx] = updated
                saveCache(sessions)
            }

        default:
            break
        }
    }

    // MARK: - Cache

    private func loadCache() -> [TerminalSession] {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([TerminalSession].self, from: data)
        else { return [] }
        return cached
    }

    private func saveCache(_ sessions: [TerminalSession]) {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}

// MARK: - Helpers

private struct EmptyParams: Encodable {}

// Extension to convert [String: JSONValue] → [String: Any] for JSONSerialization
private extension Dictionary where Key == String, Value == JSONValue {
    func asDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in self {
            result[key] = value.asAny()
        }
        return result
    }
}

private extension JSONValue {
    func asAny() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let n): return n
        case .double(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { $0.asAny() }
        case .object(let dict): return dict.asDictionary()
        }
    }
}
