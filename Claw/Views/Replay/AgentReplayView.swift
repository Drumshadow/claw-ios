import SwiftUI

struct AgentReplayView: View {
    let sessionTitle: String
    let messages: [ClawMessage]
    @State private var replayStore: ReplayStore
    @State private var showTokenGraph: Bool = false

    init(sessionTitle: String, messages: [ClawMessage]) {
        self.sessionTitle = sessionTitle
        self.messages = messages
        _replayStore = State(initialValue: ReplayStore(sessionId: "", messages: messages))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Token graph (collapsible)
            if showTokenGraph {
                TokenGraphView(steps: replayStore.steps, currentIndex: replayStore.currentIndex)
                    .padding(.vertical, 8)
                    .background(Color.clawBgAccent)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Message replay area (read-only, shows visibleMessages)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(replayStore.visibleMessages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.2), value: replayStore.currentIndex)
            }
            .background(Color.clawBg)

            Divider().background(Color.clawBorder)

            // Timeline scrubber at bottom
            TimelineScrubberView(store: replayStore)
        }
        .navigationTitle("Replay: \(sessionTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation { showTokenGraph.toggle() }
                } label: {
                    Image(systemName: showTokenGraph ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis.circle")
                }
                .tint(Color.clawAccent)
            }
        }
    }
}
