import SwiftUI
import AVFoundation

// MARK: - GatewaySetupView

struct GatewaySetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(GatewayDiscovery.self) private var discovery
    @Environment(GatewayStore.self) private var gatewayStore

    @State private var showManualEntry = false
    @State private var showQRScanner = false
    @State private var connectingConfig: GatewayConfig?
    @State private var editingConfig: GatewayConfig?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Discovered gateways
                    section(title: "Discovered Gateways", trailing: AnyView(
                        Group {
                            if discovery.isSearching {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.7)
                                    .tint(Color.clawAccent)
                            } else {
                                Button {
                                    discovery.clearDiscovered()
                                    discovery.stopDiscovery()
                                    discovery.startDiscovery()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.clawAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    )) {
                        if discovery.discovered.isEmpty {
                            emptyDiscoveryCard
                        } else {
                            VStack(spacing: 8) {
                                ForEach(discovery.discovered) { gateway in
                                    GatewayRow(
                                        name: gateway.name,
                                        address: "\(gateway.host):\(gateway.port)",
                                        isConnecting: connectingConfig?.id == gateway.id
                                    ) {
                                        connectTo(gateway.asConfig)
                                    }
                                }
                            }
                        }
                    }

                    // Saved connections
                    if !gatewayStore.gateways.isEmpty {
                        section(title: "Saved Connections") {
                            VStack(spacing: 8) {
                                ForEach(gatewayStore.gateways) { saved in
                                    GatewayRow(
                                        name: saved.name,
                                        address: saved.displayAddress,
                                        isConnecting: connectingConfig?.id == saved.id,
                                        menu: AnyView(savedGatewayMenu(saved))
                                    ) {
                                        gatewayStore.setDefault(saved)
                                        connectTo(saved)
                                    }
                                }
                            }
                        }
                    }

                    // Error display
                    if case .failed(let reason) = appState.connectionState {
                        errorCard(reason: reason)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color.clawBg)
            .navigationTitle("Claw")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .tint(Color.clawAccent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Add manually", systemImage: "plus")
                    }
                    .tint(Color.clawAccent)
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualGatewayEntryView { config in
                    showManualEntry = false
                    gatewayStore.upsert(config, setDefault: true)
                    connectTo(config)
                }
            }
            .sheet(item: $editingConfig) { config in
                ManualGatewayEntryView(initialConfig: config, actionTitle: "Save") { updated in
                    editingConfig = nil
                    gatewayStore.upsert(updated, setDefault: config.isDefault)
                    appState.selectedConfig = updated
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { config in
                    showQRScanner = false
                    gatewayStore.upsert(config, setDefault: true)
                    connectTo(config)
                }
            }
            .task { migrateLastUsedIntoSavedConnectionsIfNeeded() }
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.clawMuted)
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
    }

    // MARK: - Empty discovery card

    private var emptyDiscoveryCard: some View {
        HStack(spacing: 12) {
            if discovery.isSearching {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(Color.clawAccent)
            } else {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(Color.clawMuted)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(discovery.isSearching ? "Searching for gateways…" : "No gateways found on this network")
                    .foregroundStyle(Color.clawText)
                    .font(.subheadline.weight(.semibold))
                Text(discovery.isSearching ? "Keep this screen open, or scan a setup QR code." : "Make sure OpenClaw gateway is running, then refresh or add the address manually.")
                    .foregroundStyle(Color.clawMuted)
                    .font(.caption)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    // MARK: - Error card

    private func errorCard(reason: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.clawDanger)
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn’t connect to the gateway")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.clawDanger)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Color.clawDanger.opacity(0.9))
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clawDanger.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawDanger.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Connect helper

    private func migrateLastUsedIntoSavedConnectionsIfNeeded() {
        guard gatewayStore.gateways.isEmpty, let selected = appState.selectedConfig else { return }
        gatewayStore.upsert(selected, setDefault: true)
    }

    private func savedGatewayMenu(_ config: GatewayConfig) -> some View {
        Menu {
            Button {
                editingConfig = config
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                gatewayStore.setDefault(config)
                appState.selectedConfig = config
            } label: {
                Label("Set Default", systemImage: "checkmark.circle")
            }

            Button(role: .destructive) {
                gatewayStore.remove(config)
                if appState.selectedConfig?.id == config.id {
                    appState.selectedConfig = gatewayStore.defaultGateway
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.clawMuted)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private func connectTo(_ config: GatewayConfig) {
        var defaulted = config
        defaulted.isDefault = true
        connectingConfig = defaulted
        gatewayStore.upsert(defaulted, setDefault: true)
        Task {
            await appState.connect(to: defaulted)
            await MainActor.run { connectingConfig = nil }
        }
    }
}

// MARK: - GatewayRow

struct GatewayRow: View {
    let name: String
    let address: String
    let isConnecting: Bool
    var menu: AnyView? = nil
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.clawAccentSubtle)
                            .frame(width: 40, height: 40)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.clawAccent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.clawTextStrong)
                        Text(address)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawMuted)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            if isConnecting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(Color.clawAccent)
            } else if let menu {
                menu
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.clawMuted.opacity(0.6))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - ManualGatewayEntryView

struct ManualGatewayEntryView: View {
    var initialConfig: GatewayConfig? = nil
    var actionTitle: String = "Connect"
    let onConnect: (GatewayConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var portText: String = "18789"
    @State private var name: String = ""
    @State private var isSecure: Bool = true
    @State private var didInitialize = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, host, port }

    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(portText) != nil &&
        (Int(portText) ?? 0) > 0 &&
        (Int(portText) ?? 0) < 65536
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field(label: "Name (optional)", text: $name, field: .name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .host }

                    field(label: "Host or IP address", text: $host, field: .host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { focusedField = .port }

                    field(label: "Port", text: $portText, field: .port)
                        .keyboardType(.numberPad)
                        .submitLabel(.done)

                    Toggle(isOn: $isSecure) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use TLS (WSS)")
                                .foregroundStyle(Color.clawTextStrong)
                            Text(isSecure ? "wss://\(host.isEmpty ? "host" : host):\(portText)" : "ws://\(host.isEmpty ? "host" : host):\(portText)")
                                .font(.caption)
                                .foregroundStyle(Color.clawMuted)
                                .animation(.none, value: isSecure)
                        }
                    }
                    .tint(Color.clawAccent)
                } header: {
                    Text("Gateway Details")
                        .foregroundStyle(Color.clawMuted)
                }
                .listRowBackground(Color.clawCard)

                Section {
                    Text("Default port is **18789**. Disable TLS only for local networks without a certificate.")
                        .font(.footnote)
                        .foregroundStyle(Color.clawMuted)
                }
                .listRowBackground(Color.clawCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .tint(Color.clawAccent)
            .navigationTitle("Add Gateway")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(actionTitle) {
                        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
                        let port = Int(portText) ?? 18789
                        let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? trimmedHost
                            : name.trimmingCharacters(in: .whitespaces)
                        let config = GatewayConfig(
                            id: initialConfig?.id ?? UUID(),
                            name: displayName,
                            host: trimmedHost,
                            port: port,
                            isDefault: initialConfig?.isDefault ?? false,
                            isSecure: isSecure
                        )
                        onConnect(config)
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                    .tint(Color.clawAccent)
                }
            }
            .onAppear { initializeFieldsIfNeeded() }
        }
    }

    private func initializeFieldsIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        if let initialConfig {
            name = initialConfig.name
            host = initialConfig.host
            portText = String(initialConfig.port)
            isSecure = initialConfig.isSecure
        } else {
            focusedField = .host
        }
    }

    @ViewBuilder
    private func field(label: String, text: Binding<String>, field: Field) -> some View {
        TextField(label, text: text)
            .foregroundStyle(Color.clawText)
            .focused($focusedField, equals: field)
            .autocorrectionDisabled()
    }
}
