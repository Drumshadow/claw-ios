import Foundation

// MARK: - Commandment

struct Commandment: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var isEnabled: Bool = true
}

extension Commandment {
    static func load() -> [Commandment] {
        guard let data = UserDefaults.standard.data(forKey: "commandments"),
              let list = try? JSONDecoder().decode([Commandment].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Commandment]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "commandments")
    }
}
