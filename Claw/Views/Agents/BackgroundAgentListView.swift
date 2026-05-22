import SwiftUI

// MARK: - BackgroundAgentListView
//
// Shows background watchers grouped by status, and active incidents list.
// Backed by BackgroundAgentStore.

struct BackgroundAgentListView: View {
    @Environment(BackgroundAgentStore.self) private var store
    @State private var selectedTab: AgentListTab = .watchers
    @State private var showNewWatcher: Bool = false

    enum AgentListTab: String, CaseIterable {
        case watchers = "Watchers"
        case incidents = "Incidents"
        case proposals = "Proposals"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(AgentListTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clawBgAccent)

            Divider().background(Color.clawBorder)

            // Summary bar
            summaryBar

            Divider().background(Color.clawBorder)

            // Content
            switch selectedTab {
            case .watchers:
                watcherList
            case .incidents:
                incidentList
            case .proposals:
                proposalList
            }
        }
        .background(Color.clawBg)
        .navigationTitle("Background Agents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNewWatcher = true } label: {
                    Image(systemName: "plus")
                }
                .tint(Color.clawAccent)
            }
        }
        .sheet(isPresented: $showNewWatcher) {
            newWatcherPlaceholder
        }
        .task { await store.loadAll() }
        .refreshable { await store.loadAll() }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 0) {
            statCell(value: store.watchers.count, label: "Watchers", color: .clawText)
            Divider().frame(height: 28).background(Color.clawBorder)
            statCell(value: store.activeIncidents.count, label: "Active", color: store.activeIncidents.isEmpty ? .clawMuted : .clawWarn)
            Divider().frame(height: 28).background(Color.clawBorder)
            statCell(value: store.criticalCount, label: "Critical", color: store.criticalCount > 0 ? .clawDanger : .clawMuted)
            Divider().frame(height: 28).background(Color.clawBorder)
            statCell(value: store.pendingProposals.count, label: "Pending", color: store.pendingProposals.isEmpty ? .clawMuted : .clawTeal)
        }
        .padding(.vertical, 10)
        .background(Color.clawBgAccent)
    }

    private func statCell(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Watcher List

    private var watcherList: some View {
        List {
            if store.watchers.isEmpty {
                emptyState(
                    icon: "eye.slash",
                    title: "No watchers",
                    message: "Create a watcher to monitor your infrastructure autonomously."
                )
                .listRowBackground(Color.clawBg)
            } else {
                Section("Active") {
                    ForEach(store.watchers.filter { $0.isEnabled }) { watcher in
                        NavigationLink {
                            BackgroundAgentDetailView(watcher: watcher)
                                .environment(store)
                        } label: {
                            WatcherRowView(watcher: watcher)
                        }
                        .listRowBackground(Color.clawCard)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await store.deleteWatcher(watcher.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                Task { await store.toggleWatcher(watcher.id) }
                            } label: {
                                Label("Disable", systemImage: "pause.circle")
                            }
                            .tint(Color.clawWarn)
                        }
                    }
                }

                Section("Disabled") {
                    ForEach(store.watchers.filter { !$0.isEnabled }) { watcher in
                        NavigationLink {
                            BackgroundAgentDetailView(watcher: watcher)
                                .environment(store)
                        } label: {
                            WatcherRowView(watcher: watcher)
                        }
                        .listRowBackground(Color.clawCard)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await store.deleteWatcher(watcher.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                Task { await store.toggleWatcher(watcher.id) }
                            } label: {
                                Label("Enable", systemImage: "play.circle")
                            }
                            .tint(Color.clawOk)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
    }

    // MARK: - Incident List

    private var incidentList: some View {
        List {
            if store.incidents.isEmpty {
                emptyState(
                    icon: "checkmark.shield",
                    title: "No incidents",
                    message: "All systems are nominal. Watchers will surface issues here."
                )
                .listRowBackground(Color.clawBg)
            } else {
                if !store.activeIncidents.isEmpty {
                    Section("Active") {
                        ForEach(store.activeIncidents) { incident in
                            NavigationLink {
                                IncidentDetailView(incident: incident)
                                    .environment(store)
                            } label: {
                                IncidentRowView(incident: incident)
                            }
                            .listRowBackground(Color.clawCard)
                        }
                    }
                }

                let resolved = store.incidents.filter { !$0.status.isActive }
                if !resolved.isEmpty {
                    Section("Resolved") {
                        ForEach(resolved) { incident in
                            NavigationLink {
                                IncidentDetailView(incident: incident)
                                    .environment(store)
                            } label: {
                                IncidentRowView(incident: incident)
                            }
                            .listRowBackground(Color.clawCard)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
    }

    // MARK: - Proposal List

    private var proposalList: some View {
        List {
            if store.proposals.isEmpty {
                emptyState(
                    icon: "lightbulb.slash",
                    title: "No proposals",
                    message: "When a watcher triggers remediation, agent proposals appear here."
                )
                .listRowBackground(Color.clawBg)
            } else {
                ForEach(store.proposals) { proposal in
                    ProposalRowView(proposal: proposal) {
                        Task { await store.approveProposal(proposal.id) }
                    } onReject: {
                        Task { await store.rejectProposal(proposal.id, reason: nil) }
                    }
                    .listRowBackground(Color.clawCard)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
    }

    // MARK: - New Watcher Placeholder

    private var newWatcherPlaceholder: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "eyes")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.clawAccent)
                Text("New Watcher")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.clawTextStrong)
                Text("Watcher configuration UI coming in next sprint.\nGateway contract: background.agent.create")
                    .font(.subheadline)
                    .foregroundStyle(Color.clawMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clawBg)
            .navigationTitle("New Watcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showNewWatcher = false }
                        .tint(Color.clawAccent)
                }
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text(title).font(.headline).foregroundStyle(Color.clawMuted)
            Text(message).font(.subheadline).foregroundStyle(Color.clawMuted.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - WatcherRowView

struct WatcherRowView: View {
    let watcher: BackgroundWatcher

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(watcher.isEnabled ? Color.clawOk : Color.clawMuted.opacity(0.4))
                .frame(width: 8, height: 8)

            // Trigger icon
            Image(systemName: watcher.triggerType.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(Color.clawTeal)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(watcher.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                Text(watcher.condition)
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)

                if let last = watcher.lastTriggeredAt {
                    Text("Last: " + relativeTime(last))
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted.opacity(0.7))
                }
            }

            Spacer()

            if watcher.remediationEnabled {
                Image(systemName: "wand.and.stars")
                    .font(.caption2)
                    .foregroundStyle(Color.clawTeal.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = -date.timeIntervalSinceNow
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        if diff < 86400 { return "\(Int(diff/3600))h ago" }
        return "\(Int(diff/86400))d ago"
    }
}

// MARK: - IncidentRowView

struct IncidentRowView: View {
    let incident: Incident

    var body: some View {
        HStack(spacing: 12) {
            // Severity indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: incident.severity.colorHex))
                .frame(width: 3, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(incident.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                        .lineLimit(1)
                    Spacer()
                    Text(incident.severity.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: incident.severity.colorHex))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: incident.severity.colorHex).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(incident.description)
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Image(systemName: incident.status.systemImage)
                        .font(.caption2)
                    Text(incident.status.displayName)
                        .font(.caption2)
                    Text("·")
                    Text(incident.createdAt, style: .relative)
                        .font(.caption2)
                }
                .foregroundStyle(Color.clawMuted.opacity(0.7))
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - ProposalRowView

struct ProposalRowView: View {
    let proposal: AnomalyProposal
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Risk badge
                Text(proposal.riskLevel.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: proposal.riskLevel.colorHex))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: proposal.riskLevel.colorHex).opacity(0.12))
                    .clipShape(Capsule())

                Text(proposal.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                Spacer()

                Text(proposal.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }

            Text(proposal.description)
                .font(.caption)
                .foregroundStyle(Color.clawMuted)
                .lineLimit(2)

            if proposal.status == .pending {
                HStack(spacing: 8) {
                    Button(action: onApprove) {
                        Label("Approve", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.clawOk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.clawOk.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onReject) {
                        Label("Reject", systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.clawDanger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.clawDanger.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
