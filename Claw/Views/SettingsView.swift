import SwiftUI

// MARK: - SettingsView

/// Full-screen settings sheet. Presented from ConnectedView toolbar.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(GatewayStore.self) private var gatewayStore
    @Environment(SessionStore.self) private var sessionStore: SessionStore?
    @Environment(AgentMonitorStore.self) private var agentMonitorStore: AgentMonitorStore?
    @Environment(BackgroundAgentStore.self) private var bgAgentStore: BackgroundAgentStore?
    @Environment(MemoryTimelineStore.self) private var timelineStore: MemoryTimelineStore?
    @Environment(TerminalSessionStore.self) private var terminalSessionStore: TerminalSessionStore?
    @Environment(RunbookStore.self) private var runbookStore: RunbookStore?
    @Environment(HomeOrchestrationStore.self) private var homeStore: HomeOrchestrationStore?
    @Environment(ToolApprovalStore.self) private var approvalStore: ToolApprovalStore?
    @Environment(\.dismiss) private var dismiss

    @State private var showAddGateway = false
    @State private var editingGateway: GatewayConfig?
    @State private var showResetPairingAlert = false
    @State private var deviceID: String = ""
    @State private var copiedDeviceID = false
    @State private var sampleModeEnabled = AppReviewSampleData.isEnabled
    @State private var sampleModeLoaded = false

    // MARK: - Commandments state
    @State private var commandments: [Commandment] = []
    @State private var showAddCommandment: Bool = false
    @State private var showEditCommandment: Bool = false
    @State private var editingCommandment: Commandment?
    @State private var commandmentDraftText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                gatewaysSection
                currentConnectionSection
                platformSection
                appReviewSection
                powerSection
                commandmentsSection
                deviceSection
                dangerSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .tint(Color.clawAccent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(Color.clawAccent)
                }
            }
            .sheet(isPresented: $showAddGateway) {
                ManualGatewayEntryView { config in
                    showAddGateway = false
                    gatewayStore.add(config)
                }
            }
            .sheet(item: $editingGateway) { gateway in
                ManualGatewayEntryView(initialConfig: gateway, actionTitle: "Save") { updated in
                    editingGateway = nil
                    gatewayStore.upsert(updated, setDefault: gateway.isDefault)
                    if appState.selectedConfig?.id == gateway.id {
                        appState.selectedConfig = updated
                    }
                }
            }
            .alert("Reset Pairing", isPresented: $showResetPairingAlert) {
                Button("Reset", role: .destructive) {
                    Task { await resetPairing() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete your device token for the current gateway and disconnect. You will need to re-pair to reconnect.")
            }
            .task {
                deviceID = (try? await DeviceIdentity.shared.deviceID()) ?? "Unknown"
                commandments = Commandment.load()
            }
            .sheet(isPresented: $showAddCommandment) {
                CommandmentEditSheet(
                    title: "New Commandment",
                    draftText: $commandmentDraftText
                ) {
                    let c = Commandment(text: commandmentDraftText.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !c.text.isEmpty {
                        commandments.append(c)
                        Commandment.save(commandments)
                    }
                    commandmentDraftText = ""
                    showAddCommandment = false
                } onCancel: {
                    commandmentDraftText = ""
                    showAddCommandment = false
                }
            }
            .sheet(isPresented: $showEditCommandment) {
                CommandmentEditSheet(
                    title: "Edit Commandment",
                    draftText: $commandmentDraftText
                ) {
                    if var c = editingCommandment {
                        let trimmed = commandmentDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, let idx = commandments.firstIndex(where: { $0.id == c.id }) {
                            c.text = trimmed
                            commandments[idx] = c
                            Commandment.save(commandments)
                        }
                    }
                    commandmentDraftText = ""
                    editingCommandment = nil
                    showEditCommandment = false
                } onCancel: {
                    commandmentDraftText = ""
                    editingCommandment = nil
                    showEditCommandment = false
                }
            }
        }
    }

    // MARK: - Gateways section

    private var gatewaysSection: some View {
        Section {
            if gatewayStore.gateways.isEmpty {
                Text("No saved gateways")
                    .foregroundStyle(Color.clawMuted)
                    .font(.subheadline)
            } else {
                ForEach(gatewayStore.gateways) { gateway in
                    HStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gateway.name)
                                    .font(.body)
                                    .foregroundStyle(Color.clawTextStrong)
                                Text(gateway.displayAddress)
                                    .font(.caption)
                                    .foregroundStyle(Color.clawMuted)
                            }
                            Spacer()
                            if gateway.isDefault {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.clawAccent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { gatewayStore.setDefault(gateway) }

                        Button {
                            editingGateway = gateway
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Color.clawMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit gateway")
                    }
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        gatewayStore.remove(gatewayStore.gateways[idx])
                    }
                }
            }

            Button {
                showAddGateway = true
            } label: {
                Label("Add Gateway", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.clawAccent)
            }
        } header: {
            Text("Gateways")
                .foregroundStyle(Color.clawMuted)
        } footer: {
            Text("Tap a gateway to set it as the default. Swipe left to remove.")
                .foregroundStyle(Color.clawMuted.opacity(0.8))
        }
        .listRowBackground(Color.clawCard)
    }

    // MARK: - Current connection section

    private var currentConnectionSection: some View {
        Section {
            if let config = appState.selectedConfig {
                LabeledContent {
                    Text(config.name).foregroundStyle(Color.clawText)
                } label: {
                    Text("Gateway").foregroundStyle(Color.clawTextStrong)
                }
                LabeledContent {
                    Text(config.displayAddress).foregroundStyle(Color.clawText)
                } label: {
                    Text("Address").foregroundStyle(Color.clawTextStrong)
                }
            } else {
                Text("Not configured")
                    .foregroundStyle(Color.clawMuted)
            }

            LabeledContent {
                connectionStatusBadge
            } label: {
                Text("Status").foregroundStyle(Color.clawTextStrong)
            }

            Button(role: .destructive) {
                Task { await appState.disconnect() }
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
                    .foregroundStyle(Color.clawDanger)
            }
        } header: {
            Text("Current Connection")
                .foregroundStyle(Color.clawMuted)
        }
        .listRowBackground(Color.clawCard)
    }

    private var isConnectionAlive: Bool {
        if case .connected = appState.connectionState { return true }
        return false
    }

    private var connectionStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnectionAlive ? Color.clawOk : Color.clawDanger)
                .frame(width: 8, height: 8)
            Text(isConnectionAlive ? "Alive" : "Offline")
                .font(.subheadline)
                .foregroundStyle(isConnectionAlive ? Color.clawOk : Color.clawDanger)
        }
    }

    // MARK: - Platform section

    @State private var showPolicyEditor   = false
    @State private var showModelRouting   = false

    private var platformSection: some View {
        Section {
            NavigationLink {
                SkillsView()
            } label: {
                platformRow(icon: "wand.and.stars", title: "Skills", subtitle: "Enable or disable agent skills")
            }
            NavigationLink {
                AgentsConfigView()
            } label: {
                platformRow(icon: "cpu", title: "Agents & Models", subtitle: "View configured agents")
            }
            NavigationLink {
                GatewayConfigView()
            } label: {
                platformRow(icon: "slider.horizontal.3", title: "Gateway Config", subtitle: "Inspect gateway settings")
            }
            // MARK: Safe Ops & Routing
            Button(action: { showPolicyEditor = true }) {
                platformRow(
                    icon: "shield.checkered",
                    title: "Approval Policies",
                    subtitle: "Risk gates, biometric rules, auto-approve"
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPolicyEditor) {
                PolicyEditorView()
            }

            Button(action: { showModelRouting = true }) {
                platformRow(
                    icon: "arrow.triangle.branch",
                    title: "Model Routing",
                    subtitle: "Local, cloud, and fallback model profiles"
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showModelRouting) {
                ModelRoutingView()
            }
        } header: {
            Text("Platform")
                .foregroundStyle(Color.clawMuted)
        } footer: {
            Text("Manage the platform that runs your agents. These screens read live values from the gateway.")
                .foregroundStyle(Color.clawMuted.opacity(0.8))
        }
        .listRowBackground(Color.clawCard)
    }

    private func platformRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color.clawAccent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.clawTextStrong)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
            }
        }
    }

    // MARK: - App Review section

    private var appReviewSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { sampleModeEnabled },
                set: { enabled in
                    sampleModeEnabled = enabled
                    AppReviewSampleData.isEnabled = enabled
                    if enabled {
                        loadAppReviewSamples()
                    } else {
                        sampleModeLoaded = false
                        reloadLiveDataAfterSampleModeDisabled()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Review Sample Data")
                        .foregroundStyle(Color.clawTextStrong)
                    Text("Screenshot-safe local data for internal Claw features only")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                }
            }
            .tint(Color.clawAccent)

            Button {
                sampleModeEnabled = true
                AppReviewSampleData.enable()
                loadAppReviewSamples()
            } label: {
                Label(sampleModeLoaded ? "Sample Data Loaded" : "Load Sample Data Now", systemImage: sampleModeLoaded ? "checkmark.circle.fill" : "photo.on.rectangle.angled")
                    .foregroundStyle(sampleModeLoaded ? Color.clawOk : Color.clawAccent)
            }

            if sampleModeEnabled {
                Button(role: .destructive) {
                    sampleModeEnabled = false
                    sampleModeLoaded = false
                    AppReviewSampleData.disable()
                    reloadLiveDataAfterSampleModeDisabled()
                } label: {
                    Label("Turn Off Sample Mode", systemImage: "xmark.circle")
                        .foregroundStyle(Color.clawDanger)
                }
            }
        } header: {
            Text("App Review")
                .foregroundStyle(Color.clawMuted)
        } footer: {
            Text("Loads local sample sessions, messages, agents, topology, terminal sessions, runbooks, memory timeline, and dashboards. It intentionally avoids external integrations and third-party app data so screenshots can be captured without live services.")
                .foregroundStyle(Color.clawMuted.opacity(0.8))
        }
        .listRowBackground(Color.clawCard)
    }

    private func loadAppReviewSamples() {
        sessionStore?.loadAppReviewSampleData()
        agentMonitorStore?.loadAppReviewSampleData()
        bgAgentStore?.loadAppReviewSampleData()
        timelineStore?.loadAppReviewSampleData()
        terminalSessionStore?.loadAppReviewSampleData()
        runbookStore?.loadAppReviewSampleData()
        homeStore?.loadAppReviewSampleData()
        approvalStore?.loadAppReviewSampleData()
        withAnimation { sampleModeLoaded = true }
    }

    private func reloadLiveDataAfterSampleModeDisabled() {
        Task {
            try? await sessionStore?.load()
            await agentMonitorStore?.refresh()
            await bgAgentStore?.loadAll()
            await timelineStore?.reload()
            try? await terminalSessionStore?.load()
            try? await runbookStore?.load()
            await homeStore?.loadAll()
        }
    }

    // MARK: - Power section

    private var powerSection: some View {
        Section {
            NavigationLink {
                CronView()
            } label: {
                platformRow(icon: "clock.badge.checkmark", title: "Scheduled Tasks", subtitle: "Cron jobs running on the gateway")
            }
            NavigationLink {
                MemoryBrowserView()
            } label: {
                platformRow(icon: "brain.head.profile", title: "Memory", subtitle: "Search and manage stored memory")
            }
            NavigationLink {
                UsageDashboardView()
            } label: {
                platformRow(icon: "chart.bar.xaxis", title: "Usage & Costs", subtitle: "Token usage and spending")
            }
        } header: {
            Text("Power")
                .foregroundStyle(Color.clawMuted)
        } footer: {
            Text("Advanced features. Scheduled tasks, memory, and usage data live on the gateway.")
                .foregroundStyle(Color.clawMuted.opacity(0.8))
        }
        .listRowBackground(Color.clawCard)
    }

    // MARK: - Device section

    private var deviceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Device ID")
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                Text(deviceID)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 4)

            Button {
                UIPasteboard.general.string = deviceID
                withAnimation { copiedDeviceID = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { withAnimation { copiedDeviceID = false } }
                }
            } label: {
                Label(
                    copiedDeviceID ? "Copied!" : "Copy Device ID",
                    systemImage: copiedDeviceID ? "checkmark" : "doc.on.doc"
                )
                .foregroundStyle(copiedDeviceID ? Color.clawOk : Color.clawAccent)
            }
        } header: {
            Text("Device")
                .foregroundStyle(Color.clawMuted)
        }
        .listRowBackground(Color.clawCard)
    }

    // MARK: - Danger zone section

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showResetPairingAlert = true
            } label: {
                Label("Reset Pairing", systemImage: "trash")
                    .foregroundStyle(Color.clawDanger)
            }
        } header: {
            Text("Danger Zone")
                .foregroundStyle(Color.clawMuted)
        } footer: {
            Text("Resetting pairing removes the stored device token and disconnects from the gateway. You must re-approve this device to reconnect.")
                .foregroundStyle(Color.clawMuted.opacity(0.8))
        }
        .listRowBackground(Color.clawCard)
    }

    // MARK: - Commandments section

    private var commandmentsSection: some View {
        Section {
            if commandments.isEmpty {
                Text("No commandments yet")
                    .foregroundStyle(Color.clawMuted)
                    .font(.subheadline)
            } else {
                ForEach($commandments) { $commandment in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: $commandment.isEnabled)
                            .labelsHidden()
                            .tint(Color.clawAccent)
                            .onChange(of: commandment.isEnabled) { _, _ in
                                Commandment.save(commandments)
                            }
                        Text(commandment.text)
                            .font(.system(size: 14))
                            .foregroundStyle(commandment.isEnabled ? Color.clawText : Color.clawMuted)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingCommandment = commandment
                        commandmentDraftText = commandment.text
                        showEditCommandment = true
                    }
                }
                .onDelete { indexSet in
                    commandments.remove(atOffsets: indexSet)
                    Commandment.save(commandments)
                }
            }

            Button {
                commandmentDraftText = ""
                showAddCommandment = true
            } label: {
                Label("Add Commandment", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.clawAccent)
            }
        } header: {
            Text("Commandments")
                .foregroundStyle(Color.clawMuted)
        } footer: {
            let enabledCount = commandments.filter { $0.isEnabled }.count
            let totalChars = commandments.filter { $0.isEnabled }.reduce(0) { $0 + $1.text.count }
            let estimatedTokens = max(0, (totalChars / 4) + 20) // overhead for XML tags
            if enabledCount > 0 {
                Text("Injected once per session on your first message. ~\(estimatedTokens) tokens. Toggle to enable or disable. Swipe left to delete.")
                    .foregroundStyle(Color.clawMuted.opacity(0.8))
            } else {
                Text("Persistent rules injected once per session. Toggle to enable or disable. Swipe left to delete.")
                    .foregroundStyle(Color.clawMuted.opacity(0.8))
            }
        }
        .listRowBackground(Color.clawCard)
    }

    // MARK: - Reset pairing action

    private func resetPairing() async {
        guard let config = appState.selectedConfig else { return }

        // Delete device token from Keychain
        try? await DeviceIdentity.shared.clearDeviceToken(forGatewayID: config.id.uuidString)

        // Disconnect
        await appState.disconnect()
        dismiss()
    }
}

// MARK: - CommandmentEditSheet

private struct CommandmentEditSheet: View {
    let title: String
    @Binding var draftText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rule text")
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                TextEditor(text: $draftText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.clawText)
                    .tint(Color.clawAccent)
                    .scrollContentBackground(.hidden)
                    .background(Color.clawBgElevated)
                    .cornerRadius(10)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.clawBorderStrong, lineWidth: 1)
                            .padding(.horizontal, 16)
                    )

                Spacer()
            }
            .background(Color.clawBg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                        .tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                        .tint(Color.clawAccent)
                        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
