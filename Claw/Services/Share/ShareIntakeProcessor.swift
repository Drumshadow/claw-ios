import Foundation

// MARK: - ShareIntakeProcessor

/// Drives intake items from ShareIntakeQueue through metadata extraction → gateway send.
/// Attach to the main app's lifecycle; call process() when a connection becomes available.
///
/// This class is intentionally separate from ShareIntakeQueue so the queue
/// (which uses only Foundation + URLSession) can be compiled into the share
/// extension without pulling in GatewayClient or SessionStore.
@Observable
@MainActor
final class ShareIntakeProcessor {

    private let queue: ShareIntakeQueue
    private let metadataExtractor: ShareMetadataExtractor
    nonisolated(unsafe) private var processingTask: Task<Void, Never>?

    init(queue: ShareIntakeQueue? = nil) {
        self.queue = queue ?? ShareIntakeQueue.shared
        self.metadataExtractor = ShareMetadataExtractor()
    }

    deinit {
        processingTask?.cancel()
    }

    // MARK: - Public API

    /// Begin processing the queue with the given gateway client.
    func process(client: GatewayClient, sessionStore: SessionStore?) {
        processingTask?.cancel()
        processingTask = Task {
            await processAll(client: client, sessionStore: sessionStore)
        }
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
    }

    /// Deliver a single, already-enqueued item to the gateway immediately, reporting whether
    /// it was sent. Used by the in-app share sheet so it can show real success/failure; the
    /// batch `process` path handles items queued while offline. Idempotent per item id, so a
    /// later batch drain of the same item can't double-send it.
    func deliver(_ item: ShareIntakeItem, client: GatewayClient, sessionStore: SessionStore?) async -> Bool {
        queue.updateStatus(id: item.id, status: .sending)
        let sessionKey = resolveSessionKey(for: item, sessionStore: sessionStore)
        do {
            let params = ProcessorSendParams(
                sessionKey: sessionKey,
                message: item.composeAgentMessage(),
                idempotencyKey: item.id.uuidString
            )
            _ = try await client.send(method: GatewayMethod.chatSend, params: params)
            queue.markDelivered(id: item.id)
            return true
        } catch {
            // Transient send failure — keep it drain-eligible (.ready) so the next connect
            // retries, rather than stranding it in a terminal state nothing ever resends.
            queue.updateStatus(id: item.id, status: .ready)
            return false
        }
    }

    // MARK: - Processing pipeline

    private func processAll(client: GatewayClient, sessionStore: SessionStore?) async {
        let pending = queue.pendingItems
        guard !pending.isEmpty else { return }

        queue.setProcessing(true)
        defer { queue.setProcessing(false) }

        for var item in pending {
            guard !Task.isCancelled else { break }

            // Step 1: Extract metadata
            if item.status == .pending {
                queue.updateStatus(id: item.id, status: .extracting)
                let metadata = await metadataExtractor.extract(from: item)
                if let metadata {
                    queue.updateMetadata(id: item.id, metadata: metadata)
                } else {
                    queue.updateStatus(id: item.id, status: .ready)
                }
                item = queue.items.first(where: { $0.id == item.id }) ?? item
            }

            guard item.status == .ready else { continue }
            guard !Task.isCancelled else { break }

            // Step 2: Resolve target session
            let sessionKey = resolveSessionKey(for: item, sessionStore: sessionStore)

            // Step 3: Send to gateway
            queue.updateStatus(id: item.id, status: .sending)
            do {
                let message = item.composeAgentMessage()
                let params = ProcessorSendParams(
                    sessionKey: sessionKey,
                    message: message,
                    idempotencyKey: item.id.uuidString
                )
                _ = try await client.send(method: GatewayMethod.chatSend, params: params)
                queue.markDelivered(id: item.id)
            } catch {
                // Keep failed sends drain-eligible so a later connect retries them.
                queue.updateStatus(id: item.id, status: .ready)
            }
        }
    }

    private func resolveSessionKey(for item: ShareIntakeItem, sessionStore: SessionStore?) -> String {
        switch item.routing {
        case .session(let id, _):
            return id
        case .autoSelect:
            if let idle = sessionStore?.sessions.first(where: { $0.agentStatus == .idle }) {
                return idle.id
            }
            fallthrough
        case .newSession:
            return "auto-\(item.id.uuidString.prefix(8))"
        }
    }
}

// MARK: - Private params

private struct ProcessorSendParams: Encodable {
    let sessionKey: String
    let message: String
    let idempotencyKey: String
}
