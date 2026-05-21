import ActivityKit
import ClawShared
import SwiftUI
import WidgetKit

private func shortModel(_ m: String?) -> String? {
    guard let m else { return nil }
    return m.hasPrefix("claude-") ? String(m.dropFirst(7)) : m
}

struct AgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            AgentLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if context.state.status == "idle" {
                            Circle()
                                .fill(.green.opacity(0.7))
                                .frame(width: 8, height: 8)
                        } else {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.green)
                        }
                        Text(context.state.status == "idle" ? "Connected" : (context.state.currentTool ?? "Running…"))
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(shortModel(context.state.model) ?? String(context.attributes.sessionId.prefix(8)))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.sessionTitle)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        if let model = shortModel(context.state.model) {
                            Text(model)
                                .font(.caption2)
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }
            } compactLeading: {
                if context.state.status == "idle" {
                    Circle()
                        .fill(.green.opacity(0.7))
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: "cpu")
                        .foregroundStyle(.green)
                        .font(.caption2)
                }
            } compactTrailing: {
                Text(shortModel(context.state.model) ?? String(context.state.sessionTitle.prefix(10)))
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                if context.state.status == "idle" {
                    Circle()
                        .fill(.green.opacity(0.7))
                        .frame(width: 6, height: 6)
                } else {
                    Image(systemName: "cpu")
                        .foregroundStyle(.green)
                        .font(.system(size: 9))
                }
            }
        }
    }
}

struct AgentLockScreenView: View {
    let state: AgentActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if state.status == "idle" {
                Circle()
                    .fill(.green.opacity(0.7))
                    .frame(width: 10, height: 10)
            } else {
                ProgressView()
                    .tint(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.sessionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let model = shortModel(state.model) {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                if state.status != "idle", let tool = state.currentTool {
                    Text(tool)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(state.status == "idle" ? "Connected" : state.status.capitalized)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
}
