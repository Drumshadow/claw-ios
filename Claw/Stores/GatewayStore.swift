import Foundation

// MARK: - GatewayStore

/// Observable store for the list of saved gateway configurations.
/// Loaded from UserDefaults on init; all mutations are persisted immediately.
@Observable
@MainActor
final class GatewayStore {

    // MARK: - Observable state

    private(set) var gateways: [GatewayConfig]

    // MARK: - Init

    init() {
        gateways = GatewayConfig.loadAll()
    }

    // MARK: - Mutations

    /// Appends a new gateway and persists the list.
    func add(_ config: GatewayConfig) {
        upsert(config, setDefault: gateways.isEmpty)
    }

    /// Inserts or updates a gateway and persists immediately.
    ///
    /// Matching prefers stable id, then falls back to host + port + TLS so manual
    /// retries don't create duplicates. This intentionally saves even if the
    /// connection attempt later fails, so users can name/edit gateways before
    /// pairing or fixing network details.
    func upsert(_ config: GatewayConfig, setDefault: Bool = false) {
        var updated = config
        if gateways.isEmpty || setDefault {
            updated.isDefault = true
        }

        if let idx = gateways.firstIndex(where: { $0.id == updated.id }) {
            gateways[idx] = updated
        } else if let idx = gateways.firstIndex(where: {
            $0.host == updated.host && $0.port == updated.port && $0.isSecure == updated.isSecure
        }) {
            updated.id = gateways[idx].id
            if !setDefault { updated.isDefault = gateways[idx].isDefault }
            gateways[idx] = updated
        } else {
            gateways.append(updated)
        }

        if updated.isDefault {
            for i in gateways.indices where gateways[i].id != updated.id {
                gateways[i].isDefault = false
            }
        }
        GatewayConfig.saveAll(gateways)
    }

    /// Removes a gateway by id and persists the list.
    func remove(_ config: GatewayConfig) {
        gateways.removeAll { $0.id == config.id }
        // If we removed the default, promote the first remaining entry
        if !gateways.isEmpty && !gateways.contains(where: { $0.isDefault }) {
            gateways[0].isDefault = true
        }
        GatewayConfig.saveAll(gateways)
    }

    /// Marks the given config as the default and clears the flag on all others.
    func setDefault(_ config: GatewayConfig) {
        for i in gateways.indices {
            gateways[i].isDefault = (gateways[i].id == config.id)
        }
        GatewayConfig.saveAll(gateways)
    }

    /// Returns the current default config, if any.
    var defaultGateway: GatewayConfig? {
        gateways.first { $0.isDefault } ?? gateways.first
    }
}
