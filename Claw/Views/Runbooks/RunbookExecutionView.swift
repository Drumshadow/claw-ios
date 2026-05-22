import SwiftUI

// MARK: - RunbookExecutionView
//
// Live execution progress view — shows each step with status indicators,
// streaming log output, approval gates, rollback controls, and overall progress.

struct RunbookExecutionView: View {
    @State var execution: RunbookExecution
    let store: RunbookStore?

    @State private var expandedStepIds: Set<UUID> = []
    @State private var showAbortAlert: Bool = false
    @State private var showRollbackAlert: Bool = false
    @State private var rollbackStepId: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Progress header
                    progressHeader

                    // Overall status banner
                    if execution.status.isTerminal {
                        completionBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    // Steps
                    VStack(spacing: 0) {
                        ForEach(Array(execution.runbook.steps.enumerated()), id: \.element.id) { index, step in
                            if let stepExec = execution.stepExecution(for: step.id) {
                                executionStepRow(
                                    step: step,
                                    stepExec: stepExec,
                                    index: index
                                )
                                .id(step.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .onChange(of: execution.currentStepIndex) { _, newIdx in
                if newIdx < execution.runbook.steps.count {
                    let stepId = execution.runbook.steps[newIdx].id
                    withAnimation { proxy.scrollTo(stepId, anchor: .center) }
                }
            }
        }
        .background(Color.clawBg)
        .navigationTitle(execution.isDryRun ? "Dry Run — \(execution.runbook.name)" : execution.runbook.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .alert("Abort Runbook?", isPresented: $showAbortAlert) {
            Button("Abort", role: .destructive) {
                Task { try? await store?.abort(executionId: execution.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The running step will be interrupted. Any completed steps will not be rolled back automatically.")
        }
        .alert("Rollback Step?", isPresented: $showRollbackAlert) {
            Button("Rollback", role: .destructive) {
                if let stepId = rollbackStepId {
                    Task { try? await store?.rollback(executionId: execution.id, stepId: stepId) }
                }
                rollbackStepId = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The rollback command for this step will be executed.")
        }
    }

    // MARK: - Progress header

    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Overall progress ring
                ZStack {
                    Circle()
                        .stroke(Color.clawBorder, lineWidth: 4)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: execution.progress)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: execution.progress)
                    Text("\(Int(execution.progress * 100))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(progressColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        statusIndicator
                        Text(execution.status.displayLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.clawTextStrong)

                        if execution.isDryRun {
                            Text("DRY RUN")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.clawTeal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.clawTeal.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Text("\(execution.completedStepCount)/\(execution.runbook.steps.count) steps")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.clawMuted)

                        if let dur = execution.duration {
                            Text(formatDuration(dur))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.clawMuted)
                        }
                    }
                }

                Spacer()

                Text(execution.mode.displayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.clawBgElevated)
                    .clipShape(Capsule())
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.clawBorder)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geo.size.width * execution.progress, height: 4)
                        .animation(.easeInOut(duration: 0.4), value: execution.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(16)
        .background(Color.clawCard)
        .overlay(
            Rectangle()
                .fill(Color.clawBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch execution.status {
        case .running:
            ProgressView()
                .scaleEffect(0.7)
                .tint(Color.clawAccent)
        case .completed, .dryRunComplete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.clawOk)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.clawDanger)
                .font(.system(size: 14))
        case .aborted:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(Color.clawWarn)
                .font(.system(size: 14))
        default:
            Image(systemName: "clock.fill")
                .foregroundStyle(Color.clawMuted)
                .font(.system(size: 14))
        }
    }

    private var progressColor: Color {
        switch execution.status {
        case .completed, .dryRunComplete: return Color.clawOk
        case .failed:                     return Color.clawDanger
        case .aborted:                    return Color.clawWarn
        default:                          return Color.clawAccent
        }
    }

    // MARK: - Completion banner

    @ViewBuilder
    private var completionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: execution.status == .completed || execution.status == .dryRunComplete
                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(execution.status == .completed || execution.status == .dryRunComplete
                                 ? Color.clawOk : Color.clawDanger)

            VStack(alignment: .leading, spacing: 2) {
                Text(execution.status.displayLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                if let err = execution.errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawDanger)
                }
                if let dur = execution.duration {
                    Text("Completed in \(formatDuration(dur))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            (execution.status == .completed || execution.status == .dryRunComplete
             ? Color.clawOk : Color.clawDanger).opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    (execution.status == .completed || execution.status == .dryRunComplete
                     ? Color.clawOk : Color.clawDanger).opacity(0.25),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Step row

    @ViewBuilder
    private func executionStepRow(
        step: RunbookStep,
        stepExec: RunbookStepExecution,
        index: Int
    ) -> some View {
        VStack(spacing: 0) {
            // Connector line
            if index > 0 {
                Rectangle()
                    .fill(connectorColor(for: stepExec))
                    .frame(width: 2, height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 21)
            }

            RunbookLiveStepRow(
                step: step,
                stepExec: stepExec,
                index: index,
                executionId: execution.id,
                mode: execution.mode,
                isDryRun: execution.isDryRun,
                isExpanded: expandedStepIds.contains(step.id),
                onToggle: {
                    withAnimation(.spring(response: 0.3)) {
                        if expandedStepIds.contains(step.id) {
                            expandedStepIds.remove(step.id)
                        } else {
                            expandedStepIds.insert(step.id)
                        }
                    }
                },
                onApprove: {
                    Task { try? await store?.approveStep(executionId: execution.id, stepId: step.id) }
                },
                onDeny: {
                    Task { try? await store?.denyStep(executionId: execution.id, stepId: step.id, reason: "Denied by user") }
                },
                onRollback: {
                    rollbackStepId = step.id
                    showRollbackAlert = true
                }
            )
        }
        .onChange(of: stepExec.status) { _, newStatus in
            // Auto-expand the running or awaiting-approval step
            if newStatus == .running || newStatus == .awaitingApproval {
                expandedStepIds.insert(step.id)
            }
        }
    }

    private func connectorColor(for stepExec: RunbookStepExecution) -> Color {
        switch stepExec.status {
        case .completed, .dryRun: return Color.clawOk.opacity(0.5)
        case .failed:             return Color.clawDanger.opacity(0.5)
        case .skipped:            return Color.clawMuted.opacity(0.3)
        default:                  return Color.clawBorder
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if execution.status == .running {
                Button(role: .destructive) {
                    showAbortAlert = true
                } label: {
                    Label("Abort", systemImage: "stop.circle")
                        .foregroundStyle(Color.clawDanger)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ d: TimeInterval) -> String {
        let s = Int(d)
        let m = s / 60
        if m > 0 { return "\(m)m \(s % 60)s" }
        return "\(s)s"
    }
}

// MARK: - RunbookLiveStepRow

struct RunbookLiveStepRow: View {
    let step: RunbookStep
    @Bindable var stepExec: RunbookStepExecution
    let index: Int
    let executionId: String
    let mode: RunbookExecutionMode
    let isDryRun: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onRollback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    statusBubble
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(step.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(headerTextColor)
                                .multilineTextAlignment(.leading)
                        }
                        HStack(spacing: 8) {
                            riskPill
                            if let dur = stepExec.formattedDuration {
                                Text(dur)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.clawMuted)
                            }
                            if let code = stepExec.exitCode {
                                Text("exit \(code)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(code == 0 ? Color.clawOk : Color.clawDanger)
                            }
                        }
                    }
                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            // Expanded area
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(Color.clawBorder).padding(.horizontal, 12)

                    // Approval gate
                    if stepExec.status == .awaitingApproval {
                        approvalGate
                            .padding(.horizontal, 12)
                    }

                    // Error message
                    if let err = stepExec.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.clawDanger)
                                .font(.system(size: 12))
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clawDanger)
                        }
                        .padding(10)
                        .background(Color.clawDanger.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)
                    }

                    // Output log
                    if !stepExec.outputLines.isEmpty {
                        outputBlock
                    }

                    // Rollback button (completed or failed with rollback available)
                    if step.canRollback && stepExec.status.isTerminal && stepExec.status != .rolledBack {
                        Button(action: onRollback) {
                            Label("Rollback This Step", systemImage: "arrow.uturn.backward")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.clawWarn)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(stepBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(stepBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Status bubble

    @ViewBuilder
    private var statusBubble: some View {
        ZStack {
            Circle()
                .fill(bubbleBackground)
                .frame(width: 28, height: 28)
            Group {
                switch stepExec.status {
                case .running:
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(Color.clawAccent)
                case .awaitingApproval:
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.clawWarn)
                default:
                    Image(systemName: stepExec.status.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(bubbleForeground)
                }
            }
        }
    }

    // MARK: - Approval gate

    private var approvalGate: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Color.clawWarn)
                    .font(.system(size: 13))
                Text("Step requires approval")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.clawWarn)
            }

            // Command preview
            Text(step.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.clawTeal)
                .padding(8)
                .background(Color(UIColor(hex: 0x0a0c0f)))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 10) {
                Button(action: onDeny) {
                    Label("Deny", systemImage: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.clawDanger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.clawDanger.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.clawOk)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.clawWarn.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.clawWarn.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Output block

    private var outputBlock: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(stepExec.outputLines.suffix(50).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(UIColor(hex: 0xd4d4d8)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 160)
        .background(Color(UIColor(hex: 0x0a0c0f)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    // MARK: - Color helpers

    private var riskPill: some View {
        Text(step.risk.displayLabel)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(step.risk.badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(step.risk.badgeColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var bubbleBackground: Color {
        switch stepExec.status {
        case .pending:          return Color.clawBgElevated
        case .running:          return Color.clawAccent.opacity(0.14)
        case .completed, .dryRun: return Color.clawOk.opacity(0.14)
        case .failed:           return Color.clawDanger.opacity(0.14)
        case .skipped:          return Color.clawMuted.opacity(0.1)
        case .awaitingApproval: return Color.clawWarn.opacity(0.14)
        case .rolledBack:       return Color.clawTeal.opacity(0.14)
        }
    }

    private var bubbleForeground: Color {
        switch stepExec.status {
        case .pending:          return Color.clawMuted
        case .running:          return Color.clawAccent
        case .completed, .dryRun: return Color.clawOk
        case .failed:           return Color.clawDanger
        case .skipped:          return Color.clawMuted
        case .awaitingApproval: return Color.clawWarn
        case .rolledBack:       return Color.clawTeal
        }
    }

    private var headerTextColor: Color {
        switch stepExec.status {
        case .pending: return Color.clawMuted
        case .failed:  return Color.clawDanger
        default:       return Color.clawTextStrong
        }
    }

    private var stepBackgroundColor: Color {
        switch stepExec.status {
        case .running:          return Color.clawAccent.opacity(0.04)
        case .awaitingApproval: return Color.clawWarn.opacity(0.04)
        case .failed:           return Color.clawDanger.opacity(0.04)
        default:                return Color.clawCard
        }
    }

    private var stepBorderColor: Color {
        switch stepExec.status {
        case .running:          return Color.clawAccent.opacity(0.3)
        case .awaitingApproval: return Color.clawWarn.opacity(0.35)
        case .completed, .dryRun: return Color.clawOk.opacity(0.2)
        case .failed:           return Color.clawDanger.opacity(0.3)
        default:                return Color.clawBorder
        }
    }
}

private extension RiskLevel {
    var badgeColor: Color {
        switch self {
        case .info:     return Color.clawOk
        case .caution:  return Color.clawWarn
        case .danger:   return Color.clawDanger
        case .critical: return Color.clawDanger
        }
    }
}

// MARK: - Preview

#Preview("Runbook Execution") {
    let store = RunbookStore()
    let execution = RunbookExecution(
        id: "exec-preview",
        runbook: Runbook.restartAPIService,
        mode: .semiAutonomous,
        isDryRun: false
    )
    execution.startedAt = Date()
    execution.status = .running
    // Pre-seed some state
    execution.stepExecutions[0].status = .completed
    execution.stepExecutions[0].exitCode = 0
    execution.stepExecutions[1].status = .completed
    execution.stepExecutions[1].exitCode = 0
    execution.stepExecutions[2].status = .awaitingApproval

    return NavigationStack {
        RunbookExecutionView(execution: execution, store: store)
    }
    .preferredColorScheme(.dark)
}
