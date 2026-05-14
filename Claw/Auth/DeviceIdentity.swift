import Foundation
import CryptoKit

/// Manages the device's persistent Ed25519 signing identity.
/// On first launch, generates a Curve25519 key pair and stores it in the Keychain.
/// The device ID is the SHA-256 hash of the public key, hex-encoded.
actor DeviceIdentity {
    // MARK: - Keychain keys
    private static let privateKeyKeychainKey = "claw.device.privateKey"
    private static let deviceTokenKeychainKey = "claw.device.token"

    // MARK: - Shared instance
    static let shared = DeviceIdentity()

    // MARK: - Cached values
    private var _privateKey: Curve25519.Signing.PrivateKey?

    private init() {}

    // MARK: - Public interface

    /// Returns the private key, loading from Keychain or generating a new one.
    func privateKey() throws -> Curve25519.Signing.PrivateKey {
        if let cached = _privateKey { return cached }

        let key: Curve25519.Signing.PrivateKey
        do {
            let rawBytes = try KeychainStore.load(key: Self.privateKeyKeychainKey)
            key = try Curve25519.Signing.PrivateKey(rawRepresentation: rawBytes)
        } catch KeychainError.itemNotFound {
            let newKey = Curve25519.Signing.PrivateKey()
            let rawBytes = newKey.rawRepresentation
            try KeychainStore.save(key: Self.privateKeyKeychainKey, data: rawBytes)
            key = newKey
        }

        _privateKey = key
        return key
    }

    /// Returns the raw Ed25519 public key as base64url-encoded string (no padding).
    func publicKeyBase64Url() throws -> String {
        let key = try privateKey()
        return Self.base64UrlEncode(key.publicKey.rawRepresentation)
    }

    /// Returns the device ID: SHA-256 of the raw public key bytes, hex-encoded.
    func deviceID() throws -> String {
        let key = try privateKey()
        let pubKeyBytes = key.publicKey.rawRepresentation
        let digest = SHA256.hash(data: pubKeyBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Builds and signs the V3 device auth payload, returning a base64url-encoded signature.
    ///
    /// Payload: "v3|{deviceId}|{clientId}|{clientMode}|{role}|{scopes}|{signedAtMs}|{token}|{nonce}|{platform}|{deviceFamily}"
    func signV3(
        deviceID: String,
        clientID: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int,
        token: String,
        nonce: String,
        platform: String,
        deviceFamily: String = ""
    ) throws -> String {
        let key = try privateKey()
        let payload = [
            "v3",
            deviceID,
            clientID,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAtMs),
            token,
            nonce,
            platform.lowercased().trimmingCharacters(in: .whitespaces),
            deviceFamily.lowercased().trimmingCharacters(in: .whitespaces)
        ].joined(separator: "|")

        guard let messageData = payload.data(using: .utf8) else {
            throw DeviceIdentityError.encodingFailed
        }
        let signature = try key.signature(for: messageData)
        return Self.base64UrlEncode(signature)
    }

    // MARK: - Device token persistence

    func saveDeviceToken(_ token: String, forGatewayID gatewayID: String) throws {
        let key = "\(Self.deviceTokenKeychainKey).\(gatewayID)"
        guard let data = token.data(using: .utf8) else {
            throw DeviceIdentityError.encodingFailed
        }
        try KeychainStore.save(key: key, data: data)
    }

    func loadDeviceToken(forGatewayID gatewayID: String) -> String? {
        let key = "\(Self.deviceTokenKeychainKey).\(gatewayID)"
        guard let data = try? KeychainStore.load(key: key),
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    func clearDeviceToken(forGatewayID gatewayID: String) throws {
        let key = "\(Self.deviceTokenKeychainKey).\(gatewayID)"
        try KeychainStore.delete(key: key)
    }

    // MARK: - Base64url helpers

    static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64UrlEncode(_ bytes: some DataProtocol) -> String {
        base64UrlEncode(Data(bytes))
    }
}

// MARK: - Errors

enum DeviceIdentityError: Error, LocalizedError {
    case encodingFailed
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode data for signing"
        case .signingFailed: return "Signing operation failed"
        }
    }
}
