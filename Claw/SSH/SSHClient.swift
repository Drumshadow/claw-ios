import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH
import Security

// MARK: - Host key validation

private final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let keychainKey: String

    init(host: String, port: Int) {
        let normalizedHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.keychainKey = "ssh_host_key_fingerprint_\(normalizedHost)_\(port)"
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = Self.fingerprint(for: hostKey)
        if let storedData = try? KeychainStore.load(key: keychainKey),
           let stored = String(data: storedData, encoding: .utf8) {
            if stored == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(SSHClient.SSHError.hostKeyMismatch)
            }
            return
        }

        do {
            try KeychainStore.save(key: keychainKey, data: Data(fingerprint.utf8))
            validationCompletePromise.succeed(())
        } catch {
            validationCompletePromise.fail(error)
        }
    }

    private static func fingerprint(for hostKey: NIOSSHPublicKey) -> String {
        // NIOSSH exposes parsing and equality publicly but not a stable public encoder
        // for the wire-format key bytes. Hash the reflected key representation as a
        // compile-safe TOFU pin; replace with raw wire bytes if/when Citadel/NIOSSH
        // exposes a public encoder in the app's pinned dependency version.
        let digest = SHA256.hash(data: Data(String(reflecting: hostKey).utf8))
        return Data(digest).base64EncodedString()
    }
}

// MARK: - SSHClient

/// A lightweight namespace for fire-and-forget SSH command execution via Citadel.
/// Each call opens a fresh TCP connection, runs the command, and closes.
enum SSHClient {

    enum SSHError: LocalizedError {
        case unsupportedKeyType(String)
        case keyParseFailure(String)
        case connectionFailed(String)
        case commandFailed(String)
        case hostKeyMismatch

        var errorDescription: String? {
            switch self {
            case .unsupportedKeyType(let t):
                return "The private key type '\(t)' is not supported. Use Ed25519, P-256, P-384, or P-521 keys."
            case .keyParseFailure(let msg):
                return "Failed to parse private key: \(msg)"
            case .connectionFailed(let msg):
                return "SSH connection failed: \(msg)"
            case .commandFailed(let msg):
                return "SSH command failed: \(msg)"
            case .hostKeyMismatch:
                return "SSH host key changed. Refusing to connect because this may indicate a man-in-the-middle attack."
            }
        }
    }

    /// Execute a single command over SSH and return stdout as a String.
    /// Supports Ed25519, P-256, P-384, and P-521 OpenSSH private keys.
    static func executeCommand(
        _ command: String,
        host: String,
        port: Int = 22,
        username: String,
        privateKeyPEM: String
    ) async throws -> String {

        let authMethod: SSHAuthenticationMethod
        do {
            authMethod = try buildAuthMethod(username: username, privateKeyPEM: privateKeyPEM)
        } catch let e as SSHError {
            throw e
        } catch {
            throw SSHError.keyParseFailure(error.localizedDescription)
        }

        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { authMethod },
            hostKeyValidator: .custom(TOFUHostKeyValidator(host: host, port: port))
        )

        let client: Citadel.SSHClient
        do {
            client = try await Citadel.SSHClient.connect(to: settings)
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }

        defer {
            Task { try? await client.close() }
        }

        let outputBuffer: ByteBuffer
        do {
            outputBuffer = try await client.executeCommand(command)
        } catch {
            throw SSHError.commandFailed(error.localizedDescription)
        }

        return String(buffer: outputBuffer)
    }

    // MARK: - Key parsing

    private static func buildAuthMethod(username: String, privateKeyPEM: String) throws -> SSHAuthenticationMethod {
        let trimmed = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)

        // AWS console downloads RSA keys in PKCS#1 PEM format
        if trimmed.hasPrefix("-----BEGIN RSA PRIVATE KEY-----") {
            return try buildRSASecKeyAuthMethod(username: username, pem: trimmed)
        }

        guard trimmed.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") else {
            throw SSHError.keyParseFailure(
                "Unrecognised key format. Supported: OpenSSH (-----BEGIN OPENSSH PRIVATE KEY-----) " +
                "and RSA PKCS#1 (-----BEGIN RSA PRIVATE KEY-----)."
            )
        }

        let keyTypeStr = try readOpenSSHKeyType(from: trimmed)

        switch keyTypeStr {
        case "ssh-ed25519":
            let privateKey = try parseEd25519Key(from: trimmed)
            return .ed25519(username: username, privateKey: privateKey)

        case "ecdsa-sha2-nistp256":
            let rawBytes = try extractOpenSSHPrivateKeyBytes(from: trimmed, expectedKeyType: keyTypeStr, isECDSA: true)
            let privateKey = try P256.Signing.PrivateKey(rawRepresentation: rawBytes)
            return .p256(username: username, privateKey: privateKey)

        case "ecdsa-sha2-nistp384":
            let rawBytes = try extractOpenSSHPrivateKeyBytes(from: trimmed, expectedKeyType: keyTypeStr, isECDSA: true)
            let privateKey = try P384.Signing.PrivateKey(rawRepresentation: rawBytes)
            return .p384(username: username, privateKey: privateKey)

        case "ecdsa-sha2-nistp521":
            let rawBytes = try extractOpenSSHPrivateKeyBytes(from: trimmed, expectedKeyType: keyTypeStr, isECDSA: true)
            let privateKey = try P521.Signing.PrivateKey(rawRepresentation: rawBytes)
            return .p521(username: username, privateKey: privateKey)

        default:
            throw SSHError.unsupportedKeyType(keyTypeStr)
        }
    }

    /// Partially parse an OpenSSH PEM to extract the key type string from the private block.
    private static func readOpenSSHKeyType(from pem: String) throws -> String {
        let base64 = try stripPEMHeaders(from: pem)
        guard let keyData = Data(base64Encoded: base64) else {
            throw SSHError.keyParseFailure("Invalid base64 in private key PEM")
        }

        var reader = DataReader(data: keyData)

        guard let magic = reader.readBytes(count: 15),
              String(bytes: magic, encoding: .ascii) == "openssh-key-v1",
              reader.readByte() == 0x00 else {
            throw SSHError.keyParseFailure("Invalid OpenSSH magic header")
        }

        guard reader.readSSHString() != nil,   // cipher
              reader.readSSHString() != nil,   // kdf
              reader.readSSHBytes() != nil,    // kdf options
              let numKeysBytes = reader.readBytes(count: 4) else {
            throw SSHError.keyParseFailure("Failed to read OpenSSH header fields")
        }

        guard bigEndianUInt32(numKeysBytes) == 1 else {
            throw SSHError.keyParseFailure("Expected exactly 1 key in the file")
        }

        guard reader.readSSHBytes() != nil,          // public key block
              let privateBlock = reader.readSSHBytes() else {
            throw SSHError.keyParseFailure("Failed to read key blocks")
        }

        var privReader = DataReader(data: privateBlock)

        guard let c0 = privReader.readBytes(count: 4),
              let c1 = privReader.readBytes(count: 4) else {
            throw SSHError.keyParseFailure("Private key block too short")
        }
        guard bigEndianUInt32(c0) == bigEndianUInt32(c1) else {
            throw SSHError.keyParseFailure("Key integrity check failed — key may be passphrase-protected")
        }

        guard let keyTypeStr = privReader.readSSHString() else {
            throw SSHError.keyParseFailure("Failed to read key type string from private block")
        }

        return keyTypeStr
    }

    // MARK: - RSA (PKCS#1 PEM) support via Security framework

    private static func buildRSASecKeyAuthMethod(username: String, pem: String) throws -> SSHAuthenticationMethod {
        let (secPrivKey, n, e) = try parseRSAPKCS1PEM(pem)
        return .custom(RSAAuthDelegate(username: username, secKey: secPrivKey, n: n, e: e))
    }

    /// Parse a PKCS#1 RSA private key PEM into a SecKey and extract modulus (n) and public exponent (e).
    private static func parseRSAPKCS1PEM(_ pem: String) throws -> (SecKey, Data, Data) {
        var s = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        let begin = "-----BEGIN RSA PRIVATE KEY-----"
        let end   = "-----END RSA PRIVATE KEY-----"
        guard s.hasPrefix(begin), s.hasSuffix(end) else {
            throw SSHError.keyParseFailure("Not a PKCS#1 RSA private key PEM")
        }
        s.removeFirst(begin.count)
        s.removeLast(end.count)
        let b64 = s.replacingOccurrences(of: "\n", with: "")
                   .replacingOccurrences(of: "\r", with: "")
                   .trimmingCharacters(in: .whitespaces)
        guard let der = Data(base64Encoded: b64) else {
            throw SSHError.keyParseFailure("Invalid base64 in RSA PEM")
        }

        // Import as SecKey
        let attrs: [String: Any] = [
            kSecAttrKeyType as String:  kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var cfErr: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &cfErr) else {
            throw SSHError.keyParseFailure("Could not import RSA key: \(cfErr?.takeRetainedValue().localizedDescription ?? "unknown")")
        }

        // Parse n and e from PKCS#1 DER
        let (n, e) = try extractRSAComponents(from: der)
        return (secKey, n, e)
    }

    /// Parse a PKCS#1 RSAPrivateKey DER blob to extract modulus (n) and publicExponent (e).
    /// RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, dp, dq, qp }
    private static func extractRSAComponents(from der: Data) throws -> (n: Data, e: Data) {
        var r = DataReader(data: der)
        // SEQUENCE
        guard r.readByte() == 0x30, r.readDERLength() != nil else {
            throw SSHError.keyParseFailure("RSA DER: expected SEQUENCE")
        }
        // version INTEGER (skip)
        guard r.readByte() == 0x02,
              let vLen = r.readDERLength(),
              r.skip(count: vLen) else {
            throw SSHError.keyParseFailure("RSA DER: bad version field")
        }
        // n (modulus)
        guard let n = r.readDERInteger() else {
            throw SSHError.keyParseFailure("RSA DER: could not read modulus")
        }
        // e (publicExponent)
        guard let e = r.readDERInteger() else {
            throw SSHError.keyParseFailure("RSA DER: could not read public exponent")
        }
        return (n, e)
    }

    // MARK: - Ed25519

    private static func parseEd25519Key(from pem: String) throws -> Curve25519.Signing.PrivateKey {
        let rawBytes = try extractOpenSSHPrivateKeyBytes(from: pem, expectedKeyType: "ssh-ed25519", isECDSA: false)
        // Ed25519 blob: [32 bytes private scalar] ++ [32 bytes public key]
        guard rawBytes.count >= 32 else {
            throw SSHError.keyParseFailure("Ed25519 key blob too short (\(rawBytes.count) bytes)")
        }
        let scalar = rawBytes.prefix(32)
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: scalar)
        } catch {
            throw SSHError.keyParseFailure("Invalid Ed25519 scalar: \(error.localizedDescription)")
        }
    }

    // MARK: - OpenSSH key parser

    /// Decode an OpenSSH private key PEM and return the raw private key bytes.
    /// Reference: https://dnaeon.github.io/openssh-private-key-binary-format/
    private static func extractOpenSSHPrivateKeyBytes(
        from pem: String,
        expectedKeyType: String,
        isECDSA: Bool
    ) throws -> Data {
        let base64 = try stripPEMHeaders(from: pem)
        guard let keyData = Data(base64Encoded: base64) else {
            throw SSHError.keyParseFailure("Invalid base64 in private key PEM")
        }

        var reader = DataReader(data: keyData)

        // Magic header "openssh-key-v1\0"
        guard let magic = reader.readBytes(count: 15),
              String(bytes: magic, encoding: .ascii) == "openssh-key-v1",
              reader.readByte() == 0x00 else {
            throw SSHError.keyParseFailure("Invalid OpenSSH magic header")
        }

        // cipher name, kdf name, kdf options
        guard reader.readSSHString() != nil,   // cipher name
              reader.readSSHString() != nil,   // kdf name
              reader.readSSHBytes() != nil     // kdf options
        else {
            throw SSHError.keyParseFailure("Failed to read OpenSSH header fields")
        }

        // number of keys
        guard let numKeysBytes = reader.readBytes(count: 4) else {
            throw SSHError.keyParseFailure("Failed to read key count")
        }
        let numKeys = bigEndianUInt32(numKeysBytes)
        guard numKeys == 1 else {
            throw SSHError.keyParseFailure("Expected 1 key, found \(numKeys)")
        }

        // Public key block (skip)
        guard reader.readSSHBytes() != nil else {
            throw SSHError.keyParseFailure("Failed to read public key block")
        }

        // Private key block
        guard let privateBlock = reader.readSSHBytes() else {
            throw SSHError.keyParseFailure("Failed to read private key block")
        }

        var privReader = DataReader(data: privateBlock)

        // check0 + check1
        guard let check0Bytes = privReader.readBytes(count: 4),
              let check1Bytes = privReader.readBytes(count: 4) else {
            throw SSHError.keyParseFailure("Private key block too short")
        }
        guard bigEndianUInt32(check0Bytes) == bigEndianUInt32(check1Bytes) else {
            throw SSHError.keyParseFailure("Key check values mismatch — may be passphrase-protected")
        }

        // Key type string
        guard let keyTypeStr = privReader.readSSHString() else {
            throw SSHError.keyParseFailure("Failed to read key type in private block")
        }
        guard keyTypeStr == expectedKeyType else {
            throw SSHError.keyParseFailure("Key type mismatch: expected '\(expectedKeyType)', got '\(keyTypeStr)'")
        }

        if !isECDSA {
            // Ed25519: public key buffer comes next, then private scalar buffer
            guard privReader.readSSHBytes() != nil else {
                throw SSHError.keyParseFailure("Failed to read Ed25519 public key buffer")
            }
        } else {
            // ECDSA: curve name + public key point come next
            guard privReader.readSSHString() != nil,  // curve name
                  privReader.readSSHBytes() != nil     // public key point
            else {
                throw SSHError.keyParseFailure("Failed to read ECDSA public key fields")
            }
        }

        // Private key bytes
        guard let privateKeyBytes = privReader.readSSHBytes() else {
            throw SSHError.keyParseFailure("Failed to read private key scalar")
        }

        return privateKeyBytes
    }

    private static func stripPEMHeaders(from pem: String) throws -> String {
        var s = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        let begin = "-----BEGIN OPENSSH PRIVATE KEY-----"
        let end = "-----END OPENSSH PRIVATE KEY-----"
        guard s.hasPrefix(begin), s.hasSuffix(end) else {
            throw SSHError.keyParseFailure("Not a valid OpenSSH private key PEM")
        }
        s.removeFirst(begin.count)
        s.removeLast(end.count)
        return s
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func bigEndianUInt32(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else { return 0 }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }
}

// MARK: - RSA NIOSSHPrivateKeyProtocol impl (Security framework)

private struct RSAPrivateKeyForSSH: NIOSSHPrivateKeyProtocol {
    static let keyPrefix = "ssh-rsa"
    let secKey: SecKey
    let n: Data
    let e: Data

    var publicKey: NIOSSHPublicKeyProtocol {
        let pub = SecKeyCopyPublicKey(secKey)
        return RSAPublicKeyForSSH(n: n, e: e, secKey: pub)
    }

    func signature<D: DataProtocol>(for data: D) throws -> NIOSSHSignatureProtocol {
        var error: Unmanaged<CFError>?
        let input = Data(data) as CFData
        guard let sig = SecKeyCreateSignature(secKey, .rsaSignatureMessagePKCS1v15SHA1, input, &error) else {
            throw SSHClient.SSHError.keyParseFailure(
                "RSA sign failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")"
            )
        }
        return RSASignatureForSSH(rawRepresentation: sig as Data)
    }
}

private struct RSAPublicKeyForSSH: NIOSSHPublicKeyProtocol {
    static let publicKeyPrefix = "ssh-rsa"
    let n: Data   // modulus (big-endian, may have leading 0x00)
    let e: Data   // public exponent
    let secKey: SecKey?

    var rawRepresentation: Data {
        var buf = ByteBuffer()
        _ = sshMPInt(e, into: &buf)
        _ = sshMPInt(n, into: &buf)
        return Data(buf.readableBytesView)
    }

    func write(to buffer: inout ByteBuffer) -> Int {
        sshMPInt(e, into: &buffer) + sshMPInt(n, into: &buffer)
    }

    static func read(from buffer: inout ByteBuffer) throws -> RSAPublicKeyForSSH {
        guard let eData = readSSHBytes(from: &buffer),
              let nData = readSSHBytes(from: &buffer) else {
            throw SSHClient.SSHError.keyParseFailure("RSA pubkey: truncated buffer")
        }
        return RSAPublicKeyForSSH(n: nData, e: eData, secKey: nil)
    }

    func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        guard let sig = signature as? RSASignatureForSSH, let key = secKey else { return false }
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            key, .rsaSignatureMessagePKCS1v15SHA1,
            Data(data) as CFData, sig.rawRepresentation as CFData, &error
        )
    }

    /// Read a 4-byte big-endian length-prefixed blob from a ByteBuffer, returning it as Data.
    private static func readSSHBytes(from buffer: inout ByteBuffer) -> Data? {
        guard let length = buffer.readInteger(as: UInt32.self).map(Int.init) else { return nil }
        guard let bytes = buffer.readBytes(length: length) else { return nil }
        return Data(bytes)
    }

    /// Write `bytes` as an SSH mpint: strip leading 0x00, prepend 0x00 if high-bit set, length-prefix.
    @discardableResult
    private func sshMPInt(_ bytes: Data, into buffer: inout ByteBuffer) -> Int {
        var stripped = bytes
        while stripped.first == 0x00 { stripped.removeFirst() }
        if let first = stripped.first, first & 0x80 != 0 {
            stripped = Data([0x00]) + stripped
        }
        return writeLengthPrefixed(stripped, into: &buffer)
    }

    /// Write Data as a 4-byte big-endian length followed by the bytes.
    @discardableResult
    private func writeLengthPrefixed(_ data: Data, into buffer: inout ByteBuffer) -> Int {
        let written = buffer.writeInteger(UInt32(data.count))
        return written + buffer.writeBytes(data)
    }
}

private struct RSASignatureForSSH: NIOSSHSignatureProtocol {
    static let signaturePrefix = "ssh-rsa"
    var rawRepresentation: Data

    func write(to buffer: inout ByteBuffer) -> Int {
        let written = buffer.writeInteger(UInt32(rawRepresentation.count))
        return written + buffer.writeBytes(rawRepresentation)
    }

    static func read(from buffer: inout ByteBuffer) throws -> RSASignatureForSSH {
        guard let length = buffer.readInteger(as: UInt32.self).map(Int.init),
              let bytes = buffer.readBytes(length: length) else {
            throw SSHClient.SSHError.keyParseFailure("RSA signature: truncated buffer")
        }
        return RSASignatureForSSH(rawRepresentation: Data(bytes))
    }
}

// MARK: - RSA SHA-256 types (rsa-sha2-256, for OpenSSH 8.8+)

private struct RSAPrivateKey256ForSSH: NIOSSHPrivateKeyProtocol {
    static let keyPrefix = "rsa-sha2-256"
    let secKey: SecKey
    let n: Data
    let e: Data

    var publicKey: NIOSSHPublicKeyProtocol {
        let pub = SecKeyCopyPublicKey(secKey)
        return RSAPublicKey256ForSSH(n: n, e: e, secKey: pub)
    }

    func signature<D: DataProtocol>(for data: D) throws -> NIOSSHSignatureProtocol {
        var error: Unmanaged<CFError>?
        let input = Data(data) as CFData
        guard let sig = SecKeyCreateSignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, input, &error) else {
            throw SSHClient.SSHError.keyParseFailure(
                "RSA sign failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")"
            )
        }
        return RSASignature256ForSSH(rawRepresentation: sig as Data)
    }
}

private struct RSAPublicKey256ForSSH: NIOSSHPublicKeyProtocol {
    static let publicKeyPrefix = "rsa-sha2-256"
    let n: Data   // modulus (big-endian, may have leading 0x00)
    let e: Data   // public exponent
    let secKey: SecKey?

    var rawRepresentation: Data {
        var buf = ByteBuffer()
        _ = sshMPInt(e, into: &buf)
        _ = sshMPInt(n, into: &buf)
        return Data(buf.readableBytesView)
    }

    func write(to buffer: inout ByteBuffer) -> Int {
        sshMPInt(e, into: &buffer) + sshMPInt(n, into: &buffer)
    }

    static func read(from buffer: inout ByteBuffer) throws -> RSAPublicKey256ForSSH {
        guard let eData = readSSHBytes(from: &buffer),
              let nData = readSSHBytes(from: &buffer) else {
            throw SSHClient.SSHError.keyParseFailure("RSA-256 pubkey: truncated buffer")
        }
        return RSAPublicKey256ForSSH(n: nData, e: eData, secKey: nil)
    }

    func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        guard let sig = signature as? RSASignature256ForSSH, let key = secKey else { return false }
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            key, .rsaSignatureMessagePKCS1v15SHA256,
            Data(data) as CFData, sig.rawRepresentation as CFData, &error
        )
    }

    private static func readSSHBytes(from buffer: inout ByteBuffer) -> Data? {
        guard let length = buffer.readInteger(as: UInt32.self).map(Int.init) else { return nil }
        guard let bytes = buffer.readBytes(length: length) else { return nil }
        return Data(bytes)
    }

    @discardableResult
    private func sshMPInt(_ bytes: Data, into buffer: inout ByteBuffer) -> Int {
        var stripped = bytes
        while stripped.first == 0x00 { stripped.removeFirst() }
        if let first = stripped.first, first & 0x80 != 0 {
            stripped = Data([0x00]) + stripped
        }
        return writeLengthPrefixed(stripped, into: &buffer)
    }

    @discardableResult
    private func writeLengthPrefixed(_ data: Data, into buffer: inout ByteBuffer) -> Int {
        let written = buffer.writeInteger(UInt32(data.count))
        return written + buffer.writeBytes(data)
    }
}

private struct RSASignature256ForSSH: NIOSSHSignatureProtocol {
    static let signaturePrefix = "rsa-sha2-256"
    var rawRepresentation: Data

    func write(to buffer: inout ByteBuffer) -> Int {
        let written = buffer.writeInteger(UInt32(rawRepresentation.count))
        return written + buffer.writeBytes(rawRepresentation)
    }

    static func read(from buffer: inout ByteBuffer) throws -> RSASignature256ForSSH {
        guard let length = buffer.readInteger(as: UInt32.self).map(Int.init),
              let bytes = buffer.readBytes(length: length) else {
            throw SSHClient.SSHError.keyParseFailure("RSA-256 signature: truncated buffer")
        }
        return RSASignature256ForSSH(rawRepresentation: Data(bytes))
    }
}

// MARK: - RSA Auth Delegate (tries rsa-sha2-256 first, falls back to ssh-rsa)

private final class RSAAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    let username: String
    let privateKey: RSAPrivateKeyForSSH       // sha1 fallback
    let privateKey256: RSAPrivateKey256ForSSH  // sha256 primary
    private var attempt = 0

    init(username: String, secKey: SecKey, n: Data, e: Data) {
        self.username = username
        self.privateKey = RSAPrivateKeyForSSH(secKey: secKey, n: n, e: e)
        self.privateKey256 = RSAPrivateKey256ForSSH(secKey: secKey, n: n, e: e)
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(RSAAuthDelegateError.noPublicKeyMethod)
            return
        }
        defer { attempt += 1 }
        switch attempt {
        case 0:
            // Try rsa-sha2-256 first (modern EC2 / OpenSSH 8.8+)
            let nioKey = NIOSSHPrivateKey(custom: privateKey256)
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username, serviceName: "",
                offer: .privateKey(.init(privateKey: nioKey))
            ))
        case 1:
            // Fall back to ssh-rsa (SHA-1) for older servers
            let nioKey = NIOSSHPrivateKey(custom: privateKey)
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username, serviceName: "",
                offer: .privateKey(.init(privateKey: nioKey))
            ))
        default:
            nextChallengePromise.fail(RSAAuthDelegateError.allAttemptsFailed)
        }
    }

    enum RSAAuthDelegateError: Error {
        case noPublicKeyMethod
        case allAttemptsFailed
    }
}

// MARK: - DataReader

/// A simple cursor-based reader over a Data blob.
private struct DataReader {
    let data: Data
    var offset: Int = 0

    var remaining: Int { data.count - offset }

    mutating func readByte() -> UInt8? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readBytes(count: Int) -> [UInt8]? {
        guard offset + count <= data.count else { return nil }
        let bytes = Array(data[offset..<(offset + count)])
        offset += count
        return bytes
    }

    mutating func readUInt32() -> UInt32? {
        guard let b = readBytes(count: 4) else { return nil }
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    /// Read a 4-byte big-endian length then that many bytes, return as Data.
    mutating func readSSHBytes() -> Data? {
        guard let length = readUInt32().map(Int.init) else { return nil }
        guard offset + length <= data.count else { return nil }
        let result = data[offset..<(offset + length)]
        offset += length
        return result
    }

    /// Read a 4-byte big-endian length then that many bytes, decode as UTF-8 String.
    mutating func readSSHString() -> String? {
        guard let bytes = readSSHBytes() else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    mutating func readDERLength() -> Int? {
        guard let first = readByte() else { return nil }
        if first & 0x80 == 0 { return Int(first) }
        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4,
              let lengthBytes = readBytes(count: numBytes) else { return nil }
        return lengthBytes.reduce(0) { ($0 << 8) | Int($1) }
    }

    mutating func readDERInteger() -> Data? {
        guard readByte() == 0x02,
              let length = readDERLength(),
              let bytes = readBytes(count: length) else { return nil }
        return Data(bytes)
    }

    mutating func skip(count: Int) -> Bool {
        guard offset + count <= data.count else { return false }
        offset += count
        return true
    }
}
