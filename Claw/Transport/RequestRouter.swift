import Foundation

/// Tracks in-flight requests by ID, vending async continuations for each.
/// Thread-safe via actor isolation.
actor RequestRouter {
    // MARK: - Types

    typealias Continuation = CheckedContinuation<[String: JSONValue], Error>

    // MARK: - State

    private var pending: [String: Continuation] = [:]

    // MARK: - Public interface

    /// Registers an in-flight request and returns the continuation.
    /// The caller should store the continuation and resume it when the response arrives.
    func register(id: String) async throws -> [String: JSONValue] {
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
        }
    }

    /// Fulfills a pending request with a successful payload.
    func resolve(id: String, payload: [String: JSONValue]) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: payload)
    }

    /// Rejects a pending request with an error.
    func reject(id: String, error: Error) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }

    /// Cancels all pending requests with a given error (e.g., on disconnect).
    func cancelAll(with error: Error) {
        let all = pending
        pending.removeAll()
        for (_, continuation) in all {
            continuation.resume(throwing: error)
        }
    }

    /// Returns true if there is a pending request with the given ID.
    func hasPending(id: String) -> Bool {
        return pending[id] != nil
    }

    /// Number of in-flight requests.
    var count: Int { pending.count }
}
