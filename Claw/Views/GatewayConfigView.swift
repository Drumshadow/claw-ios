import SwiftUI

// MARK: - GatewayConfigView

/// Read-only display of high-signal gateway configuration values:
/// mode, bind address, primary model + fallbacks, concurrency limits,
/// active plugins, auth mode, and a guarded partial-patch editor.
struct GatewayConfigView: View {
    @Environment(AppState.self) private var appState

    @State private var config: [String: JSONValue] = [:]
    @State private var configHash: String?
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var showPatchEditor = false
    @State private var patchText = "{\n  \n}"
    @State private var patchNote = "Edited from Claw iOS"
    @State private var isSavingPatch = false
    @State private var patchError: String?
    @State private var patchSuccess: String?

    var body: some View {
        ScrollView {
            Group {
                if isLoading && config.isEmpty {
                    loadingView
                } else if let err = loadError, config.isEmpty {
                    errorView(err)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        gatewaySection
                        modelsSection
                        concurrencySection
                        pluginsSection
                        authSection
                        editSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            await loadConfig()
        }
        .navigationTitle("Gateway Config")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if config.isEmpty { await loadConfig() }
        }
        .sheet(isPresented: $showPatchEditor) {
            ConfigPatchEditor(
                patchText: $patchText,
                note: $patchNote,
                isSaving: isSavingPatch,
                errorMessage: patchError,
                successMessage: patchSuccess,
                onApply: { Task { await applyPatch() } }
            )
        }
    }

    // MARK: - Sections

    private var gatewaySection: some View {
        configCard(title: "Gateway") {
            ConfigKVRow(key: "mode", value: lookup("gateway", "mode"))
            ConfigKVRow(key: "bind", value: lookup("gateway", "bind"))
            ConfigKVRow(key: "host", value: lookup("gateway", "host"))
            ConfigKVRow(key: "port", value: lookup("gateway", "port"))
        }
    }

    private var modelsSection: some View {
        configCard(title: "Models") {
            ConfigKVRow(key: "primary", value: lookup("models", "primary"))
            ConfigKVRow(key: "fallbacks", value: lookup("models", "fallbacks"))
            ConfigKVRow(key: "default", value: lookup("models", "default"))
        }
    }

    private var concurrencySection: some View {
        configCard(title: "Concurrency") {
            ConfigKVRow(key: "maxAgents", value: lookup("limits", "maxAgents"))
            ConfigKVRow(key: "maxSubagents", value: lookup("limits", "maxSubagents"))
            ConfigKVRow(key: "maxConcurrent", value: lookup("limits", "maxConcurrent"))
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Active Plugins")
            VStack(alignment: .leading, spacing: 6) {
                let plugins = activePlugins
                if plugins.isEmpty {
                    Text("None")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.clawMuted)
                        .padding(12)
                } else {
                    ForEach(plugins, id: \.self) { plugin in
                        HStack(spacing: 8) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawTeal)
                            Text(plugin)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color.clawText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if plugin != plugins.last {
                                Rectangle()
                                    .fill(Color.clawBorder.opacity(0.5))
                                    .frame(height: 1)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
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
    }

    private var authSection: some View {
        configCard(title: "Auth") {
            ConfigKVRow(key: "mode", value: lookup("auth", "mode"))
            ConfigKVRow(key: "scheme", value: lookup("auth", "scheme"))
        }
    }

    private var editSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Edit Config")
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    patchError = nil
                    patchSuccess = nil
                    showPatchEditor = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.clawAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apply partial patch")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.clawTextStrong)
                            Text(configHash == nil ? "Load the gateway hash, then send a JSON/JSON5 merge patch." : "Uses base hash \(configHashPrefix) to avoid clobbering newer config.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.clawMuted)
                    }
                    .padding(12)
                }
                .buttonStyle(.plain)

                Button {
                    patchText = prettyConfig
                    patchError = nil
                    patchSuccess = nil
                    showPatchEditor = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.clawTeal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use current config as draft")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.clawTextStrong)
                            Text("Remove keys you do not intend to patch before applying.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawMuted)
                        }
                        Spacer()
                    }
                    .padding(12)
                }
                .buttonStyle(.plain)
                .disabled(config.isEmpty)
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
    }

    // MARK: - Card / header helpers

    @ViewBuilder
    private func configCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title)
            VStack(spacing: 0) {
                content()
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
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.clawMuted)
            .textCase(.uppercase)
    }

    // MARK: - Load

    private func loadConfig() async {
        guard let client = appState.activeClient else {
            loadError = "Not connected to a gateway"
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let payload = try await client.send(method: GatewayMethod.configGet, params: EmptyConfigParams())
            if case .string(let hash) = payload["hash"] ?? .null {
                configHash = hash
            }

            if case .object(let obj) = payload["config"] ?? .null {
                config = obj
            } else if case .object(let obj) = payload["snapshot"] ?? .null {
                config = obj
            } else {
                config = payload.filter { $0.key != "hash" }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func applyPatch() async {
        guard let client = appState.activeClient else {
            patchError = "Not connected to a gateway"
            return
        }
        guard !patchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            patchError = "Patch cannot be empty"
            return
        }

        if configHash == nil { await loadConfig() }
        guard let baseHash = configHash else {
            patchError = "Could not load the current config hash. Refresh and try again."
            return
        }

        isSavingPatch = true
        patchError = nil
        patchSuccess = nil
        defer { isSavingPatch = false }

        struct PatchParams: Encodable {
            let raw: String
            let baseHash: String
            let note: String?
        }

        do {
            _ = try await client.send(
                method: GatewayMethod.configPatch,
                params: PatchParams(
                    raw: patchText,
                    baseHash: baseHash,
                    note: patchNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : patchNote
                )
            )
            patchSuccess = "Patch applied. Refreshing config…"
            await loadConfig()
        } catch {
            patchError = error.localizedDescription
        }
    }

    // MARK: - Config lookup helpers

    /// Looks up a nested value at `path` in the loaded config. Returns `.null`
    /// when the value is missing, so the row still renders.
    private func lookup(_ path: String...) -> JSONValue {
        var current: JSONValue = .object(config)
        for key in path {
            guard case .object(let obj) = current, let next = obj[key] else {
                return .null
            }
            current = next
        }
        return current
    }

    /// Returns the names of active plugins. Tries `plugins.active`, then `plugins`
    /// as a top-level array of strings or objects with a `name` field.
    private var activePlugins: [String] {
        let candidates: [JSONValue] = [
            lookup("plugins", "active"),
            lookup("plugins")
        ]
        for candidate in candidates {
            if case .array(let arr) = candidate {
                let names: [String] = arr.compactMap { item in
                    if case .string(let s) = item { return s }
                    if case .object(let obj) = item {
                        if case .string(let s) = obj["name"] ?? .null { return s }
                        if case .string(let s) = obj["id"] ?? .null { return s }
                    }
                    return nil
                }
                if !names.isEmpty { return names }
            }
        }
        return []
    }

    private var prettyConfig: String {
        do {
            let data = try JSONEncoder.pretty.encode(JSONValue.object(config))
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    private var configHashPrefix: String {
        guard let configHash else { return "" }
        return String(configHash.prefix(8))
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            ProgressView("Loading config…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.clawDanger)
            Text("Could not load config")
                .font(.headline)
                .foregroundStyle(Color.clawTextStrong)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }
}

private struct EmptyConfigParams: Encodable {}

private struct ConfigPatchEditor: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var patchText: String
    @Binding var note: String
    let isSaving: Bool
    let errorMessage: String?
    let successMessage: String?
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Patch") {
                    TextEditor(text: $patchText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 260)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Objects merge recursively, arrays/scalars replace, and null deletes a path. Keep this patch as small as possible.")
                }

                Section("Audit note") {
                    TextField("Reason for this change", text: $note)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.clawDanger)
                    }
                }

                if let successMessage {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.clawOk)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Config Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Apply")
                        }
                    }
                    .disabled(isSaving || patchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
