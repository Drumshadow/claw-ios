import SwiftUI

// MARK: - ContainerListView

struct ContainerListView: View {
    let instance: EC2Instance
    var store: RemoteOpsStore

    @State private var sshContainers: [OpsContainer] = []
    @State private var isFetching: Bool = false
    @State private var hasFetched: Bool = false

    private var sshStore: InstanceSSHStore { store.sshStore }
    private var hasSSH: Bool { sshStore.hasCredential(for: instance.id) }

    var body: some View {
        VStack(spacing: 10) {
            if hasSSH {
                sshContainersView
            } else {
                NoSSHBanner()
                if instance.containers.isEmpty {
                    emptyStateView
                } else {
                    ForEach(instance.containers) { container in
                        ContainerRow(container: container)
                    }
                }
            }
        }
        .task {
            if hasSSH && !hasFetched {
                await fetchContainers()
            }
        }
    }

    @ViewBuilder
    private var sshContainersView: some View {
        if isFetching {
            HStack {
                Spacer()
                ProgressView("Fetching containers…")
                    .tint(Color.clawAccent)
                    .foregroundStyle(Color.clawMuted)
                Spacer()
            }
            .padding(.vertical, 24)
        } else if sshContainers.isEmpty && hasFetched {
            HStack {
                emptyStateView
                Spacer()
                Button {
                    Task { await fetchContainers() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.clawAccent)
                }
            }
            .padding(.vertical, 4)
        } else {
            if hasFetched {
                HStack {
                    Text("\(sshContainers.count) container\(sshContainers.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                    Spacer()
                    Button {
                        Task { await fetchContainers() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.clawAccent)
                    }
                }
                ForEach(sshContainers) { container in
                    ContainerRow(container: container)
                }
            } else {
                Button {
                    Task { await fetchContainers() }
                } label: {
                    Label("Fetch Containers", systemImage: "shippingbox")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.clawAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.clawAccent.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fetchContainers() async {
        isFetching = true
        sshContainers = await sshStore.fetchContainers(for: instance)
        hasFetched = true
        isFetching = false
    }

    private var emptyStateView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.clawMuted.opacity(0.4))

                Text("No containers found")
                    .font(.subheadline)
                    .foregroundStyle(Color.clawMuted)
            }
            Spacer()
        }
        .padding(.vertical, 24)
    }
}

// MARK: - NoSSHBanner

private struct NoSSHBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.clawWarn)

            Text("Add SSH credentials above to fetch live container data")
                .font(.system(size: 13))
                .foregroundStyle(Color.clawWarn)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clawWarn.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawWarn.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - ContainerRow

private struct ContainerRow: View {
    let container: OpsContainer

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                Text(container.image)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)

                if !container.ports.isEmpty {
                    Text(container.ports.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                ContainerStatusBadge(status: container.status)

                if let uptime = container.uptime {
                    Text(uptime)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }
}

// MARK: - ContainerStatusBadge

private struct ContainerStatusBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(badgeColor.opacity(0.15)))
    }

    private var badgeColor: Color {
        switch status.lowercased() {
        case "running":          return .green
        case "exited", "dead":   return Color.clawDanger
        default:                 return .orange
        }
    }
}
