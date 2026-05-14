import Foundation

// MARK: - Pairing state

enum PairingState: Equatable {
    case idle
    case connecting
    case waitingForApproval(deviceID: String)
    case approved(deviceToken: String)
    case failed(String)
}

// MARK: - PairingCoordinator

/// Orchestrates the initial device pairing flow:
/// 1. Connect to gateway
/// 2. If pending approval, poll by reconnecting every 3 seconds
/// 3. When approved, persist token and report success
@Observable
final class PairingCoordinator {

    // MARK: - Observable state
    private(set) var state: PairingState = .idle
    private(set) var deviceID: String = ""
    private(set) var attemptCount: Int = 0

    // MARK: - Private
    private var pollingTask: Task<Void, Never>?
    private let config: GatewayConfig
    private let pollInterval: TimeInterval

    // MARK: - Init

    init(config: GatewayConfig, pollInterval: TimeInterval = 3.0) {
        self.config = config
        self.pollInterval = pollInterval
    }

    // MARK: - Start pairing

    func startPairing() {
        pollingTask?.cancel()
        state = .connecting
        attemptCount = 0

        pollingTask = Task { [weak self] in
            await self?.runPairingLoop()
        }
    }

    // MARK: - Cancel

    func cancel() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .idle
    }

    // MARK: - Private: pairing loop

    private func runPairingLoop() async {
        // Resolve device ID once upfront for display
        if let id = try? await DeviceIdentity.shared.deviceID() {
            await MainActor.run { self.deviceID = id }
        }

        while !Task.isCancelled {
            await MainActor.run { self.state = .connecting }

            let client = GatewayClient(config: config)
            do {
                let result = try await client.connect()
                switch result {
                case .connected(let hello):
                    let token = hello.deviceToken ?? ""
                    await MainActor.run { self.state = .approved(deviceToken: token) }
                    await client.disconnect()
                    return

                case .pendingApproval(let devID):
                    await MainActor.run {
                        self.state = .waitingForApproval(deviceID: devID)
                        self.attemptCount += 1
                    }
                    await client.disconnect()
                    // Wait before polling again
                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                    self.attemptCount += 1
                }
                // Brief wait before retry on error
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }
}
