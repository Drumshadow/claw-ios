import SwiftUI

struct GitHubActionsView: View {
    let store: RemoteOpsStore
    var onShowMonitors: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    private var runsByRepo: [(repo: String, runs: [GitHubWorkflowRun])] {
        var dict: [String: [GitHubWorkflowRun]] = [:]
        for run in store.workflowRuns {
            dict[run.repo, default: []].append(run)
        }
        return dict.keys.sorted().map { repo in
            (repo: repo, runs: dict[repo]!)
        }
    }

    private var recentFailureCount: Int {
        let cutoff = Date().addingTimeInterval(-86400)
        return store.workflowRuns.filter {
            $0.conclusion == "failure" && ($0.updatedAt ?? .distantPast) >= cutoff
        }.count
    }

    var body: some View {
        Group {
            if store.credentials.githubToken == nil {
                emptyTokenState
            } else {
                contentView
            }
        }
        .background(Color.clawBg.ignoresSafeArea())
    }

    private var emptyTokenState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.clawMuted)
            Text("Configure GitHub token in Settings")
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        List {
            if recentFailureCount > 0 {
                Section {
                    failureBanner
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clawCard)
            }

            ForEach(runsByRepo, id: \.repo) { group in
                Section(group.repo) {
                    ForEach(group.runs) { run in
                        Button {
                            if let url = URL(string: run.htmlUrl) { openURL(url) }
                        } label: {
                            WorkflowRunRow(run: run)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .refreshable {
            await store.refresh()
        }
    }

    private var failureBanner: some View {
        Button {
            onShowMonitors?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.clawDanger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(recentFailureCount) deployment\(recentFailureCount == 1 ? "" : "s") failed in the last 24h")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.clawTextStrong)
                    Text("Tap to correlate with Datadog")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                }
                Spacer()
                if onShowMonitors != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                }
            }
            .padding(12)
            .background(Color.clawDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(onShowMonitors == nil)
    }
}

private struct WorkflowRunRow: View {
    let run: GitHubWorkflowRun

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(conclusionColor)

                HStack(spacing: 4) {
                    if let branch = run.headBranch {
                        Text(branch)
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                    }
                    if let msg = run.headCommitMessage {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let date = run.updatedAt {
                Text(relativeTime(from: date))
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clawCard)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch run.status {
        case "in_progress":
            ProgressView()
                .tint(Color.clawAccent)
                .scaleEffect(0.85)
        case "completed":
            switch run.conclusion {
            case "success":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            case "failure":
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.clawDanger)
            case "cancelled":
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.clawMuted)
            default:
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.clawMuted)
            }
        default:
            Image(systemName: "clock.fill")
                .foregroundStyle(Color.clawMuted)
        }
    }

    private var conclusionColor: Color {
        switch run.status {
        case "in_progress": return Color.clawAccent
        case "completed":
            switch run.conclusion {
            case "success": return Color.clawTextStrong
            case "failure": return Color.clawDanger
            default: return Color.clawMuted
            }
        default: return Color.clawMuted
        }
    }
}

private func relativeTime(from date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}
