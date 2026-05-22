import SwiftUI

// MARK: - TimelineEvent

enum TimelineEvent: Identifiable {
    case userMessage(id: String, text: String, date: Date?)
    case assistantMessage(id: String, text: String, date: Date?, isStreaming: Bool)
    case toolCall(id: String, name: String, input: [String: JSONValue], date: Date?)
    case toolResult(id: String, name: String, result: String, date: Date?)
    case agentError(id: String, text: String, date: Date?)

    var id: String {
        switch self {
        case .userMessage(let id, _, _): return id
        case .assistantMessage(let id, _, _, _): return id
        case .toolCall(let id, _, _, _): return id
        case .toolResult(let id, _, _, _): return id
        case .agentError(let id, _, _): return id
        }
    }

    var nodeColor: Color {
        switch self {
        case .userMessage: return Color.clawAccent
        case .assistantMessage: return .white
        case .toolCall: return Color.clawWarn
        case .toolResult: return Color.clawOk
        case .agentError: return Color.clawDanger
        }
    }

    var typeLabel: String {
        switch self {
        case .userMessage: return "User"
        case .assistantMessage: return "Assistant"
        case .toolCall: return "Tool Call"
        case .toolResult: return "Tool Result"
        case .agentError: return "Error"
        }
    }

    var contentPreview: String {
        switch self {
        case .userMessage(_, let text, _): return text
        case .assistantMessage(_, let text, _, _): return text
        case .toolCall(_, let name, let input, _):
            if input.isEmpty { return name }
            let keys = input.keys.sorted().prefix(3).joined(separator: ", ")
            return "\(name) — \(keys)"
        case .toolResult(_, let name, let result, _):
            return "\(name): \(result)"
        case .agentError(_, let text, _): return text
        }
    }

    var fullContent: String {
        switch self {
        case .userMessage(_, let text, _): return text
        case .assistantMessage(_, let text, _, _): return text
        case .toolCall(_, let name, let input, _):
            if input.isEmpty { return name }
            let pairs = input.keys.sorted().map { key -> String in
                let v = input[key] ?? .null
                return "\(key): \(jsonPreview(v))"
            }
            return "Tool: \(name)\n" + pairs.joined(separator: "\n")
        case .toolResult(_, let name, let result, _):
            return "Tool: \(name)\nResult: \(result)"
        case .agentError(_, let text, _): return text
        }
    }

    var date: Date? {
        switch self {
        case .userMessage(_, _, let d): return d
        case .assistantMessage(_, _, let d, _): return d
        case .toolCall(_, _, _, let d): return d
        case .toolResult(_, _, _, let d): return d
        case .agentError(_, _, let d): return d
        }
    }

    private func jsonPreview(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return s
        case .array(let arr): return "[\(arr.count) items]"
        case .object(let obj): return "{\(obj.count) keys}"
        }
    }
}

// MARK: - AgentTimelineView

struct AgentTimelineView: View {
    let messages: [ClawMessage]

    // Memoized cache to avoid rebuilding the timeline on every render.
    // The cache key is a lightweight fingerprint: message count + last message's
    // id/content/streaming state. This covers all mutations that change the
    // timeline (appends, content updates during streaming, tool result updates).
    @State private var cachedEvents: [TimelineEvent] = []
    @State private var cacheKey: String = ""

    private var currentCacheKey: String {
        guard let last = messages.last else { return "empty" }
        return "\(messages.count)|\(last.id)|\(last.content.count)|\(last.isStreaming)|\(last.toolResult ?? "")"
    }

    private func buildEvents() -> [TimelineEvent] {
        messages.compactMap { msg -> TimelineEvent? in
            switch msg.role {
            case .user:
                return .userMessage(id: msg.id, text: msg.content, date: msg.createdAt)
            case .assistant:
                return .assistantMessage(
                    id: msg.id,
                    text: msg.content,
                    date: msg.createdAt,
                    isStreaming: msg.isStreaming
                )
            case .tool:
                if msg.toolResult == nil {
                    return .toolCall(
                        id: msg.id,
                        name: msg.toolName ?? msg.content,
                        input: msg.toolInput ?? [:],
                        date: msg.createdAt
                    )
                } else {
                    return .toolResult(
                        id: msg.id,
                        name: msg.toolName ?? msg.content,
                        result: msg.toolResult ?? "",
                        date: msg.createdAt
                    )
                }
            case .system:
                return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            if cachedEvents.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cachedEvents.enumerated()), id: \.element.id) { index, event in
                        AgentTimelineEventRow(
                            event: event,
                            isLast: index == cachedEvents.count - 1
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color.clawBg)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: currentCacheKey) {
            // Rebuild the timeline only when the fingerprint changes.
            let key = currentCacheKey
            guard key != cacheKey else { return }
            cachedEvents = buildEvents()
            cacheKey = key
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No events yet")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.top, 80)
    }
}

// MARK: - AgentTimelineEventRow

private struct AgentTimelineEventRow: View {
    let event: TimelineEvent
    let isLast: Bool
    @State private var isExpanded: Bool = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline track
            trackColumn

            // Event content
            VStack(alignment: .leading, spacing: 0) {
                eventCard
                    .padding(.bottom, isLast ? 0 : 12)
            }
            .padding(.leading, 12)
        }
    }

    // MARK: - Track column

    private var trackColumn: some View {
        VStack(spacing: 0) {
            // Node circle
            ZStack {
                Circle()
                    .fill(event.nodeColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
            }
            .padding(.top, 4)

            // Connector line
            if !isLast {
                Rectangle()
                    .fill(Color.clawBorder)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 2)
            }
        }
        .frame(width: 12)
    }

    // MARK: - Event card

    private var eventCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.typeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(Color.clawMuted)
                    .kerning(0.5)

                Spacer()

                if let date = event.date {
                    Text(Self.timeFormatter.string(from: date))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.clawMuted)
                }
            }

            // Content preview (collapsed) or full (expanded)
            if isExpanded {
                Text(event.fullContent)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(event.contentPreview)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Expand/collapse toggle if content overflows preview
            if event.fullContent.count > 80 || event.fullContent.contains("\n") {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.clawAccent)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.clawAccent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }
}
