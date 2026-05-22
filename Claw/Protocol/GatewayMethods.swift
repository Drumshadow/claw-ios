import Foundation

// MARK: - Gateway method name constants

enum GatewayMethod {
    static let connect = "connect"
    static let ping = "ping"
    static let pong = "pong"
    static let disconnect = "disconnect"

    // Operator methods
    static let operatorSendMessage = "operator.message.send"
    static let operatorListSessions = "operator.sessions.list"
    static let operatorGetSession = "operator.session.get"
    static let operatorApproveDevice = "operator.device.approve"
    static let operatorListDevices = "operator.devices.list"

    // Session lifecycle methods
    static let sessionsList = "sessions.list"
    static let sessionsCreate = "sessions.create"
    static let sessionsDelete = "sessions.delete"
    static let sessionsRename = "sessions.rename"
    static let sessionsAbort = "sessions.abort"
    static let sessionsSubscribe = "sessions.subscribe"
    static let sessionsMessagesSubscribe = "sessions.messages.subscribe"
    static let sessionsMessagesUnsubscribe = "sessions.messages.unsubscribe"

    // Chat methods
    static let chatHistory = "chat.history"
    static let chatSend = "chat.send"

    // Node management methods
    static let nodesList = "nodes.list"
    static let nodesPending = "nodes.pending"
    static let nodesApprove = "nodes.approve"
    static let nodesReject = "nodes.reject"
    static let nodesNotify = "nodes.notify"

    // Platform administration methods
    static let skillsStatus = "skills.status"
    static let agentsList = "agents.list"
    static let configGet = "config.get"
    static let configPatch = "config.patch"

    // Cron job methods
    static let cronList = "cron.list"
    static let cronEnable = "cron.enable"
    static let cronDisable = "cron.disable"
    static let cronDelete = "cron.delete"
    static let cronCreate = "cron.create"
    static let cronUpdate = "cron.update"

    // Memory methods
    static let memorySearch = "memory.search"
    static let memoryList = "memory.list"
    static let memoryDelete = "memory.delete"

    // Usage methods
    static let usageCost = "usage.cost"

    // Tool approval methods
    static let toolsApprove = "tools.approve"
    static let toolsDeny = "tools.deny"

    // Phone context bridge methods
    static let phoneResponse = "phone.response"

    // Terminal stream methods
    // Expected backend contract:
    //   terminal.sessions.list → [TerminalSessionPayload]
    //   terminal.session.subscribe(sessionId: String) → void, starts terminal.output events
    //   terminal.session.unsubscribe(sessionId: String) → void
    //   terminal.session.history(sessionId: String, limit: Int, offset: Int) → [TerminalLinePayload]
    //   terminal.session.input(sessionId: String, text: String) → void (Take Control mode)
    //   terminal.session.resize(sessionId: String, cols: Int, rows: Int) → void
    //   terminal.session.kill(sessionId: String) → void
    static let terminalSessionsList = "terminal.sessions.list"
    static let terminalSessionSubscribe = "terminal.session.subscribe"
    static let terminalSessionUnsubscribe = "terminal.session.unsubscribe"
    static let terminalSessionHistory = "terminal.session.history"
    static let terminalSessionInput = "terminal.session.input"
    static let terminalSessionResize = "terminal.session.resize"
    static let terminalSessionKill = "terminal.session.kill"

    // Runbook methods
    // Expected backend contract:
    //   runbooks.list → [RunbookPayload]
    //   runbooks.execute(runbookId: String, mode: String, dryRun: Bool) → RunbookExecutionPayload
    //   runbooks.execution.status(executionId: String) → RunbookExecutionPayload
    //   runbooks.execution.approve(executionId: String, stepId: String) → void
    //   runbooks.execution.deny(executionId: String, stepId: String, reason: String?) → void
    //   runbooks.execution.abort(executionId: String) → void
    //   runbooks.execution.rollback(executionId: String, stepId: String?) → void (nil = full rollback)
    static let runbooksList = "runbooks.list"
    static let runbooksExecute = "runbooks.execute"
    static let runbooksExecutionStatus = "runbooks.execution.status"
    static let runbooksExecutionApprove = "runbooks.execution.approve"
    static let runbooksExecutionDeny = "runbooks.execution.deny"
    static let runbooksExecutionAbort = "runbooks.execution.abort"
    static let runbooksExecutionRollback = "runbooks.execution.rollback"

    // Topology / Infrastructure graph methods
    // Expected gateway contract:
    //   topology.snapshot  → { nodes: [...], edges: [...], incidents: [...], deployments: [...], snapshotAt: ISO8601, version: Int }
    //   topology.subscribe → acknowledge (starts topology.* event stream)
    static let topologySnapshot = "topology.snapshot"
    static let topologySubscribe = "topology.subscribe"
}

// MARK: - Agent IDs offered when creating sessions

enum GatewayAgentId {
    static let main = "main"
    static let claude = "claude"

    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
    }

    /// Fallback display options for the agent picker when gateway capabilities are unavailable.
    static let options: [Option] = [
        Option(id: main, label: "Main"),
        Option(id: claude, label: "Claude Code")
    ]
}

// MARK: - Gateway event name constants

enum GatewayEventName {
    static let connectChallenge = "connect.challenge"
    static let helloOk = "hello-ok"
    static let sessionStarted = "session.started"
    static let sessionEnded = "session.ended"
    static let messageDelta = "message.delta"
    static let messageComplete = "message.complete"
    static let devicePaired = "device.paired"
    static let devicePendingApproval = "device.pending_approval"
    static let nodeConnected = "node.connected"
    static let nodeDisconnected = "node.disconnected"
    static let nodePending = "node.pending"

    // Phone context bridge events
    static let phoneRequest = "phone.request"

    // Terminal stream events
    static let terminalOutput = "terminal.output"
    static let terminalSessionStarted = "terminal.session.started"
    static let terminalSessionEnded = "terminal.session.ended"
    static let terminalSessionError = "terminal.session.error"

    // Runbook events
    static let runbookStepStarted = "runbook.step.started"
    static let runbookStepOutput = "runbook.step.output"
    static let runbookStepCompleted = "runbook.step.completed"
    static let runbookStepFailed = "runbook.step.failed"
    static let runbookStepAwaitingApproval = "runbook.step.awaiting_approval"
    static let runbookExecutionCompleted = "runbook.execution.completed"
    static let runbookExecutionFailed = "runbook.execution.failed"

    // Topology / Infrastructure graph events
    static let topologySnapshot = "topology.snapshot"
    static let topologyNodeUpdated = "topology.node.updated"
    static let topologyIncidentOpened = "topology.incident.opened"
    static let topologyIncidentClosed = "topology.incident.closed"
    static let topologyDeploymentUpdated = "topology.deployment.updated"
}

// MARK: - Connection state enum (shared between transport + app layer)

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case reconnecting
    case pairing(deviceID: String)
    case connected
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isPairing: Bool {
        if case .pairing = self { return true }
        return false
    }

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }

    var displayDescription: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .pairing(let id): return "Waiting for approval (device: \(id.prefix(12))…)"
        case .connected: return "Connected"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}
