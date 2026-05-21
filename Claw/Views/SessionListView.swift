import SwiftUI

// MARK: - SessionListView

struct SessionListView: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppState.self) private var appState
    let onSelect: (ClawSession) -> Void

    @State private var showNewSession: Bool = false
    @State private var showOps: Bool = false
    @State private var showAgentMonitor: Bool = false
    @State private var agentMonitorStore: AgentMonitorStore?
    @State private var pendingDelete: ClawSession?
    @State private var deleteError: String?
    @State private var searchText: String = ""
    @State private var statusFilter: SessionStatusFilter = .all
    @State private var sessionToRename: ClawSession?
    @State private var renameText: String = ""
    @State private var showRenameAlert: Bool = false

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredSessions: [ClawSession] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.sessions.filter { session in
            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .running:
                switch session.agentStatus {
                case .running, .thinking: matchesStatus = true
                case .idle: matchesStatus = false
                }
            case .idle: matchesStatus = session.agentStatus == .idle
            }
            guard matchesStatus else { return false }

            if trimmed.isEmpty { return true }
            if session.title.lowercased().contains(trimmed) { return true }
            if let last = session.lastMessage?.lowercased(), last.contains(trimmed) { return true }
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterChipsRow

                Group {
                    if store.isLoading && store.sessions.isEmpty {
                        loadingView
                    } else if store.sessions.isEmpty {
                        emptyStateView
                    } else if filteredSessions.isEmpty {
                        noMatchesView
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredSessions) { session in
                                Button {
                                    onSelect(session)
                                } label: {
                                    SessionCardView(session: session)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        let isPinned = session.isPinned
                                        if isPinned { store.unpinSession(id: session.id) }
                                        else { store.pinSession(id: session.id) }
                                    } label: {
                                        Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
                                    }

                                    Button {
                                        sessionToRename = session
                                        renameText = session.title
                                        showRenameAlert = true
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        pendingDelete = session
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                // Force a new view identity when display-relevant fields change.
                                // ClawSession.== only compares id, so SwiftUI would otherwise skip
                                // re-rendering when title, pin state, or agent status changes.
                                .id("\(session.id)|\(session.isPinned)|\(session.title)|\(session.agentStatus.rawValue)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sessions")
        .refreshable {
            try? await store.load()
        }
        .task {
            if agentMonitorStore == nil, let client = appState.activeClient {
                agentMonitorStore = AgentMonitorStore(client: client)
                await agentMonitorStore?.refresh()
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAgentMonitor = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "cpu")
                            .font(.system(size: 16))
                        if let count = agentMonitorStore?.runningCount, count > 0 {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .tint(Color.clawAccent)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showOps = true
                } label: {
                    Label("Remote Ops", systemImage: "server.rack")
                }
                .tint(Color.clawAccent)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewSession = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .tint(Color.clawAccent)
            }
        }
        .sheet(isPresented: $showAgentMonitor) {
            if let monitorStore = agentMonitorStore {
                AgentMonitorView(store: monitorStore)
            }
        }
        .sheet(isPresented: $showOps) {
            RemoteOpsDashboardView()
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionView(onCreated: { key in Task { @MainActor in try? await Task.sleep(nanoseconds: 400_000_000); if let session = store.sessions.first(where: { $0.id == key }) { onSelect(session) } } })
                .environment(store)
        }
        .confirmationDialog(
            "Delete session?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { session in
            Button("Delete \"\(session.title)\"", role: .destructive) {
                Task { await performDelete(session) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { _ in
            Text("This permanently removes the session and its transcript.")
        }
        .alert(
            "Delete failed",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            ),
            presenting: deleteError
        ) { _ in
            Button("OK") { deleteError = nil }
        } message: { detail in
            Text(detail)
        }
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Session name", text: $renameText)
            Button("Rename") {
                // sessionToRename is NOT cleared by this binding, so it's safe to read here.
                if let s = sessionToRename {
                    Task { await store.renameSession(id: s.id, newLabel: renameText) }
                }
                sessionToRename = nil
            }
            Button("Cancel", role: .cancel) { sessionToRename = nil }
        } message: {
            Text("Enter a new name for this session.")
        }
    }

    // MARK: - Actions

    private func performDelete(_ session: ClawSession) async {
        pendingDelete = nil
        do {
            try await store.deleteSession(id: session.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            ProgressView("Loading sessions…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))

            Text("No sessions yet")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)

            Text("Tap + to start a new session.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    private var noMatchesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No sessions match")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    // MARK: - Filter chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SessionStatusFilter.allCases) { option in
                    FilterChipView(
                        title: option.title,
                        isSelected: statusFilter == option
                    ) {
                        statusFilter = option
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.clawBg)
    }
}

// MARK: - SessionStatusFilter

enum SessionStatusFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case idle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .idle: return "Idle"
        }
    }
}

// MARK: - FilterChipView

private struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.clawTextStrong : Color.clawMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.clawAccentSubtle : Color.clawBgAccent)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clawAccent : Color.clawBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SessionCardView

struct SessionCardView: View {
    let session: ClawSession

    private var isActive: Bool {
        switch session.agentStatus {
        case .thinking, .running: return true
        case .idle: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: status dot + unread badge
            HStack(alignment: .top) {
                Text(session.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.clawAccent)
                }

                statusDot
            }

            // Last message preview
            if let lastMessage = session.lastMessage, !lastMessage.isEmpty {
                Text(lastMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No messages")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted.opacity(0.6))
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // Bottom row: last active time + unread
            HStack(spacing: 6) {
                if let date = session.lastMessageAt {
                    Text(relativeDate(date))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                }

                Spacer()

                if session.unreadCount > 0 {
                    Text("\(min(session.unreadCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.clawAccent))
                }
            }
        }
        .padding(12)
        .frame(height: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isActive ? Color.clawAccent : Color.clawBorder,
                    lineWidth: isActive ? 1.5 : 1
                )
        )
        .shadow(
            color: isActive ? Color.clawAccentGlow : .clear,
            radius: isActive ? 8 : 0
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Status dot

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(statusDotColor.opacity(0.3), lineWidth: 3)
                    .scaleEffect(isActive ? 1.6 : 1)
                    .opacity(isActive ? 0.6 : 0)
            )
    }

    private var statusDotColor: Color {
        switch session.agentStatus {
        case .idle:     return Color.clawMuted.opacity(0.5)
        case .thinking: return Color.clawWarn
        case .running:  return Color.clawOk
        }
    }

    // MARK: - Date formatting

    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return Self.shortDateFormatter.string(from: date)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
}
