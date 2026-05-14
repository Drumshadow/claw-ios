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
        // Avoid exact duplicates (same host + port)
        guard !gateways.contains(where: { $0.host == config.host && $0.port == config.port }) else {
            return
        }
        var updated = config
        // If this is the first entry, make it the default automatically
        if gateways.isEmpty {
            updated.isDefault = true
        }
        gateways.append(updated)
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
