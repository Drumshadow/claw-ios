import SwiftUI

// MARK: - GatewaySetupView

struct GatewaySetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(GatewayDiscovery.self) private var discovery

    @State private var showManualEntry = false
    @State private var connectingConfig: GatewayConfig?

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

                    // Last used
                    if let saved = appState.selectedConfig {
                        section(title: "Last Used") {
                            GatewayRow(
                                name: saved.name,
                                address: saved.displayAddress,
                                isConnecting: connectingConfig?.id == saved.id
                            ) {
                                connectTo(saved)
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
                    connectTo(config)
                }
            }
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
            Text(discovery.isSearching ? "Searching for gateways…" : "No gateways found")
                .foregroundStyle(Color.clawMuted)
                .font(.subheadline)
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
            Text(reason)
                .font(.footnote)
                .foregroundStyle(Color.clawDanger)
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

    private func connectTo(_ config: GatewayConfig) {
        connectingConfig = config
        Task {
            await appState.connect(to: config)
            await MainActor.run { connectingConfig = nil }
        }
    }
}

// MARK: - GatewayRow

struct GatewayRow: View {
    let name: String
    let address: String
    let isConnecting: Bool
    let onTap: () -> Void

    var body: some View {
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

                if isConnecting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                        .tint(Color.clawAccent)
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
        .buttonStyle(.plain)
        .disabled(isConnecting)
    }
}

// MARK: - ManualGatewayEntryView

struct ManualGatewayEntryView: View {
    let onConnect: (GatewayConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var portText: String = "3000"
    @State private var name: String = ""
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
                } header: {
                    Text("Gateway Details")
                        .foregroundStyle(Color.clawMuted)
                }
                .listRowBackground(Color.clawCard)

                Section {
                    Text("Default port for OpenClaw gateway is **3000**.")
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
                    Button("Connect") {
                        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
                        let port = Int(portText) ?? 3000
                        let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? trimmedHost
                            : name.trimmingCharacters(in: .whitespaces)
                        let config = GatewayConfig(
                            name: displayName,
                            host: trimmedHost,
                            port: port
                        )
                        onConnect(config)
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                    .tint(Color.clawAccent)
                }
            }
            .onAppear { focusedField = .host }
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
