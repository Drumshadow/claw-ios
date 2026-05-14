import SwiftUI

struct DatadogView: View {
    let store: RemoteOpsStore

    @State private var filter: MonitorFilter = .all

    private enum MonitorFilter: String, CaseIterable {
        case all = "All"
        case alerting = "Alerting"
        case ok = "OK"
    }

    private var filteredMonitors: [DatadogMonitor] {
        switch filter {
        case .all:
            return store.datadogMonitors
        case .alerting:
            return store.datadogMonitors.filter {
                let s = $0.overallState.lowercased()
                return s == "alert" || s == "warn"
            }
        case .ok:
            return store.datadogMonitors.filter {
                $0.overallState.lowercased() == "ok"
            }
        }
    }

    var body: some View {
        Group {
            if store.credentials.datadogApiKey == nil {
                emptyCredentialsState
            } else {
                contentView
            }
        }
        .background(Color.clawBg.ignoresSafeArea())
    }

    private var emptyCredentialsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.clawMuted)
            Text("Configure Datadog API key in Settings")
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(MonitorFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clawBgAccent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(filteredMonitors) { monitor in
                MonitorRow(monitor: monitor)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .refreshable {
            await store.refresh()
        }
    }
}

private struct MonitorRow: View {
    let monitor: DatadogMonitor

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(monitor.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.clawTextStrong)
                        .layoutPriority(1)

                    stateBadge
                }

                if !monitor.tags.isEmpty {
                    tagsRow
                }
            }

            Spacer()

            if let date = monitor.modified {
                Text(relativeTime(from: date))
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clawCard)
    }

    private var stateBadge: some View {
        Text(monitor.overallState)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(badgeColor, in: Capsule())
    }

    private var badgeColor: Color {
        switch monitor.overallState.lowercased() {
        case "alert": return Color.clawDanger
        case "warn": return Color.orange
        case "ok": return Color.green
        default: return Color.clawMuted
        }
    }

    private var tagsRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(monitor.tags.prefix(3)), id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.clawBgAccent, in: RoundedRectangle(cornerRadius: 4))
            }
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
