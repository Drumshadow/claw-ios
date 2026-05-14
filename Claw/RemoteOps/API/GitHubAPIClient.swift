import Foundation

struct GitHubAPIClient {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchWorkflowRuns(token: String) async throws -> [GitHubWorkflowRun] {
        let repos = try await fetchRepos(token: token)
        let capped = Array(repos.prefix(10))

        var allRuns: [GitHubWorkflowRun] = []

        try await withThrowingTaskGroup(of: [GitHubWorkflowRun].self) { group in
            for repo in capped {
                group.addTask {
                    try await self.fetchRuns(for: repo, token: token)
                }
            }
            for try await runs in group {
                allRuns.append(contentsOf: runs)
            }
        }

        return allRuns.sorted {
            let lhs = $0.updatedAt ?? .distantPast
            let rhs = $1.updatedAt ?? .distantPast
            return lhs > rhs
        }
    }

    // MARK: - Private

    private func fetchRepos(token: String) async throws -> [RepoRef] {
        var components = URLComponents(string: "https://api.github.com/user/repos")!
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        let request = makeRequest(url: components.url!, token: token)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let raw = try JSONDecoder().decode([[String: JSONAny]].self, from: data)
        return raw.compactMap { obj -> RepoRef? in
            guard let fullName = (obj["full_name"] as? JSONAny).flatMap({ $0.stringValue }),
                  let ownerObj = (obj["owner"] as? JSONAny).flatMap({ $0.objectValue }),
                  let owner = ownerObj["login"]?.stringValue,
                  let name = (obj["name"] as? JSONAny).flatMap({ $0.stringValue }) else { return nil }
            _ = fullName
            return RepoRef(owner: owner, name: name)
        }
    }

    private func fetchRuns(for repo: RepoRef, token: String) async throws -> [GitHubWorkflowRun] {
        var components = URLComponents(string: "https://api.github.com/repos/\(repo.owner)/\(repo.name)/actions/runs")!
        components.queryItems = [URLQueryItem(name: "per_page", value: "5")]
        let request = makeRequest(url: components.url!, token: token)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let envelope = try decoder.decode(RunsEnvelope.self, from: data)
        let repoFullName = "\(repo.owner)/\(repo.name)"
        return envelope.workflowRuns.map { raw in
            GitHubWorkflowRun(
                id: raw.id,
                name: raw.name,
                repo: repoFullName,
                status: raw.status,
                conclusion: raw.conclusion,
                startedAt: raw.runStartedAt,
                updatedAt: raw.updatedAt,
                htmlUrl: raw.htmlUrl,
                headCommitMessage: raw.headCommit?.message,
                headBranch: raw.headBranch
            )
        }
    }

    private func makeRequest(url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return req
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GitHubAPIError.httpError(code)
        }
    }
}

// MARK: - Supporting types

private struct RepoRef {
    let owner: String
    let name: String
}

private struct RunsEnvelope: Decodable {
    let workflowRuns: [RawRun]
}

private struct RawRun: Decodable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let runStartedAt: Date?
    let updatedAt: Date?
    let htmlUrl: String
    let headBranch: String?
    let headCommit: HeadCommit?
}

private struct HeadCommit: Decodable {
    let message: String?
}

// Minimal dynamic JSON for repo listing
private struct JSONAny: Decodable {
    private let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let obj = try? container.decode([String: JSONAny].self) { value = obj }
        else if let arr = try? container.decode([JSONAny].self) { value = arr }
        else { value = NSNull() }
    }

    var stringValue: String? { value as? String }
    var objectValue: [String: JSONAny]? { value as? [String: JSONAny] }
}

enum GitHubAPIError: Error, LocalizedError {
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "GitHub API returned HTTP \(code)"
        }
    }
}
