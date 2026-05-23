import Foundation

// MARK: - HomeIntegration
//
// Entry in the personal/home integration registry.
// Gateway contract:
//   - List:   GatewayMethod.homeIntegrationsList  → { integrations: [HomeIntegration] }
//   - Toggle: GatewayMethod.homeIntegrationToggle → { id, enabled }
//   - Sync:   GatewayMethod.homeIntegrationSync   → { id }
//   Event:    GatewayEventName.homeIntegrationStatusChange

struct HomeIntegration: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: IntegrationKind
    var isEnabled: Bool
    var connectionStatus: IntegrationConnectionStatus
    var lastSyncAt: Date?
    var capabilities: [IntegrationCapability]
    var endpoint: String?           // URL or local path
    var description: String
    var authMethod: AuthMethod?
    var metadata: [String: String]  // flexible config storage
}

// MARK: - IntegrationKind

enum IntegrationKind: String, CaseIterable, Identifiable, Hashable {
    case homeAssistant  = "home_assistant"
    case appleReminders = "apple_reminders"
    case appleCalendar  = "apple_calendar"
    case groceries      = "groceries"
    case notion         = "notion"
    case obsidian       = "obsidian"
    case todoist        = "todoist"
    case appleHealth    = "apple_health"
    case weather        = "weather"
    case custom         = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .homeAssistant:  return "Home Assistant"
        case .appleReminders: return "Reminders"
        case .appleCalendar:  return "Calendar"
        case .groceries:      return "Groceries"
        case .notion:         return "Notion"
        case .obsidian:       return "Obsidian"
        case .todoist:        return "Todoist"
        case .appleHealth:    return "Health"
        case .weather:        return "Weather"
        case .custom:         return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .homeAssistant:  return "house.fill"
        case .appleReminders: return "checklist"
        case .appleCalendar:  return "calendar"
        case .groceries:      return "cart.fill"
        case .notion:         return "doc.fill"
        case .obsidian:       return "diamond.fill"
        case .todoist:        return "checkmark.circle.fill"
        case .appleHealth:    return "heart.fill"
        case .weather:        return "cloud.sun.fill"
        case .custom:         return "plug.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .homeAssistant:  return "038fc7"
        case .appleReminders: return "ff5c5c"
        case .appleCalendar:  return "3b82f6"
        case .groceries:      return "22c55e"
        case .notion:         return "d4d4d8"
        case .obsidian:       return "8b5cf6"
        case .todoist:        return "ef4444"
        case .appleHealth:    return "ec4899"
        case .weather:        return "f59e0b"
        case .custom:         return "838387"
        }
    }
}

// MARK: - IntegrationConnectionStatus

enum IntegrationConnectionStatus: String, Hashable {
    case connected    = "connected"
    case disconnected = "disconnected"
    case syncing      = "syncing"
    case error        = "error"
    case unconfigured = "unconfigured"

    var displayName: String {
        switch self {
        case .connected:    return "Connected"
        case .disconnected: return "Disconnected"
        case .syncing:      return "Syncing…"
        case .error:        return "Error"
        case .unconfigured: return "Not configured"
        }
    }

    var isActive: Bool { self == .connected || self == .syncing }
}

// MARK: - IntegrationCapability

enum IntegrationCapability: String, CaseIterable, Hashable {
    case read     = "read"
    case write    = "write"
    case notify   = "notify"
    case automate = "automate"
    case listen   = "listen"

    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .read:     return "eye"
        case .write:    return "pencil"
        case .notify:   return "bell"
        case .automate: return "cpu"
        case .listen:   return "ear"
        }
    }
}

// MARK: - AuthMethod

enum AuthMethod: String, Hashable {
    case apiKey    = "api_key"
    case oauth     = "oauth"
    case localOnly = "local_only"  // e.g. Apple Reminders — just a permission
    case webhook   = "webhook"
    case password  = "password"
}

// MARK: - HomeTask
//
// A household or personal task that can be assigned to an AI agent.
// Gateway contract:
//   - List:   GatewayMethod.homeTasksList   → { tasks: [HomeTask] }
//   - Create: GatewayMethod.homeTasksCreate → HomeTask
//   - Update: GatewayMethod.homeTasksUpdate → HomeTask
//   Event:    GatewayEventName.homeTaskCreated, homeTaskUpdated

struct HomeTask: Identifiable, Hashable {
    let id: String
    var title: String
    var description: String?
    var status: HomeTaskStatus
    var priority: HomeTaskPriority
    var dueDate: Date?
    var integrationId: String?   // linked integration (e.g. Reminders)
    var externalId: String?      // ID in external system
    var assignedToAgent: Bool
    var agentSessionId: String?
    var createdAt: Date
    var completedAt: Date?
    var tags: [String]
}

// MARK: - HomeTaskStatus

enum HomeTaskStatus: String, CaseIterable, Hashable {
    case pending    = "pending"
    case inProgress = "in_progress"
    case done       = "done"
    case cancelled  = "cancelled"

    var displayName: String {
        switch self {
        case .pending:    return "Pending"
        case .inProgress: return "In Progress"
        case .done:       return "Done"
        case .cancelled:  return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:    return "circle"
        case .inProgress: return "circle.dotted"
        case .done:       return "checkmark.circle.fill"
        case .cancelled:  return "minus.circle"
        }
    }
}

// MARK: - HomeTaskPriority

enum HomeTaskPriority: String, CaseIterable, Hashable {
    case low    = "low"
    case normal = "normal"
    case high   = "high"
    case urgent = "urgent"

    var displayName: String { rawValue.capitalized }

    var colorHex: String {
        switch self {
        case .low:    return "838387"
        case .normal: return "3b82f6"
        case .high:   return "f59e0b"
        case .urgent: return "ef4444"
        }
    }
}

// MARK: - GroceryItem
//
// Gateway contract:
//   - List:   GatewayMethod.homeGroceriesList   → { items: [GroceryItem], lists: [GroceryList] }
//   - Create: GatewayMethod.homeGroceriesCreate → GroceryItem
//   - Update: GatewayMethod.homeGroceriesUpdate → { id, isBought }

struct GroceryItem: Identifiable, Hashable {
    let id: String
    var name: String
    var quantity: String?
    var category: GroceryCategory
    var isBought: Bool
    var listId: String
    var addedAt: Date
    var notes: String?
    var addedByAgent: Bool
}

// MARK: - GroceryCategory

enum GroceryCategory: String, CaseIterable, Hashable {
    case produce   = "produce"
    case dairy     = "dairy"
    case meat      = "meat"
    case bakery    = "bakery"
    case frozen    = "frozen"
    case pantry    = "pantry"
    case beverage  = "beverage"
    case household = "household"
    case other     = "other"

    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .produce:   return "leaf"
        case .dairy:     return "drop"
        case .meat:      return "flame"
        case .bakery:    return "bag"
        case .frozen:    return "snowflake"
        case .pantry:    return "cabinet"
        case .beverage:  return "cup.and.saucer"
        case .household: return "house"
        case .other:     return "ellipsis"
        }
    }
}

// MARK: - GroceryList

struct GroceryList: Identifiable, Hashable {
    let id: String
    var name: String
    var items: [GroceryItem]
    var createdAt: Date
    var integrationId: String?

    var unboughtCount: Int { items.filter { !$0.isBought }.count }
    var boughtCount: Int { items.filter { $0.isBought }.count }
}

// MARK: - Preview Data

extension HomeIntegration {
    static let previewIntegrations: [HomeIntegration] = [
        HomeIntegration(
            id: "int-ha",
            name: "Home Assistant",
            kind: .homeAssistant,
            isEnabled: true,
            connectionStatus: .connected,
            lastSyncAt: Date().addingTimeInterval(-300),
            capabilities: [.read, .write, .automate, .listen],
            endpoint: "http://homeassistant.local:8123",
            description: "Control smart home devices and automations",
            authMethod: .apiKey,
            metadata: ["version": "2024.5.0"]
        ),
        HomeIntegration(
            id: "int-rem",
            name: "Reminders",
            kind: .appleReminders,
            isEnabled: true,
            connectionStatus: .connected,
            lastSyncAt: Date().addingTimeInterval(-60),
            capabilities: [.read, .write],
            endpoint: nil,
            description: "Sync with Apple Reminders",
            authMethod: .localOnly,
            metadata: [:]
        ),
        HomeIntegration(
            id: "int-gro",
            name: "Groceries",
            kind: .groceries,
            isEnabled: true,
            connectionStatus: .connected,
            lastSyncAt: Date().addingTimeInterval(-1800),
            capabilities: [.read, .write],
            endpoint: nil,
            description: "AI-assisted grocery list management",
            authMethod: .localOnly,
            metadata: [:]
        ),
        HomeIntegration(
            id: "int-cal",
            name: "Calendar",
            kind: .appleCalendar,
            isEnabled: true,
            connectionStatus: .connected,
            lastSyncAt: Date().addingTimeInterval(-120),
            capabilities: [.read],
            endpoint: nil,
            description: "Read-only calendar context for scheduling",
            authMethod: .localOnly,
            metadata: [:]
        ),
        HomeIntegration(
            id: "int-not",
            name: "Notion",
            kind: .notion,
            isEnabled: false,
            connectionStatus: .unconfigured,
            lastSyncAt: nil,
            capabilities: [.read, .write],
            endpoint: nil,
            description: "Sync notes and databases with Notion",
            authMethod: .oauth,
            metadata: [:]
        ),
    ]
}

extension GroceryList {
    static let previewList = GroceryList(
        id: "list-1",
        name: "This Week",
        items: [
            GroceryItem(id: "g1", name: "Oat milk", quantity: "2 cartons", category: .dairy, isBought: false, listId: "list-1", addedAt: Date().addingTimeInterval(-3600), notes: nil, addedByAgent: false),
            GroceryItem(id: "g2", name: "Sourdough bread", quantity: "1 loaf", category: .bakery, isBought: false, listId: "list-1", addedAt: Date().addingTimeInterval(-3600), notes: nil, addedByAgent: false),
            GroceryItem(id: "g3", name: "Avocados", quantity: "4", category: .produce, isBought: true, listId: "list-1", addedAt: Date().addingTimeInterval(-7200), notes: nil, addedByAgent: false),
            GroceryItem(id: "g4", name: "Greek yogurt", quantity: "1 tub", category: .dairy, isBought: false, listId: "list-1", addedAt: Date().addingTimeInterval(-1800), notes: "Full fat", addedByAgent: false),
            GroceryItem(id: "g5", name: "Salmon fillets", quantity: "2 lbs", category: .meat, isBought: false, listId: "list-1", addedAt: Date().addingTimeInterval(-900), notes: nil, addedByAgent: true),
            GroceryItem(id: "g6", name: "Dish soap", quantity: nil, category: .household, isBought: false, listId: "list-1", addedAt: Date().addingTimeInterval(-600), notes: nil, addedByAgent: true),
        ],
        createdAt: Date().addingTimeInterval(-7200),
        integrationId: "int-gro"
    )
}

extension HomeTask {
    static let previewTasks: [HomeTask] = [
        HomeTask(
            id: "task-1",
            title: "Review home insurance renewal",
            description: "Policy expires June 15. Compare with 3 alternatives.",
            status: .pending,
            priority: .high,
            dueDate: Date().addingTimeInterval(86400 * 3),
            integrationId: "int-rem",
            externalId: nil,
            assignedToAgent: true,
            agentSessionId: nil,
            createdAt: Date().addingTimeInterval(-86400),
            completedAt: nil,
            tags: ["finance", "insurance"]
        ),
        HomeTask(
            id: "task-2",
            title: "Schedule HVAC service",
            description: "Annual maintenance before summer",
            status: .inProgress,
            priority: .normal,
            dueDate: Date().addingTimeInterval(86400 * 14),
            integrationId: "int-rem",
            externalId: nil,
            assignedToAgent: true,
            agentSessionId: "session-def",
            createdAt: Date().addingTimeInterval(-3600),
            completedAt: nil,
            tags: ["home", "maintenance"]
        ),
        HomeTask(
            id: "task-3",
            title: "Order birthday gift for Mom",
            description: nil,
            status: .done,
            priority: .urgent,
            dueDate: Date().addingTimeInterval(-86400),
            integrationId: nil,
            externalId: nil,
            assignedToAgent: false,
            agentSessionId: nil,
            createdAt: Date().addingTimeInterval(-86400 * 3),
            completedAt: Date().addingTimeInterval(-86400 * 2),
            tags: ["family"]
        ),
    ]
}
