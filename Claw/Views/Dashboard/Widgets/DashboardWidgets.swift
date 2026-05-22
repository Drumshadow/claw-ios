import SwiftUI

// MARK: - Widget container shell
//
// Wraps every widget in the standard card chrome (title bar, border, bg).

struct WidgetCard<Content: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    var isLoading: Bool = false
    var alertCount: Int = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color.clawMuted)
                }
                if alertCount > 0 {
                    Text("\(alertCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.clawDanger))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Color.clawBorder)

            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clawCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - System Health Widget

struct SystemHealthWidget: View {
    let graph: InfraGraph

    private var healthCounts: (ok: Int, degraded: Int, down: Int, unknown: Int) {
        let ok       = graph.nodes.filter { $0.health == .ok }.count
        let degraded = graph.nodes.filter { $0.health == .degraded }.count
        let down     = graph.nodes.filter { $0.health == .down }.count
        let unknown  = graph.nodes.filter { $0.health == .unknown }.count
        return (ok, degraded, down, unknown)
    }

    var body: some View {
        WidgetCard(
            title: "System Health",
            icon: "heart.fill",
            accentColor: graph.overallHealth.color,
            alertCount: healthCounts.down + healthCounts.degraded
        ) {
            VStack(spacing: 10) {
                // Overall status
                HStack(spacing: 10) {
                    Image(systemName: graph.overallHealth.systemImage)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(graph.overallHealth.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(graph.overallHealth.label)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(graph.overallHealth.color)
                        Text("\(graph.nodes.count) nodes · \(graph.activeIncidents.count) incidents")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.clawMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Health breakdown bar
                let counts = healthCounts
                let total  = max(1, graph.nodes.count)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if counts.ok > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.clawOk)
                                .frame(width: geo.size.width * CGFloat(counts.ok) / CGFloat(total))
                        }
                        if counts.degraded > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.clawWarn)
                                .frame(width: geo.size.width * CGFloat(counts.degraded) / CGFloat(total))
                        }
                        if counts.down > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.clawDanger)
                                .frame(width: geo.size.width * CGFloat(counts.down) / CGFloat(total))
                        }
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 14)

                // Legend row
                HStack(spacing: 12) {
                    healthLegendItem(count: counts.ok,       label: "ok",       color: .clawOk)
                    healthLegendItem(count: counts.degraded, label: "degraded", color: .clawWarn)
                    healthLegendItem(count: counts.down,     label: "down",     color: .clawDanger)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private func healthLegendItem(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11))
                .foregroundStyle(Color.clawMuted)
        }
    }
}

// MARK: - Incident List Widget

struct IncidentListWidget: View {
    let graph: InfraGraph

    private var sorted: [InfraIncident] {
        graph.activeIncidents.sorted { $0.severity < $1.severity }
    }

    var body: some View {
        WidgetCard(
            title: "Active Incidents",
            icon: "exclamationmark.triangle.fill",
            accentColor: .clawDanger,
            alertCount: graph.activeIncidents.count
        ) {
            if sorted.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.clawOk)
                    Text("No active incidents")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.clawMuted)
                }
                .padding(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.prefix(5).enumerated()), id: \.element.id) { idx, inc in
                        incidentRow(inc)
                        if idx < min(sorted.count, 5) - 1 {
                            Divider().background(Color.clawBorder).padding(.horizontal, 14)
                        }
                    }
                    if sorted.count > 5 {
                        Text("+\(sorted.count - 5) more")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.clawMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func incidentRow(_ inc: InfraIncident) -> some View {
        HStack(spacing: 10) {
            // Severity indicator
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(inc.severity.color)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(inc.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(inc.severity.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(inc.severity.color)
                    Text("·")
                        .foregroundStyle(Color.clawMuted)
                    Text(inc.durationDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.clawMuted)
                    if let src = inc.source {
                        Text("·")
                            .foregroundStyle(Color.clawMuted)
                        Text(src)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.clawMuted)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Deployment Feed Widget

struct DeploymentFeedWidget: View {
    let graph: InfraGraph

    private var sorted: [DeploymentEvent] {
        graph.deployments.sorted { $0.deployedAt > $1.deployedAt }
    }

    var body: some View {
        let running = graph.deployments.filter { $0.status == .running }.count
        WidgetCard(
            title: "Deployments",
            icon: "arrow.triangle.2.circlepath",
            accentColor: .clawTeal,
            alertCount: running
        ) {
            if sorted.isEmpty {
                Text("No recent deployments")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawMuted)
                    .padding(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.prefix(6).enumerated()), id: \.element.id) { idx, dep in
                        deployRow(dep)
                        if idx < min(sorted.count, 6) - 1 {
                            Divider().background(Color.clawBorder).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    private func deployRow(_ dep: DeploymentEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: dep.status.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(dep.status.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dep.service)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                    Text(dep.version)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.clawMuted)
                }
                HStack(spacing: 6) {
                    Text(dep.environment)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                    if let by = dep.deployedBy {
                        Text("·")
                            .foregroundStyle(Color.clawMuted)
                        Text(by)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.clawMuted)
                    }
                }
            }
            Spacer()
            Text(relativeTime(dep.deployedAt))
                .font(.system(size: 11))
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func relativeTime(_ date: Date) -> String {
        let e = -date.timeIntervalSinceNow
        if e < 60 { return "\(Int(e))s" }
        if e < 3600 { return "\(Int(e/60))m" }
        if e < 86400 { return "\(Int(e/3600))h" }
        return "\(Int(e/86400))d"
    }
}

// MARK: - EC2 Health Widget

struct EC2HealthWidget: View {
    let nodes: [InfraNode]

    private var ec2Nodes: [InfraNode] { nodes.filter { $0.kind == .ec2 || $0.kind == .kubernetes } }

    var body: some View {
        WidgetCard(
            title: "Compute",
            icon: "server.rack",
            accentColor: Color(clawHex: 0xff9900),
            alertCount: ec2Nodes.filter { $0.health != .ok }.count
        ) {
            VStack(spacing: 0) {
                ForEach(Array(ec2Nodes.prefix(4).enumerated()), id: \.element.id) { idx, node in
                    computeRow(node)
                    if idx < min(ec2Nodes.count, 4) - 1 {
                        Divider().background(Color.clawBorder).padding(.horizontal, 12)
                    }
                }
                if ec2Nodes.isEmpty {
                    Text("No compute nodes")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                        .padding(12)
                }
            }
        }
    }

    private func computeRow(_ node: InfraNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(node.health.color)
                    .frame(width: 6, height: 6)
                Text(node.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(1)
                Spacer()
                if let n = node.instanceCount {
                    Text("×\(n)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.clawMuted)
                }
            }
            if node.cpuPercent != nil || node.memPercent != nil {
                HStack(spacing: 8) {
                    if let cpu = node.cpuPercent {
                        miniGaugeLine(label: "CPU", value: cpu / 100)
                    }
                    if let mem = node.memPercent {
                        miniGaugeLine(label: "MEM", value: mem / 100)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func miniGaugeLine(label: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.clawBorder)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(value > 0.85 ? Color.clawDanger : value > 0.65 ? Color.clawWarn : Color.clawOk)
                        .frame(width: max(3, geo.size.width * CGFloat(value)), height: 4)
                }
            }
            .frame(height: 4)
            Text("\(Int(value * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.clawMuted)
        }
    }
}

// MARK: - RDS Metrics Widget

struct RDSMetricsWidget: View {
    let nodes: [InfraNode]
    private var rdsNodes: [InfraNode] { nodes.filter { $0.kind == .rds } }

    var body: some View {
        WidgetCard(
            title: "RDS",
            icon: "cylinder.fill",
            accentColor: Color(clawHex: 0x527fff),
            alertCount: rdsNodes.filter { $0.health != .ok }.count
        ) {
            VStack(spacing: 0) {
                ForEach(Array(rdsNodes.prefix(3).enumerated()), id: \.element.id) { idx, node in
                    rdsRow(node)
                    if idx < min(rdsNodes.count, 3) - 1 {
                        Divider().background(Color.clawBorder).padding(.horizontal, 12)
                    }
                }
                if rdsNodes.isEmpty {
                    Text("No RDS instances")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                        .padding(12)
                }
            }
        }
    }

    private func rdsRow(_ node: InfraNode) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(node.health.color)
                .frame(width: 7, height: 7)
            Text(node.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.clawText)
                .lineLimit(1)
            Spacer()
            if let cpu = node.cpuPercent {
                statPill(label: "CPU", value: "\(Int(cpu))%", highlight: cpu > 80)
            }
            if let rps = node.requestRate {
                statPill(label: "QPS", value: compactFloat(rps), highlight: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func statPill(label: String, value: String, highlight: Bool) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(highlight ? Color.clawDanger : Color.clawTextStrong)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.clawMuted)
        }
    }

    private func compactFloat(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : String(format: "%.0f", v)
    }
}

// MARK: - Queue Depth Widget

struct QueueDepthWidget: View {
    let nodes: [InfraNode]
    private var queueNodes: [InfraNode] { nodes.filter { $0.kind == .queue || $0.kind == .nats } }

    var body: some View {
        WidgetCard(
            title: "Queues",
            icon: "list.bullet.rectangle",
            accentColor: Color(clawHex: 0xa855f7)
        ) {
            if queueNodes.isEmpty {
                Text("No queue nodes")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)
                    .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    let maxDepth = queueNodes.compactMap(\.queueDepth).max() ?? 1
                    ForEach(queueNodes) { node in
                        if let depth = node.queueDepth {
                            queueBar(node: node, depth: depth, maxDepth: max(1, maxDepth))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private func queueBar(node: InfraNode, depth: Int, maxDepth: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: node.kind.systemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(node.kind.accentColor)
                Text(node.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.clawText)
                Spacer()
                Text("\(depth)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(depth > 5000 ? Color.clawWarn : Color.clawTextStrong)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.clawBorder)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(node.kind.accentColor.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(depth) / CGFloat(maxDepth), height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Agent Activity Widget

struct AgentActivityWidget: View {
    let activeSessions: Int
    let runningAgents: Int
    let pendingApprovals: Int

    var body: some View {
        WidgetCard(
            title: "Agents",
            icon: "cpu",
            accentColor: .clawAccent,
            alertCount: pendingApprovals
        ) {
            HStack(spacing: 0) {
                agentStat(value: "\(activeSessions)", label: "Sessions", color: .clawTeal)
                Divider().frame(height: 40).background(Color.clawBorder)
                agentStat(value: "\(runningAgents)", label: "Running", color: .clawOk)
                Divider().frame(height: 40).background(Color.clawBorder)
                agentStat(value: "\(pendingApprovals)", label: "Approvals", color: pendingApprovals > 0 ? .clawWarn : .clawMuted)
            }
            .padding(.vertical, 12)
        }
    }

    private func agentStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Token Cost Widget

struct TokenCostWidget: View {
    let totalTokensToday: Int
    let totalCostTodayUsd: Double

    var body: some View {
        WidgetCard(
            title: "Token Spend",
            icon: "dollarsign.circle.fill",
            accentColor: .clawAccent
        ) {
            HStack(spacing: 0) {
                costStat(value: formatCost(totalCostTodayUsd), label: "Today", color: .clawAccent)
                Divider().frame(height: 40).background(Color.clawBorder)
                costStat(value: formatTokens(totalTokensToday), label: "Tokens", color: .clawTeal)
            }
            .padding(.vertical, 12)
        }
    }

    private func costStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatCost(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$0.00"
    }

    private func formatTokens(_ v: Int) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000     { return String(format: "%.1fk", Double(v) / 1_000) }
        return "\(v)"
    }
}

// MARK: - Datadog Alerts Widget

struct DatadogAlertsWidget: View {
    let graph: InfraGraph

    private var alertNodes: [InfraNode] {
        graph.nodes.filter { $0.kind == .datadogAlert }
    }

    var body: some View {
        WidgetCard(
            title: "Datadog",
            icon: "waveform.path.ecg",
            accentColor: Color(clawHex: 0x774aa4),
            alertCount: alertNodes.filter { $0.health == .down }.count
        ) {
            if alertNodes.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.clawOk)
                    Text("No active alerts")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                }
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(alertNodes.prefix(3).enumerated()), id: \.element.id) { idx, node in
                        HStack(spacing: 8) {
                            Image(systemName: node.health.systemImage)
                                .font(.system(size: 12))
                                .foregroundStyle(node.health.color)
                            Text(node.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawText)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if idx < min(alertNodes.count, 3) - 1 {
                            Divider().background(Color.clawBorder).padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Cron Status Widget

struct CronStatusWidget: View {
    let recentFailures: Int

    var body: some View {
        WidgetCard(
            title: "Cron",
            icon: "clock.fill",
            accentColor: .clawTeal,
            alertCount: recentFailures
        ) {
            HStack(spacing: 10) {
                Image(systemName: recentFailures > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(recentFailures > 0 ? Color.clawWarn : Color.clawOk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recentFailures > 0 ? "\(recentFailures) recent failures" : "All jobs healthy")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(recentFailures > 0 ? Color.clawWarn : Color.clawOk)
                    Text("Scheduled jobs")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Topology Mini Widget
// Embeds TopologyGraphView in a fixed-height card for dashboard display

struct TopologyMiniWidget: View {
    let graph: InfraGraph
    @State private var showFullscreen = false

    var body: some View {
        WidgetCard(
            title: "Topology",
            icon: "point.3.connected.trianglepath.dotted",
            accentColor: .clawTeal
        ) {
            TopologyGraphView(graph: graph)
                .frame(height: 280)
                .clipShape(
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                )
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        showFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.clawTextStrong)
                            .padding(8)
                            .background(
                                Circle().fill(Color.clawBgElevated.opacity(0.9))
                            )
                    }
                    .padding(10)
                }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            NavigationStack {
                TopologyGraphView(graph: graph)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") { showFullscreen = false }
                                .tint(Color.clawAccent)
                        }
                    }
            }
        }
    }
}

// Color(clawHex:) is defined as internal in ClawTheme.swift and available throughout the module.
