import AuthenticationServices
import CryptoKit

@Observable @MainActor final class GitHubOAuthManager: NSObject {
    var isAuthenticating: Bool = false
    var error: String? = nil

    static let clientId: String = Bundle.main.object(forInfoDictionaryKey: "GITHUB_CLIENT_ID") as? String ?? ""
    static let callbackScheme = "claw"
    static let callbackURL = "claw://oauth/github"

    private var presentationAnchorRef: ASPresentationAnchor?

    func authenticate(presentationAnchor: ASPresentationAnchor) async throws -> String {
        isAuthenticating = true
        error = nil
        presentationAnchorRef = presentationAnchor
        defer {
            isAuthenticating = false
            presentationAnchorRef = nil
        }

        let codeVerifier = Self.generateRandomString(byteCount: 32)
        let codeChallenge = Self.codeChallenge(for: codeVerifier)
        let state = Self.generateRandomString(byteCount: 16)

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            // OAuth Apps need the broad `repo` scope for private Actions workflow-run reads.
            // Keep the mobile token limited to public repositories; private repo support should
            // move to a GitHub App/server-side broker with fine-grained Actions read permission.
            URLQueryItem(name: "scope", value: "public_repo"),
            URLQueryItem(name: "redirect_uri", value: Self.callbackURL),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: Self.callbackScheme
            ) { url, sessionError in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: sessionError ?? OAuthError.cancelled)
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            session.start()
        }

        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard let returnedState = callbackComponents?.queryItems?.first(where: { $0.name == "state" })?.value,
              Self.constantTimeEquals(returnedState, state)
        else {
            throw OAuthError.stateMismatch
        }
        guard let code = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }

        let token = try await exchangeCodeForToken(code, codeVerifier: codeVerifier)

        if let data = token.data(using: .utf8) {
            try KeychainStore.save(key: "claw.ops.github.token", data: data)
        }

        return token
    }

    private func exchangeCodeForToken(_ code: String, codeVerifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": Self.clientId,
            "code": code,
            "redirect_uri": Self.callbackURL,
            "code_verifier": codeVerifier
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        // Reject non-2xx responses before trying to decode. GitHub returns 200
        // even on OAuth errors (with an `error` field instead of `access_token`),
        // but a 4xx/5xx response should never be treated as success.
        if let http = urlResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OAuthError.tokenExchangeFailed
        }
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        guard !response.accessToken.isEmpty else {
            throw OAuthError.tokenExchangeFailed
        }
        return response.accessToken
    }

    // MARK: - PKCE / state helpers

    private static func generateRandomString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return DeviceIdentity.base64UrlEncode(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return DeviceIdentity.base64UrlEncode(Data(hash))
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }
}

extension GitHubOAuthManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            presentationAnchorRef ?? ASPresentationAnchor()
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private enum OAuthError: LocalizedError {
    case cancelled, missingCode, tokenExchangeFailed, stateMismatch

    var errorDescription: String? {
        switch self {
        case .cancelled: return "GitHub sign-in was cancelled."
        case .missingCode: return "No authorization code returned from GitHub."
        case .tokenExchangeFailed: return "Failed to exchange authorization code for a token."
        case .stateMismatch: return "OAuth state mismatch — possible CSRF attempt."
        }
    }
}
