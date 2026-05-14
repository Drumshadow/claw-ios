import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - ChatThreadView

struct ChatThreadView: View {
    let session: ClawSession
    let client: GatewayClient
    var onOpenChildSession: ((ClawSession) -> Void)? = nil

    @State private var store: MessageStore
    @State private var composeText: String = ""
    @State private var pendingScrollRestore: String? = nil
    @State private var showStoppedToast: Bool = false
    @State private var subagentsExpanded: Bool = false
    @State private var pendingAttachments: [AttachmentItem] = []
    @State private var showAttachmentSheet: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showTimeline: Bool = false
    @State private var voiceManager = VoiceInputManager()
    @FocusState private var isComposeFocused: Bool
    @Environment(SessionStore.self) private var sessionStore

    init(
        session: ClawSession,
        client: GatewayClient,
        onOpenChildSession: ((ClawSession) -> Void)? = nil
    ) {
        self.session = session
        self.client = client
        self.onOpenChildSession = onOpenChildSession
        _store = State(initialValue: MessageStore(client: client, sessionKey: session.id))
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
            if let statusText = agentStatus.displayText {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(sessionForHeader.title)
                            .font(.headline)
                            .foregroundStyle(Color.clawTextStrong)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                    }
                }
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
        }
        .task {
            await store.subscribe()
            do {
                try await store.load()
            } catch {
                // Surfaced on store.loadError
            }
        }
        .task {
            await voiceManager.requestPermissions()
        }
        .onChange(of: voiceManager.transcribedText) { _, text in
            if voiceManager.isRecording {
                // Live transcription preview while recording — no-op at MVP;
                // composeText is appended when recording stops.
            }
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
        .onDisappear {
            Task { await store.unsubscribe() }
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
                        ForEach(store.messages) { message in
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
                        }
                        // Bottom padding + scroll anchor combined
                        Color.clear
                            .frame(height: 8)
                            .id("bottom-anchor")
                    }
                }
                .padding(.top, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.messages.count) { oldCount, newCount in
                // Don't auto-scroll-to-bottom when older messages were prepended;
                // the scrollAnchorAfterPrepend handler below restores position.
                let isPrepending = store.scrollAnchorAfterPrepend != nil ||
                                   store.isLoadingMore ||
                                   pendingScrollRestore != nil
                if !isPrepending, newCount > oldCount {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: store.messages.last?.content) { _, _ in
                if store.scrollAnchorAfterPrepend == nil, pendingScrollRestore == nil {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .onChange(of: store.isLoading) { _, isLoading in
                // Yield one run-loop turn after load so LazyVStack finishes layout
                // before scrollToBottom fires (defaultScrollAnchor handles cold-open;
                // this catches the edge case where messages arrive after first render).
                if !isLoading, pendingScrollRestore == nil {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
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

    // MARK: - Compose bar

    private var composeBar: some View {
        VStack(spacing: 0) {
            if !pendingAttachments.isEmpty {
                attachmentChips
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
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
                            .fill(Color.clawBgElevated)
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

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isSendDisabled ? Color.clawMuted : Color.clawAccent)
                }
                .disabled(isSendDisabled)
                .animation(.easeInOut(duration: 0.15), value: isSendDisabled)
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
