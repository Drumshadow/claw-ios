import SwiftUI

// MARK: - IntegrationRegistryView
//
// Full integration management: enable/disable, sync, configuration.
// Grouped by category: Connected / Available.

struct IntegrationRegistryView: View {
    @Environment(HomeOrchestrationStore.self) private var store
    @State private var selectedIntegration: HomeIntegration? = nil
    @State private var showCustomIntegrationForm = false

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

            Section {
                Button {
                    showCustomIntegrationForm = true
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
        .sheet(isPresented: $showCustomIntegrationForm) {
            CustomIntegrationForm { name, endpoint, description, capabilities in
                Task {
                    await store.createCustomIntegration(
                        name: name,
                        endpoint: endpoint,
                        description: description,
                        capabilities: capabilities
                    )
                }
            }
        }
    }
}

// MARK: - CustomIntegrationForm

private struct CustomIntegrationForm: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String?, String, Set<IntegrationCapability>) -> Void

    @State private var name = ""
    @State private var endpoint = ""
    @State private var description = ""
    @State private var capabilities: Set<IntegrationCapability> = [.read]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !capabilities.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Endpoint or local path", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("Capabilities") {
                    ForEach(IntegrationCapability.allCases, id: \.self) { capability in
                        Button {
                            toggle(capability)
                        } label: {
                            HStack {
                                Label(capability.displayName, systemImage: capability.systemImage)
                                Spacer()
                                if capabilities.contains(capability) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.clawAccent)
                                }
                            }
                        }
                        .foregroundStyle(Color.clawText)
                    }
                }

                Section {
                    Text("Custom integrations are registered with the gateway when supported. Until a backend connector is configured, they appear as unconfigured so you can keep the registry accurate without pretending a connection exists.")
                        .font(.footnote)
                        .foregroundStyle(Color.clawMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Custom Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(
                            name,
                            endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : endpoint,
                            description,
                            capabilities
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func toggle(_ capability: IntegrationCapability) {
        if capabilities.contains(capability) {
            if capabilities.count > 1 { capabilities.remove(capability) }
        } else {
            capabilities.insert(capability)
        }
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
