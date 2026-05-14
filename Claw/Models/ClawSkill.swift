import Foundation

// MARK: - ClawSkill

struct ClawSkill: Identifiable, Hashable {
    var id: String { skillKey }
    let skillKey: String
    let name: String
    let emoji: String?
    let description: String
    let source: String
    var enabled: Bool      // = !disabled from gateway
    let eligible: Bool     // true = ready to use
    var category: String   // derived from source

    func hash(into hasher: inout Hasher) {
        hasher.combine(skillKey)
    }

    static func == (lhs: ClawSkill, rhs: ClawSkill) -> Bool {
        lhs.skillKey == rhs.skillKey && lhs.enabled == rhs.enabled
    }
}
