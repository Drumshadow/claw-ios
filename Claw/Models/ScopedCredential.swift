import Foundation

// MARK: - ScopedCredential
//
// A temporary, scoped credential that authorizes specific tool patterns
// in specific environments for a limited time window.
//
// The actual credential token is stored ONLY in Keychain — this model
// contains metadata only. Credential tokens are never stored in
// UserDefaults or transmitted unencrypted.
//
// Gateway contract:
//   method: credentials.create  → { id, name, scopes, expiresAt }
//   method: credentials.revoke  → { id }
//   event:  credential.expired  → { id }

struct ScopedCredential: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var environment: String          // "production", "staging", "dev", "*"
    var allowedToolPatterns: [String] // Glob patterns: ["deploy*", "db.read*"]
    var deniedToolPatterns: [String]  // Explicit deny list (takes priority)
    var expiresAt: Date?
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    var maxUses: Int?                // nil = unlimited
    var isEnabled: Bool
    var serverCredentialId: String?  // Opaque ID from gateway

    // MARK: - Token Keychain key

    /// Keychain key under which the actual credential token is stored.
    var keychainTokenKey: String { "ai.clawos.cred.\(id.uuidString)" }

    // MARK: - Computed

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }

    var isExhausted: Bool {
        guard let max = maxUses else { return false }
        return useCount >= max
    }

    var isActive: Bool {
        isEnabled && !isExpired && !isExhausted
    }

    var expiryDescription: String {
        guard let exp = expiresAt else { return "Never" }
        let delta = exp.timeIntervalSince(Date())
        if delta <= 0 { return "Expired" }
        if delta < 3600 { return "\(Int(delta / 60))m remaining" }
        if delta < 86400 { return "\(Int(delta / 3600))h remaining" }
        return "\(Int(delta / 86400))d remaining"
    }

    /// Returns true if the credential authorizes the given tool in the given environment
    func authorizes(tool: String, environment: String) -> Bool {
        guard isActive else { return false }

        // Check environment match
        let envMatch = self.environment == "*" ||
                       self.environment.lowercased() == environment.lowercased()
        guard envMatch else { return false }

        // Check explicit denies first
        if deniedToolPatterns.contains(where: { pattern in
            globMatches(pattern: pattern, input: tool)
        }) { return false }

        // Check allows
        return allowedToolPatterns.contains(where: { pattern in
            globMatches(pattern: pattern, input: tool)
        })
    }

    private func globMatches(pattern: String, input: String) -> Bool {
        let regexPattern = "^" +
            pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*") +
            "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, range: range) != nil
    }
}

// MARK: - ScopedCredentialStore

@Observable
@MainActor
final class ScopedCredentialStore {

    static let shared = ScopedCredentialStore()

    private(set) var credentials: [ScopedCredential] = []

    private static let userDefaultsKey = "ai.clawos.scopedCredentials"
    private static let keychainMetadataKey = "ai.clawos.scopedCredentials.metadata"

    private init() {
        credentials = loadCredentials()
        pruneExpired()
    }

    // MARK: - CRUD

    /// Creates a new scoped credential. Token and metadata are stored in Keychain.
    func create(
        name: String,
        description: String,
        environment: String,
        allowedToolPatterns: [String],
        deniedToolPatterns: [String] = [],
        token: String,
        expiresAt: Date? = nil,
        maxUses: Int? = nil
    ) -> ScopedCredential {
        let cred = ScopedCredential(
            name: name,
            description: description,
            environment: environment,
            allowedToolPatterns: allowedToolPatterns,
            deniedToolPatterns: deniedToolPatterns,
            expiresAt: expiresAt,
            createdAt: Date(),
            lastUsedAt: nil,
            useCount: 0,
            maxUses: maxUses,
            isEnabled: true,
            serverCredentialId: nil
        )
        // Store token securely in Keychain
        if let tokenData = token.data(using: .utf8) {
            try? KeychainStore.save(key: cred.keychainTokenKey, data: tokenData)
        }
        credentials.append(cred)
        saveCredentials()
        return cred
    }

    func revoke(_ credential: ScopedCredential) {
        // Delete token from Keychain
        try? KeychainStore.delete(key: credential.keychainTokenKey)
        credentials.removeAll { $0.id == credential.id }
        saveCredentials()
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        guard let idx = credentials.firstIndex(where: { $0.id == id }) else { return }
        credentials[idx].isEnabled = enabled
        saveCredentials()
    }

    func recordUse(_ id: UUID) {
        guard let idx = credentials.firstIndex(where: { $0.id == id }) else { return }
        credentials[idx].useCount += 1
        credentials[idx].lastUsedAt = Date()
        saveCredentials()
    }

    /// Retrieve the actual token for a credential (Keychain read).
    /// Returns nil if token has been revoked or Keychain unavailable.
    func token(for credential: ScopedCredential) -> String? {
        guard let data = try? KeychainStore.load(key: credential.keychainTokenKey),
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    // MARK: - Authorization query

    /// Find the best active credential authorizing this tool+env combo.
    func authorizedCredential(tool: String, environment: String) -> ScopedCredential? {
        credentials.first { $0.authorizes(tool: tool, environment: environment) }
    }

    // MARK: - Private

    private func pruneExpired() {
        // Don't auto-delete expired credentials — keep for audit trail.
        // Just mark them and let the UI surface them.
    }

    private func loadCredentials() -> [ScopedCredential] {
        if let data = try? KeychainStore.load(key: Self.keychainMetadataKey),
           let decoded = try? JSONDecoder().decode([ScopedCredential].self, from: data) {
            return decoded
        }

        // Migration path for older builds that stored non-token metadata in UserDefaults.
        guard let legacyData = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([ScopedCredential].self, from: legacyData)
        else { return [] }

        try? KeychainStore.save(key: Self.keychainMetadataKey, data: legacyData)
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        return decoded
    }

    private func saveCredentials() {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        try? KeychainStore.save(key: Self.keychainMetadataKey, data: data)
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }
}
