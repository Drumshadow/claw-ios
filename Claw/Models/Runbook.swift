import Foundation

// MARK: - Runbook Execution Mode

enum RunbookExecutionMode: String, Codable, CaseIterable, Equatable {
    /// User must approve every step before it runs.
    case manual = "manual"
    /// Steps with risk ≥ .danger require user approval; info/caution run automatically.
    case semiAutonomous = "semi_autonomous"
    /// All steps run automatically; only .critical steps get a biometric gate.
    case autonomous = "autonomous"

    var displayLabel: String {
        switch self {
        case .manual:         return "Manual"
        case .semiAutonomous: return "Semi-Auto"
        case .autonomous:     return "Autonomous"
        }
    }

    var icon: String {
        switch self {
        case .manual:         return "hand.tap"
        case .semiAutonomous: return "cpu"
        case .autonomous:     return "bolt.fill"
        }
    }
}

// MARK: - RunbookStepStatus

enum RunbookStepStatus: String, Codable, Equatable {
    case pending          // not yet started
    case running          // currently executing
    case completed        // exited 0
    case failed           // exited non-zero or timed out
    case skipped          // user skipped or auto-skipped
    case awaitingApproval // waiting for user action
    case rolledBack       // rollback command executed
    case dryRun           // executed in dry-run mode (no side effects)

    var displayLabel: String {
        switch self {
        case .pending:          return "Pending"
        case .running:          return "Running"
        case .completed:        return "Done"
        case .failed:           return "Failed"
        case .skipped:          return "Skipped"
        case .awaitingApproval: return "Waiting"
        case .rolledBack:       return "Rolled Back"
        case .dryRun:           return "Dry Run"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:          return "circle"
        case .running:          return "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed:        return "checkmark.circle.fill"
        case .failed:           return "xmark.circle.fill"
        case .skipped:          return "minus.circle.fill"
        case .awaitingApproval: return "clock.fill"
        case .rolledBack:       return "arrow.uturn.backward.circle.fill"
        case .dryRun:           return "eye.circle.fill"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .skipped, .rolledBack, .dryRun: return true
        default: return false
        }
    }
}

// MARK: - RunbookExecutionStatus

enum RunbookExecutionStatus: String, Codable, Equatable {
    case notStarted
    case running
    case completed
    case failed
    case aborted
    case dryRunComplete

    var displayLabel: String {
        switch self {
        case .notStarted:    return "Ready"
        case .running:       return "Running"
        case .completed:     return "Complete"
        case .failed:        return "Failed"
        case .aborted:       return "Aborted"
        case .dryRunComplete: return "Dry Run Done"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .aborted, .dryRunComplete: return true
        default: return false
        }
    }
}

// MARK: - RunbookStep

/// A single step within a runbook definition.
struct RunbookStep: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var command: String             // shell command / API call to execute
    var risk: RiskLevel
    var timeoutSeconds: Int         // 0 = no timeout
    var retryCount: Int             // 0 = no retries
    var canRollback: Bool
    var rollbackCommand: String?    // command to undo this step
    var checkpointAfter: Bool       // pause for verification after step completes
    var expectedOutput: String?     // optional regex/pattern to validate output
    var annotations: [String: String] // arbitrary metadata (e.g., "docs": "https://...")
    var environment: String         // "production", "staging", "dev", "*"

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        command: String,
        risk: RiskLevel = .caution,
        timeoutSeconds: Int = 300,
        retryCount: Int = 0,
        canRollback: Bool = false,
        rollbackCommand: String? = nil,
        checkpointAfter: Bool = false,
        expectedOutput: String? = nil,
        annotations: [String: String] = [:],
        environment: String = "*"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.command = command
        self.risk = risk
        self.timeoutSeconds = timeoutSeconds
        self.retryCount = retryCount
        self.canRollback = canRollback
        self.rollbackCommand = rollbackCommand
        self.checkpointAfter = checkpointAfter
        self.expectedOutput = expectedOutput
        self.annotations = annotations
        self.environment = environment
    }

    /// Whether this step requires approval in the given execution mode.
    func requiresApproval(mode: RunbookExecutionMode) -> Bool {
        switch mode {
        case .manual:         return true
        case .semiAutonomous: return risk >= .danger
        case .autonomous:     return risk == .critical
        }
    }
}

// MARK: - Runbook

/// A reusable runbook definition — a named sequence of steps with metadata.
struct Runbook: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var environment: String         // "production", "staging", "dev", "*"
    var executionMode: RunbookExecutionMode
    var steps: [RunbookStep]
    var tags: [String]
    var estimatedDurationSeconds: Int
    var createdAt: Date
    var updatedAt: Date
    var isEnabled: Bool
    var version: String             // "1.0.0" semver

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        environment: String = "*",
        executionMode: RunbookExecutionMode = .manual,
        steps: [RunbookStep] = [],
        tags: [String] = [],
        estimatedDurationSeconds: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isEnabled: Bool = true,
        version: String = "1.0.0"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.environment = environment
        self.executionMode = executionMode
        self.steps = steps
        self.tags = tags
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEnabled = isEnabled
        self.version = version
    }

    var formattedDuration: String {
        if estimatedDurationSeconds == 0 { return "unknown" }
        let mins = estimatedDurationSeconds / 60
        let secs = estimatedDurationSeconds % 60
        if mins > 0 && secs > 0 { return "~\(mins)m \(secs)s" }
        if mins > 0 { return "~\(mins)m" }
        return "~\(secs)s"
    }

    var dangerStepCount: Int {
        steps.filter { $0.risk >= .danger }.count
    }
}

// MARK: - RunbookStepExecution (live execution state per step)

/// Tracks execution state for a single step within a RunbookExecution.
/// Uses @Observable (iOS 17+) so SwiftUI views watching RunbookExecution update reactively.
@Observable
final class RunbookStepExecution: Identifiable {
    let id: UUID                // matches RunbookStep.id
    var stepIndex: Int
    var status: RunbookStepStatus = .pending
    var outputLines: [String] = []
    var startedAt: Date?
    var completedAt: Date?
    var exitCode: Int?
    var errorMessage: String?
    var retryAttempt: Int = 0

    init(id: UUID, stepIndex: Int) {
        self.id = id
        self.stepIndex = stepIndex
    }

    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    var formattedDuration: String? {
        guard let d = duration else { return nil }
        if d < 1 { return "<1s" }
        let secs = Int(d)
        let mins = secs / 60
        if mins > 0 { return "\(mins)m \(secs % 60)s" }
        return "\(secs)s"
    }
}

// MARK: - RunbookExecution

/// Live or historical runbook execution. Created when the user executes a runbook.
@Observable
@MainActor
final class RunbookExecution: Identifiable {
    let id: String              // gateway-assigned execution ID
    let runbook: Runbook
    var mode: RunbookExecutionMode
    var isDryRun: Bool
    var status: RunbookExecutionStatus = .notStarted
    var stepExecutions: [RunbookStepExecution]
    var currentStepIndex: Int = 0
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?

    init(id: String, runbook: Runbook, mode: RunbookExecutionMode, isDryRun: Bool = false) {
        self.id = id
        self.runbook = runbook
        self.mode = mode
        self.isDryRun = isDryRun
        self.stepExecutions = runbook.steps.enumerated().map { index, step in
            RunbookStepExecution(id: step.id, stepIndex: index)
        }
    }

    var currentStep: RunbookStepExecution? {
        guard currentStepIndex < stepExecutions.count else { return nil }
        return stepExecutions[currentStepIndex]
    }

    var completedStepCount: Int {
        stepExecutions.filter { $0.status == .completed || $0.status == .dryRun }.count
    }

    var progress: Double {
        guard !stepExecutions.isEmpty else { return 0 }
        return Double(completedStepCount) / Double(stepExecutions.count)
    }

    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    func stepExecution(for stepId: UUID) -> RunbookStepExecution? {
        stepExecutions.first { $0.id == stepId }
    }

    func appendOutput(stepId: UUID, line: String) {
        stepExecution(for: stepId)?.outputLines.append(line)
    }
}

// MARK: - Sample Runbook Definitions

extension Runbook {
    // MARK: Restart API Service
    static let restartAPIService = Runbook(
        id: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
        name: "Restart API Service",
        description: "Gracefully restarts the API service across all production replicas with health verification.",
        environment: "production",
        executionMode: .semiAutonomous,
        steps: [
            RunbookStep(
                name: "Check current status",
                description: "Verify replica count and health before restart.",
                command: "kubectl get pods -n api -l app=api-service",
                risk: .info,
                timeoutSeconds: 30,
                annotations: ["docs": "kubectl-get-pods"]
            ),
            RunbookStep(
                name: "Check active connections",
                description: "Ensure no long-running requests that would be dropped.",
                command: "kubectl exec -n api $(kubectl get pod -n api -l app=api-service -o name | head -1) -- curl -s localhost:9090/metrics | grep active_connections",
                risk: .info,
                timeoutSeconds: 15
            ),
            RunbookStep(
                name: "Trigger rolling restart",
                description: "Issue a rolling restart — Kubernetes will replace pods one at a time.",
                command: "kubectl rollout restart deployment/api-service -n api",
                risk: .caution,
                timeoutSeconds: 60,
                canRollback: true,
                rollbackCommand: "kubectl rollout undo deployment/api-service -n api"
            ),
            RunbookStep(
                name: "Wait for rollout",
                description: "Block until all new pods are running and ready.",
                command: "kubectl rollout status deployment/api-service -n api --timeout=5m",
                risk: .info,
                timeoutSeconds: 360,
                checkpointAfter: false
            ),
            RunbookStep(
                name: "Verify health",
                description: "Hit the health endpoint on each pod and confirm 200 OK.",
                command: "for pod in $(kubectl get pods -n api -l app=api-service -o name); do kubectl exec -n api $pod -- curl -sf http://localhost:3000/health; done",
                risk: .info,
                timeoutSeconds: 60,
                checkpointAfter: true,
                expectedOutput: "ok"
            ),
        ],
        tags: ["kubernetes", "api", "restart"],
        estimatedDurationSeconds: 480,
        version: "2.1.0"
    )

    // MARK: Rollback Deployment
    static let rollbackDeployment = Runbook(
        id: UUID(uuidString: "00000001-0000-0000-0000-000000000002")!,
        name: "Rollback Deployment",
        description: "Roll back the API service to the previous stable release. Requires explicit approval at each destructive step.",
        environment: "production",
        executionMode: .manual,
        steps: [
            RunbookStep(
                name: "Get rollout history",
                description: "List the last 5 deployment revisions.",
                command: "kubectl rollout history deployment/api-service -n api",
                risk: .info,
                timeoutSeconds: 15
            ),
            RunbookStep(
                name: "Confirm target revision",
                description: "Identify which revision to roll back to.",
                command: "kubectl rollout history deployment/api-service -n api --revision=0",
                risk: .info,
                timeoutSeconds: 15,
                checkpointAfter: true,
                annotations: ["note": "Check revision details before proceeding"]
            ),
            RunbookStep(
                name: "Scale down traffic",
                description: "Remove the deployment from the load balancer before rollback.",
                command: "kubectl patch service api-service -n api -p '{\"spec\":{\"selector\":{\"version\":\"canary\"}}}'",
                risk: .danger,
                timeoutSeconds: 30,
                canRollback: true,
                rollbackCommand: "kubectl patch service api-service -n api -p '{\"spec\":{\"selector\":{\"app\":\"api-service\"}}}'"
            ),
            RunbookStep(
                name: "Execute rollback",
                description: "Roll back to the previous revision.",
                command: "kubectl rollout undo deployment/api-service -n api",
                risk: .danger,
                timeoutSeconds: 120,
                canRollback: false,
                checkpointAfter: false
            ),
            RunbookStep(
                name: "Wait for rollout",
                description: "Wait until rollback pods are healthy.",
                command: "kubectl rollout status deployment/api-service -n api --timeout=5m",
                risk: .info,
                timeoutSeconds: 360
            ),
            RunbookStep(
                name: "Restore traffic",
                description: "Point the load balancer back at the rolled-back pods.",
                command: "kubectl patch service api-service -n api -p '{\"spec\":{\"selector\":{\"app\":\"api-service\"}}}'",
                risk: .caution,
                timeoutSeconds: 30,
                checkpointAfter: true
            ),
            RunbookStep(
                name: "Smoke test",
                description: "Run critical path smoke tests against production.",
                command: "npm run smoke:prod",
                risk: .info,
                timeoutSeconds: 120,
                expectedOutput: "All tests passed"
            ),
        ],
        tags: ["kubernetes", "rollback", "deployment", "production"],
        estimatedDurationSeconds: 900,
        version: "1.3.0"
    )

    // MARK: Investigate Unhealthy Container
    static let investigateUnhealthyContainer = Runbook(
        id: UUID(uuidString: "00000001-0000-0000-0000-000000000003")!,
        name: "Investigate Unhealthy Container",
        description: "Collect diagnostics from a crashing or unhealthy container — logs, resource usage, events.",
        environment: "*",
        executionMode: .autonomous,
        steps: [
            RunbookStep(
                name: "List unhealthy pods",
                description: "Show all pods not in Running/Completed state.",
                command: "kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded",
                risk: .info,
                timeoutSeconds: 15
            ),
            RunbookStep(
                name: "Describe failing pod",
                description: "Fetch full pod description including events.",
                command: "kubectl describe pod $POD_NAME -n $NAMESPACE",
                risk: .info,
                timeoutSeconds: 15
            ),
            RunbookStep(
                name: "Fetch recent logs",
                description: "Last 200 lines of container logs.",
                command: "kubectl logs $POD_NAME -n $NAMESPACE --tail=200 --previous",
                risk: .info,
                timeoutSeconds: 30
            ),
            RunbookStep(
                name: "Check resource usage",
                description: "Current CPU/memory consumption.",
                command: "kubectl top pod $POD_NAME -n $NAMESPACE",
                risk: .info,
                timeoutSeconds: 15
            ),
            RunbookStep(
                name: "List recent events",
                description: "Kubernetes events in the namespace (last 30 min).",
                command: "kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -30",
                risk: .info,
                timeoutSeconds: 15,
                checkpointAfter: true,
                annotations: ["note": "Review events before deciding remediation"]
            ),
        ],
        tags: ["kubernetes", "debug", "ops", "investigation"],
        estimatedDurationSeconds: 120,
        version: "1.0.0"
    )

    // MARK: All sample runbooks
    static let allSamples: [Runbook] = [
        restartAPIService,
        rollbackDeployment,
        investigateUnhealthyContainer,
    ]
}
