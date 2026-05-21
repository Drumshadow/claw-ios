import ActivityKit
import Foundation

public struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var sessionTitle: String
        public var currentTool: String?
        public var status: String  // "running", "thinking", "done", "failed"
        public var startedAt: Date
        public var model: String?

        public init(sessionTitle: String, currentTool: String?, status: String, startedAt: Date, model: String? = nil) {
            self.sessionTitle = sessionTitle
            self.currentTool = currentTool
            self.status = status
            self.startedAt = startedAt
            self.model = model
        }
    }

    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}
