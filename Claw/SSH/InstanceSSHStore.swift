import Foundation

// MARK: - InstanceSSHStore

@Observable
@MainActor
final class InstanceSSHStore {

    // MARK: - In-memory state

    /// Last health check results keyed by instanceId
    var lastHealthResults: [String: HealthCheckResult] = [:]

    // MARK: - Keychain key helpers

    private func credentialKey(for instanceId: String) -> String {
        "ssh_credential_\(instanceId)"
    }

    private func privateKeyKey(for instanceId: String) -> String {
        "ssh_private_key_\(instanceId)"
    }

    private func commandsKey(for instanceId: String) -> String {
        "ssh_commands_\(instanceId)"
    }

    private func healthConfigKey(for instanceId: String) -> String {
        "ssh_health_config_\(instanceId)"
    }

    // MARK: - Credential CRUD

    func saveCredential(_ cred: SSHCredential, privateKeyPEM: String, for instanceId: String) {
        guard let credData = try? JSONEncoder().encode(cred) else { return }
        try? KeychainStore.save(key: credentialKey(for: instanceId), data: credData)

        guard let keyData = privateKeyPEM.data(using: .utf8) else { return }
        try? KeychainStore.save(key: privateKeyKey(for: instanceId), data: keyData)
    }

    func deleteCredential(for instanceId: String) {
        try? KeychainStore.delete(key: credentialKey(for: instanceId))
        try? KeychainStore.delete(key: privateKeyKey(for: instanceId))
    }

    func loadCredential(for instanceId: String) -> SSHCredential? {
        guard let data = try? KeychainStore.load(key: credentialKey(for: instanceId)),
              let cred = try? JSONDecoder().decode(SSHCredential.self, from: data) else { return nil }
        return cred
    }

    func loadPrivateKey(for instanceId: String) -> String? {
        guard let data = try? KeychainStore.load(key: privateKeyKey(for: instanceId)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func hasCredential(for instanceId: String) -> Bool {
        KeychainStore.exists(key: credentialKey(for: instanceId))
    }

    // MARK: - Custom Commands CRUD

    func saveCommands(_ commands: [CustomCommand], for instanceId: String) {
        if commands.isEmpty {
            try? KeychainStore.delete(key: commandsKey(for: instanceId))
            return
        }
        guard let data = try? JSONEncoder().encode(commands) else { return }
        try? KeychainStore.save(key: commandsKey(for: instanceId), data: data)
    }

    func loadCommands(for instanceId: String) -> [CustomCommand] {
        guard let data = try? KeychainStore.load(key: commandsKey(for: instanceId)),
              let commands = try? JSONDecoder().decode([CustomCommand].self, from: data) else { return [] }
        return commands
    }

    // MARK: - Health Config

    func saveHealthConfig(_ config: HealthCheckConfig, for instanceId: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? KeychainStore.save(key: healthConfigKey(for: instanceId), data: data)
    }

    func loadHealthConfig(for instanceId: String) -> HealthCheckConfig {
        guard let data = try? KeychainStore.load(key: healthConfigKey(for: instanceId)),
              let config = try? JSONDecoder().decode(HealthCheckConfig.self, from: data) else {
            return HealthCheckConfig()
        }
        return config
    }

    // MARK: - SSH Execution

    /// Run the health check command for an instance and store the result.
    func runHealthCheck(for instance: EC2Instance) async -> HealthCheckResult {
        let config = loadHealthConfig(for: instance.id)

        guard let cred = loadCredential(for: instance.id),
              let pem = loadPrivateKey(for: instance.id) else {
            let result = HealthCheckResult(
                timestamp: Date(),
                output: "No SSH credentials configured.",
                success: false
            )
            lastHealthResults[instance.id] = result
            return result
        }

        do {
            let output = try await SSHClient.executeCommand(
                config.command,
                host: cred.host,
                port: cred.port,
                username: cred.username,
                privateKeyPEM: pem
            )
            let result = HealthCheckResult(timestamp: Date(), output: output, success: true)
            lastHealthResults[instance.id] = result
            return result
        } catch {
            let result = HealthCheckResult(
                timestamp: Date(),
                output: error.localizedDescription,
                success: false
            )
            lastHealthResults[instance.id] = result
            return result
        }
    }

    /// Fetch running Docker containers from an instance via direct SSH.
    func fetchContainers(for instance: EC2Instance) async -> [OpsContainer] {
        guard let cred = loadCredential(for: instance.id),
              let key = loadPrivateKey(for: instance.id) else { return [] }
        let cmd = "docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' 2>/dev/null || sudo docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' 2>/dev/null"
        do {
            let output = try await SSHClient.executeCommand(cmd, host: cred.host, port: cred.port, username: cred.username, privateKeyPEM: key)
            return output.split(separator: "\n").compactMap { line -> OpsContainer? in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 4 else { return nil }
                return OpsContainer(id: parts[0], name: parts[1], image: parts[2], status: parts[3], uptime: nil, ports: parts.count > 4 ? parts[4].split(separator: ",").map(String.init) : [])
            }
        } catch {
            return []
        }
    }

    /// Run a custom command on an instance and return the output string.
    func runCommand(_ command: CustomCommand, for instance: EC2Instance) async throws -> String {
        guard let cred = loadCredential(for: instance.id),
              let pem = loadPrivateKey(for: instance.id) else {
            throw SSHClient.SSHError.keyParseFailure("No SSH credentials configured for this instance.")
        }

        return try await SSHClient.executeCommand(
            command.command,
            host: cred.host,
            port: cred.port,
            username: cred.username,
            privateKeyPEM: pem
        )
    }
}
