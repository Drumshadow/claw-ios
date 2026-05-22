import SwiftUI

// MARK: - RunbookDetailView
//
// Displays a runbook definition with all steps and a launch panel.
// Supports selecting execution mode and dry-run toggle before launching.

struct RunbookDetailView: View {
    let runbook: Runbook

    @Environment(RunbookStore.self) private var store: RunbookStore?

    @State private var selectedMode: RunbookExecutionMode
    @State private var isDryRun: Bool = false
    @State private var expandedStepIds: Set<UUID> = []
    @State private var isLaunching: Bool = false
    @State private var activeExecution: RunbookExecution?
    @State private var showExecution: Bool = false
    @State private var showBiometricDenied: Bool = false

    init(runbook: Runbook) {
        self.runbook = runbook
        self._selectedMode = State(initialValue: runbook.executionMode)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header card
                headerCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                // Launch panel
                launchPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Steps
                stepsSection
                    .padding(.top, 16)
            }
            .padding(.bottom, 32)
        }
        .background(Color.clawBg)
        .navigationTitle(runbook.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showExecution) {
            if let exec = activeExecution {
                RunbookExecutionView(execution: exec, store: store)
            }
        }
        .alert("Authentication Required", isPresented: $showBiometricDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Face ID or passcode authentication is required to launch this runbook in the selected environment.")
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if runbook.environment != "*" {
                        Text(runbook.environment.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(envColor(runbook.environment))
                            .tracking(1.2)
                    }
                    Text(runbook.description.isEmpty ? runbook.name : runbook.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.clawMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Divider().background(Color.clawBorder)

            // Metadata grid
            HStack(spacing: 0) {
                metaCell(label: "Steps", value: "\(runbook.steps.count)", icon: "list.number")
                Divider().frame(height: 28).background(Color.clawBorder)
                metaCell(label: "Est. Time", value: runbook.formattedDuration, icon: "clock")
                Divider().frame(height: 28).background(Color.clawBorder)
                metaCell(label: "Version", value: "v\(runbook.version)", icon: "tag")
                if runbook.dangerStepCount > 0 {
                    Divider().frame(height: 28).background(Color.clawBorder)
                    metaCell(label: "Danger", value: "\(runbook.dangerStepCount)", icon: "exclamationmark.triangle", valueColor: Color.clawWarn)
                }
            }

            // Tags
            if !runbook.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(runbook.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.clawMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.clawBgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.clawCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func metaCell(label: String, value: String, icon: String, valueColor: Color = .clawText) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.clawMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Launch panel

    private var launchPanel: some View {
        VStack(spacing: 14) {
            // Mode selector
            VStack(alignment: .leading, spacing: 8) {
                Text("EXECUTION MODE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.clawMuted)
                    .tracking(1.0)

                HStack(spacing: 8) {
                    ForEach(RunbookExecutionMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.2)) { selectedMode = mode }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(mode.displayLabel)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(selectedMode == mode ? Color.clawBg : Color.clawText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedMode == mode ? Color.clawAccent : Color.clawBgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Dry run toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dry Run")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.clawText)
                    Text("Simulate execution without making changes")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                }
                Spacer()
                Toggle("", isOn: $isDryRun)
                    .tint(Color.clawTeal)
            }
            .padding(12)
            .background(Color.clawBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Launch button
            Button {
                Task { await launchRunbook() }
            } label: {
                HStack(spacing: 8) {
                    if isLaunching {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.white)
                    } else {
                        Image(systemName: isDryRun ? "eye.fill" : "play.fill")
                    }
                    Text(isDryRun ? "Run Dry Run" : "Launch Runbook")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isDryRun ? Color.clawTeal : (runbook.dangerStepCount > 0 ? Color.clawDanger : Color.clawAccent)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLaunching)
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.clawCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    // MARK: - Steps section

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("STEPS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.clawMuted)
                    .tracking(1.2)
                    .padding(.horizontal, 16)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        if expandedStepIds.isEmpty {
                            expandedStepIds = Set(runbook.steps.map { $0.id })
                        } else {
                            expandedStepIds.removeAll()
                        }
                    }
                } label: {
                    Text(expandedStepIds.isEmpty ? "Expand All" : "Collapse All")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawAccent)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(runbook.steps.enumerated()), id: \.element.id) { index, step in
                    RunbookStepDefinitionRow(
                        step: step,
                        index: index,
                        totalSteps: runbook.steps.count,
                        mode: selectedMode,
                        isExpanded: expandedStepIds.contains(step.id)
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            if expandedStepIds.contains(step.id) {
                                expandedStepIds.remove(step.id)
                            } else {
                                expandedStepIds.insert(step.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Launch

    private func launchRunbook() async {
        // Require biometric for production danger+ runbooks in non-dry-run mode
        let hasDanger = runbook.dangerStepCount > 0
        let isProd = runbook.environment == "production"
        let needsBiometric = hasDanger && isProd && !isDryRun

        if needsBiometric {
            let ok = await BiometricGuard.shared.authenticate(
                reason: "Authenticate to launch "\(runbook.name)" in production"
            )
            guard ok else {
                showBiometricDenied = true
                return
            }
        }

        isLaunching = true
        defer { isLaunching = false }

        do {
            let useStore = store ?? RunbookStore()
            let exec = try await useStore.execute(
                runbook: runbook,
                mode: selectedMode,
                isDryRun: isDryRun
            )
            activeExecution = exec
            showExecution = true
        } catch {
            // Error surfaced in execution view
        }
    }

    private func envColor(_ env: String) -> Color {
        switch env {
        case "production": return Color.clawDanger
        case "staging":    return Color.clawWarn
        case "dev":        return Color.clawOk
        default:           return Color.clawMuted
        }
    }
}

// MARK: - RunbookStepDefinitionRow
//
// Collapsible step card showing definition (not live execution state).

struct RunbookStepDefinitionRow: View {
    let step: RunbookStep
    let index: Int
    let totalSteps: Int
    let mode: RunbookExecutionMode
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Connector line
            if index > 0 {
                Rectangle()
                    .fill(Color.clawBorder)
                    .frame(width: 2, height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 21)
            }

            // Step card
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        // Step number bubble
                        ZStack {
                            Circle()
                                .fill(step.risk.stepBubbleBackground)
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(step.risk.stepBubbleForeground)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.clawTextStrong)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 8) {
                                riskBadge
                                if step.requiresApproval(mode: mode) {
                                    approvalBadge
                                }
                                if step.canRollback {
                                    rollbackBadge
                                }
                                if step.checkpointAfter {
                                    checkpointBadge
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.clawMuted)
                    }
                    .padding(12)

                    // Expanded content
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            Divider().background(Color.clawBorder).padding(.horizontal, 12)

                            VStack(alignment: .leading, spacing: 6) {
                                if !step.description.isEmpty {
                                    Text(step.description)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.clawMuted)
                                        .padding(.horizontal, 12)
                                }

                                // Command block
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("COMMAND")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.clawMuted)
                                        .tracking(1.0)
                                    Text(step.command)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.clawTeal)
                                        .textSelection(.enabled)
                                }
                                .padding(10)
                                .background(Color(UIColor(hex: 0x0a0c0f)))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 12)

                                // Rollback command
                                if step.canRollback, let rollback = step.rollbackCommand {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("ROLLBACK")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color.clawWarn)
                                            .tracking(1.0)
                                        Text(rollback)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Color.clawWarn)
                                            .textSelection(.enabled)
                                    }
                                    .padding(10)
                                    .background(Color.clawWarn.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal, 12)
                                }

                                // Metadata chips
                                HStack(spacing: 8) {
                                    if step.timeoutSeconds > 0 {
                                        chip("Timeout \(step.timeoutSeconds)s", systemImage: "clock", color: .clawMuted)
                                    }
                                    if step.retryCount > 0 {
                                        chip("Retry ×\(step.retryCount)", systemImage: "arrow.clockwise", color: .clawMuted)
                                    }
                                    if let expected = step.expectedOutput {
                                        chip("Expects: \(expected)", systemImage: "checkmark.seal", color: .clawTeal)
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                            .padding(.bottom, 12)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .background(Color.clawCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(step.risk.stepBorderColor, lineWidth: 1)
            )
        }
    }

    private var riskBadge: some View {
        Text(step.risk.displayLabel)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(step.risk.badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(step.risk.badgeColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var approvalBadge: some View {
        Label("Approval", systemImage: "hand.raised.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.clawWarn)
            .labelStyle(.iconOnly)
    }

    private var rollbackBadge: some View {
        Label("Rollback", systemImage: "arrow.uturn.backward")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.clawTeal)
            .labelStyle(.iconOnly)
    }

    private var checkpointBadge: some View {
        Label("Checkpoint", systemImage: "flag.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.clawAccent)
            .labelStyle(.iconOnly)
    }

    private func chip(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - RiskLevel display helpers

private extension RiskLevel {
    var stepBubbleBackground: Color {
        switch self {
        case .info:     return Color.clawOk.opacity(0.14)
        case .caution:  return Color.clawWarn.opacity(0.14)
        case .danger:   return Color.clawDanger.opacity(0.14)
        case .critical: return Color.clawDanger.opacity(0.22)
        }
    }

    var stepBubbleForeground: Color {
        switch self {
        case .info:     return Color.clawOk
        case .caution:  return Color.clawWarn
        case .danger:   return Color.clawDanger
        case .critical: return Color.clawDanger
        }
    }

    var stepBorderColor: Color {
        switch self {
        case .info:     return Color.clawBorder
        case .caution:  return Color.clawWarn.opacity(0.2)
        case .danger:   return Color.clawDanger.opacity(0.25)
        case .critical: return Color.clawDanger.opacity(0.4)
        }
    }

    var badgeColor: Color {
        switch self {
        case .info:     return Color.clawOk
        case .caution:  return Color.clawWarn
        case .danger:   return Color.clawDanger
        case .critical: return Color.clawDanger
        }
    }
}

// MARK: - Previews

#Preview("Runbook Detail") {
    NavigationStack {
        RunbookDetailView(runbook: Runbook.restartAPIService)
    }
    .preferredColorScheme(.dark)
}

#Preview("Rollback Runbook") {
    NavigationStack {
        RunbookDetailView(runbook: Runbook.rollbackDeployment)
    }
    .preferredColorScheme(.dark)
}
