import Foundation

// MARK: - RollbackStatus

enum RollbackStatus: String, Codable, CaseIterable {
    case pending     // Snapshot queued, pre-state not yet captured
    case captured    // Pre-state captured; ready to execute
    case executed    // Tool executed; rollback available
    case rolledBack  // Rollback successfully applied
    case expired     // TTL elapsed, rollback no longer available
    case failed      // Snapshot or rollback failed

    var displayLabel: String {
        switch self {
        case .pending:    return "Pending"
        case .captured:   return "Ready"
        case .executed:   return "Executed"
        case .rolledBack: return "Rolled Back"
        case .expired:    return "Expired"
        case .failed:     return "Failed"
        }
    }

    var canRollback: Bool { self == .executed }
    var isTerminal: Bool  { self == .rolledBack || self == .expired || self == .failed }
}

// MARK: - RollbackSnapshot

/// Captures a pre-execution checkpoint for a tool invocation so the
/// operator can revert side effects if needed.
///
/// NOTE: The actual pre-state data (DB rows, file contents, config values)
/// is stored server-side and referenced by `serverSnapshotRef`.
/// This model is the client-side record for display + lifecycle tracking.
struct RollbackSnapshot: Identifiable, Codable {
    var id: UUID = UUID()

    // Linkage to approval lifecycle
    let approvalId: String
    let sessionKey: String

    // Tool that was / will be executed
    let toolName: String
    let toolInputSummary: String     // Human-readable summary of key params
    let environment: String

    // Server reference
    var serverSnapshotRef: String?   // Opaque ID returned by backend on capture

    // Lifecycle
    var status: RollbackStatus
    let createdAt: Date
    var capturedAt: Date?
    var executedAt: Date?
    var rolledBackAt: Date?
    var expiresAt: Date?

    // Display context
    var resourcesAffected: [String]  // e.g. ["Table: users", "Index: users_email_idx"]
    var estimatedImpact: String?     // Free-text impact summary
    var rollbackNotes: String?       // Notes about rollback procedure

    /// Seconds until this snapshot expires (nil if no expiry set)
    var secondsUntilExpiry: Int? {
        guard let exp = expiresAt else { return nil }
        let delta = Int(exp.timeIntervalSince(Date()))
        return delta > 0 ? delta : 0
    }

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }
}

// MARK: - RollbackSnapshotStore

@Observable
@MainActor
final class RollbackSnapshotStore {

    static let shared = RollbackSnapshotStore()

    private(set) var snapshots: [RollbackSnapshot] = []
    private(set) var isRollingBack: Set<UUID> = []

    private static let userDefaultsKey = "ai.clawos.rollbackSnapshots"
    private static let maxRetainedSnapshots = 50

    private init() {
        snapshots = loadSnapshots()
        purgeExpired()
    }

    // MARK: - Lifecycle

    /// Register a new snapshot when approval is received (status: .pending)
    func register(
        approvalId: String,
        sessionKey: String,
        toolName: String,
        toolInputSummary: String,
        environment: String,
        ttlSeconds: Int? = 3600
    ) -> RollbackSnapshot {
        let snapshot = RollbackSnapshot(
            approvalId: approvalId,
            sessionKey: sessionKey,
            toolName: toolName,
            toolInputSummary: toolInputSummary,
            environment: environment,
            serverSnapshotRef: nil,
            status: .pending,
            createdAt: Date(),
            capturedAt: nil,
            executedAt: nil,
            rolledBackAt: nil,
            expiresAt: ttlSeconds.map { Date().addingTimeInterval(TimeInterval($0)) },
            resourcesAffected: [],
            estimatedImpact: nil,
            rollbackNotes: nil
        )
        snapshots.insert(snapshot, at: 0)
        trimIfNeeded()
        saveSnapshots()
        return snapshot
    }

    func markCaptured(_ id: UUID, serverRef: String, resources: [String], impact: String?) {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[idx].status = .captured
        snapshots[idx].capturedAt = Date()
        snapshots[idx].serverSnapshotRef = serverRef
        snapshots[idx].resourcesAffected = resources
        snapshots[idx].estimatedImpact = impact
        saveSnapshots()
    }

    func markExecuted(_ approvalId: String) {
        guard let idx = snapshots.firstIndex(where: { $0.approvalId == approvalId }) else { return }
        snapshots[idx].status = .executed
        snapshots[idx].executedAt = Date()
        saveSnapshots()
    }

    func markRolledBack(_ id: UUID, notes: String? = nil) {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[idx].status = .rolledBack
        snapshots[idx].rolledBackAt = Date()
        snapshots[idx].rollbackNotes = notes
        isRollingBack.remove(id)
        saveSnapshots()
    }

    func markFailed(_ id: UUID) {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[idx].status = .failed
        isRollingBack.remove(id)
        saveSnapshots()
    }

    // MARK: - Rollback request (sends to gateway)

    func requestRollback(_ snapshot: RollbackSnapshot, client: GatewayClient) {
        guard snapshot.canRollback, let ref = snapshot.serverSnapshotRef else { return }
        isRollingBack.insert(snapshot.id)

        Task {
            struct RollbackParams: Encodable {
                let snapshotRef: String
                let approvalId: String
            }
            let params = RollbackParams(snapshotRef: ref, approvalId: snapshot.approvalId)
            // Gateway method: tools.rollback
            // Expected response: { success: Bool, notes: String? }
            _ = try? await client.send(method: GatewayMethod.toolsRollback, params: params)
            await MainActor.run {
                self.markRolledBack(snapshot.id)
            }
        }
    }

    // MARK: - Queries

    var activeSnapshots: [RollbackSnapshot] {
        snapshots.filter { !$0.isTerminal && !$0.isExpired }
    }

    var rollbackableSnapshots: [RollbackSnapshot] {
        snapshots.filter { $0.status == .executed && !$0.isExpired }
    }

    // MARK: - Private

    private func purgeExpired() {
        let now = Date()
        snapshots = snapshots.filter { snapshot in
            guard let exp = snapshot.expiresAt else { return true }
            if now > exp && snapshot.status == .executed {
                // Mark as expired in-place rather than removing so audit trail is preserved
                var updated = snapshot
                updated.status = .expired
                return true
            }
            return true // Keep all for history; just update status
        }
        // Actually update statuses
        for idx in snapshots.indices {
            if let exp = snapshots[idx].expiresAt, Date() > exp, snapshots[idx].status == .executed {
                snapshots[idx].status = .expired
            }
        }
    }

    private func trimIfNeeded() {
        if snapshots.count > Self.maxRetainedSnapshots {
            // Remove oldest terminal snapshots first
            let terminalIndices = snapshots.indices.filter { snapshots[$0].status.isTerminal }
            let toRemove = max(0, snapshots.count - Self.maxRetainedSnapshots)
            if toRemove > 0 && !terminalIndices.isEmpty {
                snapshots.remove(atOffsets: IndexSet(terminalIndices.suffix(toRemove)))
            }
        }
    }

    private func loadSnapshots() -> [RollbackSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([RollbackSnapshot].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveSnapshots() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
