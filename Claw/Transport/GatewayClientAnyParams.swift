import Foundation

// MARK: - GatewayClient [String: Any] convenience overload
//
// Allows callers to pass arbitrary [String: Any] dictionaries as RPC params
// without having to define a dedicated Codable struct for every call site.
// Used by RunbookStore and TerminalStore for multi-type parameter dictionaries.

extension GatewayClient {
    @discardableResult
    func send(method: String, params: [String: Any]) async throws -> [String: JSONValue] {
        try await send(method: method, params: AnyParamsWrapper(params))
    }
}

// MARK: - AnyParamsWrapper

private struct AnyParamsWrapper: Encodable {
    let dict: [String: Any]

    init(_ dict: [String: Any]) { self.dict = dict }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawCodingKey.self)
        for (key, value) in dict {
            let k = RawCodingKey(key)
            try container.encode(AnyEncodableValue(value), forKey: k)
        }
    }
}

private struct RawCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private struct AnyEncodableValue: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String:  try container.encode(s)
        case let n as Int:     try container.encode(n)
        case let n as Double:  try container.encode(n)
        case let n as Float:   try container.encode(Double(n))
        case let b as Bool:    try container.encode(b)
        case let arr as [Any]:
            var uc = encoder.unkeyedContainer()
            for item in arr { try uc.encode(AnyEncodableValue(item)) }
        case let dict as [String: Any]:
            var kc = encoder.container(keyedBy: RawCodingKey.self)
            for (k, v) in dict {
                try kc.encode(AnyEncodableValue(v), forKey: RawCodingKey(k))
            }
        default:
            try container.encodeNil()
        }
    }
}
