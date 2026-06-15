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

    /// Cumulative assistant text for the in-flight voice response. `chat` deltas carry the
    /// full message-so-far (not incremental chunks), so this is replaced, not appended.
    private var accumulatedResponse = ""

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

        // Subscribe to the response BEFORE sending. If we only subscribed after the send ack,
        // a fast reply could stream in during the round-trip and be missed (the gateway has no
        // event replay), leaving us to speak the canned fallback. chat deltas are cumulative,
        // so any event that lands before the send merely seeds the text — never a problem.
        let responseTask = Task { await waitForResponse() }
        await Task.yield()   // let the event-stream continuation register before we send

        do {
            let params = VoiceChatSendParams(
                sessionKey: sessionKey,
                message: intent.normalizedMessage,
                idempotencyKey: UUID().uuidString
            )
            _ = try await client.send(method: GatewayMethod.chatSend, params: params)
            setStatus("Waiting for agent…")
        } catch {
            responseTask.cancel()
            guard !Task.isCancelled else { return }
            let reason = "Send failed: \(error.localizedDescription)"
            setStatus(reason)
            onError?(reason)
            return
        }

        // Propagate cancellation (user "stop") to the in-flight collector.
        let response = await withTaskCancellationHandler {
            await responseTask.value
        } onCancel: {
            responseTask.cancel()
        }
        guard !Task.isCancelled else { return }

        lastResponseText = response
        setStatus("Done")
        onResponse?(response)
    }

    /// Collects the assistant's spoken response from the gateway's streaming `chat` events
    /// (the same contract MessageStore consumes), bounded by an overall timeout. Returns the
    /// final message, or the latest partial if it times out / aborts.
    private func waitForResponse() async -> String {
        accumulatedResponse = ""
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.collectResponse() }
            group.addTask { try? await Task.sleep(nanoseconds: 60_000_000_000) }
            // Whichever finishes first — the response completing, or the timeout — ends the
            // wait; cancelling the other unblocks it (AsyncStream iteration and Task.sleep
            // both honor cancellation, so neither can hang the bridge).
            await group.next()
            group.cancelAll()
        }
        return summarizeForSpeech(accumulatedResponse)
    }

    /// Reads streaming `chat` events for this bridge's session and accumulates the assistant
    /// text. Each delta carries the cumulative message, so it REPLACES the running text
    /// (matching MessageStore.handleChatEvent). Returns on final / aborted / error.
    private func collectResponse() async {
        let eventStream = await client.events()
        for await event in eventStream {
            guard event.name == "chat",
                  payloadBelongsToSession(event.payload),
                  let state = event.payload["state"]?.stringValue else { continue }

            switch state {
            case "delta":
                if let msg = event.payload["message"], let text = Self.extractText(from: msg), !text.isEmpty {
                    accumulatedResponse = text
                    setStatus("Receiving…")
                }
            case "final":
                if let msg = event.payload["message"], let text = Self.extractText(from: msg), !text.isEmpty {
                    accumulatedResponse = text
                }
                return
            case "aborted", "error":
                return
            default:
                break
            }
        }
    }

    /// True when a `chat` event payload belongs to this bridge's session.
    private func payloadBelongsToSession(_ payload: [String: JSONValue]) -> Bool {
        if let sk = payload["sessionKey"]?.stringValue { return sk == sessionKey }
        if let key = payload["key"]?.stringValue { return key == sessionKey }
        return false
    }

    /// Mirror of MessageStore.extractText: pull assistant text from a chat message value.
    private static func extractText(from value: JSONValue) -> String? {
        if case .object(let obj) = value { return extractText(from: obj) }
        if case .string(let s) = value { return s.isEmpty ? nil : s }
        return nil
    }

    private static func extractText(from obj: [String: JSONValue]) -> String? {
        if let t = obj["text"]?.stringValue, !t.isEmpty { return t }
        if let content = obj["content"] {
            switch content {
            case .string(let s) where !s.isEmpty:
                return s
            case .array(let blocks):
                let parts = blocks.compactMap { block -> String? in
                    guard case .object(let blk) = block,
                          blk["type"]?.stringValue == "text",
                          let t = blk["text"]?.stringValue, !t.isEmpty else { return nil }
                    return t
                }
                return parts.isEmpty ? nil : parts.joined(separator: "\n")
            default:
                break
            }
        }
        return nil
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
