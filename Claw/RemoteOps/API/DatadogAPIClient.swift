import Foundation

struct DatadogAPIClient {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMonitors(apiKey: String, appKey: String, site: String) async throws -> [DatadogMonitor] {
        // Validate the site against the Datadog-allowed hostname character set so
        // a malformed value can't redirect the request (which carries the API key
        // and application key headers) to an attacker-controlled host.
        guard Self.isValidDatadogSite(site) else {
            throw DatadogAPIError.invalidSite(site)
        }
        guard var components = URLComponents(string: "https://api.\(site)/api/v1/monitor") else {
            throw DatadogAPIError.invalidSite(site)
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard let url = components.url else {
            throw DatadogAPIError.invalidSite(site)
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "DD-API-KEY")
        request.setValue(appKey, forHTTPHeaderField: "DD-APPLICATION-KEY")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DatadogAPIError.httpError(code)
        }

        let raw = try JSONDecoder().decode([RawMonitor].self, from: data)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterBasic = ISO8601DateFormatter()
        isoFormatterBasic.formatOptions = [.withInternetDateTime]

        return raw.map { m in
            let modifiedDate: Date?
            if let s = m.modified {
                modifiedDate = isoFormatter.date(from: s) ?? isoFormatterBasic.date(from: s)
            } else {
                modifiedDate = nil
            }
            return DatadogMonitor(
                id: m.id,
                name: m.name,
                overallState: m.overallState,
                message: m.message,
                tags: m.tags,
                modified: modifiedDate
            )
        }
    }

    private static func isValidDatadogSite(_ site: String) -> Bool {
        guard !site.isEmpty, site.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return site.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Supporting types

private struct RawMonitor: Decodable {
    let id: Int
    let name: String
    let overallState: String
    let message: String?
    let tags: [String]
    let modified: String?

    enum CodingKeys: String, CodingKey {
        case id, name, message, tags, modified
        case overallState = "overall_state"
    }
}

enum DatadogAPIError: Error, LocalizedError {
    case httpError(Int)
    case invalidSite(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Datadog API returned HTTP \(code)"
        case .invalidSite(let site): return "Invalid Datadog site: \(site)"
        }
    }
}
