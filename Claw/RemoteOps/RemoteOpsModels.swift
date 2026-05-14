import Foundation

// MARK: - EC2

enum EC2State: String, Codable {
    case running, stopped, terminated, pending, stopping

    var displayColor: String {
        switch self {
        case .running: return "green"
        case .stopped: return "gray"
        case .terminated: return "red"
        case .pending, .stopping: return "orange"
        }
    }
}

struct EC2Instance: Identifiable, Codable {
    let id: String
    let name: String
    let state: EC2State
    let publicIP: String?
    let privateIP: String?
    let instanceType: String
    let region: String
    var metrics: InstanceMetrics?
    var containers: [OpsContainer]
}

struct InstanceMetrics: Codable {
    let cpuPercent: Double
    let memoryPercent: Double?
    let diskPercent: Double?
}

struct OpsContainer: Identifiable, Codable {
    let id: String
    let name: String
    let image: String
    let status: String
    let uptime: String?
    let ports: [String]
}

// MARK: - GitHub

struct GitHubWorkflowRun: Identifiable, Codable {
    let id: Int
    let name: String
    let repo: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let updatedAt: Date?
    let htmlUrl: String
    let headCommitMessage: String?
    let headBranch: String?
}

// MARK: - Datadog

struct DatadogMonitor: Identifiable, Codable {
    let id: Int
    let name: String
    let overallState: String
    let message: String?
    let tags: [String]
    let modified: Date?
}

// MARK: - SSH

struct SSHCredential: Codable {
    var username: String
    var host: String
    var port: Int = 22
}

struct HealthCheckConfig: Codable {
    var command: String = "uptime"
    var intervalSeconds: Int = 3600
}

struct HealthCheckResult: Codable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date
    var output: String
    var success: Bool
}

struct CustomCommand: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var command: String
}

// MARK: - Commands

struct OpsCommand: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var command: String
    var targetInstanceId: String?
    var requiresApproval: Bool
}

// MARK: - Alerts

struct OpsAlert: Identifiable {
    let id: String
    let source: OpsAlertSource
    let severity: OpsAlertSeverity
    let title: String
    let message: String
    let timestamp: Date
    let url: String?
}

enum OpsAlertSource: String, Codable {
    case datadog, github, ec2
}

enum OpsAlertSeverity: Int, Codable, Comparable {
    case critical = 0, warning = 1, info = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Credentials

struct OpsCredentials {
    var githubToken: String?
    var datadogApiKey: String?
    var datadogAppKey: String?
    var datadogSite: String = "datadoghq.com"
    var awsAccessKeyId: String?
    var awsSecretAccessKey: String?
    var awsRegion: String = "us-east-1"

    private enum Keys {
        static let githubToken = "claw.ops.github.token"
        static let ddApiKey = "claw.ops.dd.apiKey"
        static let ddAppKey = "claw.ops.dd.appKey"
        static let ddSite = "claw.ops.dd.site"
        static let awsKeyId = "claw.ops.aws.keyId"
        static let awsSecret = "claw.ops.aws.secret"
        static let awsRegion = "claw.ops.aws.region"
    }

    static func load() -> OpsCredentials {
        var creds = OpsCredentials()
        creds.githubToken = loadString(key: Keys.githubToken)
        creds.datadogApiKey = loadString(key: Keys.ddApiKey)
        creds.datadogAppKey = loadString(key: Keys.ddAppKey)
        if let site = loadString(key: Keys.ddSite) { creds.datadogSite = site }
        creds.awsAccessKeyId = loadString(key: Keys.awsKeyId)
        creds.awsSecretAccessKey = loadString(key: Keys.awsSecret)
        if let region = loadString(key: Keys.awsRegion) { creds.awsRegion = region }
        return creds
    }

    func save() {
        saveString(githubToken, key: Keys.githubToken)
        saveString(datadogApiKey, key: Keys.ddApiKey)
        saveString(datadogAppKey, key: Keys.ddAppKey)
        saveString(datadogSite, key: Keys.ddSite)
        saveString(awsAccessKeyId, key: Keys.awsKeyId)
        saveString(awsSecretAccessKey, key: Keys.awsSecret)
        saveString(awsRegion, key: Keys.awsRegion)
    }

    private static func loadString(key: String) -> String? {
        guard let data = try? KeychainStore.load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveString(_ value: String?, key: String) {
        // A nil/empty value means the user cleared the field — delete the existing
        // Keychain item rather than leaving the stale credential on disk.
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            try? KeychainStore.delete(key: key)
            return
        }
        try? KeychainStore.save(key: key, data: data)
    }
}
