import SwiftUI

// MARK: - AgentReplayView
//
// Full session replay UI with:
//   - Collapsible token / cost graphs
//   - Message timeline at the replay position (read-only)
//   - Timeline scrubber with step-dot track
//   - Transport controls (play/pause/step/jump)
//   - Branch selector (when multiple branches available)
//   - Jump-to controls (next user, next tool)
//
// Launched from ChatThreadView via the "Replay" toolbar button.
// The session's messages are passed in; live gateway replay data
// is fetched in background via GatewayMethod.sessionReplayData.

struct AgentReplayView: View {
    let sessionTitle: String
    let messages: [ClawMessage]

    @State private var replayStore: ReplayStore
    @State private var graphMode: GraphMode = .none
    @State private var showJumpMenu: Bool = false
    @State private var showBranchSheet: Bool = false

    private enum GraphMode { case none, tokens, cost }

    init(sessionTitle: String, messages: [ClawMessage]) {
        self.sessionTitle = sessionTitle
        self.messages = messages
        _replayStore = State(initialValue: ReplayStore(sessionId: "", messages: messages))
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Graph panel (collapsible)
            if graphMode != .none {
                graphPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // MARK: Replay stats bar
            statsBar

            // MARK: Message area
            replayMessageList

            Divider().background(Color.clawBorder)

            // MARK: Scrubber + controls
            TimelineScrubberView(store: replayStore)
        }
        .background(Color.clawBg)
        .navigationTitle("Replay: \(sessionTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Jump menu
                Menu {
                    Button {
                        replayStore.jumpToNextUserMessage()
                    } label: {
                        Label("Next User Message", systemImage: "person.fill")
                    }
                    Button {
                        replayStore.jumpToNextToolCall()
                    } label: {
                        Label("Next Tool Call", systemImage: "wrench.fill")
                    }
                } label: {
                    Image(systemName: "arrow.forward.to.line")
                }
                .tint(Color.clawAccent)

                // Branches
                if !replayStore.branches.isEmpty && replayStore.branches.count > 1 {
                    Button { showBranchSheet = true } label: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .tint(Color.clawTeal)
                }

                // Graph toggle
                Menu {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            graphMode = graphMode == .tokens ? .none : .tokens
                        }
                    } label: {
                        Label("Token Usage",
                              systemImage: graphMode == .tokens ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis.circle")
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            graphMode = graphMode == .cost ? .none : .cost
                        }
                    } label: {
                        Label("Cost Breakdown",
                              systemImage: graphMode == .cost ? "dollarsign.circle.fill" : "dollarsign.circle")
                    }
                } label: {
                    Image(systemName: graphMode != .none
                        ? "chart.line.uptrend.xyaxis.circle.fill"
                        : "chart.line.uptrend.xyaxis.circle")
                }
                .tint(Color.clawAccent)
            }
        }
        .sheet(isPresented: $showBranchSheet) {
            branchSheet
        }
        .onAppear {
            replayStore.loadPreviewBranches()
        }
    }

    // MARK: - Graph Panel

    @ViewBuilder
    private var graphPanel: some View {
        Group {
            switch graphMode {
            case .tokens:
                TokenGraphView(steps: replayStore.steps, currentIndex: replayStore.currentIndex)
                    .padding(.vertical, 8)
            case .cost:
                CostGraphView(steps: replayStore.steps, currentIndex: replayStore.currentIndex)
                    .padding(.vertical, 8)
            case .none:
                EmptyView()
            }
        }
        .background(Color.clawBgAccent)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            Label(
                replayStore.progressLabel,
                systemImage: "square.stack"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.clawMuted)

            Spacer()

            if replayStore.totalTokens > 0 {
                Label(
                    tokensLabel(replayStore.totalTokens),
                    systemImage: "doc.text"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.clawTeal.opacity(0.8))
            }

            if replayStore.totalCostUsd > 0 {
                Text(String(format: "$%.4f", replayStore.totalCostUsd))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.clawAccent.opacity(0.8))
            }

            if let step = replayStore.currentStep {
                Text(step.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.clawBgAccent)
    }

    // MARK: - Message List

    private var replayMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(replayStore.visibleMessages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 80)
                .animation(.easeInOut(duration: 0.18), value: replayStore.currentIndex)
            }
            .background(Color.clawBg)
            .onChange(of: replayStore.currentIndex) { _, _ in
                if let last = replayStore.visibleMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Branch Sheet

    private var branchSheet: some View {
        NavigationStack {
            List {
                ForEach(replayStore.branches) { branch in
                    Button {
                        replayStore.selectBranch(branch.isMain ? nil : branch.id)
                        showBranchSheet = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if branch.isMain {
                                        Text("main")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.clawTeal.opacity(0.15))
                                            .foregroundStyle(Color.clawTeal)
                                            .clipShape(Capsule())
                                    }
                                    Text(branch.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.clawTextStrong)
                                }
                                HStack(spacing: 8) {
                                    Text("\(branch.messageCount) steps")
                                    Text("·")
                                    Text(tokensLabel(branch.tokenCount))
                                    Text("·")
                                    Text(String(format: "$%.4f", branch.costUsd))
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.clawMuted)
                            }
                            Spacer()
                            if (branch.isMain && replayStore.selectedBranchId == nil) ||
                               branch.id == replayStore.selectedBranchId {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(Color.clawAccent)
                            }
                        }
                    }
                    .listRowBackground(Color.clawCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showBranchSheet = false }
                        .tint(Color.clawAccent)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func tokensLabel(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM tokens", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK tokens", Double(tokens) / 1_000) }
        return "\(tokens) tokens"
    }
}
