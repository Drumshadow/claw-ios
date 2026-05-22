import SwiftUI
import WatchConnectivity

@main
struct ClawWatchApp: App {
    @State private var watchBridge = WatchBridge.shared

    var body: some Scene {
        WindowGroup {
            RootWatchView()
                .environment(watchBridge)
        }
    }
}

// MARK: - RootWatchView
//
// Top-level navigation. Shows urgent approval prompt when pending,
// otherwise presents a tab-based main interface.

struct RootWatchView: View {
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        if let topApproval = bridge.pendingApprovals.first {
            // Approval takes full screen — most urgent action
            NavigationStack {
                ApprovalView(approval: topApproval)
            }
        } else {
            // Normal TabView navigation
            TabView {
                // Tab 1: Alerts + metrics overview
                NavigationStack {
                    AlertListView()
                }
                .tabItem { Label("Alerts", systemImage: "bell.fill") }

                // Tab 2: Deployments
                NavigationStack {
                    DeploymentListView()
                }
                .tabItem { Label("Deploys", systemImage: "arrow.up.to.line.circle.fill") }

                // Tab 3: Incidents
                NavigationStack {
                    IncidentListView()
                }
                .tabItem { Label("Incidents", systemImage: "exclamationmark.shield.fill") }

                // Tab 4: Metrics detail
                NavigationStack {
                    QuickMetricsView()
                }
                .tabItem { Label("Metrics", systemImage: "chart.bar.fill") }
            }
        }
    }
}
