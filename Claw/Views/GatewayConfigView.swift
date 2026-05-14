import SwiftUI

// MARK: - GatewayConfigView

/// Read-only display of high-signal gateway configuration values:
/// mode, bind address, primary model + fallbacks, concurrency limits,
/// active plugins, and auth mode. Editing is stubbed for now.
struct GatewayConfigView: View {
    @Environment(AppState.self) private var appState

    @State private var config: [String: JSONValue] = [:]
    @State private var isLoading: Bool = false
    @State private var loadError: String?

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
                HStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.clawMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coming soon")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.clawTextStrong)
                        Text("Editing gateway config from iOS will be available in a future release.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawMuted)
                    }
                    Spacer()
                }
                .padding(12)
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
            config = payload
        } catch {
            loadError = error.localizedDescription
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
