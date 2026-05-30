import Foundation

// MARK: - ShareIntakeQueue

/// Persistent, actor-isolated queue for share intake items.
///
/// Items are written to a shared App Group container so the share extension
/// and main app can both read/write the queue. The main app's ShareIntakeProcessor
/// monitors the queue and delivers items to the gateway.
///
/// Storage: JSON-encoded array persisted in the App Group's Documents directory.
/// Security: No sensitive tokens are stored in the queue file — only content
///   to be sent (URLs, extracted text). Auth is handled by the main app's keychain.
///
/// App Group ID: ai.clawos.shared (must be registered in Capabilities).
@Observable
@MainActor
final class ShareIntakeQueue {

    // MARK: - Shared instance

    static let shared = ShareIntakeQueue()

    // MARK: - Observable state

    private(set) var items: [ShareIntakeItem] = []
    private(set) var isProcessing: Bool = false

    // MARK: - Private

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// App Group shared container URL. Falls back to Documents if group not configured.
    private var queueFileURL: URL {
        let groupId = "group.ai.clawos.shared"
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupId) {
            return container.appendingPathComponent("share_intake_queue.json")
        }
        // Fallback to app's Documents directory (main app only, extension won't see it)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("share_intake_queue.json")
    }

    // MARK: - Init

    private init() {
        loadFromDisk()
    }

    // MARK: - Enqueue

    /// Add a new item to the queue and persist immediately.
    func enqueue(_ item: ShareIntakeItem) {
        items.append(item)
        saveToDisk()
    }

    /// Enqueue multiple items atomically.
    func enqueue(contentsOf newItems: [ShareIntakeItem]) {
        items.append(contentsOf: newItems)
        saveToDisk()
    }

    // MARK: - Status updates

    func updateStatus(id: UUID, status: ShareIntakeItem.IntakeStatus) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].status = status
        saveToDisk()
    }

    func updateMetadata(id: UUID, metadata: ShareItemMetadata) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].extractedMetadata = metadata
        if items[idx].status == .extracting {
            items[idx].status = .ready
        }
        saveToDisk()
    }

    func markDelivered(id: UUID, intakeId: String? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].status = .delivered
        items[idx].intakeId = intakeId
        saveToDisk()
    }

    func markFailed(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].status = .failed
        saveToDisk()
    }

    // MARK: - Remove

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        saveToDisk()
    }

    func removeDelivered() {
        items.removeAll { $0.status == .delivered }
        saveToDisk()
    }

    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }

    // MARK: - Query

    var pendingItems: [ShareIntakeItem] {
        items.filter { $0.status == .pending || $0.status == .ready }
    }

    var failedItems: [ShareIntakeItem] {
        items.filter { $0.status == .failed }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try encoder.encode(items)
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtection)
            #endif
            try data.write(to: queueFileURL, options: options)
        } catch {
            // Non-fatal — queue still works in-memory
            #if DEBUG
            print("[ShareIntakeQueue] Save failed: \(error)")
            #endif
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: queueFileURL),
              let decoded = try? decoder.decode([ShareIntakeItem].self, from: data) else {
            return
        }
        // On load, reset any items stuck in .sending → .ready so they can retry
        items = decoded.map { item in
            var mutable = item
            if mutable.status == .sending { mutable.status = .ready }
            return mutable
        }
    }

    /// Reload from disk (called when main app becomes active after extension use).
    func reloadFromDisk() {
        loadFromDisk()
    }
}

// NOTE: ShareIntakeProcessor is defined in ShareIntakeProcessor.swift.
// It is a separate file so the share extension can compile ShareIntakeQueue
// without pulling in GatewayClient or SessionStore.
