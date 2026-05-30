import ActivityKit
import ClawShared
import SwiftUI
import WidgetKit

private enum ModelProvider {
    case anthropic
    case openAI
    case google
    case groq
    case local
    case unknown

    init(model: String?) {
        let value = (model ?? "").lowercased()
        if value.contains("anthropic") || value.contains("claude") {
            self = .anthropic
        } else if value.contains("openai") || value.contains("gpt") || value.contains("o3") || value.contains("o4") {
            self = .openAI
        } else if value.contains("google") || value.contains("gemini") {
            self = .google
        } else if value.contains("groq") || value.contains("llama") || value.contains("mixtral") {
            self = .groq
        } else if value.contains("local") || value.contains("ollama") {
            self = .local
        } else {
            self = .unknown
        }
    }

    var badgeText: String {
        switch self {
        case .anthropic: return "A"
        case .openAI: return "GPT"
        case .google: return "G"
        case .groq: return "GQ"
        case .local: return "L"
        case .unknown: return "AI"
        }
    }

    var symbolName: String {
        switch self {
        case .anthropic: return "a.circle.fill"
        case .openAI: return "sparkle"
        case .google: return "g.circle.fill"
        case .groq: return "bolt.circle.fill"
        case .local: return "desktopcomputer"
        case .unknown: return "brain.head.profile"
        }
    }

    var accent: Color {
        switch self {
        case .anthropic: return Color(red: 0.85, green: 0.72, blue: 0.55)
        case .openAI: return Color(red: 0.35, green: 0.86, blue: 0.68)
        case .google: return Color(red: 0.48, green: 0.68, blue: 1.0)
        case .groq: return Color(red: 1.0, green: 0.55, blue: 0.26)
        case .local: return .green
        case .unknown: return .green
        }
    }
}

private func shortModel(_ m: String?) -> String? {
    guard let m, !m.isEmpty else { return nil }
    let name = String(m.split(separator: "/").last ?? Substring(m))
        .lowercased()
        .replacingOccurrences(of: "-latest", with: "")

    if name.contains("sonnet") { return "Sonnet 4.6" }
    if name.contains("opus") { return "Opus 4.7" }
    if name.contains("haiku") { return "Haiku" }
    if name.hasPrefix("gpt-") { return name.uppercased() }
    if name.contains("gpt-5.5") { return "GPT-5.5" }
    if name.contains("gemini") { return name.replacingOccurrences(of: "gemini-", with: "Gemini ") }
    if name.contains("llama") { return name.replacingOccurrences(of: "llama-", with: "Llama ") }
    return name
        .replacingOccurrences(of: "claude-", with: "")
        .replacingOccurrences(of: "-", with: " ")
}

private func compactStatusSymbol(_ status: String) -> String {
    switch status {
    case "thinking": return "brain.head.profile"
    case "running": return "bolt.fill"
    case "done": return "checkmark"
    case "failed": return "exclamationmark"
    default: return "sparkles"
    }
}

private func activityTitle(_ state: AgentActivityAttributes.ContentState) -> String {
    switch state.status {
    case "thinking": return "Thinking"
    case "running": return state.currentTool == nil ? "Running" : "Using tool"
    case "done": return "Done"
    case "failed": return "Failed"
    case "idle": return "Ready"
    default: return "Working"
    }
}

private struct StatusOrb: View {
    let state: AgentActivityAttributes.ContentState
    let provider: ModelProvider

    private var color: Color {
        switch state.status {
        case "failed": return .red
        case "done", "idle": return .green.opacity(0.75)
        default: return .green
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                if state.status == "thinking" || state.status == "running" {
                    Circle()
                        .stroke(color.opacity(0.45), lineWidth: 3)
                        .scaleEffect(1.8)
                }
            }
            .shadow(color: color.opacity(0.8), radius: 4)
    }
}

private struct ProviderBadge: View {
    let provider: ModelProvider
    var compact: Bool = false

    var body: some View {
        if compact {
            Image(systemName: provider.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(provider.accent)
        } else {
            Text(provider.badgeText)
                .font(.system(size: provider.badgeText.count > 1 ? 8 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(provider.accent))
        }
    }
}

private struct CompactIslandGlyph: View {
    let state: AgentActivityAttributes.ContentState
    let provider: ModelProvider

    var body: some View {
        Image(systemName: compactStatusSymbol(state.status))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(provider.accent)
            .symbolEffect(.pulse, options: .repeating, value: state.status == "thinking" || state.status == "running")
    }
}

struct AgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            AgentLockScreenView(state: context.state)
        } dynamicIsland: { context in
            let provider = ModelProvider(model: context.state.model)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ProviderBadge(provider: provider)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Claw")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(activityTitle(context.state))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.68))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let model = shortModel(context.state.model) {
                            Text(model)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(provider.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        HStack(spacing: 4) {
                            StatusOrb(state: context.state, provider: provider)
                            Text(context.state.currentTool == nil ? provider.badgeText : "Tool")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.sessionTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let tool = context.state.currentTool {
                            Text("Using \(tool)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                ProviderBadge(provider: provider, compact: true)
            } compactTrailing: {
                CompactIslandGlyph(state: context.state, provider: provider)
            } minimal: {
                CompactIslandGlyph(state: context.state, provider: provider)
            }
        }
    }
}

struct AgentLockScreenView: View {
    let state: AgentActivityAttributes.ContentState

    var body: some View {
        let provider = ModelProvider(model: state.model)
        HStack(spacing: 12) {
            ProviderBadge(provider: provider)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.sessionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusOrb(state: state, provider: provider)
                    Text(activityTitle(state))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    if let model = shortModel(state.model) {
                        Text("· \(model)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(provider.accent)
                    }
                }
                if state.status != "idle", let tool = state.currentTool {
                    Text(tool)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.82))
    }
}
