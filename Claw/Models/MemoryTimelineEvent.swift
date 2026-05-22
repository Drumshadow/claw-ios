import Foundation

// MARK: - MemoryTimelineEvent
//
// A persistent event in the agent's knowledge graph / memory timeline.
// Events span system incidents, deploys, conversations, fixes, infra changes,
// skill acquisitions, and raw memory writes.
//
// Gateway contract:
//   - List:   GatewayMethod.memoryTimelineList   → { events: [MemoryTimelineEvent], total: Int }
//   - Search: GatewayMethod.memoryTimelineSearch → { events: [MemoryTimelineEvent] }
//   - Add:    GatewayMethod.memoryTimelineAdd    → MemoryTimelineEvent
//   Event:    GatewayEventName.memoryTimelineEvent (live push from gateway)

struct MemoryTimelineEvent: Identifiable, Hashable {
    let id: String
    var title: String
    var summary: String
    var category: EventCategory
    var severity: EventSeverity
    var timestamp: Date
    var source: String?             // session ID, agent name, or "system"
    var tags: [String]
    var relatedEventIds: [String]
    var sessionId: String?          // session that produced this event
    var resolvedEventId: String?    // event this resolves (fix→incident, etc.)
    var metadata: [String: String]  // flexible key-value annotation
    var isBookmarked: Bool
}

// MARK: - EventCategory

enum EventCategory: String, CaseIterable, Identifiable, Hashable {
    case incident     = "incident"
    case deploy       = "deploy"
    case conversation = "conversation"
    case fix          = "fix"
    case alert        = "alert"
    case infra        = "infra"
    case skill        = "skill"
    case memory       = "memory"
    case other        = "other"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .incident:     return "exclamationmark.triangle.fill"
        case .deploy:       return "arrow.up.circle.fill"
        case .conversation: return "bubble.left.and.bubble.right.fill"
        case .fix:          return "wrench.and.screwdriver.fill"
        case .alert:        return "bell.fill"
        case .infra:        return "server.rack"
        case .skill:        return "bolt.fill"
        case .memory:       return "brain"
        case .other:        return "circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .incident:     return "ef4444"
        case .deploy:       return "22c55e"
        case .conversation: return "3b82f6"
        case .fix:          return "14b8a6"
        case .alert:        return "f59e0b"
        case .infra:        return "8b5cf6"
        case .skill:        return "ff5c5c"
        case .memory:       return "ec4899"
        case .other:        return "838387"
        }
    }
}

// MARK: - EventSeverity

enum EventSeverity: String, CaseIterable, Hashable {
    case info     = "info"
    case low      = "low"
    case medium   = "medium"
    case high     = "high"
    case critical = "critical"

    var displayName: String { rawValue.capitalized }
}

// MARK: - EventRelationship
//
// Directed relationship between two timeline events, forming the knowledge graph edges.

struct EventRelationship: Identifiable, Hashable {
    let id: String
    var fromEventId: String
    var toEventId: String
    var kind: RelationshipKind

    enum RelationshipKind: String, Hashable {
        case caused   = "caused"    // deploy caused incident
        case resolved = "resolved"  // fix resolved incident
        case related  = "related"   // loosely related
        case precedes = "precedes"  // temporal ordering
        case spawned  = "spawned"   // conversation spawned an agent run
    }

    var displayLabel: String {
        switch kind {
        case .caused:   return "caused"
        case .resolved: return "resolved"
        case .related:  return "related to"
        case .precedes: return "before"
        case .spawned:  return "spawned"
        }
    }
}

// MARK: - KnowledgeGraphSnapshot
//
// A windowed snapshot of events and their relationships used for graph rendering.

struct KnowledgeGraphSnapshot {
    var events: [MemoryTimelineEvent]
    var relationships: [EventRelationship]
    var generatedAt: Date

    /// Adjacency list (undirected) for force-layout rendering.
    var adjacencyList: [String: [String]] {
        var adj: [String: [String]] = [:]
        for rel in relationships {
            adj[rel.fromEventId, default: []].append(rel.toEventId)
            adj[rel.toEventId, default: []].append(rel.fromEventId)
        }
        return adj
    }

    /// Degree of each node (number of relationships).
    func degree(of eventId: String) -> Int {
        relationships.filter { $0.fromEventId == eventId || $0.toEventId == eventId }.count
    }
}

// MARK: - Preview Data

extension MemoryTimelineEvent {
    static let previewEvents: [MemoryTimelineEvent] = [
        MemoryTimelineEvent(
            id: "evt-1",
            title: "API Error Spike Detected",
            summary: "Error rate on /api/orders rose to 8.3% for 12 minutes",
            category: .incident,
            severity: .high,
            timestamp: Date().addingTimeInterval(-3600),
            source: "watcher-error-rate",
            tags: ["api", "orders", "errors"],
            relatedEventIds: ["evt-2", "evt-3"],
            sessionId: nil,
            resolvedEventId: nil,
            metadata: ["endpoint": "/api/orders", "errorRate": "8.3%"],
            isBookmarked: true
        ),
        MemoryTimelineEvent(
            id: "evt-2",
            title: "Deploy: backend v2.3.1",
            summary: "Deployed backend service v2.3.1 to production via GitHub Actions",
            category: .deploy,
            severity: .info,
            timestamp: Date().addingTimeInterval(-3900),
            source: "github-webhook",
            tags: ["deploy", "backend", "v2.3.1"],
            relatedEventIds: ["evt-1"],
            sessionId: nil,
            resolvedEventId: nil,
            metadata: ["version": "v2.3.1", "env": "production", "commit": "f83cdc2"],
            isBookmarked: false
        ),
        MemoryTimelineEvent(
            id: "evt-3",
            title: "Rollback: backend v2.3.0",
            summary: "Agent rolled back backend to v2.3.0 to resolve error spike",
            category: .fix,
            severity: .medium,
            timestamp: Date().addingTimeInterval(-3200),
            source: "agent-remediation",
            tags: ["rollback", "backend"],
            relatedEventIds: ["evt-1", "evt-2"],
            sessionId: "session-abc",
            resolvedEventId: "evt-1",
            metadata: ["rollbackTo": "v2.3.0", "durationMs": "2400"],
            isBookmarked: false
        ),
        MemoryTimelineEvent(
            id: "evt-4",
            title: "Skill learned: deploy-rollback",
            summary: "Agent generalized the rollback procedure into a reusable skill",
            category: .skill,
            severity: .info,
            timestamp: Date().addingTimeInterval(-3000),
            source: "agent-learn",
            tags: ["skill", "rollback", "deploy"],
            relatedEventIds: ["evt-3"],
            sessionId: nil,
            resolvedEventId: nil,
            metadata: ["skillName": "deploy-rollback", "skillId": "skill-xyz"],
            isBookmarked: false
        ),
        MemoryTimelineEvent(
            id: "evt-5",
            title: "DB Migration v89",
            summary: "PostgreSQL schema migration v89 applied successfully in 34s",
            category: .infra,
            severity: .info,
            timestamp: Date().addingTimeInterval(-7200),
            source: "system",
            tags: ["db", "migration", "postgres"],
            relatedEventIds: [],
            sessionId: nil,
            resolvedEventId: nil,
            metadata: ["migration": "v89", "db": "postgres", "durationMs": "34000"],
            isBookmarked: false
        ),
        MemoryTimelineEvent(
            id: "evt-6",
            title: "Memory: deployment runbook updated",
            summary: "Agent updated the deployment runbook memory after successful rollback",
            category: .memory,
            severity: .info,
            timestamp: Date().addingTimeInterval(-2800),
            source: "session-abc",
            tags: ["memory", "runbook"],
            relatedEventIds: ["evt-3"],
            sessionId: "session-abc",
            resolvedEventId: nil,
            metadata: ["key": "deployment-runbook"],
            isBookmarked: false
        ),
    ]

    static let previewRelationships: [EventRelationship] = [
        EventRelationship(id: "rel-1", fromEventId: "evt-2", toEventId: "evt-1", kind: .caused),
        EventRelationship(id: "rel-2", fromEventId: "evt-3", toEventId: "evt-1", kind: .resolved),
        EventRelationship(id: "rel-3", fromEventId: "evt-3", toEventId: "evt-4", kind: .spawned),
        EventRelationship(id: "rel-4", fromEventId: "evt-3", toEventId: "evt-6", kind: .spawned),
        EventRelationship(id: "rel-5", fromEventId: "evt-5", toEventId: "evt-2", kind: .precedes),
    ]

    static var previewSnapshot: KnowledgeGraphSnapshot {
        KnowledgeGraphSnapshot(
            events: previewEvents,
            relationships: previewRelationships,
            generatedAt: Date()
        )
    }
}
