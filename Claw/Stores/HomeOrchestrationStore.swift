import Foundation

// MARK: - HomeOrchestrationStore
//
// Manages personal integrations (Home Assistant, Reminders, Calendar, Groceries, etc.),
// household tasks, and grocery lists.
//
// Backend expectations:
//   methods: home.integrations.list, home.integration.create, home.integration.toggle, home.integration.sync,
//            home.tasks.list, home.tasks.create, home.tasks.update,
//            home.groceries.list, home.groceries.create, home.groceries.update
//   events:  home.integration.status, home.task.created, home.task.updated

@Observable
@MainActor
final class HomeOrchestrationStore {

    // MARK: - Observable State

    private(set) var integrations: [HomeIntegration] = []
    private(set) var tasks: [HomeTask] = []
    private(set) var groceryLists: [GroceryList] = []
    private(set) var isLoading: Bool = false
    private(set) var isSyncing: String? = nil  // integration ID currently syncing
    private(set) var loadError: Error?

    // MARK: - Computed

    var activeIntegrations: [HomeIntegration] { integrations.filter { $0.isEnabled } }
    var connectedCount: Int { integrations.filter { $0.connectionStatus.isActive }.count }
    var pendingTasks: [HomeTask] { tasks.filter { $0.status == .pending || $0.status == .inProgress } }
    var doneTasks: [HomeTask] { tasks.filter { $0.status == .done } }
    var agentTasks: [HomeTask] { tasks.filter { $0.assignedToAgent } }

    var primaryGroceryList: GroceryList? { groceryLists.first }

    var unreadTaskCount: Int { pendingTasks.count }

    // MARK: - Private

    private let client: GatewayClient
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
        if !AppReviewSampleData.isEnabled { startEventSubscription() }
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Load

    func loadAll() async {
        if AppReviewSampleData.isEnabled {
            loadAppReviewSampleData()
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        async let intLoad: Void = loadIntegrations()
        async let taskLoad: Void = loadTasks()
        async let grocLoad: Void = loadGroceries()
        _ = await (intLoad, taskLoad, grocLoad)
    }

    private func loadIntegrations() async {
        guard let payload = try? await client.send(
            method: GatewayMethod.homeIntegrationsList,
            params: EmptyParams()
        ) else {
            integrations = []
            return
        }

        if let arr = payload["integrations"], case .array(let items) = arr {
            integrations = items.compactMap { parseIntegration($0) }
        } else {
            integrations = []
        }
    }

    private func loadTasks() async {
        guard let payload = try? await client.send(
            method: GatewayMethod.homeTasksList,
            params: EmptyParams()
        ) else {
            tasks = []
            return
        }

        if let arr = payload["tasks"], case .array(let items) = arr {
            tasks = items.compactMap { parseTask($0) }
                .sorted { $0.createdAt > $1.createdAt }
        } else {
            tasks = []
        }
    }

    private func loadGroceries() async {
        guard let payload = try? await client.send(
            method: GatewayMethod.homeGroceriesList,
            params: EmptyParams()
        ) else {
            groceryLists = []
            return
        }

        if let arr = payload["lists"], case .array(let items) = arr {
            groceryLists = items.compactMap { parseGroceryList($0) }
        } else if let arr = payload["items"], case .array(let items) = arr {
            // Flat list → wrap in default list
            let parsed = items.compactMap { parseGroceryItem($0, listId: "default") }
            groceryLists = [GroceryList(
                id: "default",
                name: "Groceries",
                items: parsed,
                createdAt: Date(),
                integrationId: nil
            )]
        } else {
            groceryLists = []
        }
    }

    // MARK: - App Review sample data

    func loadAppReviewSampleData() {
        eventTask?.cancel()
        eventTask = nil
        integrations = AppReviewSampleData.homeIntegrations
        tasks = AppReviewSampleData.homeTasks
        groceryLists = AppReviewSampleData.groceryLists
        isLoading = false
        isSyncing = nil
        loadError = nil
    }

    // MARK: - Integration Actions

    func toggleIntegration(_ id: String) async {
        guard let idx = integrations.firstIndex(where: { $0.id == id }) else { return }
        let newEnabled = !integrations[idx].isEnabled
        integrations[idx].isEnabled = newEnabled

        struct ToggleParams: Encodable { let id: String; let enabled: Bool }
        _ = try? await client.send(
            method: GatewayMethod.homeIntegrationToggle,
            params: ToggleParams(id: id, enabled: newEnabled)
        )
    }

    func syncIntegration(_ id: String) async {
        guard let idx = integrations.firstIndex(where: { $0.id == id }) else { return }
        integrations[idx].connectionStatus = .syncing
        isSyncing = id
        defer {
            if isSyncing == id { isSyncing = nil }
        }

        struct IdParams: Encodable { let id: String }
        if let _ = try? await client.send(
            method: GatewayMethod.homeIntegrationSync,
            params: IdParams(id: id)
        ) {
            integrations[idx].connectionStatus = .connected
            integrations[idx].lastSyncAt = Date()
        } else {
            integrations[idx].connectionStatus = .connected // optimistic
            integrations[idx].lastSyncAt = Date()
        }
    }

    func createCustomIntegration(name: String, endpoint: String?, description: String, capabilities: Set<IntegrationCapability>) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let integration = HomeIntegration(
            id: "custom-\(UUID().uuidString)",
            name: trimmedName,
            kind: .custom,
            isEnabled: true,
            connectionStatus: .unconfigured,
            lastSyncAt: nil,
            capabilities: Array(capabilities).sorted { $0.rawValue < $1.rawValue },
            endpoint: endpoint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: nil,
            metadata: [:]
        )
        integrations.insert(integration, at: 0)

        struct CreateParams: Encodable {
            let name: String
            let kind: String
            let endpoint: String?
            let description: String
            let capabilities: [String]
            let enabled: Bool
        }

        if let payload = try? await client.send(
            method: GatewayMethod.homeIntegrationCreate,
            params: CreateParams(
                name: integration.name,
                kind: integration.kind.rawValue,
                endpoint: integration.endpoint,
                description: integration.description,
                capabilities: integration.capabilities.map(\.rawValue),
                enabled: integration.isEnabled
            )
        ),
           let created = parseCreatedIntegration(payload),
           let idx = integrations.firstIndex(where: { $0.id == integration.id }) {
            integrations[idx] = created
        }
    }

    // MARK: - Task Actions

    func createTask(title: String, description: String?, priority: HomeTaskPriority, dueDate: Date?, assignToAgent: Bool) async {
        let tempId = UUID().uuidString
        let task = HomeTask(
            id: tempId,
            title: title,
            description: description,
            status: .pending,
            priority: priority,
            dueDate: dueDate,
            integrationId: nil,
            externalId: nil,
            assignedToAgent: assignToAgent,
            agentSessionId: nil,
            createdAt: Date(),
            completedAt: nil,
            tags: []
        )
        tasks.insert(task, at: 0)

        struct CreateParams: Encodable {
            let title: String
            let description: String?
            let priority: String
            let assignToAgent: Bool
        }
        _ = try? await client.send(
            method: GatewayMethod.homeTasksCreate,
            params: CreateParams(title: title, description: description, priority: priority.rawValue, assignToAgent: assignToAgent)
        )
    }

    func updateTaskStatus(_ id: String, status: HomeTaskStatus) async {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].status = status
        if status == .done { tasks[idx].completedAt = Date() }

        struct UpdateParams: Encodable { let id: String; let status: String }
        _ = try? await client.send(
            method: GatewayMethod.homeTasksUpdate,
            params: UpdateParams(id: id, status: status.rawValue)
        )
    }

    // MARK: - Grocery Actions

    func toggleGroceryItem(listId: String, itemId: String) async {
        guard let listIdx = groceryLists.firstIndex(where: { $0.id == listId }),
              let itemIdx = groceryLists[listIdx].items.firstIndex(where: { $0.id == itemId }) else { return }

        let newBought = !groceryLists[listIdx].items[itemIdx].isBought
        groceryLists[listIdx].items[itemIdx].isBought = newBought

        struct UpdateParams: Encodable { let id: String; let isBought: Bool }
        _ = try? await client.send(
            method: GatewayMethod.homeGroceriesUpdate,
            params: UpdateParams(id: itemId, isBought: newBought)
        )
    }

    func addGroceryItem(listId: String, name: String, quantity: String?, category: GroceryCategory) async {
        guard let listIdx = groceryLists.firstIndex(where: { $0.id == listId }) else { return }

        let item = GroceryItem(
            id: UUID().uuidString,
            name: name,
            quantity: quantity,
            category: category,
            isBought: false,
            listId: listId,
            addedAt: Date(),
            notes: nil,
            addedByAgent: false
        )
        groceryLists[listIdx].items.insert(item, at: 0)

        struct CreateParams: Encodable {
            let listId: String
            let name: String
            let quantity: String?
            let category: String
        }

        if let payload = try? await client.send(
            method: GatewayMethod.homeGroceriesCreate,
            params: CreateParams(listId: listId, name: name, quantity: quantity, category: category.rawValue)
        ),
           let created = parseCreatedGroceryItem(payload, listId: listId),
           let currentListIdx = groceryLists.firstIndex(where: { $0.id == listId }),
           let tempIdx = groceryLists[currentListIdx].items.firstIndex(where: { $0.id == item.id }) {
            groceryLists[currentListIdx].items[tempIdx] = created
        }
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
        case GatewayEventName.homeIntegrationStatusChange:
            if let idVal = event.payload["id"], case .string(let id) = idVal,
               let statusVal = event.payload["status"], case .string(let statusStr) = statusVal,
               let idx = integrations.firstIndex(where: { $0.id == id }) {
                integrations[idx].connectionStatus = IntegrationConnectionStatus(rawValue: statusStr) ?? .error
            }

        case GatewayEventName.homeTaskCreated:
            if let task = parseTask(.object(event.payload)) {
                if !tasks.contains(where: { $0.id == task.id }) {
                    tasks.insert(task, at: 0)
                }
            }

        case GatewayEventName.homeTaskUpdated:
            if let task = parseTask(.object(event.payload)),
               let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx] = task
            }

        default:
            break
        }
    }

    // MARK: - Parsing

    private func parseIntegration(_ value: JSONValue) -> HomeIntegration? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal else { return nil }

        let name: String
        if let v = obj["name"], case .string(let s) = v { name = s } else { name = id }

        let kindStr: String
        if let v = obj["kind"], case .string(let s) = v { kindStr = s } else { kindStr = "custom" }
        let kind = IntegrationKind(rawValue: kindStr) ?? .custom

        let isEnabled: Bool
        if let v = obj["enabled"], case .bool(let b) = v { isEnabled = b } else { isEnabled = false }

        let statusStr: String
        if let v = obj["status"], case .string(let s) = v { statusStr = s } else { statusStr = "disconnected" }
        let status = IntegrationConnectionStatus(rawValue: statusStr) ?? .disconnected

        let description: String
        if let v = obj["description"], case .string(let s) = v { description = s } else { description = "" }

        return HomeIntegration(
            id: id,
            name: name,
            kind: kind,
            isEnabled: isEnabled,
            connectionStatus: status,
            lastSyncAt: dateFromValue(obj["lastSyncAt"]),
            capabilities: [],
            endpoint: nil,
            description: description,
            authMethod: nil,
            metadata: [:]
        )
    }

    private func parseCreatedIntegration(_ payload: [String: JSONValue]) -> HomeIntegration? {
        if let integration = parseIntegration(.object(payload)) { return integration }
        if let value = payload["integration"] { return parseIntegration(value) }
        return nil
    }

    private func parseTask(_ value: JSONValue) -> HomeTask? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal else { return nil }

        let title: String
        if let v = obj["title"], case .string(let s) = v { title = s } else { title = "" }

        let statusStr: String
        if let v = obj["status"], case .string(let s) = v { statusStr = s } else { statusStr = "pending" }
        let status = HomeTaskStatus(rawValue: statusStr) ?? .pending

        let priorityStr: String
        if let v = obj["priority"], case .string(let s) = v { priorityStr = s } else { priorityStr = "normal" }
        let priority = HomeTaskPriority(rawValue: priorityStr) ?? .normal

        return HomeTask(
            id: id,
            title: title,
            description: nil,
            status: status,
            priority: priority,
            dueDate: dateFromValue(obj["dueDate"]),
            integrationId: nil,
            externalId: nil,
            assignedToAgent: false,
            agentSessionId: nil,
            createdAt: dateFromValue(obj["createdAt"]) ?? Date(),
            completedAt: dateFromValue(obj["completedAt"]),
            tags: []
        )
    }

    private func parseGroceryList(_ value: JSONValue) -> GroceryList? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal else { return nil }

        let name: String
        if let v = obj["name"], case .string(let s) = v { name = s } else { name = "Groceries" }

        var items: [GroceryItem] = []
        if let arr = obj["items"], case .array(let raw) = arr {
            items = raw.compactMap { parseGroceryItem($0, listId: id) }
        }

        return GroceryList(id: id, name: name, items: items, createdAt: Date(), integrationId: nil)
    }

    private func parseGroceryItem(_ value: JSONValue, listId: String) -> GroceryItem? {
        guard case .object(let obj) = value,
              let idVal = obj["id"], case .string(let id) = idVal else { return nil }

        let name: String
        if let v = obj["name"], case .string(let s) = v { name = s } else { name = "" }

        let isBought: Bool
        if let v = obj["isBought"], case .bool(let b) = v { isBought = b } else { isBought = false }

        let catStr: String
        if let v = obj["category"], case .string(let s) = v { catStr = s } else { catStr = "other" }
        let category = GroceryCategory(rawValue: catStr) ?? .other

        let quantity: String?
        if let v = obj["quantity"], case .string(let s) = v { quantity = s } else { quantity = nil }

        return GroceryItem(
            id: id,
            name: name,
            quantity: quantity,
            category: category,
            isBought: isBought,
            listId: listId,
            addedAt: dateFromValue(obj["addedAt"]) ?? Date(),
            notes: nil,
            addedByAgent: false
        )
    }

    private func parseCreatedGroceryItem(_ payload: [String: JSONValue], listId: String) -> GroceryItem? {
        if let item = parseGroceryItem(.object(payload), listId: listId) { return item }
        if let value = payload["item"] { return parseGroceryItem(value, listId: listId) }
        return nil
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

// MARK: - Helpers

private struct EmptyParams: Encodable {}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
