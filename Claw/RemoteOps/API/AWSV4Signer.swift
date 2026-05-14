import Foundation
import CryptoKit

struct AWSV4Signer {

    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let service: String

    func sign(request: URLRequest, date: Date = Date()) throws -> URLRequest {
        var req = request

        guard let url = req.url, let host = url.host else {
            throw AWSV4SignerError.invalidURL
        }

        let now = date
        let dateStamp = Self.dateStamp(from: now)
        let amzDate = Self.amzDate(from: now)

        req.setValue(host, forHTTPHeaderField: "Host")
        req.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")

        let body = req.httpBody ?? Data()
        let payloadHash = SHA256.hash(data: body).hexString

        let contentType = req.value(forHTTPHeaderField: "Content-Type")
        let signedHeaders: String
        let canonicalHeaders: String
        if let ct = contentType {
            signedHeaders = "content-type;host;x-amz-date"
            canonicalHeaders = "content-type:\(ct)\nhost:\(host)\nx-amz-date:\(amzDate)\n"
        } else {
            signedHeaders = "host;x-amz-date"
            canonicalHeaders = "host:\(host)\nx-amz-date:\(amzDate)\n"
        }

        let canonicalURI = url.path.isEmpty ? "/" : url.path
        let canonicalQuery = url.query ?? ""

        let canonicalRequest = [
            req.httpMethod ?? "GET",
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).hexString

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        let signingKey = try deriveSigningKey(dateStamp: dateStamp)
        let signatureMac = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: signingKey
        )
        let signature = Data(signatureMac).map { String(format: "%02x", $0) }.joined()

        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")

        return req
    }

    // MARK: - Private

    private func deriveSigningKey(dateStamp: String) throws -> SymmetricKey {
        let kSecret = Data("AWS4\(secretAccessKey)".utf8)
        let kDate = Data(HMAC<SHA256>.authenticationCode(for: Data(dateStamp.utf8), using: SymmetricKey(data: kSecret)))
        let kRegion = Data(HMAC<SHA256>.authenticationCode(for: Data(region.utf8), using: SymmetricKey(data: kDate)))
        let kService = Data(HMAC<SHA256>.authenticationCode(for: Data(service.utf8), using: SymmetricKey(data: kRegion)))
        let kSigning = Data(HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: SymmetricKey(data: kService)))
        return SymmetricKey(data: kSigning)
    }

    private static func dateStamp(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private static func amzDate(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

// MARK: - Hex helpers

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

enum AWSV4SignerError: Error, LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Cannot sign request: URL is missing or has no host"
        }
    }
}
