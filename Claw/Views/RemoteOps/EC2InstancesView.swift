import SwiftUI

// MARK: - EC2InstancesView

struct EC2InstancesView: View {
    var store: RemoteOpsStore

    var body: some View {
        ZStack {
            Color.clawBg.ignoresSafeArea()

            if store.isRefreshing && store.ec2Instances.isEmpty {
                ProgressView("Loading instances…")
                    .tint(Color.clawAccent)
                    .foregroundStyle(Color.clawMuted)
            } else if store.ec2Instances.isEmpty {
                emptyStateView
            } else {
                instanceList
            }
        }
    }

    private var instanceList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.ec2Instances) { instance in
                    NavigationLink(destination: EC2InstanceDetailView(instance: instance, store: store)) {
                        EC2InstanceCard(instance: instance, sshStore: store.sshStore)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refresh()
        }
    }

    private var emptyStateView: some View {
        let hasCredentials = store.credentials.awsAccessKeyId != nil && store.credentials.awsSecretAccessKey != nil
        let message = store.error ?? (hasCredentials ? "No instances found — check region or IAM permissions" : "Configure AWS credentials in Settings")
        let isError = store.error != nil
        return VStack(spacing: 16) {
            Image(systemName: isError ? "exclamationmark.triangle" : (hasCredentials ? "server.rack" : "gearshape"))
                .font(.system(size: 48))
                .foregroundStyle(isError ? Color.clawDanger.opacity(0.7) : Color.clawMuted.opacity(0.4))
            Text(message)
                .font(.headline)
                .foregroundStyle(isError ? Color.clawDanger : Color.clawMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - EC2InstanceCard

private struct EC2InstanceCard: View {
    let instance: EC2Instance
    let sshStore: InstanceSSHStore

    @State private var isPinging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(instance.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.clawTextStrong)
                        .lineLimit(1)

                    Text(instance.instanceType)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                }

                Spacer()

                // Health indicator
                HealthIndicatorIcon(result: sshStore.lastHealthResults[instance.id])

                EC2StateBadge(state: instance.state)
            }

            HStack(spacing: 16) {
                if let ip = instance.publicIP ?? instance.privateIP {
                    Label(ip, systemImage: "network")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawText)
                }

                Label(instance.region, systemImage: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)

                Spacer()

                // Ping button — only shown when credentials are configured
                if sshStore.hasCredential(for: instance.id) {
                    Button {
                        pingInstance()
                    } label: {
                        HStack(spacing: 4) {
                            if isPinging {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(Color.clawAccent)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10))
                            }
                            Text("Ping")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.clawAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.clawAccent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPinging)
                }
            }

            if let metrics = instance.metrics {
                MetricsSection(metrics: metrics)
            }

            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.clawMuted.opacity(0.6))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func pingInstance() {
        isPinging = true
        Task {
            _ = await sshStore.runHealthCheck(for: instance)
            await MainActor.run { isPinging = false }
        }
    }
}

// MARK: - HealthIndicatorIcon

private struct HealthIndicatorIcon: View {
    let result: HealthCheckResult?

    var body: some View {
        Group {
            if let result {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? Color.clawOk : Color.clawDanger)
            } else {
                Image(systemName: "minus.circle")
                    .foregroundStyle(Color.clawMuted.opacity(0.4))
            }
        }
        .font(.system(size: 14))
    }
}

// MARK: - EC2StateBadge

private struct EC2StateBadge: View {
    let state: EC2State

    var body: some View {
        Text(state.rawValue.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(badgeColor.opacity(0.15)))
    }

    private var badgeColor: Color {
        switch state {
        case .running:            return .green
        case .stopped:            return Color.clawMuted
        case .terminated:         return Color.clawDanger
        case .pending, .stopping: return .orange
        }
    }
}

// MARK: - MetricsSection

private struct MetricsSection: View {
    let metrics: InstanceMetrics

    var body: some View {
        VStack(spacing: 6) {
            MiniProgressBar(label: "CPU", value: metrics.cpuPercent)

            if let mem = metrics.memoryPercent {
                MiniProgressBar(label: "MEM", value: mem)
            }
        }
        .padding(.top, 2)
    }
}

private struct MiniProgressBar: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .frame(width: 28, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.clawBgAccent)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(value / 100.0, 1.0))
                }
            }
            .frame(height: 6)

            Text("\(Int(value))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.clawMuted)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var barColor: Color {
        switch value {
        case ..<60:  return .green
        case ..<85:  return .orange
        default:     return Color.clawDanger
        }
    }
}

// MARK: - EC2InstanceDetailView

struct EC2InstanceDetailView: View {
    let instance: EC2Instance
    var store: RemoteOpsStore

    @State private var showCredentialsSheet: Bool = false
    @State private var credentialExists: Bool = false

    private var sshStore: InstanceSSHStore { store.sshStore }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                detailFieldsCard
                if let metrics = instance.metrics {
                    metricsCard(metrics)
                }
                sshSection
                commandsSection
                containersSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg.ignoresSafeArea())
        .navigationTitle(instance.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showCredentialsSheet, onDismiss: {
            credentialExists = sshStore.hasCredential(for: instance.id)
        }) {
            SSHCredentialsView(instance: instance, sshStore: sshStore) {
                credentialExists = true
            }
        }
        .onAppear {
            credentialExists = sshStore.hasCredential(for: instance.id)
        }
    }

    // MARK: - SSH Section

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SSH")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 14) {
                if credentialExists, let cred = sshStore.loadCredential(for: instance.id) {
                    // Credential summary row
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(cred.username)@\(cred.host)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.clawTextStrong)
                            if cred.port != 22 {
                                Text("Port \(cred.port)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.clawMuted)
                            }
                        }
                        Spacer()
                        Button("Edit") {
                            showCredentialsSheet = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.clawAccent)
                    }

                    Divider().background(Color.clawBorder)

                    HealthCheckView(instance: instance, sshStore: sshStore)
                } else {
                    HStack {
                        Text("No SSH credentials configured.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.clawMuted)
                        Spacer()
                        Button("Add Credentials") {
                            showCredentialsSheet = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.clawAccent)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clawCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.clawBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Commands Section

    private var commandsSection: some View {
        InstanceCommandsView(instance: instance, sshStore: sshStore)
    }

    // MARK: - Existing cards

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 24))
                .foregroundStyle(Color.clawAccent)

            VStack(alignment: .leading, spacing: 4) {
                Text(instance.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.clawTextStrong)

                Text(instance.instanceType)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawMuted)
            }

            Spacer()

            EC2StateBadge(state: instance.state)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private var detailFieldsCard: some View {
        VStack(spacing: 0) {
            DetailRow(label: "Instance ID", value: instance.id)
            Divider().background(Color.clawBorder)
            DetailRow(label: "Region", value: instance.region)

            if let pub = instance.publicIP {
                Divider().background(Color.clawBorder)
                DetailRow(label: "Public IP", value: pub)
            }

            if let priv = instance.privateIP {
                Divider().background(Color.clawBorder)
                DetailRow(label: "Private IP", value: priv)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func metricsCard(_ metrics: InstanceMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)

            MiniProgressBar(label: "CPU", value: metrics.cpuPercent)

            if let mem = metrics.memoryPercent {
                MiniProgressBar(label: "MEM", value: mem)
            }

            if let disk = metrics.diskPercent {
                MiniProgressBar(label: "DISK", value: disk)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Containers")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)

            ContainerListView(instance: instance, store: store)
        }
    }
}

// MARK: - DetailRow

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.clawMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.clawText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
