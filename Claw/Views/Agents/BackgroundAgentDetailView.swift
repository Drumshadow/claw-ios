import SwiftUI

struct BackgroundAgentDetailView: View {
    let watcher: BackgroundWatcher
    @Environment(BackgroundAgentStore.self) private var store
    @State private var showDeleteAlert: Bool = false

    var body: some View {
        List {
            // Config section
            Section("Configuration") {
                LabeledContent("Type", value: watcher.triggerType.displayName)
                    .listRowBackground(Color.clawCard)
                LabeledContent("Condition", value: watcher.condition)
                    .listRowBackground(Color.clawCard)
                if let schedule = watcher.schedule {
                    LabeledContent("Schedule", value: schedule.displayLabel)
                        .listRowBackground(Color.clawCard)
                    LabeledContent("Cron", value: schedule.cronExpression)
                        .font(.system(.caption, design: .monospaced))
                        .listRowBackground(Color.clawCard)
                }
                if let agentId = watcher.assignedAgentId {
                    LabeledContent("Agent", value: agentId)
                        .listRowBackground(Color.clawCard)
                }
                LabeledContent("Remediation", value: watcher.remediationEnabled ? "Enabled" : "Disabled")
                    .listRowBackground(Color.clawCard)
            }

            // Last result
            if let result = watcher.lastResult {
                Section("Last Trigger") {
                    LabeledContent("Time", value: result.triggeredAt, format: .dateTime)
                        .listRowBackground(Color.clawCard)
                    LabeledContent("Result", value: result.conditionMet ? "Triggered" : "Clear")
                        .foregroundStyle(result.conditionMet ? Color.clawWarn : Color.clawOk)
                        .listRowBackground(Color.clawCard)
                    LabeledContent("Summary", value: result.summary)
                        .listRowBackground(Color.clawCard)
                    if let tokens = result.tokenCost {
                        LabeledContent("Token cost", value: "\(tokens) tokens")
                            .listRowBackground(Color.clawCard)
                    }
                    if let duration = result.durationMs {
                        LabeledContent("Duration", value: "\(String(format: "%.1f", Double(duration) / 1000))s")
                            .listRowBackground(Color.clawCard)
                    }
                }
            }

            // Escalation policy
            if let policy = watcher.escalationPolicy {
                Section("Escalation") {
                    LabeledContent("Push notify", value: policy.notifyOnTrigger ? "Yes" : "No")
                        .listRowBackground(Color.clawCard)
                    LabeledContent("Auto-remediate", value: policy.autoApproveRemediation ? "Yes" : "No")
                        .listRowBackground(Color.clawCard)
                    if let escalate = policy.escalateAfterMinutes {
                        LabeledContent("Escalate after", value: "\(escalate) min")
                            .listRowBackground(Color.clawCard)
                    }
                }
            }

            // Actions
            Section {
                Button {
                    Task { await store.toggleWatcher(watcher.id) }
                } label: {
                    Label(
                        watcher.isEnabled ? "Disable Watcher" : "Enable Watcher",
                        systemImage: watcher.isEnabled ? "pause.circle" : "play.circle"
                    )
                    .foregroundStyle(watcher.isEnabled ? Color.clawWarn : Color.clawOk)
                }
                .listRowBackground(Color.clawCard)

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Watcher", systemImage: "trash")
                }
                .listRowBackground(Color.clawCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .navigationTitle(watcher.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Delete Watcher?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task { await store.deleteWatcher(watcher.id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\"\(watcher.name)\" will be permanently removed.")
        }
    }
}
