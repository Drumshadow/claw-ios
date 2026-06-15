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
    @State private var terminalSessionStore: TerminalSessionStore?
    @State private var runbookStore: RunbookStore?
    @State private var modelRouterStore: ModelRouterStore?
    @State private var storeClientID: ObjectIdentifier?

    // Stream 7–14 stores
    @State private var agentMonitorStore: AgentMonitorStore?
    @State private var bgAgentStore: BackgroundAgentStore?
    @State private var timelineStore: MemoryTimelineStore?

    var body: some View {
        Group {
            if let sessions = sessionStore,
               let nodes = nodeStore,
               let skills = skillsStore,
               let client = appState.activeClient,
               let agentMon = agentMonitorStore,
               let bgAgent = bgAgentStore,
               let timeline = timelineStore,
               let modelRouter = modelRouterStore,
               let approvalStore = toolApprovalStore,
               let memStore = memoryStore,
               let cStore = cronStore,
               let terminalStore = terminalSessionStore,
               let runbookStore = runbookStore {
                content(sessions: sessions, nodes: nodes, skills: skills, client: client,
                        approvalStore: approvalStore, memStore: memStore, cStore: cStore,
                        terminalStore: terminalStore, runbookStore: runbookStore,
                        agentMon: agentMon, bgAgent: bgAgent, timeline: timeline, modelRouter: modelRouter)
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
        .onChange(of: appState.connectionState) { _, state in
            if case .connected = state { setupStoresIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshDynamicStores()
        }
        // Connection banner overlaid at the top of the whole connected experience
        .connectionBanner(state: appState.connectionState) {
            guard let config = appState.selectedConfig else { return }
            Task { await appState.connect(to: config) }
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private func content(
        sessions: SessionStore,
        nodes: NodeStore,
        skills: SkillsStore,
        client: GatewayClient,
        approvalStore: ToolApprovalStore,
        memStore: MemoryStore,
        cStore: CronStore,
        terminalStore: TerminalSessionStore,
        runbookStore: RunbookStore,
        agentMon: AgentMonitorStore,
        bgAgent: BackgroundAgentStore,
        timeline: MemoryTimelineStore,
        modelRouter: ModelRouterStore
    ) -> some View {
        AdaptiveSessionsLayout(client: client)
            .environment(sessions)
            .environment(nodes)
            .environment(skills)
            .environment(approvalStore)
            .environment(memStore)
            .environment(cStore)
            .environment(terminalStore)
            .environment(runbookStore)
            .environment(modelRouter)
            .environment(agentMon)
            .environment(bgAgent)
            .environment(timeline)
    }

    // MARK: - Setup

    private func setupStoresIfNeeded() {
        guard let client = appState.activeClient else { return }
        let clientID = ObjectIdentifier(client)
        if storeClientID != clientID {
            resetStores(for: client, clientID: clientID)
            return
        }
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
        if terminalSessionStore == nil {
            let store = TerminalSessionStore(client: client)
            terminalSessionStore = store
            Task { try? await store.load() }
        }
        if runbookStore == nil {
            let store = RunbookStore(client: client)
            runbookStore = store
            Task { try? await store.load() }
        }
        if modelRouterStore == nil {
            let store = ModelRouterStore(client: client)
            modelRouterStore = store
            Task { await store.fetchAvailableModels() }
        }
        if agentMonitorStore == nil {
            let store = AgentMonitorStore(client: client)
            agentMonitorStore = store
            Task { await store.refresh() }
        }
        if bgAgentStore == nil {
            let store = BackgroundAgentStore(client: client)
            bgAgentStore = store
            Task { await store.loadAll() }
        }
        if timelineStore == nil {
            let store = MemoryTimelineStore(client: client)
            timelineStore = store
            Task { try? await store.reload() }
        }
    }

    private func resetStores(for client: GatewayClient, clientID: ObjectIdentifier) {
        storeClientID = clientID

        let sessions = SessionStore(client: client)
        sessionStore = sessions
        Task { try? await sessions.load() }

        let nodes = NodeStore(client: client)
        nodeStore = nodes
        Task { try? await nodes.load() }

        let skills = SkillsStore(client: client)
        skillsStore = skills
        Task { try? await skills.load() }

        toolApprovalStore = ToolApprovalStore(client: client)

        let memory = MemoryStore(client: client)
        memoryStore = memory
        Task { try? await memory.reload() }

        let cron = CronStore(client: client)
        cronStore = cron
        Task { try? await cron.load() }

        let terminalSessions = TerminalSessionStore(client: client)
        terminalSessionStore = terminalSessions
        Task { try? await terminalSessions.load() }

        let runbooks = RunbookStore(client: client)
        runbookStore = runbooks
        Task { try? await runbooks.load() }

        let modelRouter = ModelRouterStore(client: client)
        modelRouterStore = modelRouter
        Task { await modelRouter.fetchAvailableModels() }

        let agentMonitor = AgentMonitorStore(client: client)
        agentMonitorStore = agentMonitor
        Task { await agentMonitor.refresh() }

        let bgAgents = BackgroundAgentStore(client: client)
        bgAgentStore = bgAgents
        Task { await bgAgents.loadAll() }

        let timeline = MemoryTimelineStore(client: client)
        timelineStore = timeline
        Task { try? await timeline.reload() }
    }

    private func refreshDynamicStores() {
        Task {
            if let sessionStore { try? await sessionStore.load() }
            if let nodeStore { try? await nodeStore.load() }
            if let skillsStore { try? await skillsStore.load() }
            if let memoryStore { try? await memoryStore.reload() }
            if let cronStore { try? await cronStore.load() }
            if let terminalSessionStore { try? await terminalSessionStore.load() }
            if let runbookStore { try? await runbookStore.load() }
            if let modelRouterStore { await modelRouterStore.fetchAvailableModels() }
            if let agentMonitorStore { await agentMonitorStore.refresh() }
            if let bgAgentStore { await bgAgentStore.loadAll() }
            if let timelineStore { try? await timelineStore.reload() }
        }
    }
}

// MARK: - AdaptiveSessionsLayout

/// Adapts between iPad split view and iPhone stack navigation.
struct AdaptiveSessionsLayout: View {
    let client: GatewayClient

    @Environment(SessionStore.self) private var sessionStore
    @Environment(NodeStore.self) private var nodeStore
    @Environment(SkillsStore.self) private var skillsStore
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(CronStore.self) private var cronStore
    @Environment(AppState.self) private var appState
    @Environment(ToolApprovalStore.self) private var toolApprovalStore
    @Environment(TerminalSessionStore.self) private var terminalSessionStore: TerminalSessionStore?
    @Environment(RunbookStore.self) private var runbookStore: RunbookStore?
    @Environment(AgentMonitorStore.self) private var agentMonitorStore
    @Environment(BackgroundAgentStore.self) private var bgAgentStore
    @Environment(MemoryTimelineStore.self) private var timelineStore
    @State private var selectedSession: ClawSession?
    @SceneStorage("claw.selectedSessionID") private var selectedSessionID: String?
    @State private var showSettings = false
    @State private var showNodes = false
    @State private var sidebarSelection: SidebarItem? = .sessions
    @State private var router = NavigationRouter()

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
        .onAppear { restoreSelectedSessionIfNeeded() }
        .onChange(of: sessionStore.sessions.map(\.id)) { _, _ in
            restoreSelectedSessionIfNeeded()
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
                        selectSession(session)
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
                            selectSession(child)
                        }
                    )
                    .environment(sessionStore)
                    .environment(skillsStore)
                    .environment(agentMonitorStore)
                    .id(session.id)
                }
            } else {
                noSessionSelectedView
            }
        }
    }

    // MARK: - iPhone: TabView with 4 tabs

    private var iPhoneLayout: some View {
        TabView(selection: Bindable(router).selectedTab) {
            // MARK: Chat tab
            NavigationStack {
                SessionListView(onSelect: { session in
                    selectSession(session)
                })
                .environment(sessionStore)
                .navigationDestination(item: $selectedSession) { session in
                    ChatThreadView(
                        session: session,
                        client: client,
                        onOpenChildSession: { child in
                            selectSession(child)
                        }
                    )
                    .environment(sessionStore)
                    .environment(skillsStore)
                    .environment(agentMonitorStore)
                    .id(session.id)
                }
                .toolbar {
                    nodesButton
                    disconnectButton
                }
            }
            .tabItem { Label(ClawTab.chat.title, systemImage: ClawTab.chat.systemImage) }
            .tag(ClawTab.chat)

            // MARK: Ops tab
            NavigationStack {
                OpsTabView()
                    .environment(terminalSessionStore)
                    .environment(runbookStore)
            }
            .tabItem { Label(ClawTab.ops.title, systemImage: ClawTab.ops.systemImage) }
            .tag(ClawTab.ops)

            // MARK: Dashboard tab
            NavigationStack {
                DashboardTabView()
                    .environment(appState)
                    .environment(sessionStore)
                    .environment(agentMonitorStore)
                    .environment(bgAgentStore)
                    .environment(timelineStore)
            }
            .tabItem { Label(ClawTab.dashboard.title, systemImage: ClawTab.dashboard.systemImage) }
            .tag(ClawTab.dashboard)

            // MARK: More tab
            NavigationStack {
                MoreTabView(client: client)
                    .environment(appState)
                    .environment(sessionStore)
                    .environment(skillsStore)
                    .environment(memoryStore)
                    .environment(cronStore)
                    .environment(nodeStore)
                    .environment(agentMonitorStore)
                    .environment(bgAgentStore)
                    .environment(timelineStore)
            }
            .tabItem { Label(ClawTab.more.title, systemImage: ClawTab.more.systemImage) }
            .tag(ClawTab.more)
        }
        .tint(Color.clawAccent)
    }

    // MARK: - Selection persistence

    private func selectSession(_ session: ClawSession) {
        selectedSession = session
        selectedSessionID = session.id
        sidebarSelection = .sessions
    }

    private func restoreSelectedSessionIfNeeded() {
        guard let id = selectedSessionID else { return }
        guard let restored = sessionStore.sessions.first(where: { $0.id == id }) else { return }
        selectedSession = restored
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
