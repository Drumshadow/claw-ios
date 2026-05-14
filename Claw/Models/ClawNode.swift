import Foundation

// MARK: - ClawNode

struct ClawNode: Identifiable, Hashable {
    let id: String           // nodeId
    var displayName: String
    var platform: String     // "darwin", "ios", "android"
    var connected: Bool
    var paired: Bool
    var approvedAt: Date?
    var caps: [String]
    var isPending: Bool      // true if not yet approved

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClawNode, rhs: ClawNode) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Platform helpers

extension ClawNode {
    /// SF Symbol name used to represent the node's platform.
    var platformIconName: String {
        switch platform.lowercased() {
        case "darwin", "macos", "osx":
            return "laptopcomputer"
        case "ios", "ipados":
            return "iphone"
        case "android":
            return "smartphone"
        case "linux":
            return "server.rack"
        case "windows":
            return "pc"
        default:
            return "questionmark.app"
        }
    }

    /// Human-readable platform label.
    var platformLabel: String {
        switch platform.lowercased() {
        case "darwin", "macos", "osx": return "macOS"
        case "ios": return "iOS"
        case "ipados": return "iPadOS"
        case "android": return "Android"
        case "linux": return "Linux"
        case "windows": return "Windows"
        default: return platform.isEmpty ? "Unknown" : platform.capitalized
        }
    }
}
