import Foundation

// MARK: - PolicyStore
//
// Persistent @Observable store for approval policies.
// Non-sensitive policies are stored in UserDefaults (JSON encoded).
// Policies that require biometric authentication are additionally
// indexed in Keychain so a UserDefaults tampering attack cannot
// silently drop the biometric gate.
//
// Thread safety: @MainActor — all mutations happen on main thread.

@Observable
@MainActor
final class PolicyStore {

    // MARK: - Singleton

    static let shared = PolicyStore()

    // MARK: - Observable state

    private(set) var policies: [ApprovalPolicy] = []

    // MARK: - Persistence keys

    private static let userDefaultsKey   = "ai.clawos.approvalPolicies"
    private static let keychainIndexKey  = "ai.clawos.sensitivePolicy.index"

    // MARK: - Init

    private init() {
        policies = loadPolicies()
        if policies.isEmpty {
            policies = Self.builtInDefaults
            savePolicies()
        }
    }

    // MARK: - CRUD

    func add(_ policy: ApprovalPolicy) {
        policies.append(policy)
        savePolicies()
        if policy.requireBiometric { indexSensitivePolicy(policy.id) }
    }

    func update(_ policy: ApprovalPolicy) {
        guard let idx = policies.firstIndex(where: { $0.id == policy.id }) else { return }
        let old = policies[idx]
        policies[idx] = policy
        savePolicies()
        // If biometric requirement changed, update Keychain index
        if old.requireBiometric && !policy.requireBiometric {
            removeSensitiveIndex(policy.id)
        } else if !old.requireBiometric && policy.requireBiometric {
            indexSensitivePolicy(policy.id)
        }
    }

    func delete(_ policy: ApprovalPolicy) {
        policies.removeAll { $0.id == policy.id }
        removeSensitiveIndex(policy.id)
        savePolicies()
    }

    func duplicate(_ policy: ApprovalPolicy) {
        var copy = policy
        copy.id = UUID()
        copy.name = "\(policy.name) (Copy)"
        add(copy)
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        guard let idx = policies.firstIndex(where: { $0.id == id }) else { return }
        policies[idx].isEnabled = enabled
        savePolicies()
    }

    func reorder(fromOffsets: IndexSet, toOffset: Int) {
        policies.move(fromOffsets: fromOffsets, toOffset: toOffset)
        savePolicies()
    }

    // MARK: - Engine access

    /// Build a PolicyEngine snapshot from current enabled policies.
    var engine: PolicyEngine {
        PolicyEngine(policies: policies.filter(\.isEnabled))
    }

    // MARK: - Sensitive policy verification
    //
    // Returns true if the policy was previously indexed as sensitive in Keychain.
    // Use this as an integrity check: if a biometric policy is in UserDefaults
    // but NOT in the Keychain index, something tampered with it.

    func isVerifiedSensitive(_ policyId: UUID) -> Bool {
        sensitiveIndex().contains(policyId.uuidString)
    }

    // MARK: - Private: persistence

    private func loadPolicies() -> [ApprovalPolicy] {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([ApprovalPolicy].self, from: data)
        else { return [] }
        return decoded
    }

    private func savePolicies() {
        guard let data = try? JSONEncoder().encode(policies) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    // MARK: - Private: Keychain index for sensitive policies

    private func sensitiveIndex() -> Set<String> {
        guard let data = try? KeychainStore.load(key: Self.keychainIndexKey),
              let index = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(index)
    }

    private func indexSensitivePolicy(_ id: UUID) {
        var index = sensitiveIndex()
        index.insert(id.uuidString)
        guard let data = try? JSONEncoder().encode(Array(index)) else { return }
        try? KeychainStore.save(key: Self.keychainIndexKey, data: data)
    }

    private func removeSensitiveIndex(_ id: UUID) {
        var index = sensitiveIndex()
        guard index.remove(id.uuidString) != nil else { return }
        guard let data = try? JSONEncoder().encode(Array(index)) else { return }
        try? KeychainStore.save(key: Self.keychainIndexKey, data: data)
    }

    // MARK: - Built-in defaults

    static let builtInDefaults: [ApprovalPolicy] = [
        ApprovalPolicy(
            name: "Production Database Operations",
            environment: "production",
            toolPattern: "db.*",
            riskLevel: .critical,
            autoApprove: false,
            requireBiometric: true,
            timeoutSeconds: 30,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Production Deployments",
            environment: "production",
            toolPattern: "deploy*",
            riskLevel: .danger,
            autoApprove: false,
            requireBiometric: false,
            timeoutSeconds: 60,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Staging Rollbacks",
            environment: "staging",
            toolPattern: "rollback*",
            riskLevel: .danger,
            autoApprove: false,
            requireBiometric: false,
            timeoutSeconds: 45,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Dev Environment Restarts",
            environment: "dev",
            toolPattern: "docker restart *",
            riskLevel: .caution,
            autoApprove: true,
            requireBiometric: false,
            timeoutSeconds: 0,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Read Operations (All Envs)",
            environment: "*",
            toolPattern: "read*",
            riskLevel: .info,
            autoApprove: true,
            requireBiometric: false,
            timeoutSeconds: 0,
            isEnabled: true
        ),
    ]
}
