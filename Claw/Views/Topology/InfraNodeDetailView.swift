import SwiftUI

// MARK: - InfraNodeDetailView
//
// Sheet shown when a topology node is tapped. Displays full metrics,
// active incidents, recent deployments, and inbound/outbound dependencies.

struct InfraNodeDetailView: View {
    let node: InfraNode
    let graph: InfraGraph

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    metricsSection
                    if !nodeIncidents.isEmpty  { incidentsSection }
                    if !nodeDeployments.isEmpty { deploymentsSection }
                    dependenciesSection
                    tagsSection
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle(node.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(Color.clawAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.clawBg)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(node.kind.accentColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: node.kind.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(node.kind.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(node.label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)

                HStack(spacing: 6) {
                    Image(systemName: node.health.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(node.health.color)
                    Text(node.health.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(node.health.color)

                    Text("·")
                        .foregroundStyle(Color.clawMuted)
                    Text(node.kind.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                }

                if let group = node.group {
                    Text(group)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.clawMuted)
                }
            }

            Spacer()

            if let score = node.impactScore {
                impactBadge(score)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clawCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
        )
    }

    private func impactBadge(_ score: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(impactColor(score))
            Text("impact")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
        }
        .frame(width: 50, height: 50)
        .background(
            Circle()
                .fill(impactColor(score).opacity(0.1))
                .overlay(Circle().strokeBorder(impactColor(score).opacity(0.3), lineWidth: 1))
        )
    }

    private func impactColor(_ score: Int) -> Color {
        score >= 80 ? .clawDanger : score >= 50 ? .clawWarn : .clawOk
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Metrics")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let cpu = node.cpuPercent  { metricCell(label: "CPU",      value: "\(Int(cpu))%",      fraction: cpu/100,   color: gaugeColor(cpu/100)) }
                if let mem = node.memPercent  { metricCell(label: "Memory",   value: "\(Int(mem))%",      fraction: mem/100,   color: .clawTeal) }
                if let rps = node.requestRate { metricCell(label: "Req/s",    value: compactFloat(rps),   fraction: nil,       color: .clawTeal) }
                if let err = node.errorRate   { metricCell(label: "Error %",  value: "\(String(format: "%.1f", err * 100))%", fraction: err, color: err > 0.05 ? .clawDanger : .clawWarn) }
                if let q   = node.queueDepth  { metricCell(label: "Q Depth",  value: "\(q)",              fraction: nil,       color: q > 5000 ? .clawWarn : .clawOk) }
                if let n   = node.instanceCount { metricCell(label: "Instances", value: "\(n)",            fraction: nil,       color: .clawTeal) }
            }
            if node.cpuPercent == nil && node.memPercent == nil && node.requestRate == nil &&
               node.errorRate == nil && node.queueDepth == nil && node.instanceCount == nil {
                Text("No metrics available")
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                    .padding(.vertical, 8)
            }
        }
    }

    private func metricCell(label: String, value: String, fraction: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let f = fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.clawBorder)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: max(4, geo.size.width * CGFloat(min(1, f))), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clawCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Incidents

    private var nodeIncidents: [InfraIncident] {
        graph.incidents.filter { $0.affectedNodeIds.contains(node.id) && $0.isActive }
    }

    private var incidentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Active Incidents")
            VStack(spacing: 0) {
                ForEach(Array(nodeIncidents.enumerated()), id: \.element.id) { idx, inc in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(inc.severity.color)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inc.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.clawTextStrong)
                            HStack(spacing: 6) {
                                Text(inc.severity.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(inc.severity.color)
                                Text("·")
                                    .foregroundStyle(Color.clawMuted)
                                Text(inc.durationDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.clawMuted)
                                if let src = inc.source {
                                    Text("·")
                                        .foregroundStyle(Color.clawMuted)
                                    Text(src)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.clawMuted)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if idx < nodeIncidents.count - 1 {
                        Divider().background(Color.clawBorder).padding(.horizontal, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clawCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clawDanger.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Deployments

    private var nodeDeployments: [DeploymentEvent] {
        graph.deployments.filter { $0.affectedNodeIds.contains(node.id) }
            .prefix(3)
            .map { $0 }
    }

    private var deploymentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recent Deployments")
            VStack(spacing: 0) {
                ForEach(Array(nodeDeployments.enumerated()), id: \.element.id) { idx, dep in
                    HStack(spacing: 10) {
                        Image(systemName: dep.status.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(dep.status.color)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(dep.service) \(dep.version)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.clawTextStrong)
                            HStack(spacing: 6) {
                                Text(dep.environment)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.clawMuted)
                                if let sha = dep.commitSha {
                                    Text("·")
                                        .foregroundStyle(Color.clawMuted)
                                    Text(sha.prefix(7))
                                        .font(.system(size: 11, design: .monospaced))
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
                    .padding(.vertical, 10)
                    if idx < nodeDeployments.count - 1 {
                        Divider().background(Color.clawBorder).padding(.horizontal, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clawCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Dependencies

    private var dependenciesSection: some View {
        let outbound = graph.validEdges.filter { $0.fromNodeId == node.id }
        let inbound  = graph.validEdges.filter { $0.toNodeId   == node.id }

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Connections")
            HStack(spacing: 10) {
                depColumn(title: "Calls", edges: outbound, incoming: false)
                depColumn(title: "Called by", edges: inbound, incoming: true)
            }
        }
    }

    private func depColumn(title: String, edges: [InfraEdge], incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
            if edges.isEmpty {
                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted.opacity(0.5))
            } else {
                ForEach(edges) { edge in
                    let targetId = incoming ? edge.fromNodeId : edge.toNodeId
                    if let target = graph.nodeMap[targetId] {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(target.health.color)
                                .frame(width: 6, height: 6)
                            Text(target.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawText)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clawCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        if !node.tags.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Tags")
                FlowLayout(spacing: 6) {
                    ForEach(node.tags.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.clawMuted)
                            Text(val)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.clawText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.clawBgElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.clawMuted)
            .textCase(.uppercase)
    }

    private func gaugeColor(_ fraction: Double) -> Color {
        fraction > 0.85 ? .clawDanger : fraction > 0.65 ? .clawWarn : .clawOk
    }

    private func compactFloat(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        return String(format: "%.0f", v)
    }

    private func relativeTime(_ date: Date) -> String {
        let elapsed = -date.timeIntervalSinceNow
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        return "\(Int(elapsed / 86400))d ago"
    }
}

// MARK: - FlowLayout (simple horizontal wrapping layout for tags)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }
        y += rowHeight
        return CGSize(width: maxX, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    InfraNodeDetailView(
        node: InfraGraph.preview.nodes.first(where: { $0.id == "rds-primary" }) ?? InfraGraph.preview.nodes[0],
        graph: .preview
    )
    .preferredColorScheme(.dark)
}
