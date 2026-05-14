import Foundation

// MARK: - SkillsStore errors

enum SkillsStoreError: Error, LocalizedError {
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let detail): return "Malformed skills response: \(detail)"
        }
    }
}

// MARK: - SkillsStore

/// Loads and maintains the list of skills available on the gateway, and toggles
/// them on/off via `config.patch` with the skills.entries structure.
@Observable
@MainActor
final class SkillsStore {

    // MARK: - Observable state

    private(set) var skills: [ClawSkill] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?
    private(set) var mutationError: Error?

    // MARK: - Private

    private let client: GatewayClient

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
    }

    // MARK: - Load

    func load() async throws {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let payload = try await client.send(method: GatewayMethod.skillsStatus, params: EmptySkillsParams())
            try applySkillsList(payload: payload)
        } catch {
            loadError = error
            throw error
        }
    }

    // MARK: - Toggle

    /// Enables or disables a skill via config.patch, applying an optimistic update and reverting on failure.
    func toggle(_ skillId: String, enabled: Bool) async throws {
        mutationError = nil
        guard let idx = skills.firstIndex(where: { $0.skillKey == skillId }) else { return }

        let previous = skills[idx].enabled
        skills[idx].enabled = enabled

        let params = SkillConfigPatchParams(skillKey: skillId, enabled: enabled)
        do {
            _ = try await client.send(method: GatewayMethod.configPatch, params: params)
        } catch {
            // Revert on error.
            if let revertIdx = skills.firstIndex(where: { $0.skillKey == skillId }) {
                skills[revertIdx].enabled = previous
            }
            mutationError = error
            throw error
        }
    }

    // MARK: - Private: parse skills list response

    private func applySkillsList(payload: [String: JSONValue]) throws {
        let arr: [JSONValue]
        if let skillsValue = payload["skills"], case .array(let a) = skillsValue {
            arr = a
        } else {
            skills = []
            return
        }

        var result: [ClawSkill] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            if let skill = parseSkill(obj: obj) {
                result.append(skill)
            }
        }
        skills = result.sorted {
            if $0.category != $1.category {
                return $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func parseSkill(obj: [String: JSONValue]) -> ClawSkill? {
        guard let keyVal = obj["skillKey"], case .string(let skillKey) = keyVal, !skillKey.isEmpty else { return nil }

        let name: String
        if let v = obj["name"], case .string(let s) = v, !s.isEmpty {
            name = s
        } else {
            name = skillKey
        }

        let description: String
        if let v = obj["description"], case .string(let s) = v {
            description = s
        } else {
            description = ""
        }

        let emoji: String?
        if let v = obj["emoji"], case .string(let s) = v, !s.isEmpty {
            emoji = s
        } else {
            emoji = nil
        }

        // enabled = !disabled; disabled defaults to false if absent
        let disabled: Bool
        if let v = obj["disabled"], case .bool(let b) = v {
            disabled = b
        } else {
            disabled = false
        }
        let enabled = !disabled

        let eligible: Bool
        if let v = obj["eligible"], case .bool(let b) = v {
            eligible = b
        } else {
            eligible = false
        }

        let source: String
        if let v = obj["source"], case .string(let s) = v {
            source = s
        } else {
            source = ""
        }

        let category: String
        switch source {
        case "openclaw-bundled": category = "Bundled"
        case "openclaw-extra":   category = "Extra"
        case "local":            category = "Local"
        default:                 category = source.isEmpty ? "Other" : "Other"
        }

        return ClawSkill(
            skillKey: skillKey,
            name: name,
            emoji: emoji,
            description: description,
            source: source,
            enabled: enabled,
            eligible: eligible,
            category: category
        )
    }
}

// MARK: - Request param types

/// Encodes the nested config.patch payload:
/// { "skills": { "entries": { "<skillKey>": { "enabled": <bool> } } } }
private struct SkillConfigPatchParams: Encodable {
    let skillKey: String
    let enabled: Bool

    func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: RootKeys.self)
        var skills = root.nestedContainer(keyedBy: SkillsKeys.self, forKey: .skills)
        var entries = skills.nestedContainer(keyedBy: DynamicKey.self, forKey: .entries)
        var entry = entries.nestedContainer(keyedBy: EntryKeys.self, forKey: DynamicKey(stringValue: skillKey)!)
        try entry.encode(enabled, forKey: .enabled)
    }

    private enum RootKeys: String, CodingKey { case skills }
    private enum SkillsKeys: String, CodingKey { case entries }
    private enum EntryKeys: String, CodingKey { case enabled }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

private struct EmptySkillsParams: Encodable {}
