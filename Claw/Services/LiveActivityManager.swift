import ActivityKit
import ClawShared
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<AgentActivityAttributes>?

    // MARK: - Start persistent (idle) activity when entering a chat
    func startPersistentActivity(sessionId: String, sessionTitle: String, model: String? = nil) {
        guard currentActivity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = AgentActivityAttributes(sessionId: sessionId)
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: sessionTitle,
            currentTool: nil,
            status: "idle",
            startedAt: Date(),
            model: model
        )
        currentActivity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    // MARK: - Start or update to "running" when an agent run begins
    func startOrUpdateActivity(sessionId: String, sessionTitle: String, model: String? = nil) {
        if currentActivity != nil {
            // Already have a persistent activity — just update status to running
            updateActivity(currentTool: nil, status: "running")
            if let model { updateModel(model) }
        } else {
            // Not started yet (e.g. opened via push) — start fresh as running
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = AgentActivityAttributes(sessionId: sessionId)
            let state = AgentActivityAttributes.ContentState(
                sessionTitle: sessionTitle.isEmpty ? String(sessionId.prefix(12)) : sessionTitle,
                currentTool: nil,
                status: "running",
                startedAt: Date(),
                model: model
            )
            currentActivity = try? Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        }
    }

    // MARK: - Update tool / status during a run
    func updateActivity(currentTool: String?, status: String) {
        guard let activity = currentActivity else { return }
        let existingModel = activity.content.state.model
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: activity.content.state.sessionTitle,
            currentTool: currentTool,
            status: status,
            startedAt: activity.content.state.startedAt,
            model: existingModel
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - Push model update mid-activity
    func updateModel(_ model: String?) {
        guard let activity = currentActivity, let model else { return }
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: activity.content.state.sessionTitle,
            currentTool: activity.content.state.currentTool,
            status: activity.content.state.status,
            startedAt: activity.content.state.startedAt,
            model: model
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - Set idle after a run completes (keeps activity alive on island)
    func setIdle() {
        guard let activity = currentActivity else { return }
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: activity.content.state.sessionTitle,
            currentTool: nil,
            status: "idle",
            startedAt: activity.content.state.startedAt,
            model: activity.content.state.model
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - Truly end the activity (called when leaving the chat)
    func terminateActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}
