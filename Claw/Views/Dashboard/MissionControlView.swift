import SwiftUI

// MARK: - MissionControlView
//
// The Mission Control dashboard: tabbed between Overview (widget grid),
// Topology (full graph), and Incidents (active incident + deployment log).
//
// Stores are received as environment objects; the parent (DashboardTabView)
// owns and initialises them.

struct MissionControlView: View {

    // Passed in (owned by DashboardTabView)
    @Bindable var dashboardStore: DashboardStore
    @Bindable var topologyStore: TopologyStore

    // MARK: - State

    @State private var selectedTab: DashboardTab = .overview
    @State private var isEditMode: Bool = false
    @State private var showAddWidget: Bool = false
    @State private var showLayoutPicker: Bool = false
    @State private var showRenameSheet: Bool = false
    @State private var renameText: String = ""
    @State private var resourceSetupKind: InfraNodeKind?

    enum DashboardTab: String, CaseIterable {
        case overview  = "overview"
        case topology  = "topology"
        case incidents = "incidents"

        var label: String {
            switch self {
            case .overview:  return "Overview"
            case .topology:  return "Topology"
            case .incidents: return "Incidents"
            }
        }

        var icon: String {
            switch self {
            case .overview:  return "square.grid.2x2"
            case .topology:  return "point.3.connected.trianglepath.dotted"
            case .incidents: return "exclamationmark.triangle"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().background(Color.clawBorder)

            ZStack {
                switch selectedTab {
                case .overview:
                    overviewTab
                case .topology:
                    topologyTab
                case .incidents:
                    incidentsTab
                }
            }
        }
        .background(Color.clawBg.ignoresSafeArea())
        .navigationTitle("Mission Control")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddWidget) { addWidgetSheet }
        .sheet(isPresented: $showRenameSheet) { renameSheet }
        .sheet(item: $resourceSetupKind) { kind in
            ResourceSetupSheet(kind: kind, topologyStore: topologyStore)
        }
        .confirmationDialog("Dashboards", isPresented: $showLayoutPicker, titleVisibility: .visible) {
            ForEach(Array(dashboardStore.layouts.enumerated()), id: \.element.id) { idx, layout in
                Button(layout.name) {
                    dashboardStore.activeLayoutIndex = idx
                }
            }
            Button("New Dashboard") {
                let newLayout = DashboardLayout(name: "Dashboard \(dashboardStore.layouts.count + 1)", widgets: DashboardLayout.defaultOps.widgets)
                dashboardStore.addLayout(newLayout)
                dashboardStore.activeLayoutIndex = dashboardStore.layouts.count - 1
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .semibold))

                            // Badge for incidents/alerts
                            if tab == .incidents && !topologyStore.graph.activeIncidents.isEmpty {
                                Text("\(topologyStore.graph.activeIncidents.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.clawDanger))
                            }

                            Text(tab.label)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(selectedTab == tab ? Color.clawAccent : Color.clawMuted)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.clawAccent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .background(Color.clawBgAccent)
    }

    // MARK: - Overview tab

    private var overviewTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Live status banner if unhealthy
                if topologyStore.graph.overallHealth != .ok && !isEditMode {
                    alertBanner
                }

                // 2-column widget grid
                let visible = dashboardStore.activeLayout.visibleWidgets
                let layout  = computeGridLayout(visible)

                if visible.isEmpty {
                    dashboardEmptyState
                }

                ForEach(layout, id: \.widget.id) { item in
                    widgetView(for: item.widget)
                        .frame(maxWidth: .infinity)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {
                            guard !isEditMode, let kind = item.widget.kind.connectableNodeKind else { return }
                            resourceSetupKind = kind
                        }
                        .overlay(alignment: .bottomTrailing) {
                            connectHint(for: item.widget)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isEditMode {
                                editOverlay(widget: item.widget)
                            }
                        }
                }

                // Edit mode: show hidden widgets
                if isEditMode {
                    hiddenWidgetsSection
                }

                // Bottom padding for tab bar
                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            await topologyStore.refresh()
        }
        .overlay(alignment: .bottom) {
            if let ts = topologyStore.lastRefreshedAt {
                refreshFooter(ts)
            }
        }
    }

    // MARK: - Topology tab

    private var topologyTab: some View {
        TopologyGraphView(graph: topologyStore.graph)
    }

    // MARK: - Incidents tab

    private var incidentsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                incidentsSection
                deploymentsSection
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            await topologyStore.refresh()
        }
    }

    // MARK: - Widget rendering

    @ViewBuilder
    private func widgetView(for widget: DashboardWidget) -> some View {
        let graph = topologyStore.graph

        switch widget.kind {
        case .systemHealth:
            SystemHealthWidget(graph: graph)

        case .incidentList:
            IncidentListWidget(graph: graph)

        case .deploymentFeed:
            DeploymentFeedWidget(graph: graph)

        case .ec2Health, .containerHealth:
            EC2HealthWidget(nodes: graph.nodes)

        case .rdsMetrics:
            RDSMetricsWidget(nodes: graph.nodes)

        case .redisMetrics:
            redisWidget(nodes: graph.nodes)

        case .queueDepth:
            QueueDepthWidget(nodes: graph.nodes)

        case .agentActivity:
            AgentActivityWidget(
                activeSessions: dashboardStore.activeSessions,
                runningAgents: dashboardStore.runningAgents,
                pendingApprovals: dashboardStore.pendingApprovals
            )

        case .cronStatus:
            CronStatusWidget(recentFailures: dashboardStore.cronRecentFailures)

        case .tokenCost:
            TokenCostWidget(
                totalTokensToday: dashboardStore.totalTokensToday,
                totalCostTodayUsd: dashboardStore.totalCostTodayUsd
            )

        case .datadogAlerts:
            DatadogAlertsWidget(graph: graph)

        case .topologyMini:
            TopologyMiniWidget(graph: graph)

        case .lambdaActivity:
            lambdaWidget(nodes: graph.nodes)
        }
    }

    // Inline small widgets for lambda / redis (not worth separate files)
    private func redisWidget(nodes: [InfraNode]) -> some View {
        let redis = nodes.filter { $0.kind == .redis }
        return WidgetCard(title: "Redis", icon: "bolt.horizontal.circle.fill", accentColor: Color.clawDanger) {
            if redis.isEmpty {
                Text("No Redis nodes").font(.caption).foregroundStyle(Color.clawMuted).padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(redis.prefix(3).enumerated()), id: \.element.id) { idx, node in
                        HStack(spacing: 8) {
                            Circle().fill(node.health.color).frame(width: 6, height: 6)
                            Text(node.label).font(.system(size: 12)).foregroundStyle(Color.clawText).lineLimit(1)
                            Spacer()
                            if let m = node.memPercent {
                                Text("\(Int(m))%").font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(m > 80 ? Color.clawWarn : Color.clawMuted)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        if idx < min(redis.count, 3) - 1 {
                            Divider().background(Color.clawBorder).padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }

    private func lambdaWidget(nodes: [InfraNode]) -> some View {
        let lambdas = nodes.filter { $0.kind == .lambda }
        return WidgetCard(title: "Lambda", icon: "bolt.fill", accentColor: Color(red: 1, green: 0.6, blue: 0)) {
            if lambdas.isEmpty {
                Text("No Lambda functions").font(.caption).foregroundStyle(Color.clawMuted).padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(lambdas.prefix(3).enumerated()), id: \.element.id) { idx, node in
                        HStack(spacing: 8) {
                            Circle().fill(node.health.color).frame(width: 6, height: 6)
                            Text(node.label).font(.system(size: 12)).foregroundStyle(Color.clawText).lineLimit(1)
                            Spacer()
                            if let rps = node.requestRate {
                                Text("\(Int(rps))/s").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.clawMuted)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        if idx < min(lambdas.count, 3) - 1 {
                            Divider().background(Color.clawBorder).padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grid layout computation
    //
    // Groups widgets into rows: compact widgets share rows (2 per row),
    // full-width widgets get their own row.

    private struct GridItem {
        let widget: DashboardWidget
    }

    private func computeGridLayout(_ widgets: [DashboardWidget]) -> [GridItem] {
        // We render sequentially in a LazyVStack; full-width gets full row.
        // Compact widgets are paired inside an HStack rendered as a single GridItem.
        // For simplicity we render each widget individually and use a 2-col LazyVGrid externally.
        widgets.map { GridItem(widget: $0) }
    }

    // MARK: - Alert banner

    private var alertBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: topologyStore.graph.overallHealth.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(topologyStore.graph.overallHealth.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Infrastructure \(topologyStore.graph.overallHealth.label)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(topologyStore.graph.overallHealth.color)
                let count = topologyStore.graph.activeIncidents.count
                Text("\(count) active incident\(count == 1 ? "" : "s") · \(topologyStore.graph.unhealthyNodes.count) unhealthy nodes")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clawMuted)
            }
            Spacer()
            Button {
                selectedTab = .incidents
            } label: {
                Text("View")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(topologyStore.graph.overallHealth.color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(topologyStore.graph.overallHealth.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(topologyStore.graph.overallHealth.color.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Incidents section (incidents tab)

    private var incidentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Active Incidents (\(topologyStore.graph.activeIncidents.count))")

            if topologyStore.graph.activeIncidents.isEmpty {
                emptyState(icon: "checkmark.shield.fill", message: "No active incidents", color: .clawOk)
            } else {
                VStack(spacing: 8) {
                    ForEach(topologyStore.graph.activeIncidents.sorted { $0.severity < $1.severity }) { inc in
                        incidentCard(inc)
                    }
                }
            }
        }
    }

    private func incidentCard(_ inc: InfraIncident) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(inc.severity.color)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(inc.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                    HStack(spacing: 8) {
                        Text(inc.severity.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
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

            // Affected nodes
            if !inc.affectedNodeIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(inc.affectedNodeIds, id: \.self) { nodeId in
                            if let node = topologyStore.graph.nodeMap[nodeId] {
                                HStack(spacing: 4) {
                                    Image(systemName: node.kind.systemImage)
                                        .font(.system(size: 10))
                                        .foregroundStyle(node.kind.accentColor)
                                    Text(node.label)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.clawText)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.clawBgElevated)
                                        .overlay(Capsule().strokeBorder(Color.clawBorder, lineWidth: 1))
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(inc.severity.color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Deployments section (incidents tab)

    private var deploymentsSection: some View {
        let sorted = topologyStore.graph.deployments.sorted { $0.deployedAt > $1.deployedAt }
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Deployment History")
            if sorted.isEmpty {
                emptyState(icon: "arrow.triangle.2.circlepath", message: "No recent deployments", color: .clawMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, dep in
                        deploymentRow(dep)
                        if idx < sorted.count - 1 {
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
    }

    private func deploymentRow(_ dep: DeploymentEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dep.status.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(dep.status.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(dep.service)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                    Text(dep.version)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.clawMuted)
                    Spacer()
                    Text(dep.status.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(dep.status.color)
                }
                HStack(spacing: 6) {
                    Text(dep.environment.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.clawMuted)
                    if let by = dep.deployedBy {
                        Text("·")
                            .foregroundStyle(Color.clawMuted)
                        Text(by)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.clawMuted)
                    }
                    if let sha = dep.commitSha {
                        Text("·")
                            .foregroundStyle(Color.clawMuted)
                        Text(sha.prefix(7))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.clawMuted)
                    }
                    Spacer()
                    Text(relativeTime(dep.deployedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Edit mode overlay

    private var dashboardEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44))
                .foregroundStyle(Color.clawMuted.opacity(0.3))
            Text("Build Your Ops Dashboard")
                .font(.headline)
                .foregroundStyle(Color.clawTextStrong)
            Text("Add widgets for sessions, approvals, topology health, incidents, deployments, cost, and custom layouts. Sample widgets only appear when App Review Sample Data is enabled.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
            Button {
                showAddWidget = true
            } label: {
                Label("Add Widget", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.clawAccent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.clawCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
        )
    }

    private func editOverlay(widget: DashboardWidget) -> some View {
        Button {
            dashboardStore.removeWidget(id: widget.id)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.clawDanger)
                .background(Circle().fill(Color.clawBg))
        }
        .offset(x: -8, y: 8)
    }

    @ViewBuilder
    private func connectHint(for widget: DashboardWidget) -> some View {
        if !isEditMode,
           let kind = widget.kind.connectableNodeKind,
           !topologyStore.graph.nodes.contains(where: { $0.kind == kind }) {
            HStack(spacing: 4) {
                Image(systemName: "link.badge.plus")
                Text("Tap to connect")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.clawAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.clawAccent.opacity(0.14)))
            .padding(10)
        }
    }

    private var hiddenWidgetsSection: some View {
        let hidden = dashboardStore.activeLayout.widgets.filter { $0.isHidden }
        return Group {
            if !hidden.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hidden Widgets")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.clawMuted)
                        .textCase(.uppercase)
                    ForEach(hidden) { w in
                        Button {
                            dashboardStore.toggleWidget(id: w.id)
                        } label: {
                            HStack {
                                Image(systemName: w.kind.systemImage)
                                    .foregroundStyle(Color.clawMuted)
                                Text(w.displayTitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.clawMuted)
                                Spacer()
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.clawAccent)
                            }
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
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Layout picker (left)
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showLayoutPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(dashboardStore.activeLayout.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.clawText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.clawMuted)
                }
            }
            .buttonStyle(.plain)
        }

        // Edit / Add (right)
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if selectedTab == .overview {
                Button {
                    showAddWidget = true
                } label: {
                    Image(systemName: "plus.circle")
                        .tint(Color.clawAccent)
                }
                Button {
                    withAnimation { isEditMode.toggle() }
                } label: {
                    Text(isEditMode ? "Done" : "Edit")
                        .font(.system(size: 14, weight: .semibold))
                        .tint(isEditMode ? Color.clawAccent : Color.clawMuted)
                }
            }

            if selectedTab == .topology {
                // Refresh topology
                Button {
                    Task { await topologyStore.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .tint(topologyStore.isLoading ? Color.clawMuted : Color.clawAccent)
                }
                .disabled(topologyStore.isLoading)
            }
        }
    }

    // MARK: - Add Widget sheet

    private var addWidgetSheet: some View {
        NavigationStack {
            List {
                ForEach(WidgetKind.allCases) { kind in
                    Button {
                        dashboardStore.addWidget(DashboardWidget(kind: kind))
                        showAddWidget = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.clawAccent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.defaultTitle)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.clawTextStrong)
                                Text(kind.defaultSize == .full ? "Full width" : "Compact")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.clawMuted)
                            }
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clawCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showAddWidget = false }
                        .tint(Color.clawAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.clawBg)
    }

    // MARK: - Rename sheet

    private var renameSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Dashboard name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                Spacer()
            }
            .padding(20)
            .background(Color.clawBg)
            .navigationTitle("Rename Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showRenameSheet = false }.tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if !renameText.isEmpty {
                            dashboardStore.renameActiveLayout(to: renameText)
                        }
                        showRenameSheet = false
                    }
                    .fontWeight(.semibold)
                    .tint(Color.clawAccent)
                }
            }
        }
        .presentationDetents([.height(180)])
        .presentationBackground(Color.clawBg)
    }

    // MARK: - Refresh footer

    private func refreshFooter(_ date: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: topologyStore.isLive ? "circle.fill" : "circle.dashed")
                .font(.system(size: 7))
                .foregroundStyle(topologyStore.isLive ? Color.clawOk : Color.clawMuted)
            Text(topologyStore.isLive ? "Live · \(relativeTime(date))" : "Preview data")
                .font(.system(size: 10))
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Shared helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.clawMuted)
            .textCase(.uppercase)
    }

    private func emptyState(icon: String, message: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.clawMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let e = -date.timeIntervalSinceNow
        if e < 60  { return "\(Int(e))s ago" }
        if e < 3600 { return "\(Int(e/60))m ago" }
        return "\(Int(e/3600))h ago"
    }
}

// MARK: - Resource setup

private extension WidgetKind {
    var connectableNodeKind: InfraNodeKind? {
        switch self {
        case .ec2Health:       return .ec2
        case .containerHealth: return .container
        case .lambdaActivity:  return .lambda
        case .rdsMetrics:      return .rds
        case .redisMetrics:    return .redis
        case .queueDepth:      return .queue
        case .datadogAlerts:   return .datadogAlert
        case .topologyMini:    return .service
        default:               return nil
        }
    }
}

private struct ResourceSetupSheet: View {
    let kind: InfraNodeKind
    let topologyStore: TopologyStore

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var identifier = ""
    @State private var region = ""
    @State private var group = ""
    @State private var source = ""
    @State private var monitorURL = ""
    @State private var isSaving = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(defaultNamePlaceholder, text: $name)
                    TextField(identifierPlaceholder, text: $identifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Environment / group, e.g. production", text: $group)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Region, e.g. us-east-1", text: $region)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Resource")
                } footer: {
                    Text("This connects the widget to a topology node. The gateway can enrich it with live metrics; until then it appears as a pending manual resource.")
                }

                Section {
                    TextField(sourcePlaceholder, text: $source)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Monitor URL or dashboard link", text: $monitorURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Live data source")
                } footer: {
                    Text("Use an AWS identifier/ARN, Datadog monitor, Prometheus target, NATS subject, or whatever the gateway connector understands for this resource.")
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Connect \(kind.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Connecting…" : "Connect") { Task { await connect() } }
                        .fontWeight(.semibold)
                        .tint(Color.clawAccent)
                        .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.clawBg)
    }

    private var defaultNamePlaceholder: String {
        switch kind {
        case .rds: return "Primary database"
        case .redis: return "Redis cache"
        case .queue, .nats: return "Event queue"
        case .ec2: return "API host"
        case .container, .kubernetes: return "API container"
        case .lambda: return "Image processor"
        case .datadogAlert: return "Datadog monitor"
        default: return "\(kind.label) name"
        }
    }

    private var identifierPlaceholder: String {
        switch kind {
        case .rds: return "DB identifier or ARN"
        case .redis: return "Cluster id or endpoint"
        case .queue, .nats: return "Queue/subject name or ARN"
        case .ec2: return "Instance id, ASG, or hostname"
        case .container, .kubernetes: return "Container, service, or namespace"
        case .lambda: return "Function name or ARN"
        case .datadogAlert: return "Monitor id"
        default: return "Resource id"
        }
    }

    private var sourcePlaceholder: String {
        switch kind {
        case .datadogAlert: return "datadog"
        case .rds, .ec2, .lambda, .redis, .queue, .s3: return "aws"
        case .container, .kubernetes: return "docker / kubernetes"
        case .nats: return "nats"
        default: return "gateway connector"
        }
    }

    private func connect() async {
        isSaving = true
        resultMessage = nil
        defer { isSaving = false }

        let result = await topologyStore.createResource(
            kind: kind,
            label: name,
            identifier: identifier,
            region: region,
            group: group,
            source: source.isEmpty ? sourcePlaceholder : source,
            monitorURL: monitorURL
        )
        resultMessage = result.message
        if result.isGatewayBacked {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    let dashStore = DashboardStore()
    let topoStore = TopologyStore(
        client: GatewayClient(config: GatewayConfig(name: "Preview", host: "localhost", port: 7777, isSecure: false))
    )

    return NavigationStack {
        MissionControlView(
            dashboardStore: dashStore,
            topologyStore: topoStore
        )
    }
    .preferredColorScheme(.dark)
}
