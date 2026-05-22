import Foundation

// MARK: - ModelRouterStore
//
// @Observable store managing model routing configuration.
// Persists routing profiles and provider configs to UserDefaults.
// API keys are stored in Keychain (never UserDefaults).
//
// Gateway contract (expected — backend must implement):
//   method: models.list       → [{ id, name, provider, contextWindow, ... }]
//   method: models.capabilities → { modelId: [capability] }
//   method: routing.get       → { activeProfileId, profiles: [...] }
//   method: routing.set       → { profileId }
//   event:  model.routing.changed → { profileId }
//   event:  model.health.update → { modelId, isAvailable, latencyMs? }

@Observable
@MainActor
final class ModelRouterStore {

    // MARK: - Observable state

    private(set) var profiles:        [RoutingProfile] = []
    private(set) var providers:       [ModelProvider]  = []
    private(set) var availableModels: [ModelDefinition] = ModelDefinition.catalog
    private(set) var activeProfileId: UUID?
    private(set) var isLoadingModels: Bool = false
    private(set) var lastSyncDate:    Date? = nil

    // MARK: - Gateway client (optional — store works offline)

    private var client: GatewayClient?
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    // MARK: - Persistence keys

    private static let profilesKey        = "ai.clawos.modelRoutingProfiles"
    private static let providersKey       = "ai.clawos.modelProviders"
    private static let activeProfileIdKey = "ai.clawos.activeRoutingProfileId"
    private static let apiKeyPrefix       = "ai.clawos.provider.apikey."

    // MARK: - Init

    init(client: GatewayClient? = nil) {
        self.client = client
        loadFromDisk()
        if profiles.isEmpty {
            profiles = RoutingProfile.defaultProfiles
            if let first = profiles.first { activeProfileId = first.id }
            saveProfiles()
        }
        if let c = client { startEventSubscription(client: c) }
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Active profile

    var activeProfile: RoutingProfile? {
        guard let id = activeProfileId else { return profiles.first }
        return profiles.first { $0.id == id }
    }

    func setActiveProfile(_ id: UUID) {
        activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileIdKey)
        // Notify gateway of routing change
        if let client {
            Task {
                struct SetParams: Encodable { let profileId: String }
                _ = try? await client.send(
                    method: GatewayMethod.routingSet,
                    params: SetParams(profileId: id.uuidString)
                )
            }
        }
    }

    // MARK: - Profile CRUD

    func addProfile(_ profile: RoutingProfile) {
        profiles.append(profile)
        saveProfiles()
    }

    func updateProfile(_ profile: RoutingProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        saveProfiles()
    }

    func deleteProfile(_ profile: RoutingProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileId == profile.id {
            activeProfileId = profiles.first?.id
        }
        saveProfiles()
    }

    func duplicateProfile(_ profile: RoutingProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) (Copy)"
        copy.isDefault = false
        addProfile(copy)
    }

    // MARK: - Provider management

    func addProvider(_ provider: ModelProvider) {
        providers.append(provider)
        saveProviders()
    }

    func updateProvider(_ provider: ModelProvider) {
        guard let idx = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[idx] = provider
        saveProviders()
    }

    func removeProvider(_ provider: ModelProvider) {
        // Revoke stored API key
        if let keyRef = provider.apiKeyKeychainRef {
            try? KeychainStore.delete(key: keyRef)
        }
        providers.removeAll { $0.id == provider.id }
        saveProviders()
    }

    /// Store API key in Keychain, returns the keychain reference key.
    func setAPIKey(_ key: String, for provider: ModelProvider) -> String {
        let keychainKey = Self.apiKeyPrefix + provider.id.uuidString
        if let data = key.data(using: .utf8) {
            try? KeychainStore.save(key: keychainKey, data: data)
        }
        return keychainKey
    }

    func apiKey(for provider: ModelProvider) -> String? {
        guard let ref = provider.apiKeyKeychainRef else { return nil }
        guard let data = try? KeychainStore.load(key: ref) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Model routing decision

    /// Ask the active profile which model to use for a given task.
    func selectModel(for taskType: String) -> ModelDefinition? {
        activeProfile?.selectModel(for: taskType, availableModels: availableModels)
    }

    // MARK: - Model discovery (gateway)

    func fetchAvailableModels() async {
        guard let client else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        struct ModelsListParams: Encodable { let view: String }
        guard let response = try? await client.send(method: GatewayMethod.modelsList, params: ModelsListParams(view: "configured")) else { return }

        if let modelsArr = response["models"]?.arrayValue {
            let updated: [ModelDefinition] = modelsArr.compactMap { item in
                guard let obj = item.objectValue else { return nil }
                let id = obj["id"]?.stringValue
                    ?? obj["model"]?.stringValue
                    ?? obj["modelId"]?.stringValue
                guard let id, !id.isEmpty else { return nil }
                let name = obj["name"]?.stringValue
                    ?? obj["displayName"]?.stringValue
                    ?? obj["label"]?.stringValue
                    ?? id
                let providerStr = obj["provider"]?.stringValue
                    ?? obj["modelProvider"]?.stringValue
                    ?? id.split(separator: "/").first.map(String.init)
                    ?? "custom"
                let provider = Self.providerType(fromGatewayProvider: providerStr)

                let contextWindow = obj["contextWindow"]?.intValue
                    ?? obj["contextTokens"]?.intValue
                    ?? 4096
                let maxOutput     = obj["maxOutput"]?.intValue
                    ?? obj["maxOutputTokens"]?.intValue
                    ?? 2048
                let latencyStr    = obj["latency"]?.stringValue ?? "medium"
                let latency       = LatencyClass(rawValue: latencyStr) ?? .medium
                let capStrs       = obj["capabilities"]?.arrayValue?.compactMap(\.stringValue) ?? []
                let caps          = capStrs.compactMap { ModelCapability(rawValue: $0) }
                let inputCost     = obj["costPerInputTokenMicros"]?.intValue ?? 0
                let outputCost    = obj["costPerOutputTokenMicros"]?.intValue ?? 0
                let isAvailable   = obj["isAvailable"]?.boolValue ?? true
                let notes         = obj["notes"]?.stringValue

                return ModelDefinition(
                    id: id,
                    name: name,
                    providerType: provider,
                    contextWindowTokens: contextWindow,
                    maxOutputTokens: maxOutput,
                    costPerInputTokenMicros: inputCost,
                    costPerOutputTokenMicros: outputCost,
                    latencyClass: latency,
                    capabilities: caps,
                    isAvailable: isAvailable,
                    notes: notes
                )
            }

            // Merge: keep catalog entries, update availability from gateway
            var merged = availableModels
            for remote in updated {
                if let idx = merged.firstIndex(where: { $0.id == remote.id }) {
                    merged[idx] = remote
                } else {
                    merged.append(remote)
                }
            }
            availableModels = merged
            lastSyncDate = Date()
        }
    }

    private static func providerType(fromGatewayProvider provider: String) -> ModelProviderType {
        let normalized = provider.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "anthropic", "claude", "claude-cli": return .claude
        case "openai", "openai-codex", "codex": return .openai
        case "google", "gemini": return .gemini
        case "ollama": return .ollama
        case "lmstudio", "lm-studio": return .lmstudio
        case "groq": return .groq
        default: return ModelProviderType(rawValue: normalized) ?? .custom
        }
    }

    // MARK: - Event subscription

    private func startEventSubscription(client: GatewayClient) {
        eventTask = Task { [weak self] in
            for await event in await client.events() {
                guard let self else { return }
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {
        case GatewayEventName.modelRoutingChanged:
            if let profileIdStr = event.payload["profileId"]?.stringValue,
               let profileId = UUID(uuidString: profileIdStr) {
                activeProfileId = profileId
                UserDefaults.standard.set(profileIdStr, forKey: Self.activeProfileIdKey)
            }

        case GatewayEventName.modelHealthUpdate:
            guard let modelId = event.payload["modelId"]?.stringValue else { return }
            let isAvailable = event.payload["isAvailable"]?.boolValue ?? false
            if let idx = availableModels.firstIndex(where: { $0.id == modelId }) {
                availableModels[idx].isAvailable = isAvailable
            }

        case "models.changed", "config.changed", "providers.changed":
            Task { await fetchAvailableModels() }

        default:
            break
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([RoutingProfile].self, from: data) {
            profiles = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.providersKey),
           let decoded = try? JSONDecoder().decode([ModelProvider].self, from: data) {
            providers = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: Self.activeProfileIdKey),
           let id = UUID(uuidString: idStr) {
            activeProfileId = id
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
    }

    private func saveProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: Self.providersKey)
        }
    }
}

// MARK: - GatewayEventName extensions (added in GatewayMethods.swift, referenced here)

private extension GatewayEventName {
    // Declared in GatewayMethods.swift:
    // static let modelRoutingChanged = "model.routing.changed"
    // static let modelHealthUpdate   = "model.health.update"
}
