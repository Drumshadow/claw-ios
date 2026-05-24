import Foundation

// MARK: - RunbookStore
//
// Manages the runbook catalog and active executions.
//
// Gateway contract:
//   runbooks.list → [RunbookPayload]
//   runbooks.create(runbook) → { runbook }
//   runbooks.execute(runbookId, mode, dryRun) → { executionId }
//   runbooks.execution.approve(executionId, stepId)
//   runbooks.execution.deny(executionId, stepId, reason?)
//   runbooks.execution.abort(executionId)
//   runbooks.execution.rollback(executionId, stepId?)
//   Events: runbook.step.started, runbook.step.output, runbook.step.completed,
//           runbook.step.failed, runbook.step.awaiting_approval,
//           runbook.execution.completed, runbook.execution.failed

@Observable
@MainActor
final class RunbookStore {

    // MARK: - Observable state

    private(set) var runbooks: [Runbook] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// Active execution objects — keyed by executionId.
    private(set) var executions: [String: RunbookExecution] = [:]

    /// Executions in reverse-chronological order for display.
    var sortedExecutions: [RunbookExecution] {
        executions.values.sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
    }

    // MARK: - Private

    private let client: GatewayClient?
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    // MARK: - Init

    /// `client: nil` enables the preview/mock path (uses sample runbooks).
    init(client: GatewayClient? = nil) {
        self.client = client
        if let client {
            startEventSubscription(client: client)
        } else {
            // Preview mode — seed sample data
            runbooks = Runbook.allSamples
        }
    }

    // MARK: - Load

    func load() async throws {
        if AppReviewSampleData.isEnabled {
            loadAppReviewSampleData()
            return
        }
        guard let client else {
            runbooks = AppReviewSampleData.isEnabled ? Runbook.allSamples : []
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let response = try await client.send(
                method: GatewayMethod.runbooksList,
                params: EmptyRunbookParams()
            )
            // Attempt to decode from gateway; keep empty on schema mismatch unless sample mode is enabled.
            if let listVal = response["runbooks"],
               case .array(let arr) = listVal,
               !arr.isEmpty {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let decoded: [Runbook] = arr.compactMap { item in
                    guard case .object(let dict) = item,
                          let data = try? JSONSerialization.data(withJSONObject: dict.toAny()),
                          let rb = try? decoder.decode(Runbook.self, from: data)
                    else { return nil }
                    return rb
                }
                runbooks = decoded.isEmpty ? [] : decoded
            } else {
                runbooks = []
            }
        } catch {
            loadError = error
            if runbooks.isEmpty { runbooks = [] }
        }
    }

    // MARK: - App Review sample data

    func loadAppReviewSampleData() {
        runbooks = Runbook.allSamples
        loadError = nil
    }

    @discardableResult
    func createRunbook(_ runbook: Runbook) async throws -> Runbook {
        guard let client else {
            runbooks.insert(runbook, at: 0)
            return runbook
        }

        struct CreateRunbookParams: Encodable { let runbook: Runbook }
        let response = try await client.send(
            method: GatewayMethod.runbooksCreate,
            params: CreateRunbookParams(runbook: runbook)
        )

        let created = parseRunbook(response["runbook"] ?? .object(response)) ?? runbook
        if let idx = runbooks.firstIndex(where: { $0.id == created.id }) {
            runbooks[idx] = created
        } else {
            runbooks.insert(created, at: 0)
        }
        return created
    }

    // MARK: - Execute

    /// Kick off a runbook execution. Returns the new `RunbookExecution`.
    @discardableResult
    func execute(
        runbook: Runbook,
        mode: RunbookExecutionMode,
        isDryRun: Bool = false
    ) async throws -> RunbookExecution {
        // Create a local execution object immediately for responsive UI
        let localId = "exec-\(UUID().uuidString.prefix(8))"
        let execution = RunbookExecution(id: localId, runbook: runbook, mode: mode, isDryRun: isDryRun)
        execution.startedAt = Date()
        execution.status = .running
        executions[localId] = execution

        guard let client else {
            // Preview simulation — auto-advance steps with delays
            Task { await simulateExecution(execution) }
            return execution
        }

        do {
            let response = try await client.send(
                method: GatewayMethod.runbooksExecute,
                params: [
                    "runbookId": runbook.id.uuidString,
                    "mode": mode.rawValue,
                    "dryRun": isDryRun,
                ] as [String: Any]
            )
            // Replace temporary local ID with gateway-assigned ID
            if case .string(let gatewayId) = response["executionId"] {
                executions.removeValue(forKey: localId)
                let gatewayExecution = RunbookExecution(
                    id: gatewayId, runbook: runbook, mode: mode, isDryRun: isDryRun
                )
                gatewayExecution.startedAt = Date()
                gatewayExecution.status = .running
                executions[gatewayId] = gatewayExecution
                return gatewayExecution
            }
        } catch {
            execution.status = .failed
            execution.errorMessage = error.localizedDescription
        }

        return execution
    }

    // MARK: - Approval gates

    func approveStep(executionId: String, stepId: UUID) async throws {
        guard let execution = executions[executionId] else { return }
        if let stepExec = execution.stepExecution(for: stepId) {
            stepExec.status = .running
        }
        guard let client else { return }
        try await client.send(
            method: GatewayMethod.runbooksExecutionApprove,
            params: ["executionId": executionId, "stepId": stepId.uuidString]
        )
    }

    func denyStep(executionId: String, stepId: UUID, reason: String? = nil) async throws {
        guard let execution = executions[executionId] else { return }
        if let stepExec = execution.stepExecution(for: stepId) {
            stepExec.status = .skipped
        }
        guard let client else { return }
        var params: [String: Any] = ["executionId": executionId, "stepId": stepId.uuidString]
        if let r = reason { params["reason"] = r }
        try await client.send(method: GatewayMethod.runbooksExecutionDeny, params: params)
    }

    func abort(executionId: String) async throws {
        guard let execution = executions[executionId] else { return }
        execution.status = .aborted
        execution.completedAt = Date()
        guard let client else { return }
        try await client.send(
            method: GatewayMethod.runbooksExecutionAbort,
            params: ["executionId": executionId]
        )
    }

    func rollback(executionId: String, stepId: UUID? = nil) async throws {
        guard let client else { return }
        var params: [String: Any] = ["executionId": executionId]
        if let s = stepId { params["stepId"] = s.uuidString }
        try await client.send(method: GatewayMethod.runbooksExecutionRollback, params: params)
    }

    // MARK: - Event subscription

    private func startEventSubscription(client: GatewayClient) {
        eventTask = Task { [weak self, client] in
            for await event in await client.events() {
                guard let self, !Task.isCancelled else { break }
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event.name {

        case GatewayEventName.runbookStepStarted:
            guard let execId = stringPayload(event, "executionId"),
                  let stepIdStr = stringPayload(event, "stepId"),
                  let stepId = UUID(uuidString: stepIdStr),
                  let execution = executions[execId],
                  let stepExec = execution.stepExecution(for: stepId)
            else { return }
            stepExec.status = .running
            stepExec.startedAt = Date()
            if let idx = numberPayload(event, "stepIndex") {
                execution.currentStepIndex = Int(idx)
            }

        case GatewayEventName.runbookStepOutput:
            guard let execId = stringPayload(event, "executionId"),
                  let stepIdStr = stringPayload(event, "stepId"),
                  let stepId = UUID(uuidString: stepIdStr),
                  let line = stringPayload(event, "line"),
                  let execution = executions[execId]
            else { return }
            execution.appendOutput(stepId: stepId, line: line)

        case GatewayEventName.runbookStepCompleted:
            guard let execId = stringPayload(event, "executionId"),
                  let stepIdStr = stringPayload(event, "stepId"),
                  let stepId = UUID(uuidString: stepIdStr),
                  let execution = executions[execId],
                  let stepExec = execution.stepExecution(for: stepId)
            else { return }
            stepExec.status = execution.isDryRun ? .dryRun : .completed
            stepExec.completedAt = Date()
            if let code = numberPayload(event, "exitCode") { stepExec.exitCode = Int(code) }

        case GatewayEventName.runbookStepFailed:
            guard let execId = stringPayload(event, "executionId"),
                  let stepIdStr = stringPayload(event, "stepId"),
                  let stepId = UUID(uuidString: stepIdStr),
                  let execution = executions[execId],
                  let stepExec = execution.stepExecution(for: stepId)
            else { return }
            stepExec.status = .failed
            stepExec.completedAt = Date()
            stepExec.errorMessage = stringPayload(event, "error")

        case GatewayEventName.runbookStepAwaitingApproval:
            guard let execId = stringPayload(event, "executionId"),
                  let stepIdStr = stringPayload(event, "stepId"),
                  let stepId = UUID(uuidString: stepIdStr),
                  let execution = executions[execId],
                  let stepExec = execution.stepExecution(for: stepId)
            else { return }
            stepExec.status = .awaitingApproval

        case GatewayEventName.runbookExecutionCompleted:
            guard let execId = stringPayload(event, "executionId"),
                  let execution = executions[execId]
            else { return }
            execution.status = execution.isDryRun ? .dryRunComplete : .completed
            execution.completedAt = Date()

        case GatewayEventName.runbookExecutionFailed:
            guard let execId = stringPayload(event, "executionId"),
                  let execution = executions[execId]
            else { return }
            execution.status = .failed
            execution.completedAt = Date()
            execution.errorMessage = stringPayload(event, "error")

        default:
            break
        }
    }

    // MARK: - Preview simulation

    private func simulateExecution(_ execution: RunbookExecution) async {
        let steps = execution.runbook.steps
        for (idx, step) in steps.enumerated() {
            guard !Task.isCancelled, execution.status == .running else { break }
            let stepExec = execution.stepExecution(for: step.id)

            // Awaiting approval pause
            if step.requiresApproval(mode: execution.mode) {
                stepExec?.status = .awaitingApproval
                // In preview, auto-approve after 1s so UI animates
                try? await Task.sleep(for: .seconds(1))
            }

            // Run
            stepExec?.status = .running
            stepExec?.startedAt = Date()
            execution.currentStepIndex = idx

            // Simulate output lines
            let outputLines = [
                "$ \(step.command)",
                "Running \(step.name)...",
                "  → Processing step \(idx + 1)/\(steps.count)",
                "  ✓ \(execution.isDryRun ? "[DRY-RUN] Would execute" : "Completed"): \(step.name)",
            ]
            for line in outputLines {
                execution.appendOutput(stepId: step.id, line: line)
                try? await Task.sleep(for: .milliseconds(200))
            }

            try? await Task.sleep(for: .seconds(0.5))
            stepExec?.status = execution.isDryRun ? .dryRun : .completed
            stepExec?.completedAt = Date()
            stepExec?.exitCode = 0

            if step.checkpointAfter {
                // Pause at checkpoint for user to review
                try? await Task.sleep(for: .seconds(1))
            }
        }

        execution.status = execution.isDryRun ? .dryRunComplete : .completed
        execution.completedAt = Date()
    }

    // MARK: - Payload helpers

    private func stringPayload(_ event: GatewayEvent, _ key: String) -> String? {
        guard case .string(let s) = event.payload[key] else { return nil }
        return s
    }

    private func numberPayload(_ event: GatewayEvent, _ key: String) -> Double? {
        switch event.payload[key] {
        case .int(let n):    return Double(n)
        case .double(let n): return n
        default:             return nil
        }
    }
}

private func parseRunbook(_ value: JSONValue) -> Runbook? {
    guard case .object(let dict) = value,
          let data = try? JSONSerialization.data(withJSONObject: dict.toAny())
    else { return nil }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try? decoder.decode(Runbook.self, from: data)
}

// MARK: - Helpers

private struct EmptyRunbookParams: Encodable {}

private extension Dictionary where Key == String, Value == JSONValue {
    func toAny() -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in self {
            result[key] = value.toAny()
        }
        return result
    }
}

private extension JSONValue {
    func toAny() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let n):    return n
        case .double(let n): return n
        case .bool(let b):   return b
        case .null:          return NSNull()
        case .array(let arr): return arr.map { $0.toAny() }
        case .object(let dict): return dict.toAny()
        }
    }
}

// GatewayClient [String: Any] convenience is defined in GatewayClientAnyParams.swift
