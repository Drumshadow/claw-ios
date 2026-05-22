import Foundation

// MARK: - VoiceCommandParser

/// Lightweight, on-device parser that maps a voice transcript to a structured
/// VoiceCommandIntent. This runs synchronously on the main actor so it must
/// be fast — no ML, no network. Complex NLU can be routed to the gateway
/// via VoiceGatewayMethod.voiceCommandSend; this is a client-side prefilter
/// that handles the most common operational patterns.
enum VoiceCommandParser {

    // MARK: - Public entry point

    /// Parse a transcript string into a VoiceCommandIntent.
    static func parse(_ rawTranscript: String) -> VoiceCommandIntent {
        let text = rawTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !text.isEmpty else {
            return .generic(transcript: rawTranscript)
        }

        // Check explicit confirm/cancel words first — these override everything else.
        if matchesConfirm(text) {
            return VoiceCommandIntent(
                category: .confirm,
                risk: .safe,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: nil,
                confirmButtonLabel: "Confirmed",
                executionHint: "Confirmed",
                extractedKeywords: ["confirm"]
            )
        }

        if matchesCancel(text) {
            return VoiceCommandIntent(
                category: .cancel,
                risk: .safe,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: nil,
                confirmButtonLabel: "Cancel",
                executionHint: "Cancelling…",
                extractedKeywords: ["cancel"]
            )
        }

        // Drive mode toggle
        if matches(text, patterns: ["driving mode", "drive mode", "hands free", "hands-free", "car mode"]) {
            return VoiceCommandIntent(
                category: .drivingMode,
                risk: .safe,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: nil,
                confirmButtonLabel: "Activate",
                executionHint: "Activating driving mode",
                extractedKeywords: ["driving", "mode"]
            )
        }

        // Abort / stop current run
        if matches(text, patterns: ["stop agent", "abort", "cancel run", "kill agent", "stop running", "halt"]) {
            return VoiceCommandIntent(
                category: .abort,
                risk: .caution,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: "Stop the current agent run?",
                confirmButtonLabel: "Stop Agent",
                executionHint: "Aborting current run",
                extractedKeywords: ["abort"]
            )
        }

        // Deploy — danger
        if matches(text, patterns: ["deploy", "push to production", "ship it", "release", "rollout"]) {
            return VoiceCommandIntent(
                category: .deploy,
                risk: .danger,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: "Deploy to production?",
                confirmButtonLabel: "Deploy",
                executionHint: "Initiating deployment",
                extractedKeywords: ["deploy"]
            )
        }

        // Delete — danger
        if matches(text, patterns: ["delete", "remove", "destroy", "wipe", "drop table", "purge"]) {
            return VoiceCommandIntent(
                category: .delete,
                risk: .danger,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: "Confirm destructive operation: \(rawTranscript.prefix(60))?",
                confirmButtonLabel: "Delete",
                executionHint: "Pending confirmation",
                extractedKeywords: ["delete"]
            )
        }

        // Restart — caution
        if matches(text, patterns: ["restart", "reboot", "bounce server", "reload service", "restart server"]) {
            return VoiceCommandIntent(
                category: .restart,
                risk: .caution,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: "Restart the service?",
                confirmButtonLabel: "Restart",
                executionHint: "Restarting service",
                extractedKeywords: ["restart"]
            )
        }

        // Git ops — caution for merge/force push, safe for status/log
        if matches(text, patterns: ["merge", "force push", "rebase", "cherry-pick"]) {
            return VoiceCommandIntent(
                category: .git,
                risk: .caution,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: "Run git operation: \(rawTranscript.prefix(60))?",
                confirmButtonLabel: "Run",
                executionHint: "Running git operation",
                extractedKeywords: ["git"]
            )
        }

        if matches(text, patterns: ["git status", "git log", "git diff", "git branch", "create branch", "create pr", "open pr", "pull request"]) {
            return VoiceCommandIntent(
                category: .git,
                risk: .safe,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: nil,
                confirmButtonLabel: "Run",
                executionHint: "Running git command",
                extractedKeywords: ["git"]
            )
        }

        // Incident — caution (creates a record)
        if matches(text, patterns: ["create incident", "open incident", "incident report", "page team", "page on-call"]) {
            return VoiceCommandIntent(
                category: .incident,
                risk: .caution,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: "Create an incident for: \(rawTranscript.prefix(60))?",
                confirmButtonLabel: "Create Incident",
                executionHint: "Creating incident report",
                extractedKeywords: ["incident"]
            )
        }

        // Config change — caution
        if matches(text, patterns: ["update config", "change config", "set config", "update setting", "change setting", "enable feature", "disable feature"]) {
            return VoiceCommandIntent(
                category: .config,
                risk: .caution,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: "Apply config change: \(rawTranscript.prefix(60))?",
                confirmButtonLabel: "Apply",
                executionHint: "Applying configuration",
                extractedKeywords: ["config"]
            )
        }

        // Diagnostic — safe
        if matches(text, patterns: ["run diagnostics", "health check", "check health", "status check", "ping", "test"]) {
            return VoiceCommandIntent(
                category: .diagnostic,
                risk: .safe,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: nil,
                confirmButtonLabel: "Run",
                executionHint: "Running diagnostics",
                extractedKeywords: ["diagnostic"]
            )
        }

        // Logs — safe
        if matches(text, patterns: ["show logs", "tail logs", "get logs", "fetch logs", "recent errors", "show errors", "log analysis"]) {
            return VoiceCommandIntent(
                category: .logs,
                risk: .safe,
                rawTranscript: rawTranscript,
                normalizedMessage: rawTranscript,
                confirmationPrompt: nil,
                confirmButtonLabel: "Fetch",
                executionHint: "Fetching logs",
                extractedKeywords: ["logs"]
            )
        }

        // Status/query — safe (broad catch)
        if matches(text, patterns: ["status", "what is", "show me", "tell me", "explain", "summarize", "list", "how many", "check"]) {
            return .safeQuery(
                transcript: rawTranscript,
                message: rawTranscript,
                hint: "Querying agent"
            )
        }

        // Fallback: generic safe send
        return .generic(transcript: rawTranscript)
    }

    // MARK: - Helpers

    private static func matches(_ text: String, patterns: [String]) -> Bool {
        patterns.contains(where: { text.contains($0) })
    }

    private static func matchesConfirm(_ text: String) -> Bool {
        // Must be a short utterance that is just a confirm word
        let words = text.split(separator: " ").map(String.init)
        let confirmWords = ["yes", "confirm", "proceed", "do it", "go ahead", "affirmative", "yep", "yeah", "ok", "okay"]
        if words.count <= 3 {
            return confirmWords.contains(where: { text.contains($0) })
        }
        return false
    }

    private static func matchesCancel(_ text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        let cancelWords = ["no", "cancel", "abort", "stop", "never mind", "nevermind", "forget it"]
        if words.count <= 3 {
            return cancelWords.contains(where: { text.contains($0) })
        }
        return false
    }
}
