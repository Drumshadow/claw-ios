import SwiftUI

// MARK: - TerminalSessionListView
//
// Displays all terminal sessions (live and historical) from TerminalSessionStore.
// Groups sessions into Live and Ended sections.

struct TerminalSessionListView: View {
    @Environment(TerminalSessionStore.self) private var store: TerminalSessionStore?

    @State private var searchText: String = ""
    @State private var showOnlyLive: Bool = false
    @State private var showCreateTerminal = false

    private var liveSessions: [TerminalSession] {
        filtered.filter { $0.status.isLive }
    }

    private var endedSessions: [TerminalSession] {
        filtered.filter { !$0.status.isLive }
    }

    private var filtered: [TerminalSession] {
        let sessions = store?.sessions ?? (AppReviewSampleData.isEnabled ? TerminalSession.sampleSessions : [])
        var result = sessions

        if showOnlyLive {
            result = result.filter { $0.status.isLive }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                ($0.nodeName?.lowercased().contains(q) ?? false) ||
                $0.id.lowercased().contains(q)
            }
        }

        return result
    }

    var body: some View {
        Group {
            if filtered.isEmpty && (store?.sessions.isEmpty ?? true) {
                emptyState
            } else if filtered.isEmpty {
                noResultsState
            } else {
                sessionList
            }
        }
        .searchable(text: $searchText, prompt: "Search sessions…")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateTerminal = true
                } label: {
                    Label("New Terminal", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showCreateTerminal) {
            CreateTerminalSessionSheet(store: store)
        }
        .task { try? await store?.load() }
    }

    // MARK: - List

    private var sessionList: some View {
        List {
            if !liveSessions.isEmpty {
                Section {
                    ForEach(liveSessions) { session in
                        sessionRow(session)
                    }
                } header: {
                    sectionHeader("Live", count: liveSessions.count, color: .clawOk)
                }
                .listRowBackground(Color.clawCard)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            if !endedSessions.isEmpty {
                Section {
                    ForEach(endedSessions) { session in
                        sessionRow(session)
                    }
                } header: {
                    sectionHeader("History", count: endedSessions.count, color: .clawMuted)
                }
                .listRowBackground(Color.clawCard)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
    }

    @ViewBuilder
    private func sessionRow(_ session: TerminalSession) -> some View {
        NavigationLink(value: session) {
            TerminalSessionRowView(session: session)
        }
        .listRowBackground(Color.clawCard)
    }

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.clawMuted)
        }
        .textCase(nil)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44))
                .foregroundStyle(Color.clawMuted.opacity(0.3))
            Text("No Terminal Sessions")
                .font(.headline)
                .foregroundStyle(Color.clawTextStrong)
            Text("Start a command-backed terminal, or ask an agent to open a shell. Sessions and replay history appear here once the gateway reports them.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showCreateTerminal = true
            } label: {
                Label("Start Terminal", systemImage: "terminal.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.clawAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clawBg)
    }

    private var noResultsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No results for \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clawBg)
    }
}

private struct CreateTerminalSessionSheet: View {
    let store: TerminalSessionStore?
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var command = ""
    @State private var nodeId = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Health check", text: $title)
                    TextField("Optional runner/node id", text: $nodeId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Session")
                }

                Section {
                    TextField("docker ps", text: $command, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Command")
                } footer: {
                    Text("The gateway owns execution and approval policy. The app only requests a terminal session and streams the result.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.clawDanger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Start Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Starting…" : "Start") { Task { await create() } }
                        .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() async {
        guard let store else {
            errorMessage = "Connect to a gateway before starting terminals."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await store.createSession(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? command : title,
                command: command,
                nodeId: nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nodeId
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - TerminalSessionRowView

struct TerminalSessionRowView: View {
    let session: TerminalSession

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.clawTextStrong)
                        .lineLimit(1)

                    if session.isReplay {
                        Label("Replay", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.clawTeal)
                            .labelStyle(.iconOnly)
                    }
                }

                HStack(spacing: 8) {
                    if let node = session.nodeName ?? session.nodeId {
                        Label(node, systemImage: "server.rack")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.clawMuted)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }

                    if let dur = session.formattedDuration {
                        Text(dur)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.clawMuted)
                    }

                    if let code = session.exitCode {
                        Text("exit \(code)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(code == 0 ? Color.clawOk : Color.clawDanger)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background((code == 0 ? Color.clawOk : Color.clawDanger).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Spacer(minLength: 0)

            // Relative time
            Text(session.startedAt.relativeShort)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(session.status.iconBackground)
                .frame(width: 32, height: 32)
            Image(systemName: session.status.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(session.status.iconForeground)
        }
    }
}

// MARK: - TerminalSessionStatus display helpers

private extension TerminalSessionStatus {
    var iconName: String {
        switch self {
        case .active:  return "dot.radiowaves.right"
        case .idle:    return "terminal"
        case .ended:   return "clock.arrow.circlepath"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }

    var iconBackground: Color {
        switch self {
        case .active:  return Color.clawOk.opacity(0.14)
        case .idle:    return Color.clawTeal.opacity(0.12)
        case .ended:   return Color.clawMuted.opacity(0.08)
        case .error:   return Color.clawDanger.opacity(0.12)
        }
    }

    var iconForeground: Color {
        switch self {
        case .active:  return Color.clawOk
        case .idle:    return Color.clawTeal
        case .ended:   return Color.clawMuted
        case .error:   return Color.clawDanger
        }
    }
}

// MARK: - Date relative formatting

private extension Date {
    var relativeShort: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }
}

// MARK: - Previews

#Preview("Terminal Sessions") {
    NavigationStack {
        TerminalSessionListView()
            .navigationTitle("Terminal")
    }
    .preferredColorScheme(.dark)
}
