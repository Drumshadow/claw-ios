import SwiftUI
import WatchConnectivity

@main
struct ClawWatchApp: App {
    @State private var watchBridge = WatchBridge.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(watchBridge)
        }
    }
}

struct ContentView: View {
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        if bridge.pendingApprovals.isEmpty {
            AlertListView()
        } else {
            ApprovalView(approval: bridge.pendingApprovals[0])
        }
    }
}
