import Foundation

// MARK: - Frame type discriminator

enum FrameType: String, Codable {
    case req
    case res
    case event
}

// MARK: - Outgoing request frame

struct RequestFrame: Encodable {
    let type: String = "req"
    let id: String
    let method: String
    let params: AnyEncodable

    enum CodingKeys: String, CodingKey {
        case type, id, method, params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
    }
}

// MARK: - Incoming response frame

struct ResponseFrame: Decodable {
    let type: String
    let id: String
    let ok: Bool
    let payload: JSONValue?
    let error: GatewayError?
}

// MARK: - Incoming event frame

struct EventFrame: Decodable {
    let type: String
    let event: String
    let payload: JSONValue?
    let seq: Int?
    let stateVersion: Int?
}

// MARK: - GatewayEvent (public-facing event type)

struct GatewayEvent {
    let name: String
    let payload: [String: JSONValue]
    let seq: Int?
    let stateVersion: Int?
}

// MARK: - Connect challenge payload

struct ConnectChallengePayload: Decodable {
    let nonce: String
    let ts: Int
}

// MARK: - Hello-ok payload

struct HelloOkPayload: Decodable {
    let auth: HelloAuthPayload
    let policy: HelloPolicyPayload?
    let snapshot: JSONValue?

    var role: String { auth.role }
    var deviceToken: String? { auth.deviceToken }
}

struct HelloAuthPayload: Decodable {
    let role: String
    let scopes: [String]
    let deviceToken: String?
}

struct HelloPolicyPayload: Decodable {
    let tickIntervalMs: Int?
    let maxPayload: Int?
}

// MARK: - GatewayError

struct GatewayError: Decodable, LocalizedError {
    let code: String
    let message: String
    let details: GatewayErrorDetails?

    init(code: String, message: String, details: GatewayErrorDetails?) {
        self.code = code
        self.message = message
        self.details = details
    }

    enum CodingKeys: String, CodingKey { case code, message, details }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(String.self, forKey: .code)
        self.message = try container.decode(String.self, forKey: .message)
        // Lenient by design: a present-but-wrong-typed `details` (string/number/array from
        // a buggy or hostile gateway) degrades to nil instead of throwing typeMismatch, which
        // would otherwise abort decoding the whole error — and with it the connect handshake,
        // masking the pairing signal. Absent/null/object-with-missing-fields all yield nil too.
        self.details = (try? container.decodeIfPresent(GatewayErrorDetails.self, forKey: .details)) ?? nil
    }

    var errorDescription: String? { "\(code): \(message)" }

    /// True when the gateway is rejecting the connect handshake because this device has
    /// not yet been approved by an operator (`openclaw devices approve <id>`).
    ///
    /// The gateway carries this as the structured `PAIRING_REQUIRED` reason — exposed as
    /// the top-level `code` and/or a nested `details.code` — and always includes the phrase
    /// "pairing required" in the human message (the OpenClaw first-party client matches the
    /// same phrase). We accept any of the three so a wording change on either side can't
    /// silently turn "waiting for approval" into a hard failure, or vice versa.
    var indicatesPairingRequired: Bool {
        let pairingCode = "PAIRING_REQUIRED"
        if code.caseInsensitiveCompare(pairingCode) == .orderedSame { return true }
        if let detailCode = details?.code, detailCode.caseInsensitiveCompare(pairingCode) == .orderedSame { return true }
        let lower = message.lowercased()
        return lower.contains("pairing required")
            || lower.contains("not approved")
            || lower.contains("pending approval")
    }
}

/// Optional structured detail object attached to a `GatewayError` (e.g. the connect
/// handshake's `PAIRING_REQUIRED` reason). Decodes leniently: any field may be absent.
struct GatewayErrorDetails: Decodable {
    let code: String?
    let reason: String?
}

// MARK: - Connect request params

struct ConnectParams: Encodable {
    let minProtocol: Int
    let maxProtocol: Int
    let client: ClientInfo
    let role: String
    let scopes: [String]
    let caps: [String]
    let commands: [String]
    let permissions: [String: String]
    let auth: AuthInfo
    let locale: String
    let userAgent: String
    let device: DeviceInfo
}

struct ClientInfo: Encodable {
    let id: String
    let version: String
    let platform: String
    let mode: String
}

struct AuthInfo: Encodable {
    let token: String
}

struct DeviceInfo: Encodable {
    let id: String
    let publicKey: String
    let signature: String
    let signedAt: Int
    let nonce: String
}

// MARK: - Discriminated frame for decoding

struct FrameEnvelope: Decodable {
    let type: String
    let id: String?
    let method: String?
    let event: String?
}

// MARK: - JSONValue: recursive JSON type

indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else if let arrayVal = try? container.decode([JSONValue].self) {
            self = .array(arrayVal)
        } else if let objectVal = try? container.decode([String: JSONValue].self) {
            self = .object(objectVal)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        case .object(let v):
            try container.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

// MARK: - AnyEncodable type-eraser

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
