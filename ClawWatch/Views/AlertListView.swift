import SwiftUI

struct AlertListView: View {
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        List {
            // Metrics summary at top
            Section {
                MetricsTileView(metrics: bridge.quickMetrics)
            }

            // Recent alerts
            if bridge.recentAlerts.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("All clear")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Section("Recent") {
                    ForEach(bridge.recentAlerts) { alert in
                        AlertRowView(alert: alert)
                    }
                }
            }
        }
        .navigationTitle("Claw")
        .listStyle(.carousel)
    }
}

struct MetricsTileView: View {
    let metrics: WatchBridge.WatchMetrics

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label("\(metrics.activeSessions)", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption2)
                Spacer()
                Label("\(metrics.runningAgents)", systemImage: "cpu")
                    .font(.caption2)
            }
            if metrics.pendingApprovals > 0 {
                Label("\(metrics.pendingApprovals) pending", systemImage: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
        .foregroundColor(.white)
    }
}

struct AlertRowView: View {
    let alert: WatchBridge.WatchAlert

    var severityColor: Color {
        switch alert.severity {
        case "critical": return .red
        case "warning": return .yellow
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(severityColor).frame(width: 6, height: 6)
                Text(alert.title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            Text(alert.body).font(.caption2).foregroundColor(.gray).lineLimit(2)
        }
    }
}
