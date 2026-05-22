import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - EmptyParams

private struct EmptyParams: Encodable {}

private struct ChatBottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ChatThreadView

struct ChatThreadView: View {
    let session: ClawSession
    let client: GatewayClient
    var onOpenChildSession: ((ClawSession) -> Void)? = nil

    @State private var store: MessageStore
    @State private var composeText: String = ""
    @State private var pendingScrollRestore: String? = nil
    @State private var isNearBottom: Bool = true
    @State private var forceScrollAfterSend: Bool = false
    @State private var showStoppedToast: Bool = false
    @State private var subagentsExpanded: Bool = false
    @State private var pendingAttachments: [AttachmentItem] = []
    @State private var showAttachmentSheet: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showTimeline: Bool = false
    @State private var showModelPicker = false
    @State private var sendButtonPressed = false
    @State private var avatarPulse: CGFloat = 1.0
    @State private var voiceManager = VoiceInputManager()
    @State private var slashSuggestions: [ClawSkill] = []
    // Voice Ops Mode (operational push-to-talk, separate from compose dictation)
    @State private var voiceOpsManager = VoiceOpsManager()
    @State private var showVoiceOpsOverlay: Bool = false
    @State private var showVoiceDrivingMode: Bool = false
    @FocusState private var isComposeFocused: Bool
    @Environment(SessionStore.self) private var sessionStore
    @Environment(SkillsStore.self) private var skillsStore

    init(
        session: ClawSession,
        client: GatewayClient,
        onOpenChildSession: ((ClawSession) -> Void)? = nil
    ) {
        self.session = session
        self.client = client
        self.onOpenChildSession = onOpenChildSession
        _store = State(initialValue: MessageStore(client: client, sessionKey: session.id, sessionTitle: session.title, sessionModel: session.model))
    }

    // MARK: - Computed

    // Resolved once per body render. Several computed properties below depend on
    // this — without caching, each access does a fresh linear scan of `sessionStore.sessions`
    // and SwiftUI calls them many times per frame during streaming.
    private var sessionForHeader: ClawSession {
        sessionStore.sessions.first { $0.id == session.id } ?? session
    }

    private var agentStatus: AgentStatus {
        sessionForHeader.agentStatus
    }

    private var isAgentActive: Bool {
        switch agentStatus {
        case .running, .thinking: return true
        case .idle: return false
        }
    }

    private var hasActiveStream: Bool {
        store.messages.contains { $0.id.hasPrefix("stream-") && $0.isStreaming }
    }

    private var currentToolName: String? {
        store.messages.last(where: { $0.role == .tool && $0.isStreaming })?.toolName
    }

    private var isSendDisabled: Bool {
        (composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
         pendingAttachments.isEmpty) ||
        store.isSending
    }

    private var hasMetadata: Bool {
        let s = sessionForHeader
        return (s.model != nil) ||
               (s.totalTokens != nil && (s.totalTokens ?? 0) > 0) ||
               (s.estimatedCostUsd != nil && (s.estimatedCostUsd ?? 0) > 0)
    }

    private var childSessionKeys: [String] {
        sessionForHeader.childSessionKeys
    }

    private var filteredSlashSuggestions: [ClawSkill] {
        guard composeText.hasPrefix("/") else { return [] }
        let query = String(composeText.dropFirst()).lowercased()
        let eligible = skillsStore.skills.filter { $0.enabled && $0.eligible }
        if query.isEmpty { return Array(eligible.prefix(8)) }
        return eligible.filter {
            $0.skillKey.lowercased().hasPrefix(query) ||
            $0.name.lowercased().hasPrefix(query) ||
            $0.skillKey.lowercased().contains(query)
        }.prefix(8).map { $0 }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if hasMetadata {
                    metadataRow
                }
                messageList
                    .background(Color.clawBg)
                if !childSessionKeys.isEmpty {
                    subagentsSection
                }
                if isAgentActive {
                    activePill
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.15), value: isAgentActive)
                }
                if !filteredSlashSuggestions.isEmpty {
                    slashSuggestionsPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.15), value: filteredSlashSuggestions.isEmpty)
                }
                composeBar
            }
            .background(Color.clawBg)

            if showStoppedToast {
                stoppedToast
                    .transition(.opacity)
            }
        }
        .navigationTitle(sessionForHeader.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showModelPicker = true } label: {
                    HStack(spacing: 10) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.clawTeal, Color.clawAccent],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 34, height: 34)
                            if isAgentActive {
                                Image(systemName: "cpu")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .scaleEffect(avatarPulse)
                            } else {
                                Image(systemName: "brain")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        // Title + status
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sessionForHeader.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.clawTextStrong)
                                .lineLimit(1)
                            // Status subtitle
                            if isAgentActive {
                                if let tool = currentToolName {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.clawOk)
                                            .frame(width: 3, height: 3)
                                            .scaleEffect(avatarPulse)
                                        Text(tool)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.clawTeal)
                                            .lineLimit(1)
                                    }
                                } else {
                                    HStack(spacing: 3) {
                                        Text("Thinking")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.clawMuted)
                                        AnimatedDotsView()
                                    }
                                }
                            } else if let model = sessionForHeader.model, !model.isEmpty {
                                Text(shortModelName(model))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.clawTeal.opacity(0.8))
                            } else {
                                Text("Connected")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.clawOk.opacity(0.7))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if isAgentActive {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: stopAgent) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .tint(Color.clawDanger)
                    .accessibilityLabel("Stop agent")
                }
            }
            if !isAgentActive && !store.messages.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sendExplainPrompt()
                    } label: {
                        Image(systemName: "lightbulb")
                    }
                    .tint(Color.clawAccent)
                    .accessibilityLabel("Explain what happened")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showTimeline = true
                } label: {
                    Image(systemName: "timeline.selection")
                }
                .tint(Color.clawAccent)
                .accessibilityLabel("View timeline")
            }
            // Voice Ops Mode button
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showVoiceOpsOverlay = true
                    } label: {
                        Label("Voice Command", systemImage: "mic.badge.plus")
                    }
                    Button {
                        showVoiceDrivingMode = true
                    } label: {
                        Label("Driving Mode", systemImage: "car.fill")
                    }
                } label: {
                    Image(systemName: voiceOpsManager.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            voiceOpsManager.isRecording ? Color.clawDanger :
                            (voiceOpsManager.isSpeaking ? Color.clawTeal : Color.clawAccent)
                        )
                }
                .accessibilityLabel("Voice Operations")
            }
        }
        .task {
            await store.subscribe()
            store.updateSessionModel(sessionForHeader.model)

            if isAgentActive {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    avatarPulse = 1.15
                }
            }

            // Eagerly resolve model from config.get — session.model is often nil on first open
            // because the gateway delivers it lazily. We need it now so the Dynamic Island
            // shows the model name the moment the user backgrounds the app.
            var resolvedModel: String? = sessionForHeader.model
            if (resolvedModel == nil || resolvedModel!.isEmpty),
               let payload = try? await client.send(method: GatewayMethod.configGet, params: EmptyParams()),
               let modelVal = payload["model"], case .string(let m) = modelVal, !m.isEmpty {
                resolvedModel = m
                store.updateSessionModel(m)
            }

            // Start persistent Live Activity so model name shows on island immediately
            LiveActivityManager.shared.startPersistentActivity(
                sessionId: session.id,
                sessionTitle: session.title,
                model: resolvedModel
            )
            do {
                try await store.load()
            } catch {
                // Surfaced on store.loadError
            }
        }
        .task {
            await voiceManager.requestPermissions()
        }
        // Voice Ops Overlay sheet
        .sheet(isPresented: $showVoiceOpsOverlay) {
            VoiceOpsOverlay(
                manager: voiceOpsManager,
                client: client,
                sessionKey: session.id,
                onDismiss: { showVoiceOpsOverlay = false }
            )
            .presentationDetents([.large])
            .presentationBackground(Color.clawBg)
            .presentationDragIndicator(.visible)
        }
        // Voice Driving Mode full screen
        .fullScreenCover(isPresented: $showVoiceDrivingMode) {
            VoiceDrivingModeView(
                manager: voiceOpsManager,
                client: client,
                sessionKey: session.id,
                onDismiss: { showVoiceDrivingMode = false }
            )
        }
        .sheet(isPresented: $showTimeline) {
            NavigationStack {
                AgentTimelineView(messages: store.messages)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showTimeline = false }
                                .tint(Color.clawAccent)
                        }
                    }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(client: client, currentModel: sessionForHeader.model)
        }
        .onDisappear {
            Task { await store.unsubscribe() }
            LiveActivityManager.shared.terminateActivity()
        }
        .onChange(of: sessionForHeader.model) { _, newModel in
            store.updateSessionModel(newModel)
        }
        .onChange(of: isAgentActive) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    avatarPulse = 1.15
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    avatarPulse = 1.0
                }
            }
        }
    }

    // MARK: - Metadata row

    private var metadataText: String {
        let s = sessionForHeader
        var fragments: [String] = []
        if let model = s.model, !model.isEmpty {
            fragments.append(model)
        }
        if let tokens = s.totalTokens, tokens > 0 {
            let formatted = Self.tokenFormatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
            fragments.append("\(formatted) tokens")
        }
        if let cost = s.estimatedCostUsd, cost > 0 {
            fragments.append(formatCost(cost))
        }
        return fragments.joined(separator: " · ")
    }

    private var metadataRow: some View {
        HStack {
            Text(metadataText)
                .font(.caption2)
                .foregroundStyle(Color.clawMuted)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.clawBgAccent)
        .overlay(
            Divider().background(Color.clawBorder),
            alignment: .bottom
        )
    }

    // MARK: - Message list

    private var messageList: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if store.isLoading && store.messages.isEmpty {
                            ProgressView("Loading messages…")
                                .tint(Color.clawAccent)
                                .foregroundStyle(Color.clawMuted)
                                .padding(.top, 40)
                        } else if store.messages.isEmpty && !store.isLoading {
                            emptyMessagesView
                        } else {
                            // Top sentinel — triggers `loadMore` when it appears.
                            topSentinel
                            ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                                let prevRole = index > 0 ? store.messages[index - 1].role : nil
                                let sameSender = prevRole == message.role
                                MessageBubbleView(
                                    message: message,
                                    onRetry: message.sendFailed ? {
                                        Task { await store.retrySend(messageId: message.id) }
                                    } : nil,
                                    onDiscard: message.sendFailed ? {
                                        store.discardFailed(messageId: message.id)
                                    } : nil
                                )
                                .id(message.id)
                                .padding(.top, sameSender ? 0 : 4)
                            }
                            if isAgentActive && !hasActiveStream {
                                TypingIndicatorView()
                                    .id("typing-indicator")
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                            }
                            // Bottom padding + scroll anchor combined
                            Color.clear
                                .frame(height: 8)
                                .id("bottom-anchor")
                                .background(
                                    GeometryReader { bottomProxy in
                                        Color.clear.preference(
                                            key: ChatBottomOffsetPreferenceKey.self,
                                            value: bottomProxy.frame(in: .named("chat-scroll")).minY
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.top, 8)
                }
                .coordinateSpace(name: "chat-scroll")
                .onPreferenceChange(ChatBottomOffsetPreferenceKey.self) { bottomOffset in
                    // Native chat behavior: only follow new content while the user is
                    // already near the tail. If they scroll up to read history, don't
                    // yank them back down on every stream delta.
                    isNearBottom = bottomOffset <= viewport.size.height + 160
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.messages.count) { oldCount, newCount in
                    // Don't auto-scroll-to-bottom when older messages were prepended;
                    // the scrollAnchorAfterPrepend handler below restores position.
                    let isPrepending = store.scrollAnchorAfterPrepend != nil ||
                                       store.isLoadingMore ||
                                       pendingScrollRestore != nil
                    if !isPrepending, newCount > oldCount, isNearBottom || forceScrollAfterSend {
                        scrollToBottom(proxy: proxy, animated: true)
                        forceScrollAfterSend = false
                    }
                }
                .onChange(of: store.messages.last?.content) { _, _ in
                    if store.scrollAnchorAfterPrepend == nil, pendingScrollRestore == nil, !isComposeFocused, isNearBottom {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: store.messages.last?.id) { _, _ in
                    if store.scrollAnchorAfterPrepend == nil, pendingScrollRestore == nil, !store.isLoadingMore, isNearBottom || forceScrollAfterSend {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            scrollToBottom(proxy: proxy, animated: false)
                            forceScrollAfterSend = false
                        }
                    }
                }
                .onChange(of: store.isLoading) { _, isLoading in
                    // Yield one run-loop turn after load so LazyVStack finishes layout
                    // before scrollToBottom fires (defaultScrollAnchor handles cold-open;
                    // this catches the edge case where messages arrive after first render).
                    if !isLoading, pendingScrollRestore == nil, isNearBottom {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                }
                .onChange(of: store.scrollAnchorAfterPrepend) { _, anchorId in
                    guard let anchorId else { return }
                    pendingScrollRestore = anchorId
                    proxy.scrollTo(anchorId, anchor: .top)
                    store.clearScrollAnchor()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        pendingScrollRestore = nil
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // Triggers loadMore when the top sentinel becomes visible (user scrolled to top).
    private var topSentinel: some View {
        Group {
            if store.hasMore {
                HStack {
                    Spacer()
                    if store.isLoadingMore {
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
                    Task { await store.loadMore() }
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .id("top-sentinel")
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No messages yet")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
            Text("Send a message to start the conversation.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    // MARK: - Subagents section

    private var subagentsSection: some View {
        // Snapshot keys + per-key session once per render so we don't recompute
        // `childSessionKeys` or scan `sessionStore.sessions` for every row.
        let keys = childSessionKeys
        let sessionsByKey = Dictionary(uniqueKeysWithValues:
            sessionStore.sessions.lazy
                .filter { keys.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let lastKey = keys.last
        return VStack(spacing: 0) {
            Divider().background(Color.clawBorder)
            DisclosureGroup(isExpanded: $subagentsExpanded) {
                VStack(spacing: 0) {
                    ForEach(keys, id: \.self) { key in
                        SubagentRowView(
                            key: key,
                            session: sessionsByKey[key]
                        ) {
                            openChild(key: key)
                        }
                        if key != lastKey {
                            Divider().background(Color.clawBorder)
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                    Text("Subagents (\(keys.count))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.clawText)
                }
            }
            .tint(Color.clawMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.clawBgAccent)
        }
    }

    private func openChild(key: String) {
        let resolved = sessionStore.sessions.first { $0.id == key }
        let target = resolved ?? ClawSession(
            id: key,
            title: String(key.prefix(12)),
            lastMessage: nil,
            lastMessageAt: nil,
            agentStatus: .idle,
            unreadCount: 0,
            model: nil,
            totalTokens: nil,
            estimatedCostUsd: nil
        )
        onOpenChildSession?(target)
    }

    // MARK: - Active pill

    private var activePill: some View {
        let currentTool = store.messages.last(where: { $0.role == .tool && $0.isStreaming })?.toolName
        let statusText = currentTool.map { "Running: \($0)" } ?? (agentStatus.displayText ?? "Working…")

        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(Color.clawAccent)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: stopAgent) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.clawDanger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop agent")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 36)
        .background(Color.clawBgAccent)
        .overlay(
            Divider().background(Color.clawBorder),
            alignment: .top
        )
    }

    // MARK: - Slash suggestions panel

    private var slashSuggestionsPanel: some View {
        VStack(spacing: 0) {
            Divider().background(Color.clawBorder)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(filteredSlashSuggestions) { skill in
                        Button {
                            composeText = "/\(skill.skillKey) "
                            isComposeFocused = true
                        } label: {
                            HStack(spacing: 10) {
                                if let emoji = skill.emoji {
                                    Text(emoji)
                                        .font(.system(size: 18))
                                        .frame(width: 28)
                                } else {
                                    Image(systemName: "command")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.clawAccent)
                                        .frame(width: 28)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("/\(skill.skillKey)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.clawText)
                                    if !skill.description.isEmpty {
                                        Text(skill.description)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.clawMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if skill.id != filteredSlashSuggestions.last?.id {
                            Divider()
                                .padding(.leading, 54)
                                .background(Color.clawBorder)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(Color.clawBgAccent)
        }
    }

    // MARK: - Compose bar

    private var composeBar: some View {
        VStack(spacing: 0) {
            if !pendingAttachments.isEmpty {
                attachmentChips
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            if voiceManager.isRecording && !voiceManager.transcribedText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawDanger)
                    Text(voiceManager.transcribedText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.clawText)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.clawDanger.opacity(0.08))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    if voiceManager.isRecording {
                        voiceManager.stopRecording()
                        if !voiceManager.transcribedText.isEmpty {
                            composeText += (composeText.isEmpty ? "" : " ") + voiceManager.transcribedText
                        }
                    } else {
                        voiceManager.startRecording()
                    }
                } label: {
                    Image(systemName: voiceManager.isRecording ? "waveform.circle.fill" : "mic.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(voiceManager.isRecording ? Color.clawAccent : Color.clawMuted)
                        .animation(.easeInOut(duration: 0.2), value: voiceManager.isRecording)
                }
                .buttonStyle(.plain)
                .disabled(voiceManager.permissionDenied)
                .accessibilityLabel(voiceManager.isRecording ? "Stop recording" : "Start voice input")

                Button {
                    showAttachmentSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.clawMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add attachment")
                .confirmationDialog("Add Attachment", isPresented: $showAttachmentSheet) {
                    Button("Photo Library") { showPhotoPicker = true }
                    Button("File") { showFilePicker = true }
                    Button("Cancel", role: .cancel) { }
                }
                .photosPicker(
                    isPresented: $showPhotoPicker,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 10,
                    matching: .any(of: [.images, .videos])
                )
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task { await loadPhotoItems(newItems) }
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [UTType.item],
                    allowsMultipleSelection: true
                ) { result in
                    handleFileImport(result: result)
                }

                TextField("Message", text: $composeText, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.clawText)
                    .tint(Color.clawAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clawBgHover)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.clawBorderStrong, lineWidth: 1)
                            )
                    )
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .focused($isComposeFocused)
                    .onSubmit {
                        if !isSendDisabled { sendMessage() }
                    }

                Button {
                    sendButtonPressed = true
                    Task {
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        sendButtonPressed = false
                        sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isSendDisabled ? Color.clawMuted : Color.clawAccent)
                }
                .disabled(isSendDisabled)
                .buttonStyle(.plain)
                .scaleEffect(sendButtonPressed ? 0.92 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: sendButtonPressed)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            Color.clawBgAccent
                .overlay(
                    Divider()
                        .background(Color.clawBorder),
                    alignment: .top
                )
        )
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pendingAttachments) { attachment in
                    HStack(spacing: 4) {
                        Text(attachment.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawText)
                            .lineLimit(1)
                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.clawMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.clawBgElevated)
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Stopped toast

    private var stoppedToast: some View {
        VStack {
            Spacer()
            Text("Stopped")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.clawTextStrong)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.clawBgElevated)
                )
                .overlay(
                    Capsule().strokeBorder(Color.clawBorderStrong, lineWidth: 1)
                )
                .padding(.bottom, 80)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        composeText = ""
        pendingAttachments = []
        selectedPhotoItems = []
        forceScrollAfterSend = true
        Task {
            try? await store.send(text: text, attachments: attachments)
        }
    }

    // MARK: - Attachment loading

    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            // Derive a filename and MIME type from the content type if available
            let mimeType: String
            let name: String
            if let contentType = item.supportedContentTypes.first {
                mimeType = contentType.preferredMIMEType ?? "application/octet-stream"
                let ext = contentType.preferredFilenameExtension ?? "bin"
                name = "photo.\(ext)"
            } else {
                mimeType = "image/jpeg"
                name = "photo.jpg"
            }
            let attachment = AttachmentItem(name: name, data: data, mimeType: mimeType)
            await MainActor.run {
                pendingAttachments.append(attachment)
            }
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .failure:
            break
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                let name = url.lastPathComponent
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let textContent = extractTextContent(from: data, mimeType: mimeType)
                pendingAttachments.append(AttachmentItem(name: name, data: data, mimeType: mimeType, textContent: textContent))
            }
        }
    }

    private func extractTextContent(from data: Data, mimeType: String) -> String? {
        if mimeType == "application/pdf" {
            guard let doc = PDFDocument(data: data) else { return nil }
            var text = ""
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        if mimeType.hasPrefix("text/") || ["application/json", "application/xml"].contains(mimeType) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func sendExplainPrompt() {
        let prompt = "In 2-3 sentences, summarize what you just did, what succeeded, and what failed if anything. Be concise."
        composeText = ""
        forceScrollAfterSend = true
        Task {
            try? await store.send(text: prompt)
        }
    }

    private func stopAgent() {
        // The chat "aborted" event from the gateway will clear agentStatus via SessionStore.
        Task {
            try? await store.abort()
            withAnimation(.easeInOut(duration: 0.15)) {
                showStoppedToast = true
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                showStoppedToast = false
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }

    // MARK: - Formatting helpers

    private func shortModelName(_ m: String) -> String {
        m.hasPrefix("claude-") ? String(m.dropFirst(7)) : m
    }

    private func formatCost(_ value: Double) -> String {
        let formatter = value < 1 ? Self.costFormatterPrecise : Self.costFormatterStandard
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.4f", value)
    }

    private static let tokenFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let costFormatterStandard: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let costFormatterPrecise: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 4
        f.maximumFractionDigits = 4
        return f
    }()
}

// MARK: - SubagentRowView

private struct SubagentRowView: View {
    let key: String
    let session: ClawSession?
    let onTap: () -> Void

    private var displayName: String {
        if let title = session?.title, !title.isEmpty { return title }
        return String(key.prefix(12))
    }

    private var status: AgentStatus {
        session?.agentStatus ?? .idle
    }

    private var dotColor: Color {
        switch status {
        case .idle:     return Color.clawMuted.opacity(0.5)
        case .thinking: return Color.clawWarn
        case .running:  return Color.clawOk
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TypingIndicatorView

private struct TypingIndicatorView: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.clawMuted)
                        .frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * max(0, sin(phase - Double(i) * 0.6)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clawCard)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1))
            )
            Spacer(minLength: 48)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - AnimatedDotsView

private struct AnimatedDotsView: View {
    @State private var opacities: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.clawMuted)
                    .frame(width: 3, height: 3)
                    .opacity(opacities[i])
            }
        }
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.4)
                    .delay(Double(i) * 0.15)
                    .repeatForever(autoreverses: true)
                ) {
                    opacities[i] = 1.0
                }
            }
        }
    }
}

// MARK: - ModelPickerSheet

struct ModelPickerSheet: View {
    let client: GatewayClient
    let currentModel: String?
    @State private var availableModels: [String] = []
    @State private var selectedModel: String = ""
    @State private var thinkingBudget: String = UserDefaults.standard.string(forKey: "claw.thinkingBudget") ?? "medium"
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    private let fallbackModels = ["claude-opus-4-7", "claude-opus-4-5", "claude-sonnet-4-6", "claude-sonnet-4-5", "claude-haiku-4-5"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        ForEach(availableModels, id: \.self) { model in
                            Button {
                                selectedModel = model
                                Task { await updateModel(model) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model)
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.clawText)
                                        Text(modelDescription(model))
                                            .font(.caption2)
                                            .foregroundStyle(Color.clawMuted)
                                    }
                                    Spacer()
                                    if model == selectedModel {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.clawAccent)
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clawCard)
                        }
                    }
                } header: {
                    Text("Model").foregroundStyle(Color.clawMuted).font(.caption)
                }

                Section {
                    ForEach(["low", "medium", "high"], id: \.self) { level in
                        Button {
                            thinkingBudget = level
                            UserDefaults.standard.set(level, forKey: "claw.thinkingBudget")
                            Task { await updateThinkingBudget(level) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.capitalized)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.clawText)
                                    Text(budgetDescription(level))
                                        .font(.caption2)
                                        .foregroundStyle(Color.clawMuted)
                                }
                                Spacer()
                                if level == thinkingBudget {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.clawAccent)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clawCard)
                    }
                } header: {
                    Text("Thinking Budget").foregroundStyle(Color.clawMuted).font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Session Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(Color.clawAccent)
                }
            }
            .task { await loadConfig() }
        }
        .preferredColorScheme(.dark)
    }

    private func loadConfig() async {
        isLoading = true
        selectedModel = currentModel ?? ""
        if let payload = try? await client.send(method: GatewayMethod.configGet, params: EmptyParams()) {
            if let modelsVal = payload["availableModels"] ?? payload["models"],
               case .array(let arr) = modelsVal {
                availableModels = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
            }
            if let modelVal = payload["model"], case .string(let m) = modelVal, !m.isEmpty {
                selectedModel = m
            }
        }
        if availableModels.isEmpty { availableModels = fallbackModels }
        if selectedModel.isEmpty, let first = availableModels.first { selectedModel = first }
        isLoading = false
    }

    private func updateModel(_ model: String) async {
        struct ModelPatch: Encodable { let model: String }
        _ = try? await client.send(method: GatewayMethod.configPatch, params: ModelPatch(model: model))
    }

    private func updateThinkingBudget(_ budget: String) async {
        struct BudgetPatch: Encodable { let thinkingBudget: String }
        _ = try? await client.send(method: GatewayMethod.configPatch, params: BudgetPatch(thinkingBudget: budget))
    }

    private func modelDescription(_ model: String) -> String {
        if model.contains("opus") { return "Most capable" }
        if model.contains("sonnet") { return "Balanced" }
        if model.contains("haiku") { return "Fast & efficient" }
        return ""
    }

    private func budgetDescription(_ level: String) -> String {
        switch level {
        case "low": return "~1k tokens — quick answers"
        case "medium": return "~8k tokens — balanced reasoning"
        case "high": return "~32k tokens — deep analysis"
        default: return ""
        }
    }
}
