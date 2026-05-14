import Foundation

/// Implements exponential backoff with jitter for WebSocket reconnection.
actor ReconnectManager {
    // MARK: - Configuration

    struct Config {
        var initialDelay: TimeInterval = 1.0
        var maxDelay: TimeInterval = 60.0
        var multiplier: Double = 2.0
        /// Jitter fraction: 0.0 = no jitter, 0.3 = ±30% random jitter
        var jitterFraction: Double = 0.25
        var maxAttempts: Int? = nil // nil = unlimited
    }

    // MARK: - State

    private let config: Config
    private var attemptCount: Int = 0
    private var isStopped: Bool = false

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public interface

    /// Returns the delay for the current attempt, applying exponential backoff and jitter.
    func nextDelay() -> TimeInterval? {
        guard !isStopped else { return nil }
        if let max = config.maxAttempts, attemptCount >= max { return nil }

        let base = min(
            config.initialDelay * pow(config.multiplier, Double(attemptCount)),
            config.maxDelay
        )
        let jitter = base * config.jitterFraction * Double.random(in: -1.0...1.0)
        let delay = max(0, base + jitter)

        attemptCount += 1
        return delay
    }

    /// Resets the attempt counter after a successful connection.
    func reset() {
        attemptCount = 0
        isStopped = false
    }

    /// Permanently stops reconnection (e.g., user explicitly disconnected).
    func stop() {
        isStopped = true
    }

    /// Current attempt number (0-based).
    var currentAttempt: Int { attemptCount }

    /// Whether reconnection is stopped.
    var stopped: Bool { isStopped }
}

// MARK: - Async wait helper

extension ReconnectManager {
    /// Waits for the next backoff interval and returns true if reconnect should proceed,
    /// or false if the manager is stopped or max attempts reached.
    func waitAndShouldReconnect() async -> Bool {
        guard let delay = nextDelay() else { return false }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return !isStopped
    }
}
