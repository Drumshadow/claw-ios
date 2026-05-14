import SwiftUI

// MARK: - HealthCheckView

struct HealthCheckView: View {
    let instance: EC2Instance
    let sshStore: InstanceSSHStore

    @State private var config: HealthCheckConfig = HealthCheckConfig()
    @State private var isRunning: Bool = false
    @State private var result: HealthCheckResult? = nil
    @State private var selectedInterval: HealthInterval = .manual

    private enum HealthInterval: Int, CaseIterable, Identifiable {
        case manual = 0
        case thirtyMinutes = 1800
        case oneHour = 3600
        case sixHours = 21600
        case daily = 86400

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .manual: return "Manual only"
            case .thirtyMinutes: return "Every 30 min"
            case .oneHour: return "Every hour"
            case .sixHours: return "Every 6 hours"
            case .daily: return "Daily"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // MARK: Last result
            Group {
                if let r = result ?? sshStore.lastHealthResults[instance.id] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.success ? Color.clawOk : Color.clawDanger)
                                .font(.system(size: 13))
                            Text(r.timestamp, style: .relative)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawMuted)
                            Text("ago")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawMuted)
                        }

                        Text(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.clawText)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.clawBgAccent, in: RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    Text("Never checked")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.clawMuted)
                }
            }

            // MARK: Ping Now button
            Button {
                pingNow()
            } label: {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.white)
                    } else {
                        Image(systemName: "network.badge.shield.half.filled")
                    }
                    Text(isRunning ? "Checking…" : "Ping Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.clawAccent, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .disabled(isRunning)

            Divider()
                .background(Color.clawBorder)

            // MARK: Command config
            VStack(alignment: .leading, spacing: 8) {
                Text("Health Command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
                    .textCase(.uppercase)

                TextField("e.g. uptime", text: $config.command)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.clawText)
                    .padding(10)
                    .background(Color.clawBgAccent, in: RoundedRectangle(cornerRadius: 8))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { saveConfig() }

                Text("Schedule")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
                    .textCase(.uppercase)
                    .padding(.top, 4)

                Picker("Schedule", selection: $selectedInterval) {
                    ForEach(HealthInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedInterval) { _, newVal in
                    config.intervalSeconds = newVal.rawValue
                    saveConfig()
                    if newVal.rawValue > 0 {
                        HealthCheckScheduler.scheduleNextCheck(after: newVal.rawValue)
                    }
                }
            }
        }
        .onAppear { loadConfig() }
    }

    // MARK: - Helpers

    private func loadConfig() {
        config = sshStore.loadHealthConfig(for: instance.id)
        selectedInterval = HealthInterval(rawValue: config.intervalSeconds) ?? .manual
        result = sshStore.lastHealthResults[instance.id]
    }

    private func saveConfig() {
        sshStore.saveHealthConfig(config, for: instance.id)
    }

    private func pingNow() {
        isRunning = true
        Task {
            let r = await sshStore.runHealthCheck(for: instance)
            await MainActor.run {
                result = r
                isRunning = false
            }
        }
    }
}
