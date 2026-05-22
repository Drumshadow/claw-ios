import Foundation

// MARK: - VoiceCommandRisk

/// Risk classification for voice-initiated operational commands.
/// Drives confirmation UX and gateway routing.
enum VoiceCommandRisk: Int, Comparable, Codable {
    case safe = 0       // No confirmation needed — query, status, info
    case caution = 1    // Quick tap-to-confirm — writes, restarts, config changes
    case danger = 2     // Explicit spoken/typed confirmation — delete, deploy, kill

    static func < (lhs: VoiceCommandRisk, rhs: VoiceCommandRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .safe:    return "Safe"
        case .caution: return "Caution"
        case .danger:  return "Danger"
        }
    }

    var emoji: String {
        switch self {
        case .safe:    return "✅"
        case .caution: return "⚠️"
        case .danger:  return "🔴"
        }
    }
}

// MARK: - VoiceCommandCategory

/// Broad category of an operational voice command.
enum VoiceCommandCategory: String, Codable {
    case query          // "what is...", "show me...", "status of..."
    case navigate       // "open session...", "switch to...", "go to..."
    case send           // Generic message to agent
    case abort          // Stop current agent run
    case deploy         // Trigger deployment
    case restart        // Restart service/process
    case diagnostic     // Run diagnostics, health check
    case incident       // Create/update incident
    case git            // Git-related ops: branch, PR, merge
    case config         // Config changes
    case logs           // Fetch/analyze logs
    case delete         // Destructive deletions
    case confirm        // Explicit confirmation word ("yes", "confirm", "proceed")
    case cancel         // Explicit cancellation ("cancel", "no", "abort")
    case drivingMode    // Toggle driving/hands-free mode
    case unknown        // Fallback — route as plain chat message
}

// MARK: - VoiceCommandIntent

/// A parsed, classified voice command ready for execution or confirmation.
struct VoiceCommandIntent {
    /// Parsed category of the intent.
    let category: VoiceCommandCategory

    /// Risk level — determines whether confirmation is required before executing.
    let risk: VoiceCommandRisk

    /// The original transcript this was parsed from.
    let rawTranscript: String

    /// Cleaned, normalised message text to send to the agent.
    let normalizedMessage: String

    /// Short spoken confirmation prompt read aloud before dangerous actions.
    /// nil for safe intents that execute immediately.
    let confirmationPrompt: String?

    /// UI label for the confirmation button.
    let confirmButtonLabel: String

    /// Hint displayed in voice UI during execution.
    let executionHint: String

    /// Keywords extracted for display (may be empty).
    let extractedKeywords: [String]

    // MARK: - Convenience builders

    static func safeQuery(transcript: String, message: String, hint: String) -> VoiceCommandIntent {
        VoiceCommandIntent(
            category: .query,
            risk: .safe,
            rawTranscript: transcript,
            normalizedMessage: message,
            confirmationPrompt: nil,
            confirmButtonLabel: "Send",
            executionHint: hint,
            extractedKeywords: []
        )
    }

    static func generic(transcript: String) -> VoiceCommandIntent {
        VoiceCommandIntent(
            category: .unknown,
            risk: .safe,
            rawTranscript: transcript,
            normalizedMessage: transcript,
            confirmationPrompt: nil,
            confirmButtonLabel: "Send",
            executionHint: "Sending to agent…",
            extractedKeywords: []
        )
    }
}

// MARK: - VoiceExecutionResult

/// Result returned after a voice command is processed by the bridge.
enum VoiceExecutionResult {
    /// Command was sent; contains the response text for TTS playback.
    case responded(String)
    /// Command requires confirmation before proceeding.
    case requiresConfirmation(VoiceCommandIntent)
    /// Command was cancelled by user.
    case cancelled
    /// Error occurred during send/receive.
    case failed(String)
}

// MARK: - VoiceGatewayEvents (typed event name constants)

/// Gateway event constants for voice operations.
/// Backend expectations: these are the event names the server should emit
/// to coordinate voice sessions. They are defined here for type safety;
/// if the backend doesn't support them yet the app degrades gracefully to
/// local-only speech recognition + TTS.
enum VoiceGatewayEvent {
    /// Server-side speech recognition result (e.g. Whisper via gateway).
    static let speechTranscribed = "speech.transcribed"
    /// Server requests TTS playback of a string.
    static let ttsSpeakRequested = "tts.speak"
    /// Voice command intent classification from server NLU.
    static let commandClassified = "voice.command.classified"
    /// Acknowledgment that a voice command was received.
    static let commandAck = "voice.command.ack"
    /// Voice session opened/closed.
    static let voiceSessionStarted = "voice.session.started"
    static let voiceSessionEnded = "voice.session.ended"
}

/// Gateway method constants for voice operations.
enum VoiceGatewayMethod {
    /// Send a voice command (transcript + intent) to the gateway.
    static let voiceCommandSend = "voice.command.send"
    /// Open a voice session (optional — degrades to chat.send if unavailable).
    static let voiceSessionOpen = "voice.session.open"
    static let voiceSessionClose = "voice.session.close"
}
