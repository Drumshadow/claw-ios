import Foundation

// MARK: - GatewayClient errors

enum GatewayClientError: Error, LocalizedError {
    case notConnected
    case handshakeFailed(String)
    case requestTimeout(String)
    case invalidURL
    case encodingError
    case decodingError(String)
    case serverError(GatewayError)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to gateway"
        case .handshakeFailed(let reason): return "Handshake failed: \(reason)"
        case .requestTimeout(let id): return "Request timed out: \(id)"
        case .invalidURL: return "Invalid gateway URL"
        case .encodingError: return "Failed to encode message"
        case .decodingError(let detail): return "Failed to decode message: \(detail)"
        case .serverError(let err): return "Gateway error: \(err.message)"
        case .disconnected: return "Connection lost"
        }
    }
}

// MARK: - Handshake outcome

enum HandshakeResult {
    case connected(HelloOkPayload)
    case pendingApproval(deviceID: String)
}

// MARK: - GatewayClient

/// Manages a single WebSocket connection to an OpenClaw gateway.
/// Handles the connect handshake, message routing, ping/pong, and event streaming.
actor GatewayClient {

    // MARK: - Dependencies

    private let config: GatewayConfig
    private let identity: DeviceIdentity
    private let router: RequestRouter = RequestRouter()

    // MARK: - WebSocket state

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isRunning: Bool = false
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    // MARK: - Event streaming

    private var eventContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]

    // MARK: - Handshake state

    private(set) var helloPayload: HelloOkPayload?
    private var pingInterval: TimeInterval = 15.0

    // MARK: - JSON codec

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()

    private let decoder: JSONDecoder = JSONDecoder()

    /// Maximum inbound message size (bytes). Messages larger than this are discarded
    /// rather than decoded, preventing a malicious or buggy gateway from triggering
    /// excessive memory allocation or JSON decoder crashes.
    private static let maxInboundMessageBytes = 10 * 1024 * 1024  // 10 MB

    // MARK: - Init

    init(config: GatewayConfig, identity: DeviceIdentity = .shared) {
        self.config = config
        self.identity = identity
    }

    // MARK: - Connect

    /// Establishes the WebSocket connection and performs the OpenClaw handshake.
    /// Returns `.connected(payload)` on success, `.pendingApproval(deviceID:)` if not yet approved.
    func connect() async throws -> HandshakeResult {
        guard let url = config.wsURL else {
            throw GatewayClientError.invalidURL
        }

        // Tear down any existing connection
        await disconnect(notify: false)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
        sessionConfig.timeoutIntervalForRequest = 30
        let urlSession = URLSession(configuration: sessionConfig)
        self.session = urlSession

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let task = urlSession.webSocketTask(with: request)
        self.webSocketTask = task
        self.isRunning = true
        task.resume()

        do {
            // Wait for connect.challenge
            let challenge = try await waitForChallenge()

            // Build and send connect request
            let result = try await sendConnectRequest(challenge: challenge)

            // Start the receive loop and keepalive
            startReceiveLoop()
            startPingLoop()

            return result
        } catch {
            await disconnect(notify: false)
            throw error
        }
    }

    // MARK: - Disconnect

    func disconnect(notify: Bool = true) async {
        isRunning = false
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil

        if notify {
            await router.cancelAll(with: GatewayClientError.disconnected)
            notifyEventContinuations(finish: true)
        } else {
            await router.cancelAll(with: GatewayClientError.disconnected)
        }
    }

    // MARK: - Send request

    /// Sends a typed request and awaits the response payload.
    func send<T: Encodable>(method: String, params: T) async throws -> [String: JSONValue] {
        let id = UUID().uuidString
        let frame = RequestFrame(id: id, method: method, params: AnyEncodable(params))
        let data = try encoder.encode(frame)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GatewayClientError.encodingError
        }

        guard let task = webSocketTask, isRunning else {
            throw GatewayClientError.notConnected
        }

        // Register the continuation BEFORE sending to avoid a race where the response
        // arrives before the continuation is stored. If sending itself fails, reject the
        // continuation immediately so the request cannot hang until the timeout.
        async let responseTask: [String: JSONValue] = router.register(id: id)
        do {
            try await task.send(.string(jsonString))
        } catch {
            await router.reject(id: id, error: error)
            _ = try? await responseTask
            throw error
        }
        return try await responseTask
    }

    // MARK: - Event stream

    /// Returns an AsyncStream of gateway events. The stream finishes when the connection drops.
    func events() -> AsyncStream<GatewayEvent> {
        let streamID = UUID()
        return AsyncStream { [weak self] continuation in
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeEventContinuation(id: streamID)
                }
            }
            Task { [weak self] in
                await self?.addEventContinuation(id: streamID, continuation: continuation)
            }
        }
    }

    // MARK: - Private: handshake

    private func waitForChallenge() async throws -> ConnectChallengePayload {
        guard let task = webSocketTask else { throw GatewayClientError.notConnected }

        // Gateway sends the challenge immediately after connection
        let message = try await task.receive()
        let data: Data
        switch message {
        case .string(let str):
            guard let d = str.data(using: .utf8) else { throw GatewayClientError.decodingError("UTF-8") }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            throw GatewayClientError.decodingError("unknown message type")
        }
        guard data.count <= Self.maxInboundMessageBytes else {
            throw GatewayClientError.decodingError("challenge message exceeds size limit")
        }

        let envelope = try decoder.decode(FrameEnvelope.self, from: data)
        guard envelope.type == "event", envelope.event == GatewayEventName.connectChallenge else {
            throw GatewayClientError.handshakeFailed("Expected connect.challenge, got \(envelope.type)/\(envelope.event ?? "nil")")
        }

        // Decode the full event to extract payload
        let eventFrame = try decoder.decode(EventFrame.self, from: data)
        guard let payloadValue = eventFrame.payload,
              case .object(let obj) = payloadValue,
              let nonceValue = obj["nonce"], case .string(let nonce) = nonceValue,
              let tsValue = obj["ts"]
        else {
            throw GatewayClientError.handshakeFailed("Malformed connect.challenge payload")
        }

        let ts: Int
        switch tsValue {
        case .int(let i): ts = i
        case .double(let d): ts = Int(d)
        default: throw GatewayClientError.handshakeFailed("ts is not a number")
        }

        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        guard abs(ts - nowMs) < 5 * 60 * 1000 else {
            throw GatewayClientError.handshakeFailed("Challenge timestamp out of range")
        }

        return ConnectChallengePayload(nonce: nonce, ts: ts)
    }

    private func sendConnectRequest(challenge: ConnectChallengePayload) async throws -> HandshakeResult {
        let deviceID = try await identity.deviceID()
        let pubKeyBase64Url = try await identity.publicKeyBase64Url()

        let gatewayID = config.id.uuidString
        let storedToken = await identity.loadDeviceToken(forGatewayID: gatewayID) ?? ""

        let scopes = ["operator.read", "operator.write"]
        let signature = try await identity.signV3(
            deviceID: deviceID,
            clientID: "openclaw-ios",
            clientMode: "ui",
            role: "operator",
            scopes: scopes,
            signedAtMs: challenge.ts,
            token: storedToken,
            nonce: challenge.nonce,
            platform: "ios"
        )

        let params = ConnectParams(
            minProtocol: 3,
            maxProtocol: 4,
            client: ClientInfo(
                id: "openclaw-ios",
                version: "1.0.0",
                platform: "ios",
                mode: "ui"
            ),
            role: "operator",
            scopes: scopes,
            caps: [],
            commands: [],
            permissions: [:],
            auth: AuthInfo(token: storedToken),
            locale: Locale.current.identifier,
            userAgent: "openclaw-ios/1.0.0",
            device: DeviceInfo(
                id: deviceID,
                publicKey: pubKeyBase64Url,
                signature: signature,
                signedAt: challenge.ts,
                nonce: challenge.nonce
            )
        )

        let id = UUID().uuidString
        let frame = RequestFrame(id: id, method: GatewayMethod.connect, params: AnyEncodable(params))
        let data = try encoder.encode(frame)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GatewayClientError.encodingError
        }

        guard let task = webSocketTask else { throw GatewayClientError.notConnected }
        try await task.send(.string(jsonString))

        // Wait for the response to the connect request
        let response = try await waitForConnectResponse(id: id)
        return try await processConnectResponse(response, deviceID: deviceID, gatewayID: gatewayID)
    }

    private func waitForConnectResponse(id: String) async throws -> ResponseFrame {
        guard let task = webSocketTask else { throw GatewayClientError.notConnected }

        // Loop until we receive a response frame matching our request ID
        while true {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .string(let str):
                guard let d = str.data(using: .utf8) else { throw GatewayClientError.decodingError("UTF-8") }
                data = d
            case .data(let d):
                data = d
            @unknown default:
                throw GatewayClientError.decodingError("unknown message type")
            }
            // Skip oversized messages rather than failing the handshake entirely;
            // a legitimate connect response will never be this large.
            guard data.count <= Self.maxInboundMessageBytes else { continue }

            let envelope = try decoder.decode(FrameEnvelope.self, from: data)
            if envelope.type == "res", let rid = envelope.id, rid == id {
                return try decoder.decode(ResponseFrame.self, from: data)
            }
            // Otherwise skip (could be an event), continue waiting
        }
    }

    private func processConnectResponse(
        _ response: ResponseFrame,
        deviceID: String,
        gatewayID: String
    ) async throws -> HandshakeResult {
        guard response.ok else {
            if let err = response.error {
                // An unapproved device is reported via the structured PAIRING_REQUIRED reason
                // (code/details/message). Treat only that as "keep polling for approval"; any
                // other error is a genuine handshake failure we must surface immediately.
                if err.indicatesPairingRequired {
                    return .pendingApproval(deviceID: deviceID)
                }
                throw GatewayClientError.serverError(err)
            }
            throw GatewayClientError.handshakeFailed("connect response ok=false")
        }

        guard let payloadValue = response.payload else {
            throw GatewayClientError.handshakeFailed("Missing payload in connect response")
        }

        // ok=true always means fully connected; ok=false with pairing error is handled above
        let payloadData = try encoder.encode(payloadValue)
        let hello = try decoder.decode(HelloOkPayload.self, from: payloadData)

        // Persist the device token if one was issued
        if let token = hello.deviceToken {
            try? await identity.saveDeviceToken(token, forGatewayID: gatewayID)
        }

        // Apply policy settings. Clamp the server-supplied tick interval to a
        // sane range so a malicious or buggy gateway can't drive us into a tight
        // ping loop (DoS / battery drain) or stall the keepalive entirely.
        if let policy = hello.policy, let interval = policy.tickIntervalMs {
            let clampedMs = min(max(interval, 1_000), 5 * 60 * 1_000)
            pingInterval = TimeInterval(clampedMs) / 1000.0
        }

        helloPayload = hello
        return .connected(hello)
    }

    // MARK: - Private: receive loop

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while isRunning {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let str):
                    guard let d = str.data(using: .utf8) else { continue }
                    data = d
                case .data(let d):
                    data = d
                @unknown default:
                    continue
                }
                // Discard messages that exceed the inbound size cap. A legitimate
                // gateway message should never be this large; an excessively large
                // message is most likely a protocol error or a gateway-side bug.
                guard data.count <= Self.maxInboundMessageBytes else { continue }
                await handleRawMessage(data: data)
            } catch {
                if isRunning {
                    isRunning = false
                    await router.cancelAll(with: GatewayClientError.disconnected)
                    notifyEventContinuations(finish: true)
                }
                return
            }
        }
    }

    private func handleRawMessage(data: Data) async {
        guard let envelope = try? decoder.decode(FrameEnvelope.self, from: data) else { return }

        switch envelope.type {
        case "res":
            guard let id = envelope.id,
                  let response = try? decoder.decode(ResponseFrame.self, from: data) else { return }
            if response.ok {
                let payload: [String: JSONValue]
                if let p = response.payload, case .object(let obj) = p {
                    payload = obj
                } else {
                    payload = [:]
                }
                await router.resolve(id: id, payload: payload)
            } else {
                let error = response.error ?? GatewayError(code: "unknown", message: "Unknown error", details: nil)
                await router.reject(id: id, error: GatewayClientError.serverError(error))
            }

        case "event":
            guard let eventName = envelope.event,
                  let eventFrame = try? decoder.decode(EventFrame.self, from: data) else { return }

            // Handle pong specially
            if eventName == GatewayMethod.pong { return }

            let payload: [String: JSONValue]
            if let p = eventFrame.payload, case .object(let obj) = p {
                payload = obj
            } else {
                payload = [:]
            }

            let event = GatewayEvent(
                name: eventName,
                payload: payload,
                seq: eventFrame.seq,
                stateVersion: eventFrame.stateVersion
            )
            broadcastEvent(event)

        default:
            break
        }
    }

    // MARK: - Private: ping/pong

    private func startPingLoop() {
        let interval = pingInterval
        pingTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self = self else { return }
                let running = await self.isRunning
                if !running { return }
                await self.sendPing()
            }
        }
    }

    private func sendPing() async {
        let pingFrame: [String: String] = ["type": "req", "id": UUID().uuidString, "method": "ping"]
        guard let data = try? encoder.encode(pingFrame),
              let str = String(data: data, encoding: .utf8),
              let task = webSocketTask else { return }
        try? await task.send(.string(str))
    }

    // MARK: - Private: event broadcasting

    private func addEventContinuation(id: UUID, continuation: AsyncStream<GatewayEvent>.Continuation) {
        eventContinuations[id] = continuation
    }

    private func removeEventContinuation(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func broadcastEvent(_ event: GatewayEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func notifyEventContinuations(finish: Bool) {
        if finish {
            for continuation in eventContinuations.values {
                continuation.finish()
            }
            eventContinuations.removeAll()
        }
    }
}
