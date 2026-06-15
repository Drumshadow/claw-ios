import Foundation

// MARK: - App Review Sample Data

/// Enables an offline, screenshot-safe demo mode for App Review and marketing captures.
/// Keep this data generic: no third-party app names, no real hosts, no customer data.
enum AppReviewSampleData {
    static let didChangeNotification = Notification.Name("AppReviewSampleData.didChange")

    private static let enabledKey = "claw.appReviewSampleData.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static func enable() { isEnabled = true }
    static func disable() { isEnabled = false }

    static var sessions: [ClawSession] {
        [
            ClawSession(
                id: "sample-incident-room",
                title: "Incident command room",
                lastMessage: "Rollback plan prepared. Waiting for approval before touching production.",
                lastMessageAt: Date().addingTimeInterval(-180),
                agentStatus: .running,
                unreadCount: 2,
                model: "sonnet",
                totalTokens: 18_420,
                estimatedCostUsd: 0.42,
                childSessionKeys: ["sample-agent-runner", "sample-agent-reviewer"],
                isPinned: true
            ),
            ClawSession(
                id: "sample-morning-brief",
                title: "Morning ops brief",
                lastMessage: "All scheduled jobs completed. One queue is above its normal range.",
                lastMessageAt: Date().addingTimeInterval(-2_700),
                agentStatus: .idle,
                unreadCount: 0,
                model: "sonnet",
                totalTokens: 7_810,
                estimatedCostUsd: 0.18
            ),
            ClawSession(
                id: "sample-release-plan",
                title: "Release plan review",
                lastMessage: "Deployment checklist generated with dry-run commands and rollback notes.",
                lastMessageAt: Date().addingTimeInterval(-7_200),
                agentStatus: .thinking,
                unreadCount: 1,
                model: "opus",
                totalTokens: 24_050,
                estimatedCostUsd: 1.12
            )
        ]
    }

    static func messages(for sessionKey: String) -> [ClawMessage] {
        let now = Date()
        let title: String
        switch sessionKey {
        case "sample-morning-brief": title = "morning operations status"
        case "sample-release-plan": title = "release readiness"
        default: title = "incident response"
        }

        return [
            ClawMessage(
                id: "sample-\(sessionKey)-user-1",
                sessionKey: sessionKey,
                role: .user,
                content: "Give me the latest \(title) summary.",
                isStreaming: false,
                createdAt: now.addingTimeInterval(-420)
            ),
            ClawMessage(
                id: "sample-\(sessionKey)-assistant-1",
                sessionKey: sessionKey,
                role: .assistant,
                content: "I checked the gateway state, active agents, runbooks, and recent memory events. Overall status is stable. One service is degraded, a remediation proposal is ready, and no destructive action has been approved yet.",
                isStreaming: false,
                createdAt: now.addingTimeInterval(-360)
            ),
            ClawMessage(
                id: "sample-\(sessionKey)-tool-1",
                sessionKey: sessionKey,
                role: .tool,
                content: "tool result",
                isStreaming: false,
                createdAt: now.addingTimeInterval(-300),
                toolName: "topology.snapshot",
                toolInput: ["environment": .string("production")],
                toolResult: "14 nodes checked · 12 healthy · 2 degraded · 0 unapproved changes"
            ),
            ClawMessage(
                id: "sample-\(sessionKey)-assistant-2",
                sessionKey: sessionKey,
                role: .assistant,
                content: "Recommended next step: run the database health runbook in dry-run mode, then approve the queued rollback only if the next health sample stays above threshold.",
                isStreaming: false,
                createdAt: now.addingTimeInterval(-180)
            )
        ]
    }

    static var approvals: [ToolApprovalRequest] {
        [
            ToolApprovalRequest(
                id: "sample-approval-1",
                sessionKey: "sample-incident-room",
                toolName: "runbook.execute",
                toolInput: [
                    "runbook": .string("database-health-check"),
                    "mode": .string("dry-run"),
                    "environment": .string("production")
                ],
                nodeId: "sample-node-prod",
                isDestructive: false,
                environment: "production",
                matchedPolicy: nil,
                riskLevel: .caution,
                snapshotId: nil
            ),
            ToolApprovalRequest(
                id: "sample-approval-2",
                sessionKey: "sample-release-plan",
                toolName: "deployment.rollback",
                toolInput: [
                    "service": .string("agent-api"),
                    "targetVersion": .string("1.4.2"),
                    "requiresConfirmation": .bool(true)
                ],
                nodeId: "sample-node-prod",
                isDestructive: true,
                environment: "production",
                matchedPolicy: nil,
                riskLevel: .danger,
                snapshotId: nil
            )
        ]
    }

    static var terminalSessions: [TerminalSession] {
        [
            TerminalSession(
                id: "sample-terminal-1",
                title: "Deploy Dry Run",
                nodeId: "sample-node-prod",
                nodeName: "prod-runner",
                status: .active,
                startedAt: Date().addingTimeInterval(-62),
                endedAt: nil,
                exitCode: nil,
                isReplay: false,
                pid: 14823
            ),
            TerminalSession(
                id: "sample-terminal-2",
                title: "Health Check — local service",
                nodeId: "sample-node-prod",
                nodeName: "prod-runner",
                status: .idle,
                startedAt: Date().addingTimeInterval(-320),
                endedAt: nil,
                exitCode: nil,
                isReplay: false,
                pid: 14800
            ),
            TerminalSession(
                id: "sample-terminal-3",
                title: "Build Validation",
                nodeId: "sample-node-staging",
                nodeName: "staging-runner",
                status: .ended,
                startedAt: Date().addingTimeInterval(-1_800),
                endedAt: Date().addingTimeInterval(-1_680),
                exitCode: 0,
                isReplay: true,
                pid: nil
            )
        ]
    }

    static var agentMonitorSessions: [AgentMonitorSession] {
        [
            AgentMonitorSession(
                id: "sample-agent-runner",
                title: "Runbook executor",
                status: .running,
                lastMessage: "Streaming dry-run output from step 3 of 5",
                model: "sonnet",
                updatedAt: Date().addingTimeInterval(-45),
                startedAt: Date().addingTimeInterval(-620),
                parentSessionKey: "sample-incident-room",
                agentId: "ops"
            ),
            AgentMonitorSession(
                id: "sample-agent-reviewer",
                title: "Safety reviewer",
                status: .completed,
                lastMessage: "No secret exposure or destructive command detected",
                model: "sonnet",
                updatedAt: Date().addingTimeInterval(-240),
                startedAt: Date().addingTimeInterval(-900),
                parentSessionKey: "sample-incident-room",
                agentId: "security"
            )
        ]
    }

    static var screenshotDashboardConfig: DashboardConfig {
        DashboardConfig(
            layouts: [
                DashboardLayout(name: "App Review", widgets: [
                    DashboardWidget(kind: .topologyMini, size: .full, title: "System Map"),
                    DashboardWidget(kind: .systemHealth, size: .compact),
                    DashboardWidget(kind: .agentActivity, size: .compact),
                    DashboardWidget(kind: .incidentList, size: .full),
                    DashboardWidget(kind: .deploymentFeed, size: .full),
                    DashboardWidget(kind: .containerHealth, size: .compact),
                    DashboardWidget(kind: .queueDepth, size: .full),
                    DashboardWidget(kind: .cronStatus, size: .compact),
                    DashboardWidget(kind: .tokenCost, size: .compact)
                ])
            ],
            activeLayoutIndex: 0
        )
    }

    static var topology: InfraGraph {
        InfraGraph(
            nodes: [
                InfraNode(id: "app-gateway", kind: .gateway, label: "Claw Gateway", group: "platform", health: .ok, posX: 0.50, posY: 0.10),
                InfraNode(id: "agent-api", kind: .api, label: "Agent API", group: "platform", health: .ok, posX: 0.28, posY: 0.30),
                InfraNode(id: "session-worker", kind: .agent, label: "Session Worker", group: "agents", health: .degraded, posX: 0.72, posY: 0.30),
                InfraNode(id: "tool-runner", kind: .container, label: "Tool Runner", group: "runtime", health: .ok, posX: 0.30, posY: 0.55),
                InfraNode(id: "memory-index", kind: .service, label: "Memory Index", group: "memory", health: .ok, posX: 0.70, posY: 0.55),
                InfraNode(id: "event-queue", kind: .queue, label: "Event Queue", group: "runtime", health: .degraded, posX: 0.50, posY: 0.78)
            ],
            edges: [
                InfraEdge(from: "app-gateway", to: "agent-api", kind: .dependency, health: .ok),
                InfraEdge(from: "app-gateway", to: "session-worker", kind: .dependency, health: .degraded),
                InfraEdge(from: "agent-api", to: "tool-runner", kind: .controls, health: .ok),
                InfraEdge(from: "session-worker", to: "memory-index", kind: .dataFlow, health: .ok),
                InfraEdge(from: "tool-runner", to: "event-queue", kind: .dataFlow, health: .degraded),
                InfraEdge(from: "event-queue", to: "session-worker", kind: .dataFlow, health: .degraded)
            ],
            incidents: [
                InfraIncident(
                    id: "sample-inc-1",
                    title: "Event queue latency elevated",
                    severity: .medium,
                    affectedNodeIds: ["event-queue", "session-worker"],
                    startedAt: Date().addingTimeInterval(-900),
                    source: "sample"
                )
            ],
            deployments: [
                DeploymentEvent(
                    id: "sample-dep-1",
                    service: "agent-api",
                    version: "1.4.2",
                    environment: "production",
                    status: .success,
                    deployedAt: Date().addingTimeInterval(-3_600),
                    deployedBy: "release-bot",
                    affectedNodeIds: ["agent-api"],
                    commitSha: "abc1234"
                ),
                DeploymentEvent(
                    id: "sample-dep-2",
                    service: "tool-runner",
                    version: "1.4.3",
                    environment: "production",
                    status: .running,
                    deployedAt: Date().addingTimeInterval(-240),
                    deployedBy: "release-bot",
                    affectedNodeIds: ["tool-runner"],
                    commitSha: "def5678"
                )
            ],
            snapshotAt: Date(),
            version: 1
        )
    }
}
