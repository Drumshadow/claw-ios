import SwiftUI

// MARK: - ClawAgentInfo (local read-only model)

struct ClawAgentInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let workspace: String
    let runtime: String
    /// All other fields returned by `agents.list`, surfaced in the detail view.
    let raw: [String: JSONValue]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClawAgentInfo, rhs: ClawAgentInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AgentsConfigView

/// Read-only list of configured agents on the gateway.
/// Tap a row to see the agent's full config JSON.
struct AgentsConfigView: View {
    @Environment(AppState.self) private var appState

    @State private var agents: [ClawAgentInfo] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var selectedAgent: ClawAgentInfo?

    var body: some View {
        ScrollView {
            Group {
                if isLoading && agents.isEmpty {
                    loadingView
                } else if let err = loadError, agents.isEmpty {
                    errorView(err)
                } else if agents.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 10) {
                        ForEach(agents) { agent in
                            Button {
                                selectedAgent = agent
                            } label: {
                                AgentRow(agent: agent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            await loadAgents()
        }
        .navigationTitle("Agents & Models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selectedAgent) { agent in
            AgentDetailView(agent: agent)
        }
        .task {
            if agents.isEmpty { await loadAgents() }
        }
    }

    // MARK: - Load

    private func loadAgents() async {
        guard let client = appState.activeClient else {
            loadError = "Not connected to a gateway"
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let payload = try await client.send(method: GatewayMethod.agentsList, params: EmptyAgentsParams())
            agents = parseAgents(payload: payload)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func parseAgents(payload: [String: JSONValue]) -> [ClawAgentInfo] {
        let arr: [JSONValue]
        if let v = payload["agents"], case .array(let a) = v {
            arr = a
        } else {
            return []
        }

        var result: [ClawAgentInfo] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            guard let idVal = obj["id"], case .string(let id) = idVal, !id.isEmpty else { continue }

            let name: String
            if let v = obj["name"], case .string(let s) = v, !s.isEmpty {
                name = s
            } else {
                name = id
            }

            let workspace: String
            if let v = obj["workspace"], case .string(let s) = v {
                workspace = s
            } else {
                workspace = ""
            }

            let runtime: String
            if let v = obj["runtime"], case .string(let s) = v {
                runtime = s
            } else {
                runtime = ""
            }

            result.append(ClawAgentInfo(
                id: id,
                name: name,
                workspace: workspace,
                runtime: runtime,
                raw: obj
            ))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            ProgressView("Loading agents…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No agents configured")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
            Text("The gateway has no agents registered.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.clawDanger)
            Text("Could not load agents")
                .font(.headline)
                .foregroundStyle(Color.clawTextStrong)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }
}

// MARK: - AgentRow

private struct AgentRow: View {
    let agent: ClawAgentInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 20))
                .foregroundStyle(Color.clawAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                Text(agent.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !agent.runtime.isEmpty {
                        labelChip(agent.runtime)
                    }
                    if !agent.workspace.isEmpty {
                        Text(agent.workspace)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.clawMuted.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.clawMuted.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.clawTeal)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.clawTeal.opacity(0.12)))
    }
}

// MARK: - AgentDetailView

struct AgentDetailView: View {
    let agent: ClawAgentInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Configuration")
                    VStack(spacing: 0) {
                        ForEach(sortedRawEntries, id: \.0) { key, value in
                            ConfigKVRow(key: key, value: value)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clawCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(agent.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.clawTextStrong)
            Text(agent.id)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.clawMuted)
                .textSelection(.enabled)
            if !agent.runtime.isEmpty {
                Text("Runtime: \(agent.runtime)")
                    .font(.subheadline)
                    .foregroundStyle(Color.clawText)
            }
            if !agent.workspace.isEmpty {
                Text("Workspace: \(agent.workspace)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.clawText)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.clawMuted)
            .textCase(.uppercase)
    }

    private var sortedRawEntries: [(String, JSONValue)] {
        agent.raw
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }
}

// MARK: - ConfigKVRow

struct ConfigKVRow: View {
    let key: String
    let value: JSONValue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.clawMuted)
                .frame(width: 110, alignment: .leading)

            Text(displayValue)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.clawText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.clawBorder.opacity(0.5))
                .frame(height: 1)
                .padding(.horizontal, 12)
        }
    }

    private var displayValue: String {
        JSONFormat.compact(value)
    }
}

// MARK: - JSON formatting helpers

enum JSONFormat {
    static func compact(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return s
        case .array(let arr):
            if arr.isEmpty { return "[]" }
            let parts = arr.map { compact($0) }
            return "[\(parts.joined(separator: ", "))]"
        case .object(let obj):
            if obj.isEmpty { return "{}" }
            let parts = obj
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \(compact($0.value))" }
            return "{ \(parts.joined(separator: ", ")) }"
        }
    }
}

private struct EmptyAgentsParams: Encodable {}
