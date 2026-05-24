import Foundation
import SwiftUI

// MARK: - Infrastructure Node Kind

/// All infrastructure node types the topology graph can represent.
enum InfraNodeKind: String, Codable, CaseIterable, Identifiable {
    // Compute
    case ec2           = "ec2"
    case container     = "container"
    case kubernetes    = "kubernetes"
    case lambda        = "lambda"
    // Data
    case rds           = "rds"
    case redis         = "redis"
    case queue         = "queue"
    case nats          = "nats"
    case s3            = "s3"
    // Services
    case service       = "service"
    case api           = "api"
    case loadBalancer  = "loadBalancer"
    // CI/CD & Monitoring
    case githubActions = "githubActions"
    case datadogAlert  = "datadogAlert"
    // Agents & Platform
    case agent         = "agent"
    case gateway       = "gateway"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ec2:           return "server.rack"
        case .container:     return "cube"
        case .kubernetes:    return "square.grid.3x3"
        case .lambda:        return "bolt.fill"
        case .rds:           return "cylinder.fill"
        case .redis:         return "bolt.horizontal.circle.fill"
        case .queue:         return "list.bullet.rectangle"
        case .nats:          return "network"
        case .s3:            return "archivebox.fill"
        case .service:       return "gearshape.fill"
        case .api:           return "arrow.left.arrow.right"
        case .loadBalancer:  return "point.3.connected.trianglepath.dotted"
        case .githubActions: return "arrow.triangle.2.circlepath"
        case .datadogAlert:  return "exclamationmark.triangle.fill"
        case .agent:         return "cpu"
        case .gateway:       return "antenna.radiowaves.left.and.right"
        }
    }

    var label: String {
        switch self {
        case .ec2:           return "EC2"
        case .container:     return "Container"
        case .kubernetes:    return "Kubernetes"
        case .lambda:        return "Lambda"
        case .rds:           return "RDS"
        case .redis:         return "Redis"
        case .queue:         return "Queue"
        case .nats:          return "NATS"
        case .s3:            return "S3"
        case .service:       return "Service"
        case .api:           return "API"
        case .loadBalancer:  return "Load Balancer"
        case .githubActions: return "GitHub Actions"
        case .datadogAlert:  return "Datadog Alert"
        case .agent:         return "Agent"
        case .gateway:       return "Gateway"
        }
    }

    var accentColor: Color {
        switch self {
        case .ec2:           return Color(infraHex: 0xff9900)
        case .container:     return Color(infraHex: 0x2496ed)
        case .kubernetes:    return Color(infraHex: 0x326ce5)
        case .lambda:        return Color(infraHex: 0xff9900)
        case .rds:           return Color(infraHex: 0x527fff)
        case .redis:         return Color(infraHex: 0xdc382d)
        case .queue:         return Color(infraHex: 0xa855f7)
        case .nats:          return Color(infraHex: 0x27aae1)
        case .s3:            return Color(infraHex: 0x569a31)
        case .service:       return .clawTeal
        case .api:           return Color(infraHex: 0x00d4aa)
        case .loadBalancer:  return Color(infraHex: 0x8d63f5)
        case .githubActions: return Color(infraHex: 0x888888)
        case .datadogAlert:  return .clawDanger
        case .agent:         return .clawAccent
        case .gateway:       return .clawTeal
        }
    }
}

// Private hex helper used only within InfraGraph module
private extension Color {
    init(infraHex hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Health Status

enum InfraHealth: String, Codable, Equatable {
    case ok       = "ok"
    case degraded = "degraded"
    case down     = "down"
    case unknown  = "unknown"

    var color: Color {
        switch self {
        case .ok:       return .clawOk
        case .degraded: return .clawWarn
        case .down:     return .clawDanger
        case .unknown:  return .clawMuted
        }
    }

    var label: String {
        switch self {
        case .ok:       return "Healthy"
        case .degraded: return "Degraded"
        case .down:     return "Down"
        case .unknown:  return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .ok:       return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .down:     return "xmark.circle.fill"
        case .unknown:  return "questionmark.circle"
        }
    }
}

// MARK: - Infra Node

struct InfraNode: Identifiable, Hashable, Codable {
    let id: String
    var kind: InfraNodeKind
    var label: String
    var group: String?          // cluster/namespace/region
    var health: InfraHealth

    // Position in graph canvas — normalized 0..1 coords scaled to canvas size
    var posX: Double
    var posY: Double

    // Kind-specific metrics (all optional)
    var cpuPercent: Double?
    var memPercent: Double?
    var errorRate: Double?      // fraction 0..1 of requests failing
    var requestRate: Double?    // requests / second
    var queueDepth: Int?
    var instanceCount: Int?
    var version: String?
    var region: String?
    var tags: [String: String]

    // Impact / risk
    var impactScore: Int?       // 0–100: fraction of infra that depends on this
    var incidentCount: Int      // active incidents touching this node

    var lastSeenAt: Date?
    var deployedAt: Date?

    init(
        id: String,
        kind: InfraNodeKind,
        label: String,
        group: String? = nil,
        health: InfraHealth = .unknown,
        posX: Double = 0.5,
        posY: Double = 0.5,
        tags: [String: String] = [:],
        incidentCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.group = group
        self.health = health
        self.posX = posX
        self.posY = posY
        self.tags = tags
        self.incidentCount = incidentCount
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: InfraNode, rhs: InfraNode) -> Bool { lhs.id == rhs.id }
}

// MARK: - Infra Edge

struct InfraEdge: Identifiable, Hashable, Codable {
    let id: String
    let fromNodeId: String
    let toNodeId: String
    var kind: EdgeKind
    var health: InfraHealth
    var latencyMs: Double?
    var errorRate: Double?
    var label: String?

    enum EdgeKind: String, Codable {
        case dependency = "dependency"   // A calls B
        case dataFlow   = "dataFlow"     // data flows A→B
        case controls   = "controls"     // A manages B
        case monitors   = "monitors"     // A monitors B
    }

    init(from: String, to: String, kind: EdgeKind = .dependency,
         health: InfraHealth = .ok, label: String? = nil) {
        self.id = "\(from)→\(to):\(kind.rawValue)"
        self.fromNodeId = from
        self.toNodeId = to
        self.kind = kind
        self.health = health
        self.label = label
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: InfraEdge, rhs: InfraEdge) -> Bool { lhs.id == rhs.id }
}

// MARK: - Incident

struct InfraIncident: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var severity: Severity
    var affectedNodeIds: [String]
    var startedAt: Date
    var resolvedAt: Date?
    var source: String?          // "datadog", "pagerduty", "manual"
    var url: String?

    var isActive: Bool { resolvedAt == nil }

    var durationDescription: String {
        let elapsed = (resolvedAt ?? Date()).timeIntervalSince(startedAt)
        if elapsed < 60 { return "<1m" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        return "\(Int(elapsed / 3600))h \(Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }

    enum Severity: String, Codable, Comparable {
        case critical = "critical"
        case high     = "high"
        case medium   = "medium"
        case low      = "low"

        var color: Color {
            switch self {
            case .critical: return .clawDanger
            case .high:     return Color(infraHex: 0xff6600)
            case .medium:   return .clawWarn
            case .low:      return .clawMuted
            }
        }

        var label: String { rawValue.capitalized }

        private var order: Int {
            switch self { case .critical: return 0; case .high: return 1; case .medium: return 2; case .low: return 3 }
        }
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.order < rhs.order }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: InfraIncident, rhs: InfraIncident) -> Bool { lhs.id == rhs.id }
}

// MARK: - Deployment Event

struct DeploymentEvent: Identifiable, Hashable, Codable {
    let id: String
    var service: String
    var version: String
    var environment: String
    var status: DeployStatus
    var deployedAt: Date
    var deployedBy: String?
    var affectedNodeIds: [String]
    var commitSha: String?

    enum DeployStatus: String, Codable {
        case running     = "running"
        case success     = "success"
        case failed      = "failed"
        case rolledBack  = "rolledBack"

        var color: Color {
            switch self {
            case .running:    return .clawWarn
            case .success:    return .clawOk
            case .failed:     return .clawDanger
            case .rolledBack: return .clawMuted
            }
        }

        var label: String {
            switch self {
            case .running:    return "Running"
            case .success:    return "Deployed"
            case .failed:     return "Failed"
            case .rolledBack: return "Rolled back"
            }
        }

        var systemImage: String {
            switch self {
            case .running:    return "arrow.triangle.2.circlepath"
            case .success:    return "checkmark.circle.fill"
            case .failed:     return "xmark.circle.fill"
            case .rolledBack: return "arrow.uturn.backward.circle.fill"
            }
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DeploymentEvent, rhs: DeploymentEvent) -> Bool { lhs.id == rhs.id }
}

// MARK: - InfraGraph

struct InfraGraph: Codable {
    var nodes: [InfraNode]
    var edges: [InfraEdge]
    var incidents: [InfraIncident]
    var deployments: [DeploymentEvent]
    var snapshotAt: Date
    var version: Int

    var nodeMap: [String: InfraNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    var activeIncidents: [InfraIncident] { incidents.filter { $0.isActive } }

    var unhealthyNodes: [InfraNode] { nodes.filter { $0.health != .ok && $0.health != .unknown } }

    /// Edges connecting two known nodes.
    var validEdges: [InfraEdge] {
        let ids = Set(nodes.map(\.id))
        return edges.filter { ids.contains($0.fromNodeId) && ids.contains($0.toNodeId) }
    }

    var nodesByGroup: [String: [InfraNode]] {
        var result: [String: [InfraNode]] = [:]
        for node in nodes {
            result[node.group ?? "_", default: []].append(node)
        }
        return result
    }

    var overallHealth: InfraHealth {
        if nodes.contains(where: { $0.health == .down }) { return .down }
        if nodes.contains(where: { $0.health == .degraded }) { return .degraded }
        if nodes.isEmpty { return .unknown }
        return .ok
    }

    static let empty = InfraGraph(
        nodes: [],
        edges: [],
        incidents: [],
        deployments: [],
        snapshotAt: Date(),
        version: 0
    )

    // MARK: - Rich preview / mock data

    static let preview: InfraGraph = {
        // Build nodes
        var n1  = InfraNode(id: "alb-prod",     kind: .loadBalancer, label: "ALB prod",       group: "us-east-1", health: .ok,       posX: 0.50, posY: 0.06)
        var n2  = InfraNode(id: "api-v1",        kind: .api,          label: "API v1",          group: "us-east-1", health: .ok,       posX: 0.27, posY: 0.17)
        var n3  = InfraNode(id: "api-v2",        kind: .api,          label: "API v2",          group: "us-east-1", health: .degraded, posX: 0.73, posY: 0.17)
        var n4  = InfraNode(id: "k8s-prod",      kind: .kubernetes,   label: "k8s prod",        group: "us-east-1", health: .ok,       posX: 0.22, posY: 0.34)
        var n5  = InfraNode(id: "worker-ec2",    kind: .ec2,          label: "Worker Fleet",    group: "us-east-1", health: .ok,       posX: 0.55, posY: 0.34)
        var n6  = InfraNode(id: "lambda-proc",   kind: .lambda,       label: "EventProcessor",  group: "us-east-1", health: .ok,       posX: 0.84, posY: 0.34)
        var n7  = InfraNode(id: "nats-cluster",  kind: .nats,         label: "NATS Cluster",    group: "us-east-1", health: .ok,       posX: 0.33, posY: 0.51)
        var n8  = InfraNode(id: "sqs-jobs",      kind: .queue,        label: "SQS Jobs",        group: "us-east-1", health: .ok,       posX: 0.67, posY: 0.51)
        var n9  = InfraNode(id: "rds-primary",   kind: .rds,          label: "RDS Primary",     group: "us-east-1", health: .ok,       posX: 0.19, posY: 0.68)
        var n10 = InfraNode(id: "redis-cache",   kind: .redis,        label: "Redis Cache",     group: "us-east-1", health: .ok,       posX: 0.50, posY: 0.68)
        var n11 = InfraNode(id: "rds-replica",   kind: .rds,          label: "RDS Replica",     group: "us-east-1", health: .degraded, posX: 0.81, posY: 0.68, incidentCount: 1)
        var n12 = InfraNode(id: "datadog-alert", kind: .datadogAlert, label: "Datadog: p95↑",   group: "monitoring", health: .down,    posX: 0.14, posY: 0.85, incidentCount: 1)
        var n13 = InfraNode(id: "gh-actions",    kind: .githubActions,label: "GitHub Actions",  group: "ci-cd",      health: .ok,      posX: 0.50, posY: 0.85)
        var n14 = InfraNode(id: "claw-gateway",  kind: .gateway,      label: "Claw Gateway",    group: "agents",     health: .ok,      posX: 0.84, posY: 0.85)

        n1.requestRate = 3200; n1.instanceCount = 2
        n2.requestRate = 2800; n2.errorRate = 0.003
        n3.requestRate = 420;  n3.errorRate = 0.12
        n4.cpuPercent = 61;    n4.memPercent = 74; n4.instanceCount = 12
        n5.cpuPercent = 38;    n5.memPercent = 55; n5.instanceCount = 6; n5.region = "us-east-1"
        n6.requestRate = 180
        n7.queueDepth = 1204;  n7.instanceCount = 3
        n8.queueDepth = 347
        n9.cpuPercent = 45;    n9.memPercent = 62; n9.requestRate = 3800; n9.impactScore = 95
        n10.memPercent = 41;   n10.requestRate = 12000
        n11.cpuPercent = 88;   n11.impactScore = 60
        n13.version = "deploy/v2.4.1"
        n14.instanceCount = 1; n14.requestRate = 24

        let nodes = [n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n11, n12, n13, n14]

        let edges: [InfraEdge] = [
            InfraEdge(from: "alb-prod",     to: "api-v1",       kind: .dependency, health: .ok),
            InfraEdge(from: "alb-prod",     to: "api-v2",       kind: .dependency, health: .degraded),
            InfraEdge(from: "api-v1",       to: "k8s-prod",     kind: .dependency, health: .ok),
            InfraEdge(from: "api-v2",       to: "worker-ec2",   kind: .dependency, health: .degraded),
            InfraEdge(from: "k8s-prod",     to: "nats-cluster", kind: .dataFlow,   health: .ok),
            InfraEdge(from: "worker-ec2",   to: "sqs-jobs",     kind: .dataFlow,   health: .ok),
            InfraEdge(from: "lambda-proc",  to: "sqs-jobs",     kind: .dependency, health: .ok),
            InfraEdge(from: "k8s-prod",     to: "rds-primary",  kind: .dependency, health: .ok),
            InfraEdge(from: "k8s-prod",     to: "redis-cache",  kind: .dependency, health: .ok),
            InfraEdge(from: "worker-ec2",   to: "rds-primary",  kind: .dependency, health: .ok),
            InfraEdge(from: "rds-primary",  to: "rds-replica",  kind: .dataFlow,   health: .degraded),
            InfraEdge(from: "datadog-alert",to: "rds-replica",  kind: .monitors,   health: .down),
            InfraEdge(from: "gh-actions",   to: "k8s-prod",     kind: .controls,   health: .ok),
            InfraEdge(from: "claw-gateway", to: "k8s-prod",     kind: .monitors,   health: .ok),
            InfraEdge(from: "claw-gateway", to: "rds-primary",  kind: .monitors,   health: .ok),
        ]

        let incidents: [InfraIncident] = [
            InfraIncident(
                id: "inc-1",
                title: "RDS Replica CPU > 85%",
                severity: .high,
                affectedNodeIds: ["rds-replica", "datadog-alert"],
                startedAt: Date().addingTimeInterval(-1800),
                source: "datadog"
            ),
            InfraIncident(
                id: "inc-2",
                title: "API v2 error rate elevated (12%)",
                severity: .medium,
                affectedNodeIds: ["api-v2"],
                startedAt: Date().addingTimeInterval(-600),
                source: "datadog"
            ),
        ]

        let deployments: [DeploymentEvent] = [
            DeploymentEvent(
                id: "dep-1",
                service: "api-v2",
                version: "2.4.1",
                environment: "prod",
                status: .success,
                deployedAt: Date().addingTimeInterval(-3600),
                deployedBy: "ci-bot",
                affectedNodeIds: ["api-v2"],
                commitSha: "a1b2c3d"
            ),
            DeploymentEvent(
                id: "dep-2",
                service: "worker",
                version: "1.9.3",
                environment: "prod",
                status: .running,
                deployedAt: Date().addingTimeInterval(-120),
                deployedBy: "drumshadow",
                affectedNodeIds: ["worker-ec2"],
                commitSha: "f4e5d6c"
            ),
            DeploymentEvent(
                id: "dep-3",
                service: "k8s-prod",
                version: "chart-3.1.0",
                environment: "prod",
                status: .success,
                deployedAt: Date().addingTimeInterval(-86400),
                deployedBy: "ci-bot",
                affectedNodeIds: ["k8s-prod"],
                commitSha: "d7e8f9a"
            ),
        ]

        return InfraGraph(
            nodes: nodes,
            edges: edges,
            incidents: incidents,
            deployments: deployments,
            snapshotAt: Date(),
            version: 1
        )
    }()
}
