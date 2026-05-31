import Foundation

// MARK: - AttachmentItem

struct AttachmentItem: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let mimeType: String
    var textContent: String? = nil
}

// MARK: - ClawMessage

struct ClawMessage: Identifiable, Hashable, Codable {
    let id: String
    let sessionKey: String
    var role: MessageRole
    var content: String          // may grow as tokens stream in; may be UI-truncated for pathological transcripts
    var fullContent: String? = nil // original full text when content is shortened for safe rendering
    var isStreaming: Bool
    var createdAt: Date
    var sendFailed: Bool = false
    var pendingText: String? = nil   // original text retained for retry on failed sends

    // Attachment filenames shown in the bubble (populated for user messages with attachments)
    var attachmentNames: [String]? = nil

    // Tool-call fields (populated when role == .tool)
    var toolName: String? = nil
    var toolInput: [String: JSONValue]? = nil
    var toolResult: String? = nil

    // Thinking content (for extended thinking)
    var thinkingContent: String? = nil

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClawMessage, rhs: ClawMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.fullContent == rhs.fullContent &&
        lhs.isStreaming == rhs.isStreaming &&
        lhs.sendFailed == rhs.sendFailed &&
        lhs.toolResult == rhs.toolResult &&
        lhs.thinkingContent == rhs.thinkingContent
    }
}

// MARK: - MessageRole

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool

    init(rawString: String) {
        switch rawString.lowercased() {
        case "user": self = .user
        case "assistant": self = .assistant
        case "system": self = .system
        case "tool": self = .tool
        default: self = .assistant
        }
    }
}
