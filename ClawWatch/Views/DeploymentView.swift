import SwiftUI

// MARK: - DeploymentListView

struct DeploymentListView: View {
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        if bridge.deploymentEvents.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.to.line.circle")
                    .font(.title2)
                    .foregroundColor(.gray)
                Text("No deployments")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Deploys")
        } else {
            List {
                ForEach(bridge.deploymentEvents) { event in
                    NavigationLink {
                        DeploymentDetailView(event: event)
                    } label: {
                        DeploymentRowView(event: event)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.carousel)
            .navigationTitle("Deploys")
        }
    }
}

// MARK: - DeploymentRowView

struct DeploymentRowView: View {
    let event: WatchBridge.WatchDeploymentItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.statusIcon)
                .font(.title3)
                .foregroundColor(event.statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.service)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(event.version)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("→")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    Text(event.environment)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - DeploymentDetailView

struct DeploymentDetailView: View {
    let event: WatchBridge.WatchDeploymentItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Status header
                HStack(spacing: 6) {
                    Image(systemName: event.statusIcon)
                        .font(.title3)
                        .foregroundColor(event.statusColor)
                    Text(event.status.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Service info
                InfoRow(label: "Service", value: event.service, icon: "cube.box")
                InfoRow(label: "Version", value: event.version, icon: "tag")
                InfoRow(label: "Env",     value: event.environment.uppercased(), icon: "cloud")

                // Timestamp
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(event.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text("ago")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                // Rollback available
                if event.rollbackAvailable {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Rollback Available")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .navigationTitle("Deploy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - InfoRow helper

private struct InfoRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .frame(width: 14)
            Text(label + ":")
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}
