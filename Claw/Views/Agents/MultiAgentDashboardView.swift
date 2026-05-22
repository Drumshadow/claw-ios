import SwiftUI
import Charts

// MARK: - MultiAgentDashboardView
//
// Live parent/child agent tree with task ownership, dependencies,
// communication timeline, and resource usage.
//
// Data sources:
//   - SessionStore (session list for tree building)
//   - AgentMonitorStore (live status, resource usage)
//   - BackgroundAgentStore (incident/watcher counts)

struct MultiAgentDashboardView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(AgentMonitorStore.self) private var agentMonitor
    @Environment(BackgroundAgentStore.self) private var bgAgentStore

    @State private var selectedNodeId: String? = nil
    @State private var viewMode: ViewMode = .tree
    @State private var communicationLog: [AgentMessage] = AgentMessage.previewMessages

    enum ViewMode: String, CaseIterable {
        case tree = "Tree"
        case list = "List"
        case comms = "Comms"
    }

    // MARK: - Computed

    private var rootSessions: [ClawSession] {
        sessionStore.sessions.filter { session in
            !sessionStore.sessions.contains { $0.childSessionKeys.contains(session.id) }
        }
    }

    private var allNodes: [AgentTreeNode] {
        guard let first = rootSessions.first else { return [] }
        guard let root = AgentTreeNode.buildTree(from: sessionStore.sessions, rootId: first.id) else { return [] }
        return root.flatten()
    }

    private var rootNode: AgentTreeNode? {
        guard let first = rootSessions.first else { return nil }
        return AgentTreeNode.buildTree(from: sessionStore.sessions, rootId: first.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clawBgAccent)

            Divider().background(Color.clawBorder)

            // Stats strip
            agentStatsStrip

            Divider().background(Color.clawBorder)

            // Content
            switch viewMode {
            case .tree:
                treeContent
            case .list:
                listContent
            case .comms:
                commsContent
            }
        }
        .background(Color.clawBg)
        .navigationTitle("Agent Network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await agentMonitor.refresh() }
        .refreshable { await agentMonitor.refresh() }
    }

    // MARK: - Stats Strip

    private var agentStatsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                statChip(
                    icon: "cpu",
                    value: "\(agentMonitor.runningCount)",
                    label: "Running",
                    color: agentMonitor.runningCount > 0 ? .clawOk : .clawMuted
                )
                statChip(
                    icon: "exclamationmark.triangle",
                    value: "\(bgAgentStore.activeIncidents.count)",
                    label: "Incidents",
                    color: bgAgentStore.activeIncidents.isEmpty ? .clawMuted : .clawWarn
                )
                statChip(
                    icon: "eye",
                    value: "\(bgAgentStore.enabledWatchers.count)",
                    label: "Watchers",
                    color: .clawTeal
                )
                statChip(
                    icon: "lightbulb",
                    value: "\(bgAgentStore.pendingProposals.count)",
                    label: "Proposals",
                    color: bgAgentStore.pendingProposals.isEmpty ? .clawMuted : .clawAccent
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.clawBgAccent)
    }

    private func statChip(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Tree View

    private var treeContent: some View {
        AgentTreeView(
            rootNode: rootNode,
            allNodes: allNodes,
            onSelectNode: { id in selectedNodeId = id }
        )
    }

    // MARK: - List View

    private var listContent: some View {
        List {
            ForEach(agentMonitor.sessions) { session in
                AgentMonitorRow(session: session)
                    .listRowBackground(Color.clawCard)
            }
            if agentMonitor.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.clawMuted.opacity(0.4))
                    Text("No agent sessions")
                        .font(.headline).foregroundStyle(Color.clawMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .listRowBackground(Color.clawBg)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
    }

    // MARK: - Communications View

    private var commsContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(communicationLog) { msg in
                    AgentMessageRow(message: msg)
                    Divider().background(Color.clawBorder).padding(.leading, 52)
                }
            }
        }
        .background(Color.clawBg)
    }
}

// MARK: - AgentMonitorRow

struct AgentMonitorRow: View {
    let session: AgentMonitorSession

    var body: some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(session.status == .running ? Color.clawOk : session.status == .error ? Color.clawDanger : Color.clawMuted.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let model = session.model {
                        Text(model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model)
                            .font(.caption2)
                            .foregroundStyle(Color.clawTeal.opacity(0.8))
                    }
                    if let msg = session.lastMessage {
                        Text(msg).font(.caption2).foregroundStyle(Color.clawMuted).lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(session.status.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(session.status.isActive ? Color.clawOk : Color.clawMuted)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AgentMessage (inter-agent communication)

struct AgentMessage: Identifiable {
    let id: String
    var fromAgent: String
    var toAgent: String
    var content: String
    var timestamp: Date
    var kind: MessageKind

    enum MessageKind: String {
        case taskDelegation = "task"
        case statusUpdate   = "status"
        case dataRequest    = "request"
        case dataResponse   = "response"
        case error          = "error"
    }

    static let previewMessages: [AgentMessage] = [
        AgentMessage(id: "m1", fromAgent: "Main", toAgent: "Explore", content: "Search for all usages of `fetchUser` across the codebase", timestamp: Date().addingTimeInterval(-120), kind: .taskDelegation),
        AgentMessage(id: "m2", fromAgent: "Explore", toAgent: "Main", content: "Found 14 usages across 6 files. Returning results.", timestamp: Date().addingTimeInterval(-90), kind: .dataResponse),
        AgentMessage(id: "m3", fromAgent: "Main", toAgent: "Plan", content: "Design a refactor plan for the auth module based on these findings", timestamp: Date().addingTimeInterval(-60), kind: .taskDelegation),
        AgentMessage(id: "m4", fromAgent: "Plan", toAgent: "Main", content: "Refactor plan ready: 3 phases, estimated 2h total", timestamp: Date().addingTimeInterval(-30), kind: .dataResponse),
    ]
}

// MARK: - AgentMessageRow

struct AgentMessageRow: View {
    let message: AgentMessage

    private var kindColor: Color {
        switch message.kind {
        case .taskDelegation: return .clawAccent
        case .statusUpdate:   return .clawTeal
        case .dataRequest:    return .clawWarn
        case .dataResponse:   return .clawOk
        case .error:          return .clawDanger
        }
    }

    private var kindIcon: String {
        switch message.kind {
        case .taskDelegation: return "arrow.right.circle"
        case .statusUpdate:   return "info.circle"
        case .dataRequest:    return "questionmark.circle"
        case .dataResponse:   return "checkmark.circle"
        case .error:          return "exclamationmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kindIcon)
                .font(.system(size: 16))
                .foregroundStyle(kindColor)
                .frame(width: 32)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(message.fromAgent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted)
                    Text(message.toAgent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                    Spacer()
                    Text(message.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted)
                }
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
