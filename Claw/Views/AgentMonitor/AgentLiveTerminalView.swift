import SwiftUI

// MARK: - AgentLiveTerminalView

/// Terminal-style scrolling feed of tool calls and live agent output for a running agent.
struct AgentLiveTerminalView: View {
    let messages: [ClawMessage]

    private var visibleMessages: [ClawMessage] {
        messages.filter {
            $0.role == .tool ||
            ($0.role == .assistant && !$0.isStreaming && !$0.content.isEmpty)
        }
    }

    private var streamingAssistant: ClawMessage? {
        messages.last { $0.role == .assistant && $0.isStreaming }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visibleMessages.isEmpty && streamingAssistant == nil {
                        emptyState
                    } else {
                        ForEach(visibleMessages) { msg in
                            if msg.role == .tool {
                                TerminalRowView(message: msg)
                                    .id(msg.id)
                            } else {
                                TerminalTextRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        if let stream = streamingAssistant {
                            TerminalStreamRow(message: stream)
                                .id(stream.id)
                        }
                    }
                    Color.clear.frame(height: 8).id("term-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }
            .onChange(of: visibleMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("term-bottom", anchor: .bottom)
                }
            }
            .onChange(of: visibleMessages.last?.content) { _, _ in
                proxy.scrollTo("term-bottom", anchor: .bottom)
            }
            .onChange(of: streamingAssistant?.content) { _, _ in
                proxy.scrollTo("term-bottom", anchor: .bottom)
            }
            .defaultScrollAnchor(.bottom)
        }
        .background(Color.black.opacity(0.92))
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(.green)
            Text("Waiting for agent activity…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.green.opacity(0.6))
        }
        .padding(.top, 20)
    }
}

// MARK: - TerminalRowView

private struct TerminalRowView: View {
    let message: ClawMessage

    private var isPending: Bool { message.toolResult == nil && message.isStreaming }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: status icon + short tool label + file/detail
            HStack(alignment: .top, spacing: 8) {
                statusIcon
                    .frame(width: 14, height: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(toolLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isPending ? .green : .green.opacity(0.8))

                        if !headerDetail.isEmpty {
                            Text(headerDetail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(isPending ? 0.75 : 0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // Multi-line bash command body (shown below header when command spans multiple lines)
            if let cmd = fullBashCommand {
                Text(cmd)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
                    .padding(.leading, 22)
            }

            // Code being written (new_string for edits, content for writes)
            if let code = codeContent {
                codeBlock(code)
                    .padding(.top, 4)
                    .padding(.leading, 22)
            }

            // Tool result output (bash stdout, write confirmation, etc.)
            if let result = message.toolResult, !result.isEmpty {
                resultBlock(result)
                    .padding(.top, 3)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isPending {
            ProgressView()
                .scaleEffect(0.55)
                .tint(.green)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green.opacity(0.65))
        }
    }

    private var toolLabel: String {
        let name = message.toolName ?? message.content
        switch name {
        case "str_replace_based_edit_tool", "str_replace_editor", "str_replace": return "Edit"
        case "write_file", "create_file", "write":                               return "Write"
        case "read_file", "read":                                                return "Read"
        case "bash", "execute_bash", "run_bash":                                 return "Bash"
        case "list_directory", "ls":                                             return "List"
        case "glob_tool", "glob":                                                return "Glob"
        case "grep_tool", "grep":                                                return "Grep"
        default:                                                                 return name
        }
    }

    // Short summary shown inline with the tool name in the header row.
    private var headerDetail: String {
        guard let input = message.toolInput else { return "" }
        if let path = str(input["file_path"]) ?? str(input["path"]) { return path }
        if let cmd = str(input["command"]) {
            let first = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                           .components(separatedBy: "\n").first ?? ""
            // Multi-line commands get a trailing ellipsis here; full body shown below header.
            return cmd.contains("\n") ? String(first.prefix(60)) + "…" : String(first.prefix(80))
        }
        if let pattern = str(input["pattern"]) { return pattern }
        for key in ["query", "description", "method", "url"] {
            if let val = str(input[key]) { return val }
        }
        return ""
    }

    // Full multi-line bash command body — only populated when command contains newlines
    // (single-line commands are fully shown in the header detail).
    private var fullBashCommand: String? {
        guard let input = message.toolInput,
              let cmd = str(input["command"]),
              cmd.contains("\n") else { return nil }
        return cmd.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Code being written — present for Edit (new_string) and Write (content) tool calls.
    private var codeContent: String? {
        guard let input = message.toolInput else { return nil }
        if let s = str(input["new_string"])  { return s }
        if let s = str(input["content"])     { return s }
        return nil
    }

    @ViewBuilder
    private func codeBlock(_ code: String) -> some View {
        let lines      = code.components(separatedBy: "\n")
        let maxLines   = 25
        let truncated  = lines.count > maxLines
        let display    = (truncated ? Array(lines.prefix(maxLines)) : lines).joined(separator: "\n")

        VStack(alignment: .leading, spacing: 2) {
            Text(display)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

            if truncated {
                Text("… \(lines.count - maxLines) more lines")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 8)
            }
        }
    }

    @ViewBuilder
    private func resultBlock(_ result: String) -> some View {
        let lines     = result.components(separatedBy: "\n")
        let maxLines  = 12
        let truncated = lines.count > maxLines
        let display   = (truncated ? Array(lines.prefix(maxLines)) : lines).joined(separator: "\n")

        VStack(alignment: .leading, spacing: 0) {
            Text(display)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
            if truncated {
                Text("… \(lines.count - maxLines) more lines")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func str(_ v: JSONValue?) -> String? {
        guard let v, case .string(let s) = v, !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - TerminalTextRow

private struct TerminalTextRow: View {
    let message: ClawMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("›")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 14)
                .padding(.top, 2)

            Text(message.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TerminalStreamRow

private struct TerminalStreamRow: View {
    let message: ClawMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
                .scaleEffect(0.55)
                .tint(.green)
                .frame(width: 14)
                .padding(.top, 2)

            // Append a block cursor so the user can see streaming is live.
            Text(message.content + "▌")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }
}
