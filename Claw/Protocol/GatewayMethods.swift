import Foundation

// MARK: - Gateway method name constants

enum GatewayMethod {
    static let connect = "connect"
    static let ping = "ping"
    static let pong = "pong"
    static let disconnect = "disconnect"

    static let operatorSendMessage = "operator.message.send"
    static let operatorListSessions = "operator.sessions.list"
    static let operatorGetSession = "operator.session.get"
    static let operatorApproveDevice = "operator.device.approve"
    static let operatorListDevices = "operator.devices.list"

    static let sessionsList = "sessions.list"
    static let sessionsCreate = "sessions.create"
    static let sessionsDelete = "sessions.delete"
    static let sessionsRename = "sessions.rename"
    static let sessionsAbort = "sessions.abort"
    static let sessionsSubscribe = "sessions.subscribe"
    static let sessionsMessagesSubscribe = "sessions.messages.subscribe"
    static let sessionsMessagesUnsubscribe = "sessions.messages.unsubscribe"

    static let chatHistory = "chat.history"
    static let chatSend = "chat.send"

    static let nodesList = "nodes.list"
    static let nodesPending = "nodes.pending"
    static let nodesApprove = "nodes.approve"
    static let nodesReject = "nodes.reject"
    static let nodesNotify = "nodes.notify"

    static let skillsStatus = "skills.status"
    static let agentsList = "agents.list"
    static let configGet = "config.get"
    static let configPatch = "config.patch"

    static let cronList = "cron.list"
    static let cronEnable = "cron.enable"
    static let cronDisable = "cron.disable"
    static let cronDelete = "cron.delete"
    static let cronCreate = "cron.create"
    static let cronUpdate = "cron.update"

    static let memorySearch = "memory.search"
    static let memoryList = "memory.list"
    static let memoryDelete = "memory.delete"

    static let usageCost = "usage.cost"

    static let toolsApprove = "tools.approve"
    static let toolsDeny = "tools.deny"
    static let toolsSimulate = "tools.simulate"
    static let toolsRollback = "tools.rollback"

    static let phoneResponse = "phone.response"

    static let terminalSessionsList = "terminal.sessions.list"
    static let terminalSessionCreate = "terminal.session.create"
    static let terminalSessionSubscribe = "terminal.session.subscribe"
    static let terminalSessionUnsubscribe = "terminal.session.unsubscribe"
    static let terminalSessionHistory = "terminal.session.history"
    static let terminalSessionInput = "terminal.session.input"
    static let terminalSessionResize = "terminal.session.resize"
    static let terminalSessionKill = "terminal.session.kill"

    static let runbooksList = "runbooks.list"
    static let runbooksCreate = "runbooks.create"
    static let runbooksExecute = "runbooks.execute"
    static let runbooksExecutionStatus = "runbooks.execution.status"
    static let runbooksExecutionApprove = "runbooks.execution.approve"
    static let runbooksExecutionDeny = "runbooks.execution.deny"
    static let runbooksExecutionAbort = "runbooks.execution.abort"
    static let runbooksExecutionRollback = "runbooks.execution.rollback"

    static let topologySnapshot = "topology.snapshot"
    static let topologySubscribe = "topology.subscribe"
    static let topologyNodeCreate = "topology.node.create"

    static let modelsList = "models.list"
    static let modelsCapabilities = "models.capabilities"
    static let routingGet = "routing.get"
    static let routingSet = "routing.set"
    static let routingProfiles = "routing.profiles"

    static let voiceSessionStart = "voice.session.start"
    static let voiceSessionStop = "voice.session.stop"
    static let voiceCommandExecute = "voice.command.execute"
    static let shareIntakeCreate = "share.intake.create"
    static let shareIntakeStatus = "share.intake.status"

    static let backgroundAgentsList = "background.agents.list"
    static let backgroundAgentCreate = "background.agent.create"
    static let backgroundAgentDelete = "background.agent.delete"
    static let backgroundAgentToggle = "background.agent.toggle"
    static let backgroundAgentAcknowledge = "background.agent.acknowledge"

    static let incidentsList = "incidents.list"
    static let incidentAcknowledge = "incident.acknowledge"
    static let incidentResolve = "incident.resolve"
    static let incidentAddComment = "incident.comment"

    static let proposalsList = "proposals.list"
    static let proposalApprove = "proposal.approve"
    static let proposalReject = "proposal.reject"

    static let memoryTimelineList = "memory.timeline.list"
    static let memoryTimelineSearch = "memory.timeline.search"
    static let memoryTimelineAdd = "memory.timeline.add"

    static let sessionReplayData = "session.replay.data"
    static let sessionBranches = "session.branches"

    static let agentNetworkState = "agents.network.state"
    static let agentNetworkSubscribe = "agents.network.subscribe"

    static let homeIntegrationsList = "home.integrations.list"
    static let homeIntegrationCreate = "home.integration.create"
    static let homeIntegrationToggle = "home.integration.toggle"
    static let homeIntegrationSync = "home.integration.sync"
    static let homeReminders = "home.reminders"
    static let homeGroceriesList = "home.groceries.list"
    static let homeGroceriesCreate = "home.groceries.create"
    static let homeGroceriesUpdate = "home.groceries.update"
    static let homeTasksList = "home.tasks.list"
    static let homeTasksCreate = "home.tasks.create"
    static let homeTasksUpdate = "home.tasks.update"
}

// MARK: - Agent IDs offered when creating sessions

enum GatewayAgentId {
    static let main = "main"
    static let claude = "claude"

    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
    }

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

    static let phoneRequest = "phone.request"

    static let terminalOutput = "terminal.output"
    static let terminalSessionStarted = "terminal.session.started"
    static let terminalSessionEnded = "terminal.session.ended"
    static let terminalSessionError = "terminal.session.error"

    static let runbookStepStarted = "runbook.step.started"
    static let runbookStepOutput = "runbook.step.output"
    static let runbookStepCompleted = "runbook.step.completed"
    static let runbookStepFailed = "runbook.step.failed"
    static let runbookStepAwaitingApproval = "runbook.step.awaiting_approval"
    static let runbookExecutionCompleted = "runbook.execution.completed"
    static let runbookExecutionFailed = "runbook.execution.failed"

    static let topologySnapshot = "topology.snapshot"
    static let topologyNodeUpdated = "topology.node.updated"
    static let topologyIncidentOpened = "topology.incident.opened"
    static let topologyIncidentClosed = "topology.incident.closed"
    static let topologyDeploymentUpdated = "topology.deployment.updated"

    static let modelRoutingChanged = "model.routing.changed"
    static let modelHealthUpdate = "model.health.update"

    static let snapshotCaptured = "snapshot.captured"
    static let snapshotExpired = "snapshot.expired"
    static let rollbackCompleted = "rollback.completed"

    static let voicePartialTranscript = "voice.partial_transcript"
    static let voiceFinalTranscript = "voice.final_transcript"
    static let voiceResponseDelta = "voice.response.delta"
    static let voiceResponseCompleted = "voice.response.completed"
    static let shareIntakeCompleted = "share.intake.completed"

    static let backgroundAgentAlert = "background.agent.alert"
    static let incidentCreated = "incident.created"
    static let incidentUpdated = "incident.updated"
    static let proposalCreated = "proposal.created"

    static let memoryTimelineEvent = "memory.timeline.event"

    static let agentNetworkUpdated = "agents.network.updated"
    static let agentNetworkNodeChange = "agents.network.node.change"

    static let homeIntegrationStatusChange = "home.integration.status"
    static let homeTaskCreated = "home.task.created"
    static let homeTaskUpdated = "home.task.updated"
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
