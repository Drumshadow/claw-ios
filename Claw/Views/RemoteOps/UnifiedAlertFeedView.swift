import SwiftUI

struct UnifiedAlertFeedView: View {
    let store: RemoteOpsStore

    var body: some View {
        Group {
            if store.alerts.isEmpty {
                emptyState
            } else {
                alertList
            }
        }
        .background(Color.clawBg.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.clawMuted)
            Text("No active alerts")
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var alertList: some View {
        List(store.alerts) { alert in
            NavigationLink {
                IncidentView(alert: alert, store: store)
            } label: {
                AlertRow(alert: alert)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(
                alert.severity == .critical
                    ? Color.clawDanger.opacity(0.08)
                    : Color.clawCard
            )
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .refreshable {
            await store.refresh()
        }
    }
}

private struct AlertRow: View {
    let alert: OpsAlert

    var body: some View {
        HStack(spacing: 0) {
            severityBar

            HStack(spacing: 10) {
                Image(systemName: sourceSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.clawMuted)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(alert.severity == .critical ? Color.clawDanger : Color.clawTextStrong)

                    Text(alert.message)
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                        .lineLimit(2)
                }

                Spacer()

                Text(relativeTime(from: alert.timestamp))
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var severityBar: some View {
        Rectangle()
            .fill(barColor)
            .frame(width: 3)
    }

    private var barColor: Color {
        switch alert.severity {
        case .critical: return Color.clawDanger
        case .warning: return Color.orange
        case .info: return Color.clawBorder
        }
    }

    private var sourceSymbol: String {
        switch alert.source {
        case .datadog: return "waveform.path.ecg"
        case .github: return "arrow.triangle.branch"
        case .ec2: return "server.rack"
        }
    }
}

private func relativeTime(from date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}
