import SwiftUI

struct IncidentView: View {
    let alert: OpsAlert
    let store: RemoteOpsStore

    @State private var toastVisible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                recentDeploymentsSection
                failingMonitorsSection
                affectedInstancesSection
                aiDiagnosisCard
            }
            .padding(16)
        }
        .background(Color.clawBg.ignoresSafeArea())
        .navigationTitle("Incident")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if toastVisible {
                Text("Copied to clipboard")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.clawBgAccent, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toastVisible)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: sourceIcon)
                    .font(.title3)
                    .foregroundStyle(Color.clawAccent)
                    .frame(width: 32, height: 32)
                    .background(Color.clawAccent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.clawTextStrong)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundStyle(Color.clawText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                SeverityBadge(severity: alert.severity)
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.caption)
                Text(alert.timestamp, style: .relative)
                    .font(.caption)
                Text("ago")
                    .font(.caption)

                Spacer()

                Text(alert.source.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.clawBgAccent, in: Capsule())
            }
            .foregroundStyle(Color.clawMuted)
        }
        .padding(16)
        .background(Color.clawCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(severityBorderColor, lineWidth: 1)
        )
    }

    private var recentDeploymentsSection: some View {
        let runs = recentRuns
        return Group {
            if !runs.isEmpty {
                IncidentSection(title: "Recent Deployments", icon: "arrow.triangle.branch") {
                    ForEach(runs) { run in
                        WorkflowRunRow(run: run)
                        if run.id != runs.last?.id {
                            Divider().background(Color.clawBorder)
                        }
                    }
                }
            }
        }
    }

    private var failingMonitorsSection: some View {
        let failing = store.datadogMonitors.filter { $0.overallState.lowercased() != "ok" }
        return Group {
            if !failing.isEmpty {
                IncidentSection(title: "Failing Monitors", icon: "waveform.path.ecg") {
                    ForEach(failing) { monitor in
                        MonitorRow(monitor: monitor)
                        if monitor.id != failing.last?.id {
                            Divider().background(Color.clawBorder)
                        }
                    }
                }
            }
        }
    }

    private var affectedInstancesSection: some View {
        let affected = store.ec2Instances.filter { $0.state != .running }
        return Group {
            if !affected.isEmpty {
                IncidentSection(title: "Affected Instances", icon: "server.rack") {
                    ForEach(affected) { instance in
                        InstanceRow(instance: instance)
                        if instance.id != affected.last?.id {
                            Divider().background(Color.clawBorder)
                        }
                    }
                }
            }
        }
    }

    private var aiDiagnosisCard: some View {
        Button {
            UIPasteboard.general.string = diagnosisPrompt
            showToast()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(Color.clawAccent)
                    .frame(width: 40, height: 40)
                    .background(Color.clawAccent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask AI to Diagnose")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.clawTextStrong)

                    Text("Tap to send incident context to your agent")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                }

                Spacer()

                Image(systemName: "doc.on.clipboard")
                    .font(.body)
                    .foregroundStyle(Color.clawMuted)
            }
            .padding(16)
            .background(Color.clawCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.clawBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var diagnosisPrompt: String {
        """
Incident: \(alert.title)
Source: \(alert.source.rawValue)
Message: \(alert.message)
Timestamp: \(Self.isoFormatter.string(from: alert.timestamp))

Please diagnose this incident. Check recent deployments, Datadog monitors, and EC2 instance health.
"""
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private var recentRuns: [GitHubWorkflowRun] {
        let alertSourceLower = alert.title.lowercased()
        let matchedRuns = store.workflowRuns.filter { run in
            run.repo.lowercased().contains(alertSourceLower) ||
            alertSourceLower.contains(run.repo.lowercased().split(separator: "/").last.map(String.init) ?? "")
        }
        let base = matchedRuns.isEmpty ? store.workflowRuns : matchedRuns
        return Array(base.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }.prefix(3))
    }

    private var sourceIcon: String {
        switch alert.source {
        case .datadog: return "waveform.path.ecg"
        case .github: return "arrow.triangle.branch"
        case .ec2: return "server.rack"
        }
    }

    private var severityBorderColor: Color {
        switch alert.severity {
        case .critical: return Color.clawDanger.opacity(0.6)
        case .warning: return Color.orange.opacity(0.5)
        case .info: return Color.clawBorder
        }
    }

    private func showToast() {
        withAnimation { toastVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastVisible = false }
        }
    }
}

private struct SeverityBadge: View {
    let severity: OpsAlertSeverity

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .textCase(.uppercase)
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bgColor, in: Capsule())
    }

    private var label: String {
        switch severity {
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }

    private var textColor: Color {
        switch severity {
        case .critical: return .white
        case .warning: return .black
        case .info: return Color.clawText
        }
    }

    private var bgColor: Color {
        switch severity {
        case .critical: return Color.clawDanger
        case .warning: return .yellow
        case .info: return Color.clawBgAccent
        }
    }
}

private struct IncidentSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.clawMuted)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background(Color.clawCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.clawBorder, lineWidth: 1)
            )
        }
    }
}

private struct WorkflowRunRow: View {
    let run: GitHubWorkflowRun

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(conclusionColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(run.repo)
                        .foregroundStyle(Color.clawMuted)

                    if let branch = run.headBranch {
                        Text("·")
                            .foregroundStyle(Color.clawMuted)
                        Text(branch)
                            .foregroundStyle(Color.clawMuted)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer()

            if let date = run.updatedAt {
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var conclusionColor: Color {
        switch run.conclusion {
        case "success": return .green
        case "failure": return Color.clawDanger
        case "cancelled": return .gray
        default: return .orange
        }
    }
}

private struct MonitorRow: View {
    let monitor: DatadogMonitor

    var body: some View {
        HStack(spacing: 10) {
            Text(stateLabel)
                .font(.caption2)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundStyle(stateLabelColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(stateBgColor, in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()

            Text(monitor.name)
                .font(.subheadline)
                .foregroundStyle(Color.clawTextStrong)
                .lineLimit(1)

            Spacer()

            if let date = monitor.modified {
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var stateLabel: String { monitor.overallState }

    private var stateLabelColor: Color {
        switch monitor.overallState.lowercased() {
        case "alert": return .white
        case "warn": return .black
        default: return Color.clawText
        }
    }

    private var stateBgColor: Color {
        switch monitor.overallState.lowercased() {
        case "alert": return Color.clawDanger
        case "warn": return .yellow
        default: return Color.clawBgAccent
        }
    }
}

private struct InstanceRow: View {
    let instance: EC2Instance

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.clawTextStrong)

                Text("\(instance.instanceType) · \(instance.region)")
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
            }

            Spacer()

            Text(instance.state.rawValue.capitalized)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(stateColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(stateColor.opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var stateColor: Color {
        switch instance.state {
        case .running: return .green
        case .stopped: return .gray
        case .terminated: return Color.clawDanger
        case .pending, .stopping: return .orange
        }
    }
}
