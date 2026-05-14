import SwiftUI

// MARK: - AgentReadOnlyThreadView

struct AgentReadOnlyThreadView: View {
    let session: AgentMonitorSession

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var messageStore: MessageStore?
    @State private var pendingScrollRestore: String? = nil
    @State private var viewMode: ViewMode = .activity

    private enum ViewMode { case activity, chat }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                Group {
                    if viewMode == .activity {
                        AgentLiveTerminalView(messages: messageStore?.messages ?? [])
                    } else {
                        messageList
                            .background(Color.clawBg)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                spectatorFooter
            }
            .background(Color.clawBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(session.title)
                            .font(.headline)
                            .foregroundStyle(Color.clawTextStrong)
                            .lineLimit(1)
                        spectatorTitleBadge
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(Color.clawAccent)
                }
            }
        }
        .task {
            guard let client = appState.activeClient else { return }
            let store = MessageStore(client: client, sessionKey: session.id)
            messageStore = store
            await store.subscribe()
            try? await store.load()
            guard session.status == .running else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                store.pollUpdates()
            }
        }
        .onDisappear {
            Task { await messageStore?.unsubscribe() }
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            Text("Activity").tag(ViewMode.activity)
            Text("Chat").tag(ViewMode.chat)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.clawBgAccent)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let store = messageStore {
                        if store.isLoading && store.messages.isEmpty {
                            ProgressView("Loading messages…")
                                .tint(Color.clawAccent)
                                .foregroundStyle(Color.clawMuted)
                                .padding(.top, 40)
                        } else if store.messages.isEmpty && !store.isLoading {
                            emptyStateView
                        } else {
                            topSentinel
                            ForEach(store.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                            Color.clear
                                .frame(height: 8)
                                .id("bottom-anchor")
                        }
                    } else {
                        ProgressView("Loading messages…")
                            .tint(Color.clawAccent)
                            .foregroundStyle(Color.clawMuted)
                            .padding(.top, 40)
                    }
                }
                .padding(.top, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messageStore?.messages.count) { oldCount, newCount in
                let isPrepending = messageStore?.scrollAnchorAfterPrepend != nil ||
                                   messageStore?.isLoadingMore == true ||
                                   pendingScrollRestore != nil
                if !isPrepending, (newCount ?? 0) > (oldCount ?? 0) {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: messageStore?.messages.last?.content) { _, _ in
                if messageStore?.scrollAnchorAfterPrepend == nil, pendingScrollRestore == nil {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .onChange(of: messageStore?.isLoading) { _, isLoading in
                if isLoading == false, pendingScrollRestore == nil {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
            }
            .onChange(of: messageStore?.scrollAnchorAfterPrepend) { _, anchorId in
                guard let anchorId else { return }
                pendingScrollRestore = anchorId
                proxy.scrollTo(anchorId, anchor: .top)
                messageStore?.clearScrollAnchor()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    pendingScrollRestore = nil
                }
            }
        }
    }

    private var topSentinel: some View {
        Group {
            if messageStore?.hasMore == true {
                HStack {
                    Spacer()
                    if messageStore?.isLoadingMore == true {
                        ProgressView()
                            .tint(Color.clawAccent)
                    } else {
                        Text("Pull to load older")
                            .font(.caption2)
                            .foregroundStyle(Color.clawMuted)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .onAppear {
                    Task { await messageStore?.loadMore() }
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .id("top-sentinel")
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "ellipsis.bubble")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("Waiting for output…")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    // MARK: - Spectator badge (toolbar subtitle)

    @ViewBuilder
    private var spectatorTitleBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 9))
            Text("SPECTATING")
                .font(.system(size: 9, weight: .bold))
            if session.status == .running {
                Text("· LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .foregroundStyle(Color.clawMuted)
        .tracking(0.5)
    }

    // MARK: - Spectator footer (replaces compose bar to make read-only obvious)

    private var spectatorFooter: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusDotColor.opacity(0.25))
                    .frame(width: 18, height: 18)
                Image(systemName: "eye.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusDotColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Read-only spectator view")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.clawText)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.clawMuted)
                    if session.status == .running {
                        ProgressView()
                            .scaleEffect(0.55)
                            .tint(Color.clawMuted)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(
            Color.clawBgAccent
                .overlay(
                    Divider().background(Color.clawBorder),
                    alignment: .top
                )
        )
    }

    private var statusDotColor: Color {
        switch session.status {
        case .running:   return .green
        case .completed: return Color.clawMuted.opacity(0.5)
        case .error:     return Color.clawDanger
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .running:   return "Agent is running…"
        case .completed: return "Session completed"
        case .error:     return "Session ended with error"
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }
}
