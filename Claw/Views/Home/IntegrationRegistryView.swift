import SwiftUI

// MARK: - IntegrationRegistryView
//
// Full integration management: enable/disable, sync, configuration.
// Grouped by category: Connected / Available.

struct IntegrationRegistryView: View {
    @Environment(HomeOrchestrationStore.self) private var store
    @State private var selectedIntegration: HomeIntegration? = nil

    var body: some View {
        List {
            let connected = store.integrations.filter { $0.connectionStatus.isActive || $0.isEnabled }
            let available = store.integrations.filter { !$0.isEnabled || $0.connectionStatus == .unconfigured }

            if !connected.isEmpty {
                Section("Connected") {
                    ForEach(connected) { integration in
                        IntegrationRow(integration: integration, isSyncing: store.isSyncing == integration.id) {
                            Task { await store.toggleIntegration(integration.id) }
                        } onSync: {
                            Task { await store.syncIntegration(integration.id) }
                        }
                        .listRowBackground(Color.clawCard)
                    }
                }
            }

            if !available.isEmpty {
                Section("Available") {
                    ForEach(available) { integration in
                        IntegrationRow(integration: integration, isSyncing: store.isSyncing == integration.id) {
                            Task { await store.toggleIntegration(integration.id) }
                        } onSync: {
                            Task { await store.syncIntegration(integration.id) }
                        }
                        .listRowBackground(Color.clawCard)
                    }
                }
            }

            // Add custom integration placeholder
            Section {
                Button {
                    // TODO: custom integration creation flow
                } label: {
                    Label("Add custom integration…", systemImage: "plus.circle.dashed")
                        .foregroundStyle(Color.clawAccent)
                        .font(.system(size: 14))
                }
                .listRowBackground(Color.clawCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await store.loadAll() }
        .refreshable { await store.loadAll() }
    }
}

// MARK: - IntegrationRow

struct IntegrationRow: View {
    let integration: HomeIntegration
    let isSyncing: Bool
    let onToggle: () -> Void
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: integration.kind.colorHex).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: integration.kind.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: integration.kind.colorHex))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(integration.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)

                HStack(spacing: 6) {
                    // Status dot
                    Circle()
                        .fill(integration.connectionStatus.isActive ? Color.clawOk : Color.clawMuted.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(integration.connectionStatus.displayName)
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted)

                    if let sync = integration.lastSyncAt {
                        Text("·")
                        Text(sync, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(Color.clawMuted.opacity(0.7))
                    }
                }

                // Capability chips
                if !integration.capabilities.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(integration.capabilities, id: \.self) { cap in
                            Text(cap.displayName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.clawTeal.opacity(0.8))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.clawTeal.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 1)
                }
            }

            Spacer()

            VStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { integration.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .tint(Color.clawAccent)
                .scaleEffect(0.8)

                if integration.isEnabled && integration.connectionStatus == .connected {
                    Button(action: onSync) {
                        if isSyncing {
                            ProgressView().scaleEffect(0.6).tint(Color.clawTeal)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(Color.clawTeal.opacity(0.7))
                        }
                    }
                    .frame(width: 24, height: 20)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
