import ActivityKit
import ClawShared
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<AgentActivityAttributes>?
    private var lastActivityUpdateAt: Date = .distantPast
    private var lastActivityState: AgentActivityAttributes.ContentState?
    private let minimumUpdateInterval: TimeInterval = 1.0

    private var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Start persistent (idle) activity when entering a chat
    func startPersistentActivity(sessionId: String, sessionTitle: String, model: String? = nil) {
        // Keep idle activities disabled. Dynamic Island should reflect active work,
        // not leave a permanent "thinking" affordance after the agent is done.
    }

    // MARK: - Start or update when an agent run begins
    func startOrUpdateActivity(sessionId: String, sessionTitle: String, model: String? = nil, status: String = "running") {
        guard activitiesEnabled else { return }

        let displayTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Agent running"
            : sessionTitle

        if currentActivity != nil {
            updateActivity(currentTool: nil, status: status)
            if let model { updateModel(model) }
            return
        }

        let attributes = AgentActivityAttributes(sessionId: sessionId)
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: displayTitle,
            currentTool: nil,
            status: status,
            startedAt: Date(),
            model: model
        )
        currentActivity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
        lastActivityState = state
        lastActivityUpdateAt = Date()
    }

    // MARK: - Update tool / status during a run
    func updateActivity(currentTool: String?, status: String) {
        guard activitiesEnabled, let activity = currentActivity else { return }
        let existingModel = activity.content.state.model
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: activity.content.state.sessionTitle,
            currentTool: currentTool,
            status: status,
            startedAt: activity.content.state.startedAt,
            model: existingModel
        )
        updateActivityIfNeeded(activity, state: state)
    }

    // MARK: - Push model update mid-activity
    func updateModel(_ model: String?) {
        guard activitiesEnabled, let activity = currentActivity, let model else { return }
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: activity.content.state.sessionTitle,
            currentTool: activity.content.state.currentTool,
            status: activity.content.state.status,
            startedAt: activity.content.state.startedAt,
            model: model
        )
        updateActivityIfNeeded(activity, state: state)
    }

    private func updateActivityIfNeeded(
        _ activity: Activity<AgentActivityAttributes>,
        state: AgentActivityAttributes.ContentState
    ) {
        let now = Date()
        let unchanged = lastActivityState?.sessionTitle == state.sessionTitle &&
            lastActivityState?.currentTool == state.currentTool &&
            lastActivityState?.status == state.status &&
            lastActivityState?.model == state.model

        guard !unchanged else { return }
        guard now.timeIntervalSince(lastActivityUpdateAt) >= minimumUpdateInterval else { return }

        lastActivityState = state
        lastActivityUpdateAt = now
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - Set idle after a run completes
    func setIdle() {
        terminateActivity()
    }

    // MARK: - Truly end the activity
    func terminateActivity() {
        guard let activity = currentActivity else { return }
        Task { [weak self] in
            await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            guard let self else { return }
            if self.currentActivity?.id == activity.id {
                self.currentActivity = nil
                self.lastActivityState = nil
                self.lastActivityUpdateAt = .distantPast
            }
        }
    }
}
