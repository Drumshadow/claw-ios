import ActivityKit
import ClawShared
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<AgentActivityAttributes>?

    func startActivity(sessionId: String, sessionTitle: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = AgentActivityAttributes(sessionId: sessionId)
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: sessionTitle,
            currentTool: nil,
            status: "running",
            startedAt: Date()
        )
        currentActivity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func updateActivity(currentTool: String?, status: String) {
        guard let activity = currentActivity else { return }
        let state = AgentActivityAttributes.ContentState(
            sessionTitle: activity.content.state.sessionTitle,
            currentTool: currentTool,
            status: status,
            startedAt: activity.content.state.startedAt
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}
