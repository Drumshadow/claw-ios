import Foundation

// MARK: - MemoryEntry

struct MemoryEntry: Identifiable, Hashable {
    let id: String
    let key: String
    let value: String
    let createdAt: Date?
    let updatedAt: Date?
}

// MARK: - MemoryStore errors

enum MemoryStoreError: Error, LocalizedError {
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let detail): return "Malformed memory response: \(detail)"
        }
    }
}

// MARK: - MemoryStore

/// Loads, searches, and deletes memory entries with pagination.
@Observable
@MainActor
final class MemoryStore {

    // MARK: - Observable state

    private(set) var entries: [MemoryEntry] = []
    private(set) var searchResults: [MemoryEntry] = []
    private(set) var isLoading: Bool = false
    private(set) var isSearching: Bool = false
    private(set) var loadError: Error?
    private(set) var mutationError: Error?
    private(set) var hasMore: Bool = true
    private(set) var currentOffset: Int = 0

    /// The query that produced the current `searchResults`. Empty means "no active search".
    private(set) var currentQuery: String = ""

    // MARK: - Config

    private let pageSize: Int = 50
    private let searchLimit: Int = 50

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: - List (paginated)

    /// Loads the first page, replacing existing entries.
    func reload() async throws {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        currentOffset = 0
        hasMore = true

        do {
            let params = MemoryListParams(limit: pageSize, offset: 0)
            let payload = try await client.send(method: GatewayMethod.memoryList, params: params)
            let parsed = parseEntriesPayload(payload)
            entries = parsed
            currentOffset = parsed.count
            hasMore = parsed.count >= pageSize
        } catch {
            loadError = error
            throw error
        }
    }

    /// Loads the next page and appends.
    func loadMore() async throws {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let params = MemoryListParams(limit: pageSize, offset: currentOffset)
            let payload = try await client.send(method: GatewayMethod.memoryList, params: params)
            let parsed = parseEntriesPayload(payload)
            entries.append(contentsOf: parsed)
            currentOffset += parsed.count
            hasMore = parsed.count >= pageSize
        } catch {
            loadError = error
            throw error
        }
    }

    // MARK: - Search (debounced via cancellation)

    /// Performs a search. Cancels any in-flight search before starting a new one.
    /// Pass an empty/whitespace query to clear results.
    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        if trimmed.isEmpty {
            currentQuery = ""
            searchResults = []
            isSearching = false
            return
        }

        currentQuery = trimmed
        isSearching = true

        let limit = searchLimit
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let params = MemorySearchParams(query: trimmed, limit: limit)
                let payload = try await self.client.send(method: GatewayMethod.memorySearch, params: params)
                if Task.isCancelled { return }
                let parsed = self.parseEntriesPayload(payload)
                if self.currentQuery == trimmed {
                    self.searchResults = parsed
                    self.isSearching = false
                }
            } catch {
                if Task.isCancelled { return }
                if self.currentQuery == trimmed {
                    self.searchResults = []
                    self.isSearching = false
                    self.loadError = error
                }
            }
        }
    }

    // MARK: - Delete

    func delete(_ entryId: String) async throws {
        mutationError = nil

        // Optimistically remove from both lists.
        let listIdx = entries.firstIndex(where: { $0.id == entryId })
        let searchIdx = searchResults.firstIndex(where: { $0.id == entryId })
        let removedFromList = listIdx.map { entries.remove(at: $0) }
        let removedFromSearch = searchIdx.map { searchResults.remove(at: $0) }

        do {
            _ = try await client.send(method: GatewayMethod.memoryDelete, params: MemoryIdParams(id: entryId))
        } catch {
            if let idx = listIdx, let removed = removedFromList {
                let insertAt = min(idx, entries.count)
                entries.insert(removed, at: insertAt)
            }
            if let idx = searchIdx, let removed = removedFromSearch {
                let insertAt = min(idx, searchResults.count)
                searchResults.insert(removed, at: insertAt)
            }
            mutationError = error
            throw error
        }
    }

    // MARK: - Private: parsing

    private func parseEntriesPayload(_ payload: [String: JSONValue]) -> [MemoryEntry] {
        let arr: [JSONValue]
        if let v = payload["entries"], case .array(let a) = v {
            arr = a
        } else if let v = payload["results"], case .array(let a) = v {
            arr = a
        } else if let v = payload["memories"], case .array(let a) = v {
            arr = a
        } else if let v = payload["items"], case .array(let a) = v {
            arr = a
        } else {
            return []
        }

        var result: [MemoryEntry] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            if let entry = parseEntry(obj: obj) {
                result.append(entry)
            }
        }
        return result
    }

    private func parseEntry(obj: [String: JSONValue]) -> MemoryEntry? {
        guard let idVal = obj["id"], case .string(let id) = idVal, !id.isEmpty else { return nil }

        let key: String
        if let v = obj["key"], case .string(let s) = v {
            key = s
        } else {
            key = ""
        }

        let value: String
        if let v = obj["value"], case .string(let s) = v {
            value = s
        } else {
            value = ""
        }

        return MemoryEntry(
            id: id,
            key: key,
            value: value,
            createdAt: dateFromJSONValue(obj["createdAt"]),
            updatedAt: dateFromJSONValue(obj["updatedAt"])
        )
    }

    private func dateFromJSONValue(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }
        switch value {
        case .int(let ms):
            return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        case .double(let ms):
            return Date(timeIntervalSince1970: ms / 1000.0)
        case .string(let s):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: s) { return d }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: s)
        default:
            return nil
        }
    }
}

// MARK: - Request param types

private struct MemoryListParams: Encodable {
    let limit: Int
    let offset: Int
}

private struct MemorySearchParams: Encodable {
    let query: String
    let limit: Int
}

private struct MemoryIdParams: Encodable {
    let id: String
}
