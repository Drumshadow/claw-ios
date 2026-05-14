import SwiftUI

// MARK: - ConnectedView

/// Root view shown after a successful connection.
/// Uses NavigationSplitView on iPad (sidebar + detail) and NavigationStack on iPhone.
struct ConnectedView: View {
    @Environment(AppState.self) private var appState

    // Stores are owned here and injected into child views via environment.
    @State private var sessionStore: SessionStore?
    @State private var nodeStore: NodeStore?
    @State private var skillsStore: SkillsStore?
    @State private var toolApprovalStore: ToolApprovalStore?
    @State private var memoryStore: MemoryStore?
    @State private var cronStore: CronStore?

    var body: some View {
        Group {
            if let sessions = sessionStore,
               let nodes = nodeStore,
               let skills = skillsStore,
               let client = appState.activeClient {
                content(sessions: sessions, nodes: nodes, skills: skills, client: client)
            } else {
                ZStack {
                    Color.clawBg.ignoresSafeArea()
                    ProgressView("Preparing…")
                        .tint(Color.clawAccent)
                        .foregroundStyle(Color.clawMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { setupStoresIfNeeded() }
        .onChange(of: appState.activeClient != nil) { _, hasClient in
            if hasClient { setupStoresIfNeeded() }
        }
        // Connection banner overlaid at the top of the whole connected experience
        .connectionBanner(state: appState.connectionState) {
            guard let config = appState.selectedConfig else { return }
            Task { await appState.connect(to: config) }
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private func content(sessions: SessionStore, nodes: NodeStore, skills: SkillsStore, client: GatewayClient) -> some View {
        if let approvalStore = toolApprovalStore,
           let memStore = memoryStore,
           let cStore = cronStore {
            AdaptiveSessionsLayout(client: client)
                .environment(sessions)
                .environment(nodes)
                .environment(skills)
                .environment(approvalStore)
                .environment(memStore)
                .environment(cStore)
        } else {
            AdaptiveSessionsLayout(client: client)
                .environment(sessions)
                .environment(nodes)
                .environment(skills)
        }
    }

    // MARK: - Setup

    private func setupStoresIfNeeded() {
        guard let client = appState.activeClient else { return }
        if sessionStore == nil {
            let store = SessionStore(client: client)
            sessionStore = store
            Task { try? await store.load() }
        }
        if nodeStore == nil {
            let store = NodeStore(client: client)
            nodeStore = store
            Task { try? await store.load() }
        }
        if skillsStore == nil {
            let store = SkillsStore(client: client)
            skillsStore = store
            Task { try? await store.load() }
        }
        if toolApprovalStore == nil {
            toolApprovalStore = ToolApprovalStore(client: client)
        }
        if memoryStore == nil {
            let store = MemoryStore(client: client)
            memoryStore = store
            Task { try? await store.reload() }
        }
        if cronStore == nil {
            let store = CronStore(client: client)
            cronStore = store
            Task { try? await store.load() }
        }
    }
}

// MARK: - AdaptiveSessionsLayout

/// Adapts between iPad split view and iPhone stack navigation.
struct AdaptiveSessionsLayout: View {
    let client: GatewayClient

    @Environment(SessionStore.self) private var sessionStore
    @Environment(NodeStore.self) private var nodeStore
    @Environment(AppState.self) private var appState
    @Environment(ToolApprovalStore.self) private var toolApprovalStore
    @State private var selectedSession: ClawSession?
    @State private var showSettings = false
    @State private var showNodes = false
    @State private var sidebarSelection: SidebarItem? = .sessions

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showNodes) {
            NavigationStack {
                NodeListView()
                    .environment(nodeStore)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showNodes = false }
                                .fontWeight(.semibold)
                                .tint(Color.clawAccent)
                        }
                    }
            }
        }
        .sheet(isPresented: Binding(
            get: { toolApprovalStore.pendingApprovals.first != nil },
            set: { _ in }
        )) {
            if let req = toolApprovalStore.pendingApprovals.first {
                ToolApprovalSheet(request: req, store: toolApprovalStore)
            }
        }
    }

    // MARK: - iPad: NavigationSplitView (sidebar with Sessions + Nodes)

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(Optional(item))
                    }
                } header: {
                    Text("Browse")
                        .foregroundStyle(Color.clawMuted)
                }
                .listRowBackground(Color.clawCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Claw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                settingsButton
                disconnectButton
            }
        } content: {
            NavigationStack {
                switch sidebarSelection ?? .sessions {
                case .sessions:
                    SessionListView(onSelect: { session in
                        selectedSession = session
                    })
                    .environment(sessionStore)
                case .nodes:
                    NodeListView()
                        .environment(nodeStore)
                }
            }
        } detail: {
            if sidebarSelection == .sessions, let session = selectedSession {
                NavigationStack {
                    ChatThreadView(
                        session: session,
                        client: client,
                        onOpenChildSession: { child in
                            selectedSession = child
                        }
                    )
                    .environment(sessionStore)
                    .id(session.id)
                }
            } else {
                noSessionSelectedView
            }
        }
    }

    // MARK: - iPhone: NavigationStack

    private var iPhoneLayout: some View {
        NavigationStack {
            SessionListView(onSelect: { session in
                selectedSession = session
            })
            .environment(sessionStore)
            .navigationDestination(item: $selectedSession) { session in
                ChatThreadView(
                    session: session,
                    client: client,
                    onOpenChildSession: { child in
                        selectedSession = child
                    }
                )
                .environment(sessionStore)
                .id(session.id)
            }
            .toolbar {
                settingsButton
                nodesButton
                disconnectButton
            }
        }
    }

    // MARK: - No-selection placeholder (iPad only)

    private var noSessionSelectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: sidebarSelection == .nodes ? "macbook.and.iphone" : "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text(sidebarSelection == .nodes ? "Select a node" : "Select a session")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clawBg)
    }

    // MARK: - Toolbar items

    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .tint(Color.clawAccent)
        }
    }

    @ToolbarContentBuilder
    private var nodesButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showNodes = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "macbook.and.iphone")
                    if nodeStore.pendingNodes.count > 0 {
                        Circle()
                            .fill(Color.clawAccent)
                            .frame(width: 8, height: 8)
                            .offset(x: 6, y: -4)
                    }
                }
            }
            .accessibilityLabel("Nodes")
            .tint(Color.clawAccent)
        }
    }

    @ToolbarContentBuilder
    private var disconnectButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(role: .destructive) {
                Task { await appState.disconnect() }
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .tint(Color.clawDanger)
        }
    }
}

// MARK: - Sidebar items (iPad)

private enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case sessions
    case nodes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "Sessions"
        case .nodes: return "Nodes"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: return "bubble.left.and.bubble.right"
        case .nodes: return "macbook.and.iphone"
        }
    }
}
