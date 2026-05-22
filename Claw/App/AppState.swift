import Foundation
import SwiftUI

// MARK: - AppState

@Observable
final class AppState {

    // MARK: - Connection state

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var activeClient: GatewayClient?
    private(set) var helloPayload: HelloOkPayload?

    // NOTE: Session/Node/Skills/Cron/Memory stores are owned by ConnectedView's
    // local @State and injected into the environment from there. Duplicating
    // them on AppState would mean two @Observable copies per store, each
    // running its own gateway event subscription on every connect.

    // MARK: - Phone context handler (created when connected, torn down on disconnect)

    private(set) var phoneContextHandler: PhoneContextHandler?

    // MARK: - Config

    var selectedConfig: GatewayConfig? {
        didSet { persistConfig() }
    }

    // MARK: - Reconnect

    private let reconnectManager = ReconnectManager()
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Persistence key

    private static let configDefaultsKey = "ai.clawos.selectedGatewayConfig"

    // MARK: - Init

    init() {
        loadPersistedConfig()
    }

    // MARK: - Connect

    @MainActor
    func connect(to config: GatewayConfig) async {
        selectedConfig = config
        connectionState = .connecting

        // Cancel any in-progress reconnect attempt
        reconnectTask?.cancel()
        reconnectTask = nil

        let client = GatewayClient(config: config)
        activeClient = client

        do {
            let result = try await client.connect()
            switch result {
            case .connected(let hello):
                helloPayload = hello
                connectionState = .connected
                await reconnectManager.reset()
                setupPhoneContext(client: client)
                startDisconnectWatcher(client: client, config: config)

            case .pendingApproval(let deviceID):
                connectionState = .pairing(deviceID: deviceID)
            }
        } catch {
            #if DEBUG
            connectionState = .failed(error.localizedDescription)
            #else
            connectionState = .failed("Could not connect to gateway.")
            #endif
            activeClient = nil
        }
    }

    // MARK: - Disconnect

    @MainActor
    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        await reconnectManager.stop()

        await activeClient?.disconnect()
        activeClient = nil
        helloPayload = nil
        phoneContextHandler?.stop()
        phoneContextHandler = nil
        connectionState = .disconnected
    }

    // MARK: - Update connection state (called from PairingCoordinator)

    @MainActor
    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    @MainActor
    func setActiveClient(_ client: GatewayClient?) {
        activeClient = client
    }

    // MARK: - Private: phone context lifecycle

    @MainActor
    private func setupPhoneContext(client: GatewayClient) {
        let phoneCtx = PhoneContextHandler(client: client)
        phoneContextHandler = phoneCtx
        phoneCtx.start()
    }

    // MARK: - Private: disconnect watcher + reconnect

    /// Watches the gateway event stream for termination (EOF = disconnect)
    /// and kicks off the reconnect loop automatically.
    @MainActor
    private func startDisconnectWatcher(client: GatewayClient, config: GatewayConfig) {
        reconnectTask = Task { [weak self] in
            // Drain the event stream; when it ends the connection has dropped.
            for await _ in await client.events() { }

            // Connection ended — update state and attempt reconnect.
            guard let self else { return }
            await MainActor.run {
                guard self.connectionState == .connected else { return }
                self.connectionState = .reconnecting
                self.phoneContextHandler?.stop()
                self.phoneContextHandler = nil
            }

            await self.runReconnectLoop(config: config)
        }
    }

    private func runReconnectLoop(config: GatewayConfig) async {
        while await reconnectManager.waitAndShouldReconnect() {
            guard !Task.isCancelled else { return }

            let client = GatewayClient(config: config)

            do {
                let result = try await client.connect()
                switch result {
                case .connected(let hello):
                    await MainActor.run {
                        self.helloPayload = hello
                        self.activeClient = client
                        self.connectionState = .connected
                        self.setupPhoneContext(client: client)
                    }
                    await reconnectManager.reset()
                    await startDisconnectWatcher(client: client, config: config)
                    return

                case .pendingApproval(let deviceID):
                    // Device needs re-pairing; surface that to the user.
                    await MainActor.run {
                        self.connectionState = .pairing(deviceID: deviceID)
                    }
                    return
                }
            } catch {
                // Failed attempt — reconnectManager.waitAndShouldReconnect() will
                // apply the next backoff delay on the next iteration.
                if Task.isCancelled { return }
                await MainActor.run {
                    // Stay in .reconnecting so the banner keeps showing
                    if self.connectionState != .reconnecting {
                        self.connectionState = .reconnecting
                    }
                }
            }
        }

        // Exhausted reconnect attempts
        await MainActor.run {
            self.connectionState = .failed("Could not reconnect to gateway.")
        }
    }

    // MARK: - Persistence

    private func persistConfig() {
        guard let config = selectedConfig else {
            UserDefaults.standard.removeObject(forKey: Self.configDefaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configDefaultsKey)
        }
    }

    private func loadPersistedConfig() {
        guard let data = UserDefaults.standard.data(forKey: Self.configDefaultsKey),
              let config = try? JSONDecoder().decode(GatewayConfig.self, from: data) else {
            return
        }
        selectedConfig = config
    }
}
