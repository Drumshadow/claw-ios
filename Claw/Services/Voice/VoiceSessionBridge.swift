import Foundation
import SwiftUI

// MARK: - VoiceSessionBridge

/// Connects a VoiceOpsManager to a live GatewayClient so that voice transcripts
/// trigger real agent message sends and responses are read back via TTS.
///
/// Lifecycle:
/// 1. Create bridge with a GatewayClient + sessionKey.
/// 2. Set closure callbacks (onResponse, onConfirmationRequired, onStatusChange, onError).
/// 3. Call `processTranscript(_:)` from VoiceOpsManager.onTranscriptReady.
/// 4. Bridge parses command intent, checks risk:
///    - .safe  → sends immediately, waits for streaming response, calls onResponse.
///    - .caution/.danger → calls onConfirmationRequired; caller
///      confirms via confirmPendingIntent() or cancels via cancelPendingIntent().
/// 5. Response text is extracted from the event stream and trimmed for TTS.
@Observable
@MainActor
final class VoiceSessionBridge {

    // MARK: - Observable state

    private(set) var status: String = ""
    private(set) var isPending: Bool = false
    private(set) var pendingIntent: VoiceCommandIntent?
    private(set) var lastResponseText: String = ""

    // MARK: - Closure callbacks (set by view layer; avoids weak-struct issues)

    /// Called when the agent produces a complete response ready for TTS.
    var onResponse: (@MainActor (String) -> Void)?
    /// Called when a risky command needs user confirmation before executing.
    var onConfirmationRequired: (@MainActor (VoiceCommandIntent) -> Void)?
    /// Called on status/progress changes (for display in voice UI).
    var onStatusChange: (@MainActor (String) -> Void)?
    /// Called when a send/receive error occurs.
    var onError: (@MainActor (String) -> Void)?

    // MARK: - Dependencies

    private let client: GatewayClient
    let sessionKey: String

    // Tracks in-flight send
    nonisolated(unsafe) private var sendTask: Task<Void, Never>?

    // MARK: - Init

    init(client: GatewayClient, sessionKey: String) {
        self.client = client
        self.sessionKey = sessionKey
    }

    deinit {
        sendTask?.cancel()
    }

    // MARK: - Public interface

    /// Called when VoiceOpsManager produces a finalized transcript.
    func processTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let intent = VoiceCommandParser.parse(trimmed)

        switch intent.category {
        case .confirm:
            if isPending { confirmPendingIntent() }
            return
        case .cancel:
            if isPending { cancelPendingIntent() }
            return
        case .drivingMode:
            setStatus("Driving mode toggled")
            return
        default:
            break
        }

        if intent.risk >= .caution {
            pendingIntent = intent
            isPending = true
            onConfirmationRequired?(intent)
        } else {
            executeIntent(intent)
        }
    }

    /// Call after the user confirms a pending caution/danger intent.
    func confirmPendingIntent() {
        guard let intent = pendingIntent else { return }
        pendingIntent = nil
        isPending = false
        executeIntent(intent)
    }

    /// Call when the user cancels a pending confirmation.
    func cancelPendingIntent() {
        pendingIntent = nil
        isPending = false
        setStatus("Cancelled")
    }

    /// Interrupt any in-flight operation.
    func cancelCurrentOperation() {
        sendTask?.cancel()
        sendTask = nil
        setStatus("Stopped")
    }

    // MARK: - Private: execution

    private func executeIntent(_ intent: VoiceCommandIntent) {
        setStatus(intent.executionHint)
        sendTask?.cancel()
        sendTask = Task { await performSend(intent: intent) }
    }

    private func performSend(intent: VoiceCommandIntent) async {
        setStatus("Sending…")
        do {
            let params = VoiceChatSendParams(
                sessionKey: sessionKey,
                message: intent.normalizedMessage,
                idempotencyKey: UUID().uuidString
            )
            _ = try await client.send(method: GatewayMethod.chatSend, params: params)
            setStatus("Waiting for agent…")

            let response = await waitForResponse()
            guard !Task.isCancelled else { return }

            lastResponseText = response
            setStatus("Done")
            onResponse?(response)

        } catch {
            guard !Task.isCancelled else { return }
            let reason = "Send failed: \(error.localizedDescription)"
            setStatus(reason)
            onError?(reason)
        }
    }

    /// Listens to the gateway event stream to collect the assistant's response.
    /// Returns when message.complete fires or after a 60-second timeout.
    private func waitForResponse() async -> String {
        var accumulated = ""
        var gotComplete = false

        let eventStream = await client.events()

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }

        for await event in eventStream {
            if Task.isCancelled || timeoutTask.isCancelled { break }

            switch event.name {
            case GatewayEventName.messageDelta:
                if let delta = event.payload["delta"]?.stringValue {
                    accumulated += delta
                    setStatus("Receiving…")
                }
            case GatewayEventName.messageComplete:
                if let content = event.payload["content"]?.stringValue, !content.isEmpty {
                    accumulated = content
                }
                gotComplete = true
            default:
                break
            }

            if gotComplete { break }
        }

        timeoutTask.cancel()
        return summarizeForSpeech(accumulated)
    }

    // MARK: - TTS summary helper

    /// Strip markdown and truncate for comfortable voice playback (~35 seconds).
    private func summarizeForSpeech(_ text: String) -> String {
        guard !text.isEmpty else { return "Task complete." }

        var clean = text
        clean = clean.replacingOccurrences(
            of: #"```[\s\S]*?```"#, with: "…code omitted…", options: .regularExpression)
        clean = clean.replacingOccurrences(
            of: "`[^`]+`", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(
            of: #"#{1,6}\s+"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(
            of: "[*_]{1,3}", with: "", options: .regularExpression)
        clean = clean
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if clean.count > 450 {
            clean = String(clean.prefix(450))
                + "… I've shortened the response. Check the screen for details."
        }

        return clean.isEmpty ? "Task complete." : clean
    }

    private func setStatus(_ status: String) {
        self.status = status
        onStatusChange?(status)
    }
}

// MARK: - Private params type

private struct VoiceChatSendParams: Encodable {
    let sessionKey: String
    let message: String
    let idempotencyKey: String
}
