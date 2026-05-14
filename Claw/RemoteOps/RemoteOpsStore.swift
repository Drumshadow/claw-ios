import Foundation

@Observable
@MainActor
final class RemoteOpsStore {

    var ec2Instances: [EC2Instance] = []
    var workflowRuns: [GitHubWorkflowRun] = []
    var datadogMonitors: [DatadogMonitor] = []
    var commands: [OpsCommand] = []
    var isRefreshing: Bool = false
    var lastRefreshed: Date? = nil
    var error: String? = nil

    /// SSH sub-store — manages per-instance credentials, health checks, and custom commands.
    let sshStore: InstanceSSHStore = InstanceSSHStore()

    var credentials: OpsCredentials {
        didSet { credentials.save() }
    }

    var alerts: [OpsAlert] {
        var result: [OpsAlert] = []

        for run in workflowRuns where run.conclusion == "failure" {
            result.append(OpsAlert(
                id: "gh-\(run.id)",
                source: .github,
                severity: .warning,
                title: "\(run.name) failed",
                message: run.headCommitMessage ?? run.repo,
                timestamp: run.updatedAt ?? Date(),
                url: run.htmlUrl
            ))
        }

        for monitor in datadogMonitors {
            let severity: OpsAlertSeverity
            switch monitor.overallState.lowercased() {
            case "alert": severity = .critical
            case "warn": severity = .warning
            default: severity = .info
            }
            guard severity != .info else { continue }
            result.append(OpsAlert(
                id: "dd-\(monitor.id)",
                source: .datadog,
                severity: severity,
                title: monitor.name,
                message: monitor.message ?? monitor.overallState,
                timestamp: monitor.modified ?? Date(),
                url: nil
            ))
        }

        for instance in ec2Instances where instance.state == .stopped {
            result.append(OpsAlert(
                id: "ec2-\(instance.id)",
                source: .ec2,
                severity: .info,
                title: "\(instance.name) is stopped",
                message: "\(instance.instanceType) in \(instance.region)",
                timestamp: lastRefreshed ?? Date(),
                url: nil
            ))
        }

        return result.sorted { $0.timestamp > $1.timestamp }
    }

    // Stored in Keychain rather than UserDefaults because shell commands may
    // contain credentials, server addresses, or other text the user expects to
    // be kept locally and protected at rest.
    private let commandsKeychainKey = "claw.ops.commands"
    private let legacyCommandsDefaultsKey = "claw.ops.commands"

    init() {
        credentials = OpsCredentials.load()
        commands = loadCommands()
    }

    func addCommand(_ command: OpsCommand) {
        commands.append(command)
        persistCommands()
    }

    func updateCommand(_ command: OpsCommand) {
        guard let idx = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[idx] = command
        persistCommands()
    }

    func deleteCommand(id: UUID) {
        commands.removeAll { $0.id == id }
        persistCommands()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil
        defer { isRefreshing = false }

        async let instancesFetch: [EC2Instance] = fetchEC2()
        async let runsFetch: [GitHubWorkflowRun] = fetchGitHub()
        async let monitorsFetch: [DatadogMonitor] = fetchDatadog()

        let (instances, runs, monitors) = await (instancesFetch, runsFetch, monitorsFetch)
        ec2Instances = instances
        workflowRuns = runs
        datadogMonitors = monitors
        lastRefreshed = Date()
    }

    func runCommand(_ command: OpsCommand, on instanceId: String?) async {
        let target = instanceId ?? command.targetInstanceId ?? "unspecified"
        // Do NOT log command.command — shell text may contain credentials or other
        // secrets that would leak to the unified log / Console.app / sysdiagnose.
        #if DEBUG
        print("[RemoteOps] Run command '\(command.name)' on \(target)")
        #endif
        NotificationCenter.default.post(
            name: .opsCommandDidRun,
            object: nil,
            userInfo: ["command": command, "instanceId": target]
        )
    }

    // MARK: - Private fetch helpers

    private func fetchEC2() async -> [EC2Instance] {
        guard let keyId = credentials.awsAccessKeyId,
              let secret = credentials.awsSecretAccessKey else { return [] }
        do {
            return try await AWSAPIClient().fetchEC2Instances(
                keyId: keyId,
                secret: secret,
                region: credentials.awsRegion
            )
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    private func fetchGitHub() async -> [GitHubWorkflowRun] {
        guard let token = credentials.githubToken else { return [] }
        do {
            return try await GitHubAPIClient().fetchWorkflowRuns(token: token)
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    private func fetchDatadog() async -> [DatadogMonitor] {
        guard let apiKey = credentials.datadogApiKey,
              let appKey = credentials.datadogAppKey else { return [] }
        do {
            return try await DatadogAPIClient().fetchMonitors(
                apiKey: apiKey,
                appKey: appKey,
                site: credentials.datadogSite
            )
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    // MARK: - Commands persistence

    private func loadCommands() -> [OpsCommand] {
        if let data = try? KeychainStore.load(key: commandsKeychainKey),
           let decoded = try? JSONDecoder().decode([OpsCommand].self, from: data) {
            return decoded
        }
        // One-time migration: pull commands from the legacy UserDefaults location
        // and re-persist into the Keychain, then clear the plaintext copy.
        if let legacy = UserDefaults.standard.data(forKey: legacyCommandsDefaultsKey),
           let decoded = try? JSONDecoder().decode([OpsCommand].self, from: legacy) {
            try? KeychainStore.save(key: commandsKeychainKey, data: legacy)
            UserDefaults.standard.removeObject(forKey: legacyCommandsDefaultsKey)
            return decoded
        }
        return []
    }

    private func persistCommands() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        if commands.isEmpty {
            try? KeychainStore.delete(key: commandsKeychainKey)
            return
        }
        try? KeychainStore.save(key: commandsKeychainKey, data: data)
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let opsCommandDidRun = Notification.Name("claw.ops.commandDidRun")
}
