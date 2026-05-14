import SwiftUI

// MARK: - MessageBubbleView

struct MessageBubbleView: View {
    let message: ClawMessage
    var onRetry: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil

    private var isUser: Bool { message.role == .user }
    private var isFailed: Bool { message.sendFailed }
    private var isTool: Bool { message.role == .tool }

    var body: some View {
        if isTool {
            ToolCallRowView(message: message)
        } else {
            chatRow
        }
    }

    // MARK: - Standard chat row (user/assistant/system)

    private var chatRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                HStack(alignment: .bottom, spacing: 6) {
                    if isUser && isFailed {
                        failureIndicator
                    }
                    bubbleContent
                }
                if isFailed {
                    failureFooter
                } else {
                    timestampText
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Bubble

    private var bubbleContent: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isUser, let names = message.attachmentNames, !names.isEmpty {
                attachmentChips(names: names)
            }
            Group {
                if isUser {
                    if !message.content.isEmpty {
                        Text(displayText)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.clawText)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    MarkdownTextView(text: displayText)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.clawText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground)
        .overlay(bubbleBorder)
    }

    @ViewBuilder
    private func attachmentChips(names: [String]) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(names, id: \.self) { name in
                Label(name, systemImage: "doc")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isUser ? Color.clawAccentSubtle : Color.clawCard)
    }

    @ViewBuilder
    private var bubbleBorder: some View {
        if isFailed {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawDanger.opacity(0.7), lineWidth: 1)
        } else if message.isStreaming {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawAccent.opacity(0.5), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        }
    }

    // MARK: - Failure UI

    private var failureIndicator: some View {
        Button {
            onRetry?()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.clawDanger)
                    .frame(width: 20, height: 20)
                Text("!")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry send")
    }

    private var failureFooter: some View {
        HStack(spacing: 8) {
            Button("Retry") { onRetry?() }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.clawAccent)
                .buttonStyle(.plain)
            Text("·")
                .foregroundStyle(Color.clawMuted)
            Button("Discard") { onDiscard?() }
                .font(.system(size: 11))
                .foregroundStyle(Color.clawMuted)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Display text

    private var displayText: String {
        message.isStreaming ? message.content + "▌" : message.content
    }

    // MARK: - Timestamp

    private var timestampText: some View {
        Text(formattedTime)
            .font(.system(size: 11))
            .foregroundStyle(Color.clawMuted)
            .padding(.horizontal, 4)
    }

    private var formattedTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(message.createdAt) {
            return Self.timeOnlyFormatter.string(from: message.createdAt)
        } else if calendar.isDateInYesterday(message.createdAt) {
            return "Yesterday \(Self.timeOnlyFormatter.string(from: message.createdAt))"
        } else {
            return Self.dateTimeFormatter.string(from: message.createdAt)
        }
    }

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

// MARK: - ToolCallRowView

/// Compact, expandable row for tool_use / tool_result events shown inline in the thread.
private struct ToolCallRowView: View {
    let message: ClawMessage
    @State private var expanded: Bool = false

    private var displayName: String {
        if let n = message.toolName, !n.isEmpty { return n }
        return message.content.isEmpty ? "tool" : message.content
    }

    private var isPending: Bool { message.toolResult == nil && message.isStreaming }

    var body: some View {
        HStack {
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawAccent)
                        Text(displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.clawText)
                            .lineLimit(1)
                        if isPending {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(Color.clawMuted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.clawMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    expandedBody
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.clawBgAccent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.clawBorder, lineWidth: 1)
            )
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .onAppear {
            if isPending { expanded = true }
        }
        .onChange(of: isPending) { _, nowPending in
            if nowPending { expanded = true }
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let input = message.toolInput, !input.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Input")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.clawMuted)
                    ForEach(formattedInputLines(input), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.clawMuted)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let result = message.toolResult, !result.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Result")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.clawMuted)
                    Text(truncatedResult(result))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.clawText)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if isPending {
                Text("Running…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Formatting helpers

    private func formattedInputLines(_ input: [String: JSONValue]) -> [String] {
        input.keys.sorted().map { key in
            let valueText = previewValue(input[key] ?? .null)
            return "\(key): \(valueText)"
        }
    }

    private func previewValue(_ value: JSONValue) -> String {
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

    private func truncatedResult(_ s: String) -> String {
        let maxChars = 400
        if s.count <= maxChars { return s }
        let idx = s.index(s.startIndex, offsetBy: maxChars)
        return String(s[..<idx]) + "…"
    }
}
