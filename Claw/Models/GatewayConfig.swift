import Foundation

struct GatewayConfig: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var isDefault: Bool

    init(id: UUID = UUID(), name: String, host: String, port: Int, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.isDefault = isDefault
    }

    var wsURL: URL? {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = port
        components.path = "/ws"
        return components.url
    }

    var displayAddress: String {
        "\(host):\(port)"
    }

}

// MARK: - Multi-gateway persistence helpers

extension GatewayConfig {

    private static let allGatewaysKey = "claw.gateways"

    /// Loads all saved gateway configs from UserDefaults.
    static func loadAll() -> [GatewayConfig] {
        guard let data = UserDefaults.standard.data(forKey: allGatewaysKey),
              let configs = try? JSONDecoder().decode([GatewayConfig].self, from: data) else {
            return []
        }
        return configs
    }

    /// Saves the provided array of gateway configs to UserDefaults.
    static func saveAll(_ configs: [GatewayConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: allGatewaysKey)
        }
    }

    /// Marks the config with the given id as the default and clears the flag on all others.
    static func setDefault(_ id: UUID) {
        var configs = loadAll()
        for i in configs.indices {
            configs[i].isDefault = (configs[i].id == id)
        }
        saveAll(configs)
    }
}
