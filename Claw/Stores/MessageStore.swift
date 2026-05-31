import Foundation
import UserNotifications
import UIKit

// MARK: - MessageStore

/// Loads, streams, and sends messages for a single session.
@Observable
@MainActor
final class MessageStore {

    // MARK: - Observable state

    private(set) var messages: [ClawMessage] = []
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var isSending: Bool = false
    private(set) var loadError: Error?
    private(set) var sendError: Error?
    private(set) var hasMore: Bool = false

    // Anchor message ID requested by the store after a paginate-older fetch.
    // Views observe this to restore scroll position to the same message after
    // older messages are prepended.
    private(set) var scrollAnchorAfterPrepend: String?

    private var commandmentsInjected: Bool = false

    // MARK: - Cache helpers

    private static let messageCacheLimit = 50
    private static let maxDisplayContentCharacters = 80_000

    /// Locally-projected bubbles that should be replaced by durable transcript
    /// messages once the gateway commit arrives. `final-` covers chat.final
    /// payloads that render before chat.history/session.message catch up.
    private static func isEphemeralMessageId(_ id: String) -> Bool {
        id.hasPrefix("temp-") || id.hasPrefix("stream-") || id.hasPrefix("final-")
    }

    private var messageCacheKey: String { "claw.messages.\(sessionKey)" }

    private func loadMessageCache() -> [ClawMessage] {
        guard let data = UserDefaults.standard.data(forKey: messageCacheKey),
              let msgs = try? JSONDecoder().decode([ClawMessage].self, from: data) else { return [] }
        return msgs
    }

    private func saveMessageCache(_ messages: [ClawMessage]) {
        let toCache = messages
            .filter { !$0.isStreaming && !$0.sendFailed && $0.role != .tool && !Self.isEphemeralMessageId($0.id) }
            .suffix(Self.messageCacheLimit)
        if let data = try? JSONEncoder().encode(Array(toCache)) {
            UserDefaults.standard.set(data, forKey: messageCacheKey)
        }
    }

    // MARK: - Pagination tuning

    private static let initialPageSize: Int = 50
    private static let pageSizeStep: Int = 50
    private static let maxLimit: Int = 250   // cap to prevent LazyVStack freeze on long conversations
    private var currentLimit: Int = MessageStore.initialPageSize

    // MARK: - Private

    private let client: GatewayClient
    let sessionKey: String
    private let sessionTitle: String
    private(set) var sessionModel: String?
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    nonisolated(unsafe) private var silentReloadTask: Task<Void, Never>?
    nonisolated(unsafe) private var responseNotificationTask: Task<Void, Never>?
    // Tracks run IDs we've started Live Activities for. Capped to prevent
    // unbounded growth during long app sessions with many agent runs.
    private var seenRunIds: Set<String> = []
    private var seenRunIdOrder: [String] = []   // insertion-order tracker for eviction
    private static let seenRunIdCap = 100
    // Monotonic counter for tool message IDs to guarantee uniqueness even if
    // messages are removed between two tool_use events.
    private var toolIdSeq: Int = 0

    // MARK: - Init

    init(client: GatewayClient, sessionKey: String, sessionTitle: String = "", sessionModel: String? = nil) {
        self.client = client
        self.sessionKey = sessionKey
        self.sessionTitle = sessionTitle
        self.sessionModel = sessionModel
        let cached = loadMessageCache()
        if !cached.isEmpty { messages = cached }
        startEventSubscription()
    }

    deinit {
        eventTask?.cancel()
        silentReloadTask?.cancel()
        responseNotificationTask?.cancel()
    }

    // MARK: - Subscribe / Unsubscribe

    func subscribe() async {
        guard !AppReviewSampleData.isEnabled else { return }
        _ = try? await client.send(method: GatewayMethod.sessionsSubscribe, params: SessionKeyParams(key: sessionKey))
        _ = try? await client.send(method: GatewayMethod.sessionsMessagesSubscribe, params: SessionKeyParams(key: sessionKey))
    }

    func unsubscribe() async {
        guard !AppReviewSampleData.isEnabled else { return }
        _ = try? await client.send(method: GatewayMethod.sessionsMessagesUnsubscribe, params: SessionKeyParams(key: sessionKey))
    }

    func pollUpdates() {
        silentReload()
    }

    // MARK: - Load (initial page)

    func load() async throws {
        if AppReviewSampleData.isEnabled {
            messages = AppReviewSampleData.messages(for: sessionKey)
            hasMore = false
            loadError = nil
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        currentLimit = Self.initialPageSize
        do {
            let params = ChatHistoryParams(sessionKey: sessionKey, limit: currentLimit)
            let payload = try await client.send(method: GatewayMethod.chatHistory, params: params)
            applyHistory(payload: payload, requestedLimit: currentLimit)
        } catch {
            loadError = error
            throw error
        }
    }

    // MARK: - Load more (infinite scroll for older messages)

    /// Requests the next page of older messages. The gateway's `chat.history`
    /// only supports a "last N" form, so we re-request with a larger limit and
    /// replace the message list, asking the view to restore scroll to the
    /// previous top message.
    func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let nextLimit = min(currentLimit + Self.pageSizeStep, Self.maxLimit)
        guard nextLimit > currentLimit else {
            hasMore = false
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let priorTopId = messages.first?.id
        do {
            let params = ChatHistoryParams(sessionKey: sessionKey, limit: nextLimit)
            let payload = try await client.send(method: GatewayMethod.chatHistory, params: params)
            currentLimit = nextLimit
            // Set the anchor BEFORE mutating messages so view-side observers see
            // the anchor non-nil during the same render that the count increases,
            // suppressing auto-scroll-to-bottom in that frame.
            scrollAnchorAfterPrepend = priorTopId
            applyHistory(payload: payload, requestedLimit: nextLimit)
        } catch {
            // Keep prior view; surface as a transient load error.
            loadError = error
        }
    }

    /// Acknowledge that the view has consumed the scroll anchor and restored position.
    func clearScrollAnchor() {
        scrollAnchorAfterPrepend = nil
    }

    func updateSessionModel(_ model: String?) {
        guard model != sessionModel else { return }
        sessionModel = model
        LiveActivityManager.shared.updateModel(model)
    }

    // MARK: - Abort

    /// Requests the gateway to abort the running agent for this session.
    func abort() async throws {
        _ = try await client.send(method: GatewayMethod.sessionsAbort, params: SessionAbortParams(sessionKey: sessionKey))
    }

    // MARK: - Send

    func send(text: String, attachments: [AttachmentItem] = []) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        isSending = true
        sendError = nil
        defer { isSending = false }

        let displayTitle = sessionTitle.isEmpty ? String(sessionKey.prefix(12)) : sessionTitle
        LiveActivityManager.shared.startOrUpdateActivity(
            sessionId: sessionKey,
            sessionTitle: displayTitle,
            model: sessionModel,
            status: "thinking"
        )

        let displayText = trimmed.isEmpty ? attachments.map { $0.name }.joined(separator: ", ") : trimmed
        let tempId = "temp-\(UUID().uuidString)"
        let attachmentNames = attachments.isEmpty ? nil : attachments.map { $0.name }
        messages.append(ClawMessage(
            id: tempId,
            sessionKey: sessionKey,
            role: .user,
            content: displayText,
            isStreaming: false,
            createdAt: Date(),
            sendFailed: false,
            pendingText: trimmed.isEmpty ? nil : trimmed,
            attachmentNames: attachmentNames
        ))

        if AppReviewSampleData.isEnabled {
            messages.append(ClawMessage(
                id: "sample-reply-\(UUID().uuidString)",
                sessionKey: sessionKey,
                role: .assistant,
                content: "Sample mode is active. This reply is generated locally so screenshots never depend on a live gateway or third-party service.",
                isStreaming: false,
                createdAt: Date()
            ))
            return
        }

        do {
            // Attachment binary is not sent over the WebSocket. Text-extractable files (PDF,
            // plain text, etc.) have their content included inline so the agent can read them.
            var messageText = trimmed
            for attachment in attachments {
                if let content = attachment.textContent {
                    let capped = content.count > 12_000
                        ? String(content.prefix(12_000)) + "\n…[truncated]"
                        : content
                    messageText += (messageText.isEmpty ? "" : "\n\n")
                        + "[\(attachment.name)]\n\(capped)"
                } else {
                    messageText += (messageText.isEmpty ? "" : "\n\n")
                        + "[Attached: \(attachment.name)]"
                }
            }
            if !commandmentsInjected {
                let enabledCommandments = Commandment.load().filter { $0.isEnabled }
                if !enabledCommandments.isEmpty {
                    let rules = enabledCommandments.map { "- \($0.text)" }.joined(separator: "\n")
                    let prefix = "<commandments>\n\(rules)\n</commandments>\n\n"
                    messageText = prefix + messageText
                }
                commandmentsInjected = true
            }

            let params = ChatSendParams(
                sessionKey: sessionKey,
                message: messageText,
                idempotencyKey: UUID().uuidString
            )
            _ = try await client.send(method: GatewayMethod.chatSend, params: params)
        } catch {
            LiveActivityManager.shared.terminateActivity()
            // Keep the bubble visible but flagged as failed so the user can retry.
            if let idx = messages.firstIndex(where: { $0.id == tempId }) {
                messages[idx].sendFailed = true
            }
            sendError = error
            throw error
        }
    }

    /// Retries a previously-failed send. The original temp bubble is replaced
    /// by a fresh send; on success the gateway flow takes over.
    func retrySend(messageId: String) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].sendFailed,
              let text = messages[idx].pendingText else { return }

        messages[idx].sendFailed = false
        messages.remove(at: idx)
        try? await send(text: text)
    }

    /// Discards a failed bubble without retrying.
    func discardFailed(messageId: String) {
        messages.removeAll { $0.id == messageId && $0.sendFailed }
    }

    // MARK: - Private: silent history reload

    /// Falls back to a full history refetch. Reserved for cases where event payloads
    /// are missing required fields. Cancels any in-flight silent reload first so a
    /// burst of malformed events can't stack concurrent fetches.
    private func silentReload() {
        silentReloadTask?.cancel()
        let limit = currentLimit
        let sk = sessionKey
        silentReloadTask = Task { [weak self, client] in
            let params = ChatHistoryParams(sessionKey: sk, limit: limit)
            guard let payload = try? await client.send(method: GatewayMethod.chatHistory, params: params) else { return }
            guard !Task.isCancelled, let self else { return }
            self.applyHistory(payload: payload, requestedLimit: limit)
        }
    }

    // MARK: - Private: parse history

    private func applyHistory(payload: [String: JSONValue], requestedLimit: Int) {
        guard let messagesValue = payload["messages"],
              case .array(let arr) = messagesValue else {
            // Preserve the last-known transcript on malformed/transient history
            // responses. Treating a bad payload as an empty transcript is what
            // makes conversations look like they were archived/lost when two
            // clients race a refresh.
            if messages.isEmpty {
                messages = loadMessageCache()
            }
            return
        }

        // Index existing temp-/stream-/final- bubbles by role+content for O(1) lookup
        // instead of an O(N*M) scan-per-incoming-item. With large histories and
        // long message content this turns a quadratic blowup into a linear pass.
        struct MatchKey: Hashable {
            let roleRaw: String
            let content: String
        }
        var existingStableIds: [MatchKey: String] = [:]
        var failedBubbles: [ClawMessage] = []
        var ephemeralBubbles: [ClawMessage] = []
        var toolMessages: [ClawMessage] = []
        for msg in messages {
            if msg.sendFailed {
                failedBubbles.append(msg)
                continue
            }
            if msg.role == .tool {
                toolMessages.append(msg)
                continue
            }
            if Self.isEphemeralMessageId(msg.id) {
                let key = MatchKey(roleRaw: msg.role.rawValue, content: msg.content)
                // Earlier-inserted ID wins; later duplicates leave the first in place.
                if existingStableIds[key] == nil {
                    existingStableIds[key] = msg.id
                }
                ephemeralBubbles.append(msg)
            }
        }

        var result: [ClawMessage] = []
        result.reserveCapacity(arr.count)
        var resultKeys: Set<MatchKey> = []
        for (index, item) in arr.enumerated() {
            guard case .object(let obj) = item else { continue }
            guard let roleVal = obj["role"], case .string(let roleStr) = roleVal else { continue }
            guard isTranscriptDisplayRole(roleStr) else { continue }
            guard let rawContent = extractText(from: obj) else { continue }
            let content = prepareDisplayContent(from: rawContent)
            guard !content.isEmpty else { continue }

            let role = MessageRole(rawString: roleStr)
            let key = MatchKey(roleRaw: role.rawValue, content: content)
            // Reuse an existing local bubble ID if it matches by role+content.
            // Covers optimistic user messages, active streams, and chat.final
            // projections, preventing SwiftUI from animating the message out and back in.
            let stableId = existingStableIds[key] ?? "\(sessionKey)-h\(index)"
            resultKeys.insert(key)

            result.append(ClawMessage(
                id: stableId,
                sessionKey: sessionKey,
                role: role,
                content: content,
                isStreaming: false,
                createdAt: Date()
            ))
        }

        // Keep local bubbles (active streams and chat.final projections) not yet
        // confirmed in history. This guards the timing gap where chat.final has
        // already rendered the assistant answer but chat.history is still built
        // from the previous durable transcript; dropping final- bubbles here is
        // what made the answer disappear until leaving/reopening the thread.
        let unresolved = ephemeralBubbles.filter {
            !resultKeys.contains(MatchKey(roleRaw: $0.role.rawValue, content: $0.content))
        }

        // Tool messages are client-projected live UI, not durable chat transcript.
        // Preserve only currently-streaming tools during an in-flight run; completed
        // tool rows should not stick to the bottom after the assistant finalizes.
        let activeToolMessages = toolMessages.filter { $0.isStreaming }
        messages = result + unresolved + activeToolMessages + failedBubbles
        saveMessageCache(messages)

        // The gateway returns up to `limit` most-recent messages. If it returned
        // strictly fewer than asked, we've hit the head of history.
        hasMore = (arr.count >= requestedLimit) && (requestedLimit < Self.maxLimit)
    }

    // MARK: - Private: seenRunIds management

    /// Inserts a run ID, evicting the oldest entry when the cap is exceeded.
    private func markRunIdSeen(_ runId: String) {
        guard !seenRunIds.contains(runId) else { return }
        if seenRunIds.count >= Self.seenRunIdCap {
            // Evict the oldest tracked run ID to keep the set bounded.
            if let oldest = seenRunIdOrder.first {
                seenRunIdOrder.removeFirst()
                seenRunIds.remove(oldest)
            }
        }
        seenRunIds.insert(runId)
        seenRunIdOrder.append(runId)
    }

    // MARK: - Private: event subscription

    private func startEventSubscription() {
        // IMPORTANT: do NOT promote `self` to strong before the for-await.
        // `guard let self else { return }` outside the loop would keep `self`
        // alive for the entire stream lifetime (suspension included), creating
        // a retain cycle (self → eventTask → closure-local-self) that blocks deinit.
        eventTask = Task { [weak self, client] in
            for await event in await client.events() {
                guard let self else { return }
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {
        case "chat":
            handleChatEvent(event.payload)
        case "session.message":
            handleSessionMessageEvent(event.payload)
        case "session.tool":
            handleSessionToolEvent(event.payload)
        default:
            break
        }
    }

    private func payloadBelongsToSession(_ payload: [String: JSONValue]) -> Bool {
        if let skVal = payload["sessionKey"], case .string(let sk) = skVal {
            return sk == sessionKey
        }
        if let keyVal = payload["key"], case .string(let key) = keyVal {
            return key == sessionKey
        }
        return false
    }

    // MARK: - Private: chat event (streaming)

    private func handleChatEvent(_ payload: [String: JSONValue]) {
        guard payloadBelongsToSession(payload) else { return }
        guard let stateVal = payload["state"],
              case .string(let state) = stateVal else { return }

        let runId: String
        if let rv = payload["runId"], case .string(let r) = rv {
            runId = r
        } else {
            runId = "unknown"
        }
        let streamId = "stream-\(runId)"

        switch state {
        case "delta":
            responseNotificationTask?.cancel()
            guard let msgVal = payload["message"],
                  let rawText = extractText(from: msgVal) else { return }
            let text = prepareDisplayContent(from: rawText)
            guard !text.isEmpty else { return }

            // Keep sessionModel up-to-date if the gateway includes it in the delta payload
            if let modelVal = payload["model"], case .string(let m) = modelVal, !m.isEmpty {
                sessionModel = m
            }

            if !seenRunIds.contains(runId) {
                markRunIdSeen(runId)
                let displayTitle = sessionTitle.isEmpty ? String(sessionKey.prefix(12)) : sessionTitle
                LiveActivityManager.shared.startOrUpdateActivity(sessionId: sessionKey, sessionTitle: displayTitle, model: sessionModel)
            }

            let thinkingText: String?
            if case .object(let msgObj) = msgVal {
                thinkingText = extractThinkingText(from: msgObj)
            } else {
                thinkingText = nil
            }

            if let idx = messages.firstIndex(where: { $0.id == streamId }) {
                messages[idx].content = text
                messages[idx].thinkingContent = thinkingText
            } else {
                messages.append(ClawMessage(
                    id: streamId,
                    sessionKey: sessionKey,
                    role: .assistant,
                    content: text,
                    isStreaming: true,
                    createdAt: Date(),
                    thinkingContent: thinkingText
                ))
            }

        case "final":
            // Some gateway paths include the completed assistant message directly
            // on chat.final. Do not wait for a later history reload in that case —
            // otherwise a foreground chat can sit on the reasoning/tool UI until
            // the user leaves and reopens the thread.
            if let msgVal = payload["message"],
               case .object(let obj) = msgVal,
               let rawContent = extractText(from: obj) {
                let content = prepareDisplayContent(from: rawContent)
                if !content.isEmpty {
                    let role: MessageRole
                    if let roleVal = obj["role"], case .string(let roleStr) = roleVal {
                        role = MessageRole(rawString: roleStr)
                    } else {
                        role = .assistant
                    }
                    upsertFinishedAssistantMessage(
                        role: role,
                        content: content,
                        messageId: "final-\(runId)",
                        streamId: streamId,
                        scheduleNotification: false
                    )
                }
            }

            // Mark streaming bubble as not-streaming; the session.message event
            // (or its absence) will trigger any further sync.
            if let idx = messages.firstIndex(where: { $0.id == streamId }) {
                messages[idx].isStreaming = false
            }
            LiveActivityManager.shared.terminateActivity()
            clearStreamingStateForFinishedRun(runId: runId)
            refreshTranscriptAfterFinal()

        case "aborted", "error":
            responseNotificationTask?.cancel()
            messages.removeAll { $0.id == streamId }
            LiveActivityManager.shared.terminateActivity()
            clearStreamingStateForFinishedRun(runId: runId)

        default:
            break
        }
    }

    private func clearStreamingStateForFinishedRun(runId: String) {
        messages.indices.forEach { i in
            if messages[i].id == "stream-\(runId)" {
                messages[i].isStreaming = false
            }
        }

        // Tool rows are transient live UI, not durable transcript messages. Final
        // chat events are terminal for this subscribed session; remove any live
        // tool bubble so it cannot remain stuck at the bottom after the assistant
        // answer is already visible.
        messages.removeAll { $0.role == .tool }
    }

    // MARK: - Private: session.tool event (live tool visibility)

    private func handleSessionToolEvent(_ payload: [String: JSONValue]) {
        // Only handle events for our session
        guard payloadBelongsToSession(payload) else { return }

        guard let runIdVal = payload["runId"],
              case .string(let runId) = runIdVal else { return }

        guard let dataVal = payload["data"],
              case .object(let data) = dataVal else { return }

        let phase: String
        if let pv = data["phase"], case .string(let p) = pv { phase = p } else { return }

        let toolName: String
        if let nv = data["name"], case .string(let n) = nv, !n.isEmpty { toolName = n }
        else if let nv = payload["name"], case .string(let n) = nv, !n.isEmpty { toolName = n }
        else { return }

        var toolInput: [String: JSONValue]? = nil
        if let iv = data["input"], case .object(let obj) = iv { toolInput = obj }

        if phase == "start" {
            responseNotificationTask?.cancel()
            // Start Live Activity if first tool in this run
            if !seenRunIds.contains(runId) {
                markRunIdSeen(runId)
                let displayTitle = sessionTitle.isEmpty ? String(sessionKey.prefix(12)) : sessionTitle
                LiveActivityManager.shared.startOrUpdateActivity(sessionId: sessionKey, sessionTitle: displayTitle, model: sessionModel)
            }
            LiveActivityManager.shared.updateActivity(currentTool: toolName, status: "running")

            toolIdSeq &+= 1
            let toolId = "tool-\(runId)-\(toolName)-\(toolIdSeq)"
            messages.append(ClawMessage(
                id: toolId,
                sessionKey: sessionKey,
                role: .tool,
                content: toolName,
                isStreaming: true,
                createdAt: Date(),
                toolName: toolName,
                toolInput: toolInput,
                toolResult: nil
            ))
        } else if phase == "end" || phase == "error" {
            let result: String?
            if let rv = data["result"], case .string(let r) = rv { result = r }
            else { result = nil }

            let prefix = "tool-\(runId)-\(toolName)-"
            if let idx = messages.lastIndex(where: {
                $0.role == .tool && $0.id.hasPrefix(prefix) && $0.toolResult == nil
            }) {
                messages[idx].toolResult = result ?? (phase == "error" ? "error" : nil)
                messages[idx].isStreaming = false
                return
            }
            if let idx = messages.lastIndex(where: {
                $0.role == .tool && $0.toolName == toolName && $0.toolResult == nil
            }) {
                messages[idx].toolResult = result ?? (phase == "error" ? "error" : nil)
                messages[idx].isStreaming = false
            }
        }
    }

    // MARK: - Private: session.message event (committed messages)

    private func handleSessionMessageEvent(_ payload: [String: JSONValue]) {
        guard payloadBelongsToSession(payload) else { return }

        // The payload carries a fully-projected message — parse it directly
        // instead of refetching the entire history.
        guard let msgVal = payload["message"],
              case .object(let obj) = msgVal,
              let roleVal = obj["role"], case .string(let roleStr) = roleVal
        else {
            // Required fields missing — fall back to a full reload.
            silentReload()
            return
        }

        // Gateway transcript streams include non-chat records such as toolResult.
        // Those are not user-visible assistant replies; rendering them as normal
        // assistant bubbles is what leaves a stale-looking message at the bottom.
        guard isTranscriptDisplayRole(roleStr) else { return }
        guard let rawContent = extractText(from: obj) else { return }
        let content = prepareDisplayContent(from: rawContent)
        guard !content.isEmpty else { return }

        let role = MessageRole(rawString: roleStr)

        // For user-role messages, our optimistic bubble is already visible.
        // Reconcile by upgrading the temp- bubble to a stable ID if found.
        if role == .user {
            if let idx = messages.firstIndex(where: {
                $0.id.hasPrefix("temp-") && !$0.sendFailed &&
                $0.role == .user && $0.content == content
            }) {
                let messageId: String
                if let mv = payload["messageId"], case .string(let s) = mv {
                    messageId = s
                } else {
                    messageId = "committed-\(UUID().uuidString)"
                }
                messages[idx] = ClawMessage(
                    id: messageId,
                    sessionKey: sessionKey,
                    role: .user,
                    content: content,
                    isStreaming: false,
                    createdAt: messages[idx].createdAt
                )
            }
            return
        }

        // Assistant/system: prefer replacing an existing stream- bubble in place.
        // First try a content-equal match; if none, fall back to the most recent
        // non-streaming stream- bubble of the same role (covers the case where
        // chat.final's running text differs slightly from the committed text).
        let messageId: String
        if let mv = payload["messageId"], case .string(let s) = mv {
            messageId = s
        } else {
            messageId = "committed-\(UUID().uuidString)"
        }

        upsertFinishedAssistantMessage(
            role: role,
            content: content,
            messageId: messageId,
            streamId: nil,
            scheduleNotification: true
        )
    }

    private func upsertFinishedAssistantMessage(
        role: MessageRole,
        content: String,
        messageId: String,
        streamId: String?,
        scheduleNotification: Bool
    ) {
        if let streamId,
           let idx = messages.firstIndex(where: { $0.id == streamId }) {
            messages[idx] = ClawMessage(
                id: messageId,
                sessionKey: sessionKey,
                role: role,
                content: content,
                isStreaming: false,
                createdAt: messages[idx].createdAt
            )
            if scheduleNotification { scheduleResponseReadyNotification(messageId: messageId) }
            return
        }

        if let idx = messages.firstIndex(where: {
            ($0.id.hasPrefix("stream-") || $0.id.hasPrefix("final-")) && $0.role == role && $0.content == content
        }) {
            messages[idx] = ClawMessage(
                id: messageId,
                sessionKey: sessionKey,
                role: role,
                content: content,
                isStreaming: false,
                createdAt: messages[idx].createdAt
            )
            if scheduleNotification { scheduleResponseReadyNotification(messageId: messageId) }
            return
        }
        if let idx = messages.lastIndex(where: {
            ($0.id.hasPrefix("stream-") || $0.id.hasPrefix("final-")) && $0.role == role && !$0.isStreaming
        }) {
            messages[idx] = ClawMessage(
                id: messageId,
                sessionKey: sessionKey,
                role: role,
                content: content,
                isStreaming: false,
                createdAt: messages[idx].createdAt
            )
            if scheduleNotification { scheduleResponseReadyNotification(messageId: messageId) }
            return
        }
        if !messages.contains(where: { $0.role == role && $0.content == content }) {
            messages.append(ClawMessage(
                id: messageId,
                sessionKey: sessionKey,
                role: role,
                content: content,
                isStreaming: false,
                createdAt: Date()
            ))
            if scheduleNotification { scheduleResponseReadyNotification(messageId: messageId) }
        }
    }

    private func refreshTranscriptAfterFinal() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.silentReload() }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.silentReload() }
        }
    }

    private func scheduleResponseReadyNotification(messageId: String) {
        responseNotificationTask?.cancel()
        responseNotificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            guard UIApplication.shared.applicationState != .active else { return }
            let stillStreaming = self.messages.contains { $0.isStreaming }
            guard !stillStreaming, !self.isSending else { return }

            let content = UNMutableNotificationContent()
            content.title = "Claw agent response ready"
            content.body = self.sessionTitle.isEmpty
                ? "Your agent finished responding."
                : "Your agent finished responding in \(self.sessionTitle)."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "agent-done-\(messageId)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Private: text extraction

    private func isTranscriptDisplayRole(_ role: String) -> Bool {
        switch role.lowercased() {
        case "user", "assistant", "system":
            return true
        default:
            return false
        }
    }

    private func prepareDisplayContent(from text: String) -> String {
        let stripped = stripLeadingCommandments(from: text)
        let sanitized = stripped.replacingOccurrences(of: "\0", with: "")
        guard sanitized.count > Self.maxDisplayContentCharacters else { return sanitized }
        return String(sanitized.prefix(Self.maxDisplayContentCharacters))
            + "\n\n…[message truncated in iOS UI for stability]"
    }

    private func stripLeadingCommandments(from text: String) -> String {
        guard text.hasPrefix("<commandments>") else { return text }
        guard let endRange = text.range(of: "</commandments>") else { return text }
        let remainder = text[endRange.upperBound...]
        return String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractText(from value: JSONValue) -> String? {
        if case .object(let obj) = value { return extractText(from: obj) }
        if case .string(let s) = value { return s.isEmpty ? nil : s }
        return nil
    }

    private func extractText(from obj: [String: JSONValue]) -> String? {
        if let tv = obj["text"], case .string(let t) = tv, !t.isEmpty {
            return t
        }
        if let cv = obj["content"] {
            switch cv {
            case .string(let s) where !s.isEmpty:
                return s
            case .array(let blocks):
                let parts = blocks.compactMap { block -> String? in
                    guard case .object(let blk) = block,
                          let typeVal = blk["type"], case .string(let kind) = typeVal,
                          kind == "text",
                          let textVal = blk["text"], case .string(let t) = textVal,
                          !t.isEmpty else { return nil }
                    return t
                }
                return parts.isEmpty ? nil : parts.joined(separator: "\n")
            default:
                break
            }
        }
        return nil
    }

    private func extractThinkingText(from obj: [String: JSONValue]) -> String? {
        guard let cv = obj["content"], case .array(let blocks) = cv else { return nil }
        let parts = blocks.compactMap { block -> String? in
            guard case .object(let blk) = block,
                  let typeVal = blk["type"], case .string(let kind) = typeVal,
                  kind == "thinking",
                  let textVal = blk["text"], case .string(let t) = textVal,
                  !t.isEmpty else { return nil }
            return t
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

// MARK: - Request param types

private struct ChatHistoryParams: Encodable {
    let sessionKey: String
    let limit: Int
}

private struct ChatSendParams: Encodable {
    let sessionKey: String
    let message: String
    let idempotencyKey: String
}

private struct SessionKeyParams: Encodable {
    let key: String
}

private struct SessionAbortParams: Encodable {
    let sessionKey: String
}
