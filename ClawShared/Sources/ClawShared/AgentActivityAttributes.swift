import ActivityKit
import Foundation

public struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var sessionTitle: String
        public var currentTool: String?
        public var status: String  // "running", "thinking", "done", "failed"
        public var startedAt: Date

        public init(sessionTitle: String, currentTool: String?, status: String, startedAt: Date) {
            self.sessionTitle = sessionTitle
            self.currentTool = currentTool
            self.status = status
            self.startedAt = startedAt
        }
    }

    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}
