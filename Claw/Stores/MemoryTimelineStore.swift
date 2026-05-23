import Foundation

// MARK: - MemoryTimelineStore
//
// Manages the knowledge graph / memory timeline.
// Loads paginated events, supports search, and subscribes to live event pushes.
//
// Backend expectations:
//   methods: memory.timeline.list, memory.timeline.search, memory.timeline.add
//   events:  memory.timeline.event (pushed when new events are recorded)

@Observable
@MainActor
final class MemoryTimelineStore {

    // MARK: - Observable State

    private(set) var events: [MemoryTimelineEvent] = []
    private(set) var relationships: [EventRelationship] = []
    private(set) var searchResults: [MemoryTimelineEvent] = []
    private(set) var isLoading: Bool = false
    private(set) var isSearching: Bool = false
    private(set) var hasMore: Bool = true
    private(set) var loadError: Error?
    private(set) var currentQuery: String = ""
    private(set) var selectedCategory: EventCategory? = nil

    // MARK: - Computed

    var filteredEvents: [MemoryTimelineEvent] {
        if !currentQuery.isEmpty { return searchResults }
        guard let cat = selectedCategory else { return events }
        return events.filter { $0.category == cat }
    }

    var graphSnapshot: KnowledgeGraphSnapshot {
        KnowledgeGraphSnapshot(
            events: events,
            relationships: relationships,
            generatedAt: Date()
        )
    }

    var bookmarkedEvents: [MemoryTimelineEvent] {
        events.filter { $0.isBookmarked }
    }

    // MARK: - Config

    private let pageSize: Int = 50

    // MARK: - Private

    private let client: GatewayClient
    private var currentOffset: Int = 0
    nonisolated(unsafe) private var searchTask: Task<Void, Never>?
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
        startEventSubscription()
    }

    deinit {
        searchTask?.cancel()
        eventTask?.cancel()
    }

    // MARK: - Load

    func reload() async {
        if AppReviewSampleData.isEnabled {
            loadAppReviewSampleData()
            return
        }

        isLoading = true
        loadError = nil
        currentOffset = 0
        hasMore = true
        defer { isLoading = false }

        guard let payload = try? await client.send(
            method: GatewayMethod.memoryTimelineList,
            params: TimelineListParams(limit: pageSize, offset: 0, category: selectedCategory?.rawValue)
        ) else {
            // Backend unavailable → show preview
            events = MemoryTimelineEvent.previewEvents
            relationships = MemoryTimelineEvent.previewRelationships
            return
        }

        let parsed = parseEventsPayload(payload)
        events = parsed
        currentOffset = parsed.count
        hasMore = parsed.count >= pageSize

        if let relArr = payload["relationships"], case .array(let rels) = relArr {
            relationships = rels.compactMap { parseRelationship($0) }
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let payload = try? await client.send(
            method: GatewayMethod.memoryTimelineList,
            params: TimelineListParams(limit: pageSize, offset: currentOffset, category: selectedCategory?.rawValue)
        ) else { return }

        let parsed = parseEventsPayload(payload)
        events.append(contentsOf: parsed)
        currentOffset += parsed.count
        hasMore = parsed.count >= pageSize
    }

    // MARK: - App Review sample data

    func loadAppReviewSampleData() {
        events = MemoryTimelineEvent.previewEvents.map { event in
            var copy = event
            if copy.source.contains("github") { copy.source = "release-system" }
            copy.summary = copy.summary.replacingOccurrences(of: " via GitHub Actions", with: "")
            return copy
        }
        relationships = MemoryTimelineEvent.previewRelationships
        searchResults = []
        currentQuery = ""
        currentOffset = events.count
        hasMore = false
        loadError = nil
    }

    // MARK: - Search

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

        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.client.send(
                    method: GatewayMethod.memoryTimelineSearch,
                    params: TimelineSearchParams(query: trimmed, limit: 50)
                )
                if Task.isCancelled { return }
                let parsed = self.parseEventsPayload(payload)
                if self.currentQuery == trimmed {
                    self.searchResults = parsed
                    self.isSearching = false
                }
            } catch {
                if Task.isCancelled { return }
                // Fallback: local filter
                let lower = trimmed.lowercased()
                self.searchResults = self.events.filter {
                    $0.title.lowercased().contains(lower) ||
                    $0.summary.lowercased().contains(lower) ||
                    $0.tags.contains { $0.lowercased().contains(lower) }
                }
                self.isSearching = false
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        currentQuery = ""
        searchResults = []
        isSearching = false
    }

    // MARK: - Category Filter

    func setCategory(_ category: EventCategory?) {
        selectedCategory = category
        clearSearch()
    }

    // MARK: - Bookmark

    func toggleBookmark(_ id: String) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        events[idx].isBookmarked.toggle()
        // In a full implementation: persist to gateway or local storage
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
        guard event.name == GatewayEventName.memoryTimelineEvent else { return }
        if let newEvent = parseEvent(.object(event.payload)) {
            // Insert in chronological-descending order
            if let idx = events.firstIndex(where: { $0.timestamp < newEvent.timestamp }) {
                events.insert(newEvent, at: idx)
            } else {
                events.append(newEvent)
            }
        }
    }

    // MARK: - Parsing

    private func parseEventsPayload(_ payload: [String: JSONValue]) -> [MemoryTimelineEvent] {
        let arr: [JSONValue]
        if let v = payload["events"], case .array(let a) = v { arr = a }
        else if let v = payload["items"], case .array(let a) = v { arr = a }
        else if let v = payload["results"], case .array(let a) = v { arr = a }
        else { return [] }
        return arr.compactMap { parseEvent($0) }
    }

    private func parseEvent(_ value: JSONValue) -> MemoryTimelineEvent? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal else { return nil }

        let title: String
        if let v = obj["title"], case .string(let s) = v { title = s } else { title = "" }

        let summary: String
        if let v = obj["summary"], case .string(let s) = v { summary = s }
        else if let v = obj["description"], case .string(let s) = v { summary = s }
        else { summary = "" }

        let category: EventCategory
        if let v = obj["category"], case .string(let s) = v {
            category = EventCategory(rawValue: s) ?? .other
        } else { category = .other }

        let severity: EventSeverity
        if let v = obj["severity"], case .string(let s) = v {
            severity = EventSeverity(rawValue: s) ?? .info
        } else { severity = .info }

        let timestamp: Date
        if let ts = dateFromValue(obj["timestamp"]) { timestamp = ts }
        else if let ts = dateFromValue(obj["createdAt"]) { timestamp = ts }
        else { timestamp = Date() }

        let source: String?
        if let v = obj["source"], case .string(let s) = v { source = s } else { source = nil }

        var tags: [String] = []
        if let v = obj["tags"], case .array(let arr) = v {
            tags = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }

        var relatedIds: [String] = []
        if let v = obj["relatedEventIds"], case .array(let arr) = v {
            relatedIds = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }

        let sessionId: String?
        if let v = obj["sessionId"], case .string(let s) = v { sessionId = s } else { sessionId = nil }

        let isBookmarked: Bool
        if let v = obj["isBookmarked"], case .bool(let b) = v { isBookmarked = b } else { isBookmarked = false }

        return MemoryTimelineEvent(
            id: id,
            title: title,
            summary: summary,
            category: category,
            severity: severity,
            timestamp: timestamp,
            source: source,
            tags: tags,
            relatedEventIds: relatedIds,
            sessionId: sessionId,
            resolvedEventId: nil,
            metadata: [:],
            isBookmarked: isBookmarked
        )
    }

    private func parseRelationship(_ value: JSONValue) -> EventRelationship? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal,
              let fromVal = obj["fromEventId"], case .string(let from) = fromVal,
              let toVal = obj["toEventId"], case .string(let to) = toVal else { return nil }

        let kind: EventRelationship.RelationshipKind
        if let v = obj["kind"], case .string(let s) = v {
            kind = EventRelationship.RelationshipKind(rawValue: s) ?? .related
        } else { kind = .related }

        return EventRelationship(id: id, fromEventId: from, toEventId: to, kind: kind)
    }

    private func dateFromValue(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }
        switch value {
        case .int(let ms):    return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        case .double(let ms): return Date(timeIntervalSince1970: ms / 1000.0)
        case .string(let s):
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        default: return nil
        }
    }
}

// MARK: - Param Types

private struct TimelineListParams: Encodable {
    let limit: Int
    let offset: Int
    let category: String?
}

private struct TimelineSearchParams: Encodable {
    let query: String
    let limit: Int
}
