import SwiftUI

struct IncidentSummaryView: View {
    let incident: WatchBridge.WatchIncidentItem
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Severity bar
                Rectangle()
                    .fill(incident.severityColor)
                    .frame(height: 3)
                    .cornerRadius(1.5)

                // Title + status
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(incident.isOngoing ? incident.severityColor : Color.gray)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(incident.isOngoing ? "ONGOING" : "RESOLVED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(incident.isOngoing ? incident.severityColor : .gray)
                    }
                }

                // Environment
                Label(incident.environment.uppercased(), systemImage: "cloud")
                    .font(.caption2)
                    .foregroundColor(.gray)

                // Summary
                Text(incident.summary)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                // Affected services
                if !incident.affectedServices.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AFFECTED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                        ForEach(incident.affectedServices.prefix(3), id: \.self) { svc in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 9))
                                    .foregroundColor(incident.severityColor)
                                Text(svc)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(incident.severityColor.opacity(0.1))
                    )
                }

                // Duration
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(incident.durationDescription)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                // Action required badge
                if incident.actionRequired {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.point.right.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("Action Required")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.yellow.opacity(0.15))
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .navigationTitle("Incident")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Incident extension for duration

private extension WatchBridge.WatchIncidentItem {
    var durationDescription: String {
        let end = resolvedAt ?? Date()
        let delta = end.timeIntervalSince(startedAt)
        if delta < 60    { return "\(Int(delta))s" }
        if delta < 3600  { return "\(Int(delta / 60))m" }
        return "\(Int(delta / 3600))h \(Int((delta.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }
}
