import SwiftUI

struct RemoteOpsDashboardView: View {
    @State private var store = RemoteOpsStore()
    @State private var showSettings = false
    @State private var selectedTab: OpsTab = .instances

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                EC2InstancesView(store: store)
                    .tabItem { Label("Instances", systemImage: "server.rack") }
                    .tag(OpsTab.instances)

                GitHubActionsView(store: store, onShowMonitors: { selectedTab = .monitors })
                    .tabItem { Label("Deployments", systemImage: "arrow.triangle.branch") }
                    .tag(OpsTab.deployments)

                DatadogView(store: store)
                    .tabItem { Label("Monitors", systemImage: "waveform.path.ecg") }
                    .tag(OpsTab.monitors)

                UnifiedAlertFeedView(store: store)
                    .tabItem { Label("Alerts", systemImage: "bell.badge") }
                    .badge(criticalAlertCount)
                    .tag(OpsTab.alerts)

                OpsCommandsView(store: store)
                    .tabItem { Label("Commands", systemImage: "terminal") }
                    .tag(OpsTab.commands)
            }
            .tint(Color.clawAccent)
            .navigationTitle("Ops Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    subtitleView
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    refreshButton
                    settingsButton
                }
            }
            .sheet(isPresented: $showSettings) {
                RemoteOpsSettingsView(store: store)
            }
        }
        .task {
            await store.refresh()
        }
    }

    private var criticalAlertCount: Int {
        store.alerts.filter { $0.severity == .critical }.count
    }

    @ViewBuilder
    private var subtitleView: some View {
        if let date = store.lastRefreshed {
            Text("Updated \(date, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(Color.clawMuted)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            if store.isRefreshing {
                ProgressView()
                    .tint(Color.clawAccent)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .tint(Color.clawAccent)
        .disabled(store.isRefreshing)
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .tint(Color.clawAccent)
    }
}

private enum OpsTab: Hashable {
    case instances, deployments, monitors, alerts, commands
}
