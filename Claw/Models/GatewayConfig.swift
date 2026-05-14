import Foundation

struct GatewayConfig: Identifiable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var isDefault: Bool
    var isSecure: Bool

    init(id: UUID = UUID(), name: String, host: String, port: Int, isDefault: Bool = false, isSecure: Bool = true) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.isDefault = isDefault
        self.isSecure = isSecure
    }

    var wsURL: URL? {
        var components = URLComponents()
        components.scheme = isSecure ? "wss" : "ws"
        components.host = host
        components.port = port
        components.path = "/ws"
        return components.url
    }

    var displayAddress: String {
        "\(isSecure ? "wss" : "ws")://\(host):\(port)"
    }

}

// MARK: - Codable with isSecure migration default

extension GatewayConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, isDefault, isSecure
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        host      = try c.decode(String.self, forKey: .host)
        port      = try c.decode(Int.self,    forKey: .port)
        isDefault = try c.decode(Bool.self,   forKey: .isDefault)
        isSecure  = try c.decodeIfPresent(Bool.self, forKey: .isSecure) ?? true
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
