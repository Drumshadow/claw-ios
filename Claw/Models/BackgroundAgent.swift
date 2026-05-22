import Foundation

// MARK: - BackgroundWatcher
//
// A background watcher monitors a condition (error rate, deploy, git inactivity, etc.)
// and fires when that condition is met, optionally spawning a remediation agent.
//
// Gateway contract:
//   - List:   GatewayMethod.backgroundAgentsList    → { watchers: [BackgroundWatcher] }
//   - Create: GatewayMethod.backgroundAgentCreate   → BackgroundWatcher
//   - Delete: GatewayMethod.backgroundAgentDelete   → { id: String }
//   - Toggle: GatewayMethod.backgroundAgentToggle   → { id: String, enabled: Bool }
//   Events:   GatewayEventName.backgroundAgentAlert → { watcherId, incidentId, result }

struct BackgroundWatcher: Identifiable, Hashable {
    let id: String
    var name: String
    var description: String
    var isEnabled: Bool
    var triggerType: WatcherTriggerType
    var condition: String           // Human-readable condition summary
    var schedule: WatcherSchedule?  // nil = purely event-driven
    var eventSourceIds: [String]    // event source IDs that feed this watcher
    var assignedAgentId: String?    // agent to run on trigger
    var lastTriggeredAt: Date?
    var lastResult: WatcherResult?
    var createdAt: Date
    var escalationPolicy: EscalationPolicy?
    var remediationEnabled: Bool    // auto-propose fixes when triggered
    var incidentGroupTag: String?   // group new alerts into incidents with this tag
}

// MARK: - WatcherTriggerType

enum WatcherTriggerType: String, CaseIterable, Identifiable, Hashable {
    case errorRate       = "error_rate"
    case deployEvent     = "deploy"
    case gitActivity     = "git"
    case resourceUsage   = "resource"
    case logPattern      = "log_pattern"
    case apiHealth       = "api_health"
    case customWebhook   = "webhook"
    case scheduled       = "scheduled"
    case memoryThreshold = "memory_threshold"
    case agentIdle       = "agent_idle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .errorRate:       return "Error Rate"
        case .deployEvent:     return "Deploy Event"
        case .gitActivity:     return "Git Activity"
        case .resourceUsage:   return "Resource Usage"
        case .logPattern:      return "Log Pattern"
        case .apiHealth:       return "API Health"
        case .customWebhook:   return "Webhook"
        case .scheduled:       return "Scheduled"
        case .memoryThreshold: return "Memory Threshold"
        case .agentIdle:       return "Agent Idle"
        }
    }

    var systemImage: String {
        switch self {
        case .errorRate:       return "exclamationmark.triangle"
        case .deployEvent:     return "arrow.up.circle"
        case .gitActivity:     return "arrow.triangle.branch"
        case .resourceUsage:   return "cpu"
        case .logPattern:      return "text.magnifyingglass"
        case .apiHealth:       return "network"
        case .customWebhook:   return "bolt.horizontal"
        case .scheduled:       return "clock"
        case .memoryThreshold: return "memorychip"
        case .agentIdle:       return "pause.circle"
        }
    }
}

// MARK: - WatcherSchedule

struct WatcherSchedule: Hashable {
    var cronExpression: String   // e.g. "*/5 * * * *"
    var timezone: String         // IANA timezone, e.g. "America/New_York"
    var displayLabel: String     // human label, e.g. "Every 5 minutes"
}

// MARK: - WatcherResult

struct WatcherResult: Hashable {
    var triggeredAt: Date
    var conditionMet: Bool
    var summary: String
    var incidentId: String?
    var proposalId: String?
    var tokenCost: Int?
    var durationMs: Int?
}

// MARK: - EscalationPolicy

struct EscalationPolicy: Hashable {
    var notifyOnTrigger: Bool
    var autoApproveRemediation: Bool // skip approval dialog for low-risk fixes
    var escalateAfterMinutes: Int?   // re-alert user if still unresolved
    var alertChannels: [String]      // e.g. ["push", "email"]
}

// MARK: - Incident
//
// An incident groups one or more related watcher alerts into a single tracked event.
// Gateway contract:
//   - List:        GatewayMethod.incidentsList       → { incidents: [Incident] }
//   - Acknowledge: GatewayMethod.incidentAcknowledge → { id: String }
//   - Resolve:     GatewayMethod.incidentResolve     → { id: String, resolution: String }
//   Events:        GatewayEventName.incidentCreated, incidentUpdated

struct Incident: Identifiable, Hashable {
    let id: String
    var title: String
    var description: String
    var severity: IncidentSeverity
    var status: IncidentStatus
    var watcherIds: [String]
    var proposalIds: [String]
    var relatedSessionIds: [String]
    var timeline: [IncidentTimelineEntry]
    var createdAt: Date
    var resolvedAt: Date?
    var acknowledgedAt: Date?
    var tags: [String]
}

// MARK: - IncidentSeverity

enum IncidentSeverity: String, CaseIterable, Identifiable, Hashable {
    case info      = "info"
    case warning   = "warning"
    case critical  = "critical"
    case emergency = "emergency"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .info:      return "info.circle"
        case .warning:   return "exclamationmark.triangle"
        case .critical:  return "exclamationmark.octagon"
        case .emergency: return "flame"
        }
    }

    var colorHex: String {
        switch self {
        case .info:      return "3b82f6"
        case .warning:   return "f59e0b"
        case .critical:  return "ef4444"
        case .emergency: return "dc2626"
        }
    }
}

// MARK: - IncidentStatus

enum IncidentStatus: String, CaseIterable, Identifiable, Hashable {
    case open          = "open"
    case acknowledged  = "acknowledged"
    case investigating = "investigating"
    case remediated    = "remediated"
    case resolved      = "resolved"
    case noAction      = "no_action"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .open:          return "Open"
        case .acknowledged:  return "Acknowledged"
        case .investigating: return "Investigating"
        case .remediated:    return "Remediated"
        case .resolved:      return "Resolved"
        case .noAction:      return "No Action Needed"
        }
    }

    var isActive: Bool {
        switch self {
        case .open, .acknowledged, .investigating: return true
        default: return false
        }
    }

    var systemImage: String {
        switch self {
        case .open:          return "circle.fill"
        case .acknowledged:  return "eye"
        case .investigating: return "magnifyingglass"
        case .remediated:    return "wrench"
        case .resolved:      return "checkmark.circle.fill"
        case .noAction:      return "minus.circle"
        }
    }
}

// MARK: - IncidentTimelineEntry

struct IncidentTimelineEntry: Identifiable, Hashable {
    let id: String
    var timestamp: Date
    var kind: EntryKind
    var message: String
    var actorId: String?   // session ID or "user"

    enum EntryKind: String, Hashable {
        case triggered         = "triggered"
        case acknowledged      = "acknowledged"
        case agentStarted      = "agent_started"
        case proposalCreated   = "proposal_created"
        case proposalApproved  = "proposal_approved"
        case actionTaken       = "action_taken"
        case resolved          = "resolved"
        case escalated         = "escalated"
        case comment           = "comment"
    }
}

// MARK: - AnomalyProposal
//
// A remediation proposal generated by an agent in response to a watcher alert.
// Gateway contract:
//   - List:    GatewayMethod.proposalsList    → { proposals: [AnomalyProposal] }
//   - Approve: GatewayMethod.proposalApprove → { id: String }
//   - Reject:  GatewayMethod.proposalReject  → { id: String, reason: String? }
//   Event:     GatewayEventName.proposalCreated

struct AnomalyProposal: Identifiable, Hashable {
    let id: String
    var incidentId: String
    var watcherId: String?
    var sessionId: String?
    var title: String
    var description: String
    var proposedActions: [ProposedAction]
    var status: RemediationStatus
    var riskLevel: ProposalRiskLevel
    var estimatedImpact: String
    var createdAt: Date
    var reviewedAt: Date?
    var executedAt: Date?
    var tokenCost: Int?
}

// MARK: - ProposedAction

struct ProposedAction: Identifiable, Hashable {
    let id: String
    var description: String
    var toolName: String?
    var parameters: String?      // JSON string of parameters
    var estimatedDuration: String?
    var isReversible: Bool
    var executed: Bool
}

// MARK: - RemediationStatus

enum RemediationStatus: String, CaseIterable, Identifiable, Hashable {
    case pending   = "pending"
    case approved  = "approved"
    case rejected  = "rejected"
    case executing = "executing"
    case completed = "completed"
    case failed    = "failed"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .pending:   return "clock"
        case .approved:  return "checkmark.circle"
        case .rejected:  return "xmark.circle"
        case .executing: return "gearshape"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - ProposalRiskLevel

enum ProposalRiskLevel: String, CaseIterable, Identifiable, Hashable {
    case safe   = "safe"
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var id: String { rawValue }

    var colorHex: String {
        switch self {
        case .safe:   return "22c55e"
        case .low:    return "14b8a6"
        case .medium: return "f59e0b"
        case .high:   return "ef4444"
        }
    }
}

// MARK: - EventSource

/// An event source is a webhook, API, or gateway event feed that triggers watchers.
struct EventSource: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: EventSourceKind
    var endpoint: String?
    var isActive: Bool
    var lastEventAt: Date?
    var eventsThisHour: Int
}

enum EventSourceKind: String, CaseIterable, Hashable {
    case githubWebhook = "github_webhook"
    case datadogAlert  = "datadog_alert"
    case awsCloudWatch = "cloudwatch"
    case customWebhook = "custom_webhook"
    case cronSchedule  = "cron"
    case gatewayEvent  = "gateway_event"

    var displayName: String {
        switch self {
        case .githubWebhook: return "GitHub"
        case .datadogAlert:  return "Datadog"
        case .awsCloudWatch: return "CloudWatch"
        case .customWebhook: return "Webhook"
        case .cronSchedule:  return "Schedule"
        case .gatewayEvent:  return "Gateway"
        }
    }

    var systemImage: String {
        switch self {
        case .githubWebhook: return "chevron.left.forwardslash.chevron.right"
        case .datadogAlert:  return "chart.bar.xaxis"
        case .awsCloudWatch: return "cloud"
        case .customWebhook: return "bolt.horizontal"
        case .cronSchedule:  return "clock"
        case .gatewayEvent:  return "bolt"
        }
    }
}

// MARK: - Preview Data

extension BackgroundWatcher {
    static let previewWatchers: [BackgroundWatcher] = [
        BackgroundWatcher(
            id: "w-1",
            name: "API Error Spike",
            description: "Alert when /api error rate exceeds 5% for 3+ minutes",
            isEnabled: true,
            triggerType: .errorRate,
            condition: "error_rate > 5% for 3 minutes",
            schedule: nil,
            eventSourceIds: ["src-datadog"],
            assignedAgentId: "main",
            lastTriggeredAt: Date().addingTimeInterval(-3600),
            lastResult: WatcherResult(
                triggeredAt: Date().addingTimeInterval(-3600),
                conditionMet: true,
                summary: "Error rate hit 8.3% on /api/orders",
                incidentId: "inc-1",
                proposalId: "prop-1",
                tokenCost: 1240,
                durationMs: 4800
            ),
            createdAt: Date().addingTimeInterval(-86400 * 7),
            escalationPolicy: EscalationPolicy(
                notifyOnTrigger: true,
                autoApproveRemediation: false,
                escalateAfterMinutes: 30,
                alertChannels: ["push"]
            ),
            remediationEnabled: true,
            incidentGroupTag: "api-health"
        ),
        BackgroundWatcher(
            id: "w-2",
            name: "Nightly Git Audit",
            description: "Summarize all commits and open PRs each night",
            isEnabled: true,
            triggerType: .scheduled,
            condition: "Every night at 23:00",
            schedule: WatcherSchedule(
                cronExpression: "0 23 * * *",
                timezone: "America/New_York",
                displayLabel: "Daily at 11 PM"
            ),
            eventSourceIds: [],
            assignedAgentId: "main",
            lastTriggeredAt: Date().addingTimeInterval(-3600 * 3),
            lastResult: WatcherResult(
                triggeredAt: Date().addingTimeInterval(-3600 * 3),
                conditionMet: true,
                summary: "14 commits, 3 open PRs, 2 failing checks",
                incidentId: nil,
                proposalId: nil,
                tokenCost: 3200,
                durationMs: 12000
            ),
            createdAt: Date().addingTimeInterval(-86400 * 14),
            escalationPolicy: nil,
            remediationEnabled: false,
            incidentGroupTag: nil
        ),
        BackgroundWatcher(
            id: "w-3",
            name: "Memory Usage",
            description: "Alert when server memory exceeds 85%",
            isEnabled: false,
            triggerType: .memoryThreshold,
            condition: "memory_usage > 85%",
            schedule: nil,
            eventSourceIds: ["src-cloudwatch"],
            assignedAgentId: nil,
            lastTriggeredAt: nil,
            lastResult: nil,
            createdAt: Date().addingTimeInterval(-86400 * 3),
            escalationPolicy: EscalationPolicy(
                notifyOnTrigger: true,
                autoApproveRemediation: true,
                escalateAfterMinutes: nil,
                alertChannels: ["push"]
            ),
            remediationEnabled: true,
            incidentGroupTag: "infra"
        ),
    ]
}

extension Incident {
    static let previewIncidents: [Incident] = [
        Incident(
            id: "inc-1",
            title: "API Error Spike",
            description: "Error rate on /api/orders rose to 8.3% following deploy v2.3.1",
            severity: .critical,
            status: .remediated,
            watcherIds: ["w-1"],
            proposalIds: ["prop-1"],
            relatedSessionIds: ["session-abc"],
            timeline: [
                IncidentTimelineEntry(
                    id: "te-1",
                    timestamp: Date().addingTimeInterval(-3600),
                    kind: .triggered,
                    message: "Error rate threshold exceeded: 8.3% on /api/orders",
                    actorId: "w-1"
                ),
                IncidentTimelineEntry(
                    id: "te-2",
                    timestamp: Date().addingTimeInterval(-3580),
                    kind: .agentStarted,
                    message: "Remediation agent spawned",
                    actorId: "session-abc"
                ),
                IncidentTimelineEntry(
                    id: "te-3",
                    timestamp: Date().addingTimeInterval(-3500),
                    kind: .proposalCreated,
                    message: "Agent proposed: rollback backend to v2.3.0",
                    actorId: "session-abc"
                ),
                IncidentTimelineEntry(
                    id: "te-4",
                    timestamp: Date().addingTimeInterval(-3400),
                    kind: .proposalApproved,
                    message: "Rollback approved",
                    actorId: "user"
                ),
                IncidentTimelineEntry(
                    id: "te-5",
                    timestamp: Date().addingTimeInterval(-3200),
                    kind: .resolved,
                    message: "Error rate returned to 0.2% after rollback",
                    actorId: "w-1"
                ),
            ],
            createdAt: Date().addingTimeInterval(-3600),
            resolvedAt: Date().addingTimeInterval(-3200),
            acknowledgedAt: Date().addingTimeInterval(-3580),
            tags: ["api", "deploy", "orders"]
        ),
    ]
}
