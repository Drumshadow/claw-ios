import ActivityKit
import ClawShared
import SwiftUI
import WidgetKit

struct AgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            // Lock Screen / Notification banner
            AgentLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.currentTool ?? "Running…", systemImage: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.sessionId.prefix(8))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.green)
                        Text(context.state.sessionTitle)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(context.state.status.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            } compactLeading: {
                Image(systemName: "cpu")
                    .foregroundStyle(.green)
                    .font(.caption)
            } compactTrailing: {
                Text(context.state.sessionTitle.prefix(10))
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "cpu")
                    .foregroundStyle(.green)
            }
        }
    }
}

struct AgentLockScreenView: View {
    let state: AgentActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.sessionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let tool = state.currentTool {
                    Text(tool)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(state.status.capitalized)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
}
