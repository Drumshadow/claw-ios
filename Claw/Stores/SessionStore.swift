import Foundation

// MARK: - SessionStore errors

enum SessionStoreError: Error, LocalizedError {
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let detail): return "Malformed sessions response: \(detail)"
        }
    }
}

// MARK: - SessionStore

/// Loads and maintains the list of sessions, reacting to gateway events in real time.
@Observable
@MainActor
final class SessionStore {

    // MARK: - Observable state

    private(set) var sessions: [ClawSession] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?
    private(set) var mutationError: Error?

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    nonisolated(unsafe) private var reloadTask: Task<Void, Never>?

    private static let pinnedKey = "claw.pinnedSessions"
    private static let renamedKey = "claw.renamedSessions"
    private static let sessionCacheKey = "claw.sessions.cache"

    private func loadSessionCache() -> [ClawSession] {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionCacheKey),
              let sessions = try? JSONDecoder().decode([ClawSession].self, from: data) else { return [] }
        return sessions
    }

    private func saveSessionCache(_ sessions: [ClawSession]) {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionCacheKey)
        }
    }

    private func loadPinnedIds() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: Self.pinnedKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    private func savePinnedIds(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(ids)) {
            UserDefaults.standard.set(data, forKey: Self.pinnedKey)
        }
    }

    private func loadRenamedTitles() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Self.renamedKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private func saveRenamedTitles(_ titles: [String: String]) {
        if let data = try? JSONEncoder().encode(titles) {
            UserDefaults.standard.set(data, forKey: Self.renamedKey)
        }
    }

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
        let cached = loadSessionCache()
        if !cached.isEmpty { sessions = cached }
        startEventSubscription()
    }

    deinit {
        eventTask?.cancel()
        reloadTask?.cancel()
    }

    // MARK: - Load

    func load() async throws {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let params = SessionsListParams(
                includeDerivedTitles: true,
                includeLastMessage: true
            )
            let payload = try await client.send(method: GatewayMethod.sessionsList, params: params)
            try applySessionsList(payload: payload)
            _ = try? await client.send(method: GatewayMethod.sessionsSubscribe, params: EmptyParams())
        } catch {
            loadError = error
            throw error
        }
    }

    /// Debounced reload: cancels any in-flight reload task and waits 300 ms before
    /// issuing the request. This prevents a burst of `sessions.changed` events from
    /// flooding the gateway with concurrent list requests whose out-of-order responses
    /// could cause flickering.
    private func silentReloadSessions() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300 ms debounce
            } catch {
                return // task was cancelled — a newer reload is already queued
            }
            guard let self, !Task.isCancelled else { return }
            let params = SessionsListParams(includeDerivedTitles: true, includeLastMessage: true)
            guard let payload = try? await self.client.send(method: GatewayMethod.sessionsList, params: params) else { return }
            await MainActor.run { try? self.applySessionsList(payload: payload) }
        }
    }

    // MARK: - Create

    /// Creates a new session via the gateway and returns its key. The matching
    /// `sessions.changed` event triggers a list reload to populate the new row;
    /// we also append a placeholder optimistically in case events lag.
    @discardableResult
    func createSession(agentId: String, label: String?) async throws -> String {
        mutationError = nil
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let params = SessionsCreateParams(
            agentId: agentId,
            label: (trimmedLabel?.isEmpty ?? true) ? nil : trimmedLabel
        )
        do {
            let payload = try await client.send(method: GatewayMethod.sessionsCreate, params: params)
            guard let keyVal = payload["key"], case .string(let key) = keyVal, !key.isEmpty else {
                throw SessionStoreError.malformedResponse("sessions.create returned no key")
            }
            // Insert a minimal placeholder so the new session is visible immediately;
            // the post-create sessions.changed event will trigger silentReloadSessions
            // to backfill model/tokens/preview.
            if !sessions.contains(where: { $0.id == key }) {
                let placeholder = ClawSession(
                    id: key,
                    title: trimmedLabel?.isEmpty == false ? trimmedLabel! : String(key.prefix(12)),
                    lastMessage: nil,
                    lastMessageAt: Date(),
                    agentStatus: .idle,
                    unreadCount: 0,
                    model: nil,
                    totalTokens: nil,
                    estimatedCostUsd: nil
                )
                sessions.insert(placeholder, at: 0)
            }
            return key
        } catch {
            mutationError = error
            throw error
        }
    }

    // MARK: - Delete

    /// Deletes a session. Optimistically removes from the list; restores on error.
    func deleteSession(id: String) async throws {
        mutationError = nil
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let removed = sessions.remove(at: idx)
        do {
            let params = SessionsDeleteParams(key: id)
            _ = try await client.send(method: GatewayMethod.sessionsDelete, params: params)
        } catch {
            // Restore the removed entry at its original index (clamped).
            let insertAt = min(idx, sessions.count)
            sessions.insert(removed, at: insertAt)
            mutationError = error
            throw error
        }
    }

    // MARK: - Pin

    func pinSession(id: String) {
        var ids = loadPinnedIds()
        ids.insert(id)
        savePinnedIds(ids)
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].isPinned = true
        }
        sessions.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return (a.lastMessageAt ?? .distantPast) > (b.lastMessageAt ?? .distantPast)
        }
    }

    func unpinSession(id: String) {
        var ids = loadPinnedIds()
        ids.remove(id)
        savePinnedIds(ids)
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].isPinned = false
        }
        sessions.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return (a.lastMessageAt ?? .distantPast) > (b.lastMessageAt ?? .distantPast)
        }
    }

    // MARK: - Rename

    func renameSession(id: String, newLabel: String) async {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = trimmed
        }
        var renamed = loadRenamedTitles()
        renamed[id] = trimmed
        saveRenamedTitles(renamed)
        struct RenameParams: Encodable { let key: String; let label: String }
        _ = try? await client.send(method: GatewayMethod.sessionsRename, params: RenameParams(key: id, label: trimmed))
    }

    // MARK: - Private: parse sessions list response

    private func applySessionsList(payload: [String: JSONValue]) throws {
        guard let sessionsValue = payload["sessions"],
              case .array(let arr) = sessionsValue else {
            sessions = []
            return
        }

        var result: [ClawSession] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            if let session = parseSession(obj: obj) {
                result.append(session)
            }
        }
        let pinned = loadPinnedIds()
        let renamed = loadRenamedTitles()
        for i in result.indices {
            result[i].isPinned = pinned.contains(result[i].id)
            if let customTitle = renamed[result[i].id] {
                result[i].title = customTitle
            }
        }
        sessions = result.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return (a.lastMessageAt ?? .distantPast) > (b.lastMessageAt ?? .distantPast)
        }
        saveSessionCache(sessions)
    }

    private func parseSession(obj: [String: JSONValue]) -> ClawSession? {
        guard let keyValue = obj["key"], case .string(let key) = keyValue else { return nil }

        let title: String
        if let v = obj["label"], case .string(let s) = v, !s.isEmpty {
            title = s
        } else if let v = obj["derivedTitle"], case .string(let s) = v, !s.isEmpty {
            title = s
        } else if let v = obj["displayName"], case .string(let s) = v, !s.isEmpty,
                  !s.hasPrefix("webchat:") && !s.contains(":g-agent") {
            title = s
        } else {
            title = Self.readableName(for: key)
        }

        let lastMessage: String?
        if let lm = obj["lastMessagePreview"], case .string(let s) = lm {
            lastMessage = s.isEmpty ? nil : s
        } else {
            lastMessage = nil
        }

        let lastMessageAt: Date?
        if let ts = obj["updatedAt"] {
            lastMessageAt = dateFromJSONValue(ts)
        } else {
            lastMessageAt = nil
        }

        let agentStatus: AgentStatus
        if let v = obj["hasActiveRun"], case .bool(let active) = v, active {
            agentStatus = .running
        } else if let v = obj["status"], case .string(let s) = v {
            agentStatus = AgentStatus(rawString: s)
        } else {
            agentStatus = .idle
        }

        let model: String?
        if let v = obj["model"], case .string(let s) = v, !s.isEmpty {
            model = s
        } else {
            model = nil
        }

        let totalTokens = intFromJSONValue(obj["totalTokens"])
        let estimatedCostUsd = doubleFromJSONValue(obj["estimatedCostUsd"])

        let childSessionKeys: [String]
        if let v = obj["childSessions"], case .array(let arr) = v {
            childSessionKeys = arr.compactMap { item in
                if case .string(let s) = item, !s.isEmpty { return s }
                return nil
            }
        } else {
            childSessionKeys = []
        }

        return ClawSession(
            id: key,
            title: title,
            lastMessage: lastMessage,
            lastMessageAt: lastMessageAt,
            agentStatus: agentStatus,
            unreadCount: 0,
            model: model,
            totalTokens: totalTokens,
            estimatedCostUsd: estimatedCostUsd,
            childSessionKeys: childSessionKeys
        )
    }

    // MARK: - Private: event subscription

    private func startEventSubscription() {
        // Capture `self` weakly inside the loop, not at the closure entry.
        // Promoting via `guard let self` outside the for-await would keep `self`
        // alive for the entire stream lifetime and create a retain cycle that
        // blocks deinit.
        eventTask = Task { [weak self, client] in
            for await event in await client.events() {
                guard let self else { return }
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {

        case "session.created":
            guard let session = parseSession(obj: event.payload) else { return }
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
            }

        case "session.updated":
            guard let session = parseSession(obj: event.payload) else { return }
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx] = session
            } else {
                sessions.insert(session, at: 0)
            }

        case "session.deleted":
            guard let keyValue = event.payload["key"],
                  case .string(let key) = keyValue else { return }
            sessions.removeAll { $0.id == key }

        case "chat":
            guard let skVal = event.payload["sessionKey"],
                  case .string(let sk) = skVal,
                  let stateVal = event.payload["state"],
                  case .string(let state) = stateVal else { return }
            if state == "final" || state == "aborted" || state == "error" {
                if let idx = sessions.firstIndex(where: { $0.id == sk }) {
                    sessions[idx].agentStatus = .idle
                }
            }

        case "sessions.changed":
            if let skVal = event.payload["sessionKey"],
               case .string(let sk) = skVal,
               let statusVal = event.payload["status"],
               case .string(let s) = statusVal,
               let idx = sessions.firstIndex(where: { $0.id == sk }) {
                sessions[idx].agentStatus = AgentStatus(rawString: s)
            }
            silentReloadSessions()

        default:
            break
        }
    }

    // MARK: - Private: helpers

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

    private func intFromJSONValue(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    private func doubleFromJSONValue(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    private static func readableName(for key: String) -> String {
        let adjectives = ["amber","arctic","bold","bright","calm","cedar","cobalt","crisp","dawn","deep",
                          "dusk","echo","fast","firm","flux","gold","jade","keen","lunar","mesa",
                          "mint","nova","oak","onyx","peak","pine","pure","quick","rose","ruby",
                          "sage","salt","slim","solar","still","stone","swift","teal","tide","warm"]
        let nouns = ["arc","ash","bay","beam","blade","brook","cliff","cloud","crane","creek",
                     "crow","dune","elk","falls","finch","flame","fog","ford","fox","frost",
                     "gale","glen","hawk","hill","isle","kite","lake","leaf","lynx","mist",
                     "moon","moss","owl","path","pike","pond","rain","reed","ridge","rook",
                     "rush","shore","snow","star","storm","tern","tide","vale","wave","wren"]
        var h1 = 0, h2 = 0
        for (i, c) in key.unicodeScalars.enumerated() {
            let v = Int(c.value)
            if i.isMultiple(of: 2) { h1 = h1 &* 31 &+ v } else { h2 = h2 &* 37 &+ v }
        }
        return "\(adjectives[abs(h1) % adjectives.count])-\(nouns[abs(h2) % nouns.count])"
    }
}

// MARK: - Request param types

private struct SessionsListParams: Encodable {
    let includeDerivedTitles: Bool
    let includeLastMessage: Bool
}

private struct SessionsCreateParams: Encodable {
    let agentId: String
    let label: String?

    enum CodingKeys: String, CodingKey {
        case agentId, label
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(agentId, forKey: .agentId)
        // Only encode label when non-nil so the gateway validator doesn't see a null.
        if let label {
            try c.encode(label, forKey: .label)
        }
    }
}

private struct SessionsDeleteParams: Encodable {
    let key: String
}

private struct EmptyParams: Encodable {}
