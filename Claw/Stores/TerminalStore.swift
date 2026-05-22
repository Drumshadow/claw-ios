import Foundation

// MARK: - TerminalStore
//
// Manages a single live terminal session — subscribes to the gateway event stream,
// feeds output into the ring-buffer, and exposes reconnect/control operations.
//
// Gateway contract (see GatewayMethods for RPC names):
//   Subscribe:  terminal.session.subscribe(sessionId)
//   Unsubscribe: terminal.session.unsubscribe(sessionId)
//   History:    terminal.session.history(sessionId, limit, offset) → [TerminalHistoryLinePayload]
//   Input:      terminal.session.input(sessionId, text)    — Take Control mode
//   Kill:       terminal.session.kill(sessionId)
//   Events:     terminal.output { sessionId, data, timestamp }
//               terminal.session.ended { sessionId, exitCode }
//               terminal.session.error { sessionId, message }

@Observable
@MainActor
final class TerminalStore {

    // MARK: - Public state

    let sessionId: String
    private(set) var buffer = TerminalLineBuffer()
    private(set) var isConnected: Bool = false
    private(set) var isSubscribed: Bool = false
    private(set) var isLoadingHistory: Bool = false
    private(set) var isReconnecting: Bool = false
    private(set) var errorMessage: String?
    private(set) var exitCode: Int?
    private(set) var hasEnded: Bool = false

    /// When true, new terminal output is buffered but not pushed to `buffer`.
    var isPaused: Bool = false

    /// When true, the user has taken control — input is forwarded to the terminal.
    var isTakeControlActive: Bool = false

    // MARK: - Private

    private let client: GatewayClient?
    private var pauseBuffer: [String] = []

    nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    nonisolated(unsafe) private var reconnectTask: Task<Void, Never>?

    private static let maxPauseBuffer = 1_000   // lines buffered while paused

    // MARK: - Init

    init(sessionId: String, client: GatewayClient? = nil) {
        self.sessionId = sessionId
        self.client = client

        if sessionId == "preview" {
            loadPreviewData()
        }
    }

    // MARK: - Connection lifecycle

    /// Subscribe to the gateway terminal stream and load any available history.
    func connect() async {
        guard let client else {
            // Preview / no-backend path
            isConnected = true
            return
        }
        isConnected = true
        isReconnecting = false
        errorMessage = nil

        do {
            _ = try await client.send(
                method: GatewayMethod.terminalSessionSubscribe,
                params: ["sessionId": sessionId]
            )
            isSubscribed = true
            startEventSubscription()
            await loadHistory()
        } catch {
            errorMessage = error.localizedDescription
            isConnected = false
        }
    }

    func disconnect() {
        isConnected = false
        isSubscribed = false
        eventTask?.cancel()
        eventTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    /// Unsubscribes from gateway and stops event streaming.
    func unsubscribe() async {
        eventTask?.cancel()
        eventTask = nil

        guard let client, isSubscribed else { return }
        try? await client.send(
            method: GatewayMethod.terminalSessionUnsubscribe,
            params: ["sessionId": sessionId]
        )
        isSubscribed = false
        isConnected = false
    }

    // MARK: - Reconnect

    /// Attempt to reconnect after a transient disconnect.
    func reconnect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        var attempt = 0
        let delays: [TimeInterval] = [2, 4, 8, 15, 30]
        isReconnecting = true

        while !Task.isCancelled {
            attempt += 1
            let delay = attempt <= delays.count ? delays[attempt - 1] : 60
            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else { break }
            await connect()
            if isConnected { break }
        }

        isReconnecting = false
        reconnectTask = nil
    }

    // MARK: - History (replay)

    /// Load historical output from the gateway (for ended sessions or catch-up).
    func loadHistory(limit: Int = 500, offset: Int = 0) async {
        guard let client else { return }
        isLoadingHistory = true

        do {
            let response = try await client.send(
                method: GatewayMethod.terminalSessionHistory,
                params: ["sessionId": sessionId, "limit": limit, "offset": offset] as [String: Any]
            )
            // Decode lines array from response
            if let linesVal = response["lines"],
               case .array(let arr) = linesVal {
                let payloads: [TerminalHistoryLinePayload] = arr.compactMap { item in
                    guard case .object(let dict) = item,
                          case .string(let data) = dict["data"],
                          case .double(let ts) = dict["timestamp"]
                    else { return nil }
                    return TerminalHistoryLinePayload(data: data, timestamp: ts)
                }
                let lines = payloads.map { $0.data }
                if !lines.isEmpty {
                    buffer.appendBatch(lines)
                }
            }
        } catch {
            // Non-fatal — history is best-effort
            print("TerminalStore: history load failed: \(error)")
        }
        isLoadingHistory = false
    }

    // MARK: - Input (Take Control mode)

    /// Forward keyboard input to the remote terminal.
    /// Only active when `isTakeControlActive == true`.
    func sendInput(_ text: String) async {
        guard isTakeControlActive, let client else { return }
        try? await client.send(
            method: GatewayMethod.terminalSessionInput,
            params: ["sessionId": sessionId, "text": text]
        )
    }

    /// Send a SIGINT (Ctrl-C) to the running process.
    func sendInterrupt() async {
        await sendInput("\u{03}")    // ETX / Ctrl-C
    }

    // MARK: - Kill

    func killSession() async {
        guard let client else { return }
        try? await client.send(
            method: GatewayMethod.terminalSessionKill,
            params: ["sessionId": sessionId]
        )
    }

    // MARK: - Buffer helpers

    /// Feed new raw terminal output directly (used by StreamRouter or tests).
    func receive(_ raw: String) {
        if isPaused {
            if pauseBuffer.count < Self.maxPauseBuffer {
                pauseBuffer.append(raw)
            }
            return
        }
        buffer.append(raw)
    }

    func receiveBatch(_ lines: [String]) {
        if isPaused {
            let toAdd = lines.prefix(Self.maxPauseBuffer - pauseBuffer.count)
            pauseBuffer.append(contentsOf: toAdd)
            return
        }
        buffer.appendBatch(lines)
    }

    /// Resume streaming — flushes the pause buffer into the visible buffer.
    func resume() {
        isPaused = false
        if !pauseBuffer.isEmpty {
            buffer.appendBatch(pauseBuffer)
            pauseBuffer.removeAll()
        }
    }

    func clear() {
        buffer.clear()
        pauseBuffer.removeAll()
    }

    // MARK: - Export

    /// Returns plain-text (ANSI stripped) log suitable for sharing.
    func exportLog() -> String {
        buffer.lines.map { line in
            let ts = ISO8601DateFormatter().string(from: line.timestamp)
            return "[\(ts)] \(line.plainText)"
        }.joined(separator: "\n")
    }

    // MARK: - Event subscription

    private func startEventSubscription() {
        eventTask?.cancel()
        eventTask = Task { [weak self, client] in
            guard let client else { return }
            for await event in await client.events() {
                guard let self, !Task.isCancelled else { break }
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {
        case GatewayEventName.terminalOutput:
            guard let sidVal = event.payload["sessionId"],
                  case .string(let sid) = sidVal,
                  sid == sessionId,
                  let dataVal = event.payload["data"],
                  case .string(let data) = dataVal
            else { return }
            // Split on newlines so each logical line becomes a TerminalLine
            let lines = data.components(separatedBy: "\n")
            receiveBatch(lines)

        case GatewayEventName.terminalSessionEnded:
            guard let sidVal = event.payload["sessionId"],
                  case .string(let sid) = sidVal,
                  sid == sessionId
            else { return }
            hasEnded = true
            isConnected = false
            if case .int(let code) = event.payload["exitCode"] {
                exitCode = code
            }

        case GatewayEventName.terminalSessionError:
            guard let sidVal = event.payload["sessionId"],
                  case .string(let sid) = sidVal,
                  sid == sessionId,
                  let msgVal = event.payload["message"],
                  case .string(let msg) = msgVal
            else { return }
            errorMessage = msg
            isConnected = false

        default:
            break
        }
    }

    // MARK: - Preview Data

    private func loadPreviewData() {
        isConnected = true
        buffer.appendBatch([
            "\u{1B}[1m\u{1B}[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u{1B}[0m",
            "\u{1B}[1m\u{1B}[35m🚀 OpenClaw Deployment Pipeline\u{1B}[0m",
            "\u{1B}[1m\u{1B}[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u{1B}[0m",
            "",
            "\u{1B}[2m[2026-05-22 14:23:01]\u{1B}[0m \u{1B}[32m✓\u{1B}[0m Starting deployment pipeline",
            "\u{1B}[2m[2026-05-22 14:23:02]\u{1B}[0m \u{1B}[36m→\u{1B}[0m Checking git status...",
            "\u{1B}[2m[2026-05-22 14:23:02]\u{1B}[0m   \u{1B}[2mBranch: main\u{1B}[0m",
            "\u{1B}[2m[2026-05-22 14:23:02]\u{1B}[0m   \u{1B}[2mCommit: e7ae6f4\u{1B}[0m",
            "\u{1B}[2m[2026-05-22 14:23:03]\u{1B}[0m \u{1B}[32m✓\u{1B}[0m Git status clean",
            "",
            "\u{1B}[2m[2026-05-22 14:23:04]\u{1B}[0m \u{1B}[36m→\u{1B}[0m Building Docker image...",
            "\u{1B}[2m[2026-05-22 14:23:05]\u{1B}[0m   \u{1B}[2mStep 1/8: FROM node:20-alpine\u{1B}[0m",
            "\u{1B}[2m[2026-05-22 14:23:06]\u{1B}[0m   \u{1B}[32m---> Using cache\u{1B}[0m",
            "\u{1B}[2m[2026-05-22 14:23:10]\u{1B}[0m   \u{1B}[33m⚠\u{1B}[0m  \u{1B}[33mCache miss on layer 3\u{1B}[0m",
            "\u{1B}[2m[2026-05-22 14:23:25]\u{1B}[0m   \u{1B}[32m✓\u{1B}[0m Installed 847 packages",
            "\u{1B}[2m[2026-05-22 14:23:45]\u{1B}[0m   \u{1B}[32m✓\u{1B}[0m Build completed successfully",
            "\u{1B}[2m[2026-05-22 14:23:48]\u{1B}[0m \u{1B}[32m✓\u{1B}[0m Image built: sha256:a7f9c3e...",
            "",
            "\u{1B}[2m[2026-05-22 14:23:49]\u{1B}[0m \u{1B}[36m→\u{1B}[0m Pushing to registry...",
            "\u{1B}[2m[2026-05-22 14:24:05]\u{1B}[0m \u{1B}[32m✓\u{1B}[0m Pushed claw-api:v1.2.3",
            "",
            "\u{1B}[2m[2026-05-22 14:24:06]\u{1B}[0m \u{1B}[36m→\u{1B}[0m Deploying to prod-us-west-2...",
            "\u{1B}[2m[2026-05-22 14:24:20]\u{1B}[0m   \u{1B}[32m✓\u{1B}[0m Pod 1/3 healthy (10.0.1.45)",
            "\u{1B}[2m[2026-05-22 14:24:25]\u{1B}[0m   \u{1B}[32m✓\u{1B}[0m Pod 2/3 healthy (10.0.1.46)",
            "\u{1B}[2m[2026-05-22 14:24:30]\u{1B}[0m   \u{1B}[31m✗\u{1B}[0m \u{1B}[31mPod 3/3 health check failed\u{1B}[0m",
            "\u{1B}[2m[2026-05-22 14:24:36]\u{1B}[0m   \u{1B}[33m⚠\u{1B}[0m  Pod 3/3 still initializing",
            "\u{1B}[2m[2026-05-22 14:24:41]\u{1B}[0m   \u{1B}[32m✓\u{1B}[0m Pod 3/3 healthy (10.0.1.47)",
            "",
            "\u{1B}[2m[2026-05-22 14:24:42]\u{1B}[0m \u{1B}[1m\u{1B}[32m✓ Deployment complete!\u{1B}[0m",
            "\u{1B}[2m[2026-05-22 14:24:42]\u{1B}[0m   \u{1B}[2mURL: https://api.openclaw.dev  Version: v1.2.3  Duration: 1m 41s\u{1B}[0m",
            "",
            "\u{1B}[1m\u{1B}[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u{1B}[0m",
        ])
    }

    static func preview() -> TerminalStore {
        TerminalStore(sessionId: "preview")
    }
}
