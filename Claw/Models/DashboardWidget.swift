import Foundation

// MARK: - Widget Kind

/// All widget types available in Mission Control.
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    // Infrastructure health
    case systemHealth      = "systemHealth"       // overall traffic light + node count
    case incidentList      = "incidentList"        // active incidents
    case deploymentFeed    = "deploymentFeed"      // recent deployments

    // Compute / Cloud
    case ec2Health         = "ec2Health"           // EC2 fleet CPU/mem
    case containerHealth   = "containerHealth"     // K8s / container health
    case lambdaActivity    = "lambdaActivity"      // Lambda invocation rate

    // Data layer
    case rdsMetrics        = "rdsMetrics"          // RDS CPU/connections
    case redisMetrics      = "redisMetrics"        // Redis hit rate / mem

    // Messaging
    case queueDepth        = "queueDepth"          // SQS / NATS queue depths

    // Agent / platform
    case agentActivity     = "agentActivity"       // active sessions, running agents
    case cronStatus        = "cronStatus"          // recent cron job runs
    case tokenCost         = "tokenCost"           // token spend / cost trend

    // Observability
    case datadogAlerts     = "datadogAlerts"       // active DD alert count
    case topologyMini      = "topologyMini"        // minimap of the full topology

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .systemHealth:    return "System Health"
        case .incidentList:    return "Active Incidents"
        case .deploymentFeed:  return "Deployments"
        case .ec2Health:       return "EC2 Fleet"
        case .containerHealth: return "Containers"
        case .lambdaActivity:  return "Lambda"
        case .rdsMetrics:      return "RDS"
        case .redisMetrics:    return "Redis"
        case .queueDepth:      return "Queues"
        case .agentActivity:   return "Agent Activity"
        case .cronStatus:      return "Cron"
        case .tokenCost:       return "Token Spend"
        case .datadogAlerts:   return "Datadog"
        case .topologyMini:    return "Topology"
        }
    }

    var systemImage: String {
        switch self {
        case .systemHealth:    return "heart.fill"
        case .incidentList:    return "exclamationmark.triangle.fill"
        case .deploymentFeed:  return "arrow.triangle.2.circlepath"
        case .ec2Health:       return "server.rack"
        case .containerHealth: return "cube"
        case .lambdaActivity:  return "bolt.fill"
        case .rdsMetrics:      return "cylinder.fill"
        case .redisMetrics:    return "bolt.horizontal.circle.fill"
        case .queueDepth:      return "list.bullet.rectangle"
        case .agentActivity:   return "cpu"
        case .cronStatus:      return "clock.fill"
        case .tokenCost:       return "dollarsign.circle.fill"
        case .datadogAlerts:   return "waveform.path.ecg"
        case .topologyMini:    return "point.3.connected.trianglepath.dotted"
        }
    }

    /// Preferred column span on a 2-column grid.
    var defaultSize: WidgetSize {
        switch self {
        case .systemHealth:    return .compact
        case .incidentList:    return .full
        case .deploymentFeed:  return .full
        case .ec2Health:       return .compact
        case .containerHealth: return .compact
        case .lambdaActivity:  return .compact
        case .rdsMetrics:      return .compact
        case .redisMetrics:    return .compact
        case .queueDepth:      return .full
        case .agentActivity:   return .compact
        case .cronStatus:      return .compact
        case .tokenCost:       return .compact
        case .datadogAlerts:   return .compact
        case .topologyMini:    return .full
        }
    }
}

// MARK: - Widget Size

enum WidgetSize: String, Codable {
    case compact = "compact"   // 1 column on 2-col grid
    case full    = "full"      // spans full width

    var columnSpan: Int { self == .full ? 2 : 1 }
}

// MARK: - Dashboard Widget (one widget in a layout)

struct DashboardWidget: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: WidgetKind
    var size: WidgetSize
    var titleOverride: String?
    var isHidden: Bool

    var displayTitle: String { titleOverride ?? kind.defaultTitle }

    init(kind: WidgetKind, size: WidgetSize? = nil, title: String? = nil) {
        self.id = UUID()
        self.kind = kind
        self.size = size ?? kind.defaultSize
        self.titleOverride = title
        self.isHidden = false
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Dashboard Layout (named collection of widgets)

struct DashboardLayout: Identifiable, Codable {
    var id: UUID
    var name: String
    var widgets: [DashboardWidget]

    init(name: String, widgets: [DashboardWidget]) {
        self.id = UUID()
        self.name = name
        self.widgets = widgets
    }

    var visibleWidgets: [DashboardWidget] { widgets.filter { !$0.isHidden } }

    // MARK: - Preset layouts

    /// Default "ops" layout: broad coverage of all widget types.
    static let defaultOps = DashboardLayout(name: "Ops", widgets: [
        DashboardWidget(kind: .systemHealth),
        DashboardWidget(kind: .agentActivity),
        DashboardWidget(kind: .incidentList),
        DashboardWidget(kind: .deploymentFeed),
        DashboardWidget(kind: .ec2Health),
        DashboardWidget(kind: .containerHealth),
        DashboardWidget(kind: .rdsMetrics),
        DashboardWidget(kind: .redisMetrics),
        DashboardWidget(kind: .queueDepth),
        DashboardWidget(kind: .datadogAlerts),
        DashboardWidget(kind: .cronStatus),
        DashboardWidget(kind: .tokenCost),
    ])

    /// "Focus" layout: minimal overhead-view for war-room incident response.
    static let defaultFocus = DashboardLayout(name: "Incident Focus", widgets: [
        DashboardWidget(kind: .systemHealth,  size: .compact),
        DashboardWidget(kind: .datadogAlerts, size: .compact),
        DashboardWidget(kind: .incidentList,  size: .full),
        DashboardWidget(kind: .deploymentFeed, size: .full),
        DashboardWidget(kind: .rdsMetrics,    size: .compact),
        DashboardWidget(kind: .queueDepth,    size: .full),
    ])

    /// "Topology" layout: system map + key metrics.
    static let defaultTopology = DashboardLayout(name: "Topology", widgets: [
        DashboardWidget(kind: .topologyMini,   size: .full),
        DashboardWidget(kind: .systemHealth,   size: .compact),
        DashboardWidget(kind: .incidentList,   size: .full),
        DashboardWidget(kind: .deploymentFeed, size: .full),
    ])
}

// MARK: - Dashboard Config (persisted multi-layout config)

struct DashboardConfig: Codable {
    var layouts: [DashboardLayout]
    var activeLayoutIndex: Int

    var activeLayout: DashboardLayout {
        get {
            guard layouts.indices.contains(activeLayoutIndex) else {
                return layouts.first ?? DashboardLayout.defaultOps
            }
            return layouts[activeLayoutIndex]
        }
        set {
            guard layouts.indices.contains(activeLayoutIndex) else { return }
            layouts[activeLayoutIndex] = newValue
        }
    }

    static let `default` = DashboardConfig(
        layouts: [.defaultOps, .defaultFocus, .defaultTopology],
        activeLayoutIndex: 0
    )
}
