import SwiftUI

// MARK: - DashboardTabView
//
// Root entry point for the Mission Control tab.
// Owns TopologyStore and DashboardStore; feeds live data from
// SessionStore / ToolApprovalStore into dashboardStore periodically.

struct DashboardTabView: View {

    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToolApprovalStore.self) private var approvalStore

    @State private var dashboardStore: DashboardStore = DashboardStore()
    @State private var topologyStore: TopologyStore?

    var body: some View {
        Group {
            if let topoStore = topologyStore {
                MissionControlView(
                    dashboardStore: dashboardStore,
                    topologyStore: topoStore
                )
            } else {
                bootingView
            }
        }
        .onAppear { setupIfNeeded() }
        .onChange(of: appState.activeClient != nil) { _, hasClient in
            if hasClient { setupIfNeeded() }
        }
        .task(id: appState.activeClient != nil) {
            while !Task.isCancelled {
                syncLiveData()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppReviewSampleData.didChangeNotification)) { _ in
            if AppReviewSampleData.isEnabled {
                dashboardStore.loadAppReviewSampleData()
                topologyStore?.loadAppReviewSampleData()
            }
        }
    }

    private var bootingView: some View {
        ZStack {
            Color.clawBg.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Color.clawAccent)
                Text("Initialising Mission Control…")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .navigationTitle("Mission Control")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func setupIfNeeded() {
        guard let client = appState.activeClient else { return }
        if topologyStore == nil {
            let store = TopologyStore(client: client)
            topologyStore = store
            Task { await store.start() }
        }
    }

    private func syncLiveData() {
        if AppReviewSampleData.isEnabled {
            dashboardStore.loadAppReviewSampleData()
            return
        }
        let sessions = sessionStore.sessions
        let active = sessions.count
        let running = sessions.filter { $0.agentStatus == .running || $0.agentStatus == .thinking }.count
        let pending = approvalStore.pendingApprovals.count

        dashboardStore.updateLiveData(
            activeSessions: active,
            runningAgents: running,
            pendingApprovals: pending,
            cronRecentFailures: 0,
            totalTokensToday: sessions.reduce(0) { $0 + ($1.totalTokens ?? 0) },
            totalCostTodayUsd: sessions.reduce(0) { $0 + ($1.estimatedCostUsd ?? 0) }
        )
    }
}
