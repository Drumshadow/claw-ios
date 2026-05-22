import Foundation

// MARK: - ModelProviderType

enum ModelProviderType: String, Codable, CaseIterable, Identifiable {
    case claude   = "claude"
    case openai   = "openai"
    case gemini   = "gemini"
    case ollama   = "ollama"
    case lmstudio = "lmstudio"
    case groq     = "groq"
    case custom   = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:   return "Claude (Anthropic)"
        case .openai:   return "OpenAI"
        case .gemini:   return "Gemini (Google)"
        case .ollama:   return "Ollama (Local)"
        case .lmstudio: return "LM Studio (Local)"
        case .groq:     return "Groq"
        case .custom:   return "Custom Endpoint"
        }
    }

    var isLocal: Bool {
        self == .ollama || self == .lmstudio
    }

    var iconName: String {
        switch self {
        case .claude:   return "brain.head.profile"
        case .openai:   return "sparkles"
        case .gemini:   return "star.circle.fill"
        case .ollama:   return "desktopcomputer"
        case .lmstudio: return "laptopcomputer"
        case .groq:     return "bolt.circle.fill"
        case .custom:   return "network"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .claude:   return "https://api.anthropic.com"
        case .openai:   return "https://api.openai.com"
        case .gemini:   return "https://generativelanguage.googleapis.com"
        case .ollama:   return "http://localhost:11434"
        case .lmstudio: return "http://localhost:1234"
        case .groq:     return "https://api.groq.com"
        case .custom:   return ""
        }
    }
}

// MARK: - ModelCapability

enum ModelCapability: String, Codable, CaseIterable, Identifiable {
    case codeGeneration    = "code"
    case reasoning         = "reasoning"
    case longContext       = "long_context"
    case functionCalling   = "function_calling"
    case visionInput       = "vision"
    case imageGeneration   = "image_gen"
    case audioInput        = "audio"
    case streaming         = "streaming"
    case batchProcessing   = "batch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codeGeneration:  return "Code"
        case .reasoning:       return "Reasoning"
        case .longContext:     return "Long Context"
        case .functionCalling: return "Function Calling"
        case .visionInput:     return "Vision"
        case .imageGeneration: return "Image Gen"
        case .audioInput:      return "Audio"
        case .streaming:       return "Streaming"
        case .batchProcessing: return "Batch"
        }
    }

    var iconName: String {
        switch self {
        case .codeGeneration:  return "chevron.left.forwardslash.chevron.right"
        case .reasoning:       return "brain"
        case .longContext:     return "doc.text.magnifyingglass"
        case .functionCalling: return "function"
        case .visionInput:     return "eye"
        case .imageGeneration: return "photo.on.rectangle"
        case .audioInput:      return "waveform"
        case .streaming:       return "dot.radiowaves.right"
        case .batchProcessing: return "tray.2"
        }
    }
}

// MARK: - LatencyClass

enum LatencyClass: String, Codable, CaseIterable, Comparable, Identifiable {
    case ultrafast = "ultrafast"   // < 100ms TTFT (Groq, local small)
    case fast      = "fast"        // 100ms–1s
    case medium    = "medium"      // 1s–5s
    case slow      = "slow"        // > 5s (large models)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultrafast: return "Ultrafast (<100ms)"
        case .fast:      return "Fast (<1s)"
        case .medium:    return "Medium (<5s)"
        case .slow:      return "Slow (5s+)"
        }
    }

    static func < (lhs: LatencyClass, rhs: LatencyClass) -> Bool {
        let order: [LatencyClass] = [.ultrafast, .fast, .medium, .slow]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - ModelDefinition

/// A specific model offered by a provider, with cost/latency/capability metadata.
struct ModelDefinition: Identifiable, Codable, Hashable {
    var id: String                           // e.g. "claude-opus-4-7", "gpt-4o", "llama3.2"
    var name: String                         // Human-readable name
    var providerType: ModelProviderType
    var contextWindowTokens: Int
    var maxOutputTokens: Int
    var costPerInputTokenMicros: Int         // Microdollars per token (0 for local)
    var costPerOutputTokenMicros: Int
    var latencyClass: LatencyClass
    var capabilities: [ModelCapability]
    var isAvailable: Bool                    // Detected as reachable
    var notes: String?

    // MARK: - Computed

    var isLocal: Bool { providerType.isLocal }

    var costTier: CostTier {
        let total = costPerInputTokenMicros + costPerOutputTokenMicros
        switch total {
        case 0:          return .free
        case 1...50:     return .cheap
        case 51...500:   return .moderate
        case 501...2000: return .expensive
        default:         return .premium
        }
    }

    enum CostTier: String {
        case free, cheap, moderate, expensive, premium
        var displayLabel: String {
            switch self {
            case .free:      return "Free"
            case .cheap:     return "Low"
            case .moderate:  return "Medium"
            case .expensive: return "High"
            case .premium:   return "Premium"
            }
        }
        var color: String {
            switch self {
            case .free:      return "22c55e"
            case .cheap:     return "86efac"
            case .moderate:  return "fbbf24"
            case .expensive: return "f97316"
            case .premium:   return "ef4444"
            }
        }
    }

    var contextDescription: String {
        let k = contextWindowTokens / 1000
        return k >= 1000 ? "\(k / 1000)M ctx" : "\(k)K ctx"
    }

    func has(_ capability: ModelCapability) -> Bool {
        capabilities.contains(capability)
    }

    // MARK: - Built-in catalog

    static let catalog: [ModelDefinition] = [
        // Claude
        ModelDefinition(
            id: "claude-opus-4-7",
            name: "Claude Opus 4.7",
            providerType: .claude,
            contextWindowTokens: 200_000,
            maxOutputTokens: 32_000,
            costPerInputTokenMicros: 15,
            costPerOutputTokenMicros: 75,
            latencyClass: .medium,
            capabilities: [.codeGeneration, .reasoning, .longContext, .functionCalling, .visionInput, .streaming],
            isAvailable: false,
            notes: "Most capable Claude model"
        ),
        ModelDefinition(
            id: "claude-sonnet-4-6",
            name: "Claude Sonnet 4.6",
            providerType: .claude,
            contextWindowTokens: 200_000,
            maxOutputTokens: 16_000,
            costPerInputTokenMicros: 3,
            costPerOutputTokenMicros: 15,
            latencyClass: .fast,
            capabilities: [.codeGeneration, .reasoning, .longContext, .functionCalling, .visionInput, .streaming],
            isAvailable: false,
            notes: "Best balance of speed and intelligence"
        ),
        ModelDefinition(
            id: "claude-haiku-4-5-20251001",
            name: "Claude Haiku 4.5",
            providerType: .claude,
            contextWindowTokens: 200_000,
            maxOutputTokens: 8_000,
            costPerInputTokenMicros: 0,  // estimated
            costPerOutputTokenMicros: 1,
            latencyClass: .fast,
            capabilities: [.codeGeneration, .functionCalling, .streaming],
            isAvailable: false,
            notes: "Fast, cost-effective Claude model"
        ),
        // OpenAI
        ModelDefinition(
            id: "gpt-4o",
            name: "GPT-4o",
            providerType: .openai,
            contextWindowTokens: 128_000,
            maxOutputTokens: 16_384,
            costPerInputTokenMicros: 2,
            costPerOutputTokenMicros: 8,
            latencyClass: .fast,
            capabilities: [.codeGeneration, .reasoning, .functionCalling, .visionInput, .streaming],
            isAvailable: false
        ),
        ModelDefinition(
            id: "gpt-4o-mini",
            name: "GPT-4o Mini",
            providerType: .openai,
            contextWindowTokens: 128_000,
            maxOutputTokens: 16_384,
            costPerInputTokenMicros: 0,
            costPerOutputTokenMicros: 1,
            latencyClass: .fast,
            capabilities: [.codeGeneration, .functionCalling, .streaming],
            isAvailable: false
        ),
        // Gemini
        ModelDefinition(
            id: "gemini-2.0-flash",
            name: "Gemini 2.0 Flash",
            providerType: .gemini,
            contextWindowTokens: 1_000_000,
            maxOutputTokens: 8_192,
            costPerInputTokenMicros: 0,
            costPerOutputTokenMicros: 0,
            latencyClass: .fast,
            capabilities: [.codeGeneration, .functionCalling, .longContext, .visionInput, .streaming],
            isAvailable: false
        ),
        // Ollama (local)
        ModelDefinition(
            id: "llama3.2",
            name: "Llama 3.2 (8B)",
            providerType: .ollama,
            contextWindowTokens: 128_000,
            maxOutputTokens: 8_192,
            costPerInputTokenMicros: 0,
            costPerOutputTokenMicros: 0,
            latencyClass: .medium,
            capabilities: [.codeGeneration, .streaming],
            isAvailable: false,
            notes: "Local — requires Ollama running"
        ),
        ModelDefinition(
            id: "qwen2.5-coder:14b",
            name: "Qwen 2.5 Coder 14B",
            providerType: .ollama,
            contextWindowTokens: 32_768,
            maxOutputTokens: 8_192,
            costPerInputTokenMicros: 0,
            costPerOutputTokenMicros: 0,
            latencyClass: .medium,
            capabilities: [.codeGeneration, .streaming],
            isAvailable: false,
            notes: "Excellent local coding model"
        ),
        ModelDefinition(
            id: "deepseek-r1:7b",
            name: "DeepSeek R1 7B",
            providerType: .ollama,
            contextWindowTokens: 32_768,
            maxOutputTokens: 4_096,
            costPerInputTokenMicros: 0,
            costPerOutputTokenMicros: 0,
            latencyClass: .medium,
            capabilities: [.reasoning, .codeGeneration, .streaming],
            isAvailable: false,
            notes: "Local reasoning model"
        ),
        // Groq
        ModelDefinition(
            id: "llama-3.3-70b-versatile",
            name: "Llama 3.3 70B (Groq)",
            providerType: .groq,
            contextWindowTokens: 128_000,
            maxOutputTokens: 32_768,
            costPerInputTokenMicros: 0,
            costPerOutputTokenMicros: 1,
            latencyClass: .ultrafast,
            capabilities: [.codeGeneration, .reasoning, .functionCalling, .streaming],
            isAvailable: false,
            notes: "Fastest large model via Groq"
        ),
    ]
}

// MARK: - ModelProvider (configured endpoint)

struct ModelProvider: Identifiable, Codable {
    var id: UUID = UUID()
    var type: ModelProviderType
    var name: String
    var baseURL: String
    var apiKeyKeychainRef: String?     // Keychain key holding the actual API key
    var isEnabled: Bool
    var customHeaders: [String: String]

    var isLocal: Bool { type.isLocal }

    var availableModels: [String]     // Model IDs detected/configured for this provider
}

// MARK: - RoutingRule

struct RoutingRule: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var taskPattern: String             // Glob or regex for task type / tool name
    var preferredModelIds: [String]     // Ordered preference list
    var fallbackModelIds: [String]      // Used when preferred are unavailable
    var maxCostPerTokenMicros: Int?     // nil = no limit
    var maxLatencyClass: LatencyClass?  // nil = no preference
    var requiredCapabilities: [ModelCapability]
    var isEnabled: Bool
    var notes: String?

    func matches(taskType: String) -> Bool {
        guard isEnabled else { return false }
        if taskPattern == "*" { return true }
        let regexPattern = "^" +
            taskPattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*") +
            "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
        else { return false }
        let range = NSRange(taskType.startIndex..<taskType.endIndex, in: taskType)
        return regex.firstMatch(in: taskType, range: range) != nil
    }
}

// MARK: - RoutingProfile

struct RoutingProfile: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var isDefault: Bool
    var rules: [RoutingRule]
    var fallbackModelId: String         // Last-resort model
    var costBudgetDailyUSD: Double?     // Daily cost cap; nil = unlimited
    var preferLocalWhenAvailable: Bool  // Prefer local/Ollama when a capable model exists

    // MARK: - Routing decision

    /// Given a task type and available models, returns the best model ID.
    func selectModel(
        for taskType: String,
        availableModels: [ModelDefinition]
    ) -> ModelDefinition? {
        // Find matching rule (first match wins)
        let matchingRule = rules.first { $0.matches(taskType: taskType) }

        let candidates: [String]
        if let rule = matchingRule {
            candidates = rule.preferredModelIds + rule.fallbackModelIds
        } else {
            candidates = [fallbackModelId]
        }

        // Filter to available models that meet constraints
        let available = availableModels.filter(\.isAvailable)

        for modelId in candidates {
            guard let model = available.first(where: { $0.id == modelId }) else { continue }

            // Check capability requirements
            if let rule = matchingRule {
                let hasCapabilities = rule.requiredCapabilities.allSatisfy { model.has($0) }
                guard hasCapabilities else { continue }

                // Check cost constraint
                if let maxCost = rule.maxCostPerTokenMicros {
                    guard model.costPerInputTokenMicros <= maxCost else { continue }
                }

                // Check latency constraint
                if let maxLatency = rule.maxLatencyClass {
                    guard model.latencyClass <= maxLatency else { continue }
                }
            }

            return model
        }

        // Fallback
        return available.first { $0.id == fallbackModelId }
            ?? available.first
    }

    // MARK: - Built-in profiles

    static let defaultProfiles: [RoutingProfile] = [
        RoutingProfile(
            name: "Cost-Optimized",
            description: "Prefer cheap/local models; escalate only for complex tasks",
            isDefault: false,
            rules: [
                RoutingRule(
                    name: "Code tasks → local",
                    taskPattern: "code*",
                    preferredModelIds: ["qwen2.5-coder:14b", "llama3.2"],
                    fallbackModelIds: ["claude-haiku-4-5-20251001"],
                    requiredCapabilities: [.codeGeneration],
                    isEnabled: true
                ),
                RoutingRule(
                    name: "Reasoning → Sonnet",
                    taskPattern: "reason*",
                    preferredModelIds: ["claude-sonnet-4-6"],
                    fallbackModelIds: ["claude-opus-4-7"],
                    requiredCapabilities: [.reasoning],
                    isEnabled: true
                ),
            ],
            fallbackModelId: "claude-haiku-4-5-20251001",
            costBudgetDailyUSD: 5.0,
            preferLocalWhenAvailable: true
        ),
        RoutingProfile(
            name: "Quality-First",
            description: "Always use the most capable model for each task",
            isDefault: false,
            rules: [
                RoutingRule(
                    name: "All tasks → Opus",
                    taskPattern: "*",
                    preferredModelIds: ["claude-opus-4-7"],
                    fallbackModelIds: ["claude-sonnet-4-6"],
                    requiredCapabilities: [],
                    isEnabled: true
                ),
            ],
            fallbackModelId: "claude-sonnet-4-6",
            costBudgetDailyUSD: nil,
            preferLocalWhenAvailable: false
        ),
        RoutingProfile(
            name: "Local-First",
            description: "Use Ollama models; cloud only as fallback",
            isDefault: false,
            rules: [
                RoutingRule(
                    name: "Code → Qwen Coder",
                    taskPattern: "code*",
                    preferredModelIds: ["qwen2.5-coder:14b", "llama3.2"],
                    fallbackModelIds: ["claude-haiku-4-5-20251001"],
                    requiredCapabilities: [.codeGeneration],
                    isEnabled: true
                ),
                RoutingRule(
                    name: "Reasoning → DeepSeek",
                    taskPattern: "reason*",
                    preferredModelIds: ["deepseek-r1:7b"],
                    fallbackModelIds: ["claude-sonnet-4-6"],
                    requiredCapabilities: [.reasoning],
                    isEnabled: true
                ),
            ],
            fallbackModelId: "llama3.2",
            costBudgetDailyUSD: 0.5,
            preferLocalWhenAvailable: true
        ),
        RoutingProfile(
            name: "Speed-First",
            description: "Minimize latency with Groq and fast models",
            isDefault: false,
            rules: [
                RoutingRule(
                    name: "All tasks → Groq Llama",
                    taskPattern: "*",
                    preferredModelIds: ["llama-3.3-70b-versatile"],
                    fallbackModelIds: ["claude-sonnet-4-6"],
                    maxLatencyClass: .fast,
                    requiredCapabilities: [],
                    isEnabled: true
                ),
            ],
            fallbackModelId: "claude-haiku-4-5-20251001",
            costBudgetDailyUSD: 1.0,
            preferLocalWhenAvailable: false
        ),
    ]
}

// MARK: - RoutingRule extension for optional maxLatencyClass init

extension RoutingRule {
    init(
        name: String,
        taskPattern: String,
        preferredModelIds: [String],
        fallbackModelIds: [String],
        maxCostPerTokenMicros: Int? = nil,
        maxLatencyClass: LatencyClass? = nil,
        requiredCapabilities: [ModelCapability],
        isEnabled: Bool = true,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.taskPattern = taskPattern
        self.preferredModelIds = preferredModelIds
        self.fallbackModelIds = fallbackModelIds
        self.maxCostPerTokenMicros = maxCostPerTokenMicros
        self.maxLatencyClass = maxLatencyClass
        self.requiredCapabilities = requiredCapabilities
        self.isEnabled = isEnabled
        self.notes = notes
    }
}
