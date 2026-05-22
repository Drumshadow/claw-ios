import SwiftUI

struct QuickMetricsView: View {
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MetricCard(
                    title: "Sessions",
                    value: "\(bridge.quickMetrics.activeSessions)",
                    icon: "bubble.left.and.bubble.right",
                    color: .blue
                )
                MetricCard(
                    title: "Agents Running",
                    value: "\(bridge.quickMetrics.runningAgents)",
                    icon: "cpu",
                    color: .green
                )
                MetricCard(
                    title: "Pending",
                    value: "\(bridge.quickMetrics.pendingApprovals)",
                    icon: "clock",
                    color: bridge.quickMetrics.pendingApprovals > 0 ? .yellow : .gray
                )
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Metrics")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.weight(.bold)).foregroundColor(.white)
                Text(title).font(.caption2).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(10)
    }
}
