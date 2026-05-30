import Foundation

/// Tracks in-flight requests by ID, vending async continuations for each.
/// Thread-safe via actor isolation.
actor RequestRouter {
    // MARK: - Types

    typealias Continuation = CheckedContinuation<[String: JSONValue], Error>

    private struct PendingRequest {
        let continuation: Continuation
        var timeoutTask: Task<Void, Never>?
    }

    // MARK: - State

    private var pending: [String: PendingRequest] = [:]
    private let defaultTimeout: TimeInterval = 30

    // MARK: - Public interface

    /// Registers an in-flight request and returns the response payload.
    /// Pending continuations are always resumed: response, timeout, cancellation,
    /// or disconnect/fail-all cleanup.
    func register(id: String, timeout: TimeInterval? = nil) async throws -> [String: JSONValue] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutSeconds = timeout ?? defaultTimeout
                let timeoutTask = Task { [weak self] in
                    guard timeoutSeconds > 0 else { return }
                    let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    guard !Task.isCancelled else { return }
                    await self?.reject(id: id, error: GatewayClientError.requestTimeout(id))
                }
                pending[id] = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)
            }
        } onCancel: {
            Task { await self.reject(id: id, error: CancellationError()) }
        }
    }

    /// Fulfills a pending request with a successful payload.
    func resolve(id: String, payload: [String: JSONValue]) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask?.cancel()
        request.continuation.resume(returning: payload)
    }

    /// Rejects a pending request with an error.
    func reject(id: String, error: Error) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask?.cancel()
        request.continuation.resume(throwing: error)
    }

    /// Cancels all pending requests with a given error (e.g., on disconnect).
    func cancelAll(with error: Error) {
        let all = pending
        pending.removeAll()
        for (_, request) in all {
            request.timeoutTask?.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    /// Returns true if there is a pending request with the given ID.
    func hasPending(id: String) -> Bool {
        return pending[id] != nil
    }

    /// Number of in-flight requests.
    var count: Int { pending.count }
}
