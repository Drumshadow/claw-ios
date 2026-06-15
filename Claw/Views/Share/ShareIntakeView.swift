import SwiftUI

// MARK: - ShareIntakeView

/// In-app share intake view. Shown when the main app is opened via the
/// `claw://share` deep link from the share extension, or when the user
/// manually opens a queued share item.
///
/// Flow:
/// 1. User sees what was shared (content preview)
/// 2. Picks an action (diagnose, summarize, etc.)
/// 3. Selects target session or accepts auto-routing
/// 4. Confirms → item sent to ShareIntakeQueue → ShareIntakeProcessor delivers it
@MainActor
struct ShareIntakeView: View {

    // MARK: - Input

    /// Pre-built item (from share extension via deep link).
    let item: ShareIntakeItem
    /// Available sessions for routing selection.
    var sessions: [ClawSession] = []
    /// Delivers the finalized item to the gateway; returns whether it was sent. When nil or it
    /// returns false, the item stays safely queued for delivery on the next gateway connect.
    var onSend: ((ShareIntakeItem) async -> Bool)? = nil
    var onDelivered: ((ShareIntakeItem) -> Void)? = nil
    var onDismiss: () -> Void

    // MARK: - State

    @State private var selectedAction: ShareActionType
    @State private var customPrompt: String = ""
    @State private var selectedRouting: ShareRoutingTarget = .autoSelect
    @State private var showSessionPicker = false
    @State private var isSending = false
    @State private var didDeliver = false
    @State private var errorMessage: String?

    // MARK: - Init

    init(
        item: ShareIntakeItem,
        sessions: [ClawSession] = [],
        onSend: ((ShareIntakeItem) async -> Bool)? = nil,
        onDelivered: ((ShareIntakeItem) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.sessions = sessions
        self.onSend = onSend
        self.onDelivered = onDelivered
        self.onDismiss = onDismiss
        // Pre-select the first recommended action
        let recommended = ShareActionType.recommended(for: item.contentType)
        _selectedAction = State(initialValue: recommended.first ?? .analyze)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Content preview card
                    contentPreviewCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    Divider()
                        .background(Color.clawBorder)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 16)

                    // Action picker
                    ShareActionPickerView(
                        contentType: item.contentType,
                        selectedAction: $selectedAction,
                        customPrompt: $customPrompt
                    )
                    .padding(.horizontal, 16)

                    Divider()
                        .background(Color.clawBorder)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 16)

                    // Session routing
                    routingSection
                        .padding(.horizontal, 16)

                    // Error banner
                    if let err = errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                            Text(err)
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(Color.clawDanger)
                        .padding(12)
                        .background(Color.clawDanger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    Spacer(minLength: 100)
                }
            }
            .background(Color.clawBg.ignoresSafeArea())
            .navigationTitle("Send to Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    sendButton
                }
            }
            .safeAreaInset(edge: .bottom) {
                sendBarButton
            }
        }
    }

    // MARK: - Content preview

    private var contentPreviewCard: some View {
        HStack(spacing: 12) {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 24))
                .foregroundStyle(Color.clawTeal)
                .frame(width: 44, height: 44)
                .background(Color.clawTeal.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(contentTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                Text(contentSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(2)
            }

            Spacer()

            Text(item.contentType.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.clawTeal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.clawTeal.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color.clawBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.clawBorderStrong, lineWidth: 1)
        )
    }

    private var contentTitle: String {
        if let url = item.url { return url.host ?? url.absoluteString }
        if let name = item.fileName { return name }
        if let text = item.textContent { return String(text.prefix(60)) }
        return item.contentType.displayName
    }

    private var contentSubtitle: String {
        if let url = item.url { return url.absoluteString }
        if let text = item.textContent, !text.isEmpty {
            return String(text.prefix(120))
        }
        if let meta = item.extractedMetadata {
            if let title = meta.title { return title }
            if let pages = meta.pageCount { return "\(pages) pages" }
        }
        return "Shared content"
    }

    // MARK: - Routing section

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            // Auto-route option
            routingOption(
                label: "Auto-select session",
                subtitle: "Routes to an available idle session",
                systemImage: "bolt.fill",
                isSelected: routingIsAutoSelect
            ) {
                selectedRouting = .autoSelect
            }

            // Existing sessions
            if !sessions.isEmpty {
                ForEach(sessions.prefix(5)) { session in
                    routingOption(
                        label: session.title,
                        subtitle: statusSubtitle(for: session),
                        systemImage: session.agentStatus == .idle
                            ? "bubble.left.and.bubble.right"
                            : "cpu.fill",
                        isSelected: routingIsSession(session.id)
                    ) {
                        selectedRouting = .session(id: session.id, title: session.title)
                    }
                }
            }

            // New session
            routingOption(
                label: "New session",
                subtitle: "Create a dedicated session for this task",
                systemImage: "plus.square",
                isSelected: routingIsNewSession
            ) {
                selectedRouting = .newSession(agentId: GatewayAgentId.main)
            }
        }
    }

    private func routingOption(
        label: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .black : Color.clawTeal)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? .black : Color.clawText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .black.opacity(0.6) : Color.clawMuted)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.black)
                }
            }
            .padding(12)
            .background(isSelected ? Color.clawTeal : Color.clawBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.clawTeal : Color.clawBorderStrong,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var routingIsAutoSelect: Bool {
        if case .autoSelect = selectedRouting { return true }
        return false
    }

    private func routingIsSession(_ id: String) -> Bool {
        if case .session(let sid, _) = selectedRouting { return sid == id }
        return false
    }

    private var routingIsNewSession: Bool {
        if case .newSession = selectedRouting { return true }
        return false
    }

    private func statusSubtitle(for session: ClawSession) -> String {
        switch session.agentStatus {
        case .idle:     return session.lastMessage.map { String($0.prefix(40)) } ?? "Idle"
        case .running:  return "Agent running…"
        case .thinking: return "Agent thinking…"
        }
    }

    // MARK: - Send actions

    private var sendButton: some View {
        Button("Send") { sendItem() }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSending ? Color.clawMuted : Color.clawAccent)
            .disabled(isSending)
    }

    private var sendBarButton: some View {
        Button(action: sendItem) {
            HStack(spacing: 10) {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.black)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                }
                Text(isSending ? "Sending…" : sendButtonLabel)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isSending ? Color.clawTeal.opacity(0.6) : Color.clawTeal)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .disabled(isSending || didDeliver)
        .background(Color.clawBg)
    }

    private var sendButtonLabel: String {
        "\(selectedAction.displayName)"
    }

    private func sendItem() {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil

        // Build the finalized item with the chosen action + routing. It supersedes the
        // original queued item (created by the share extension with default action/routing),
        // so remove that and enqueue this one — otherwise the same share could be delivered
        // twice with different prompts.
        var finalItem = ShareIntakeItem(
            contentType: item.contentType,
            action: selectedAction,
            routing: selectedRouting,
            customPrompt: selectedAction == .custom ? customPrompt : nil,
            url: item.url,
            fileName: item.fileName,
            fileData: item.fileData,
            textContent: item.textContent
        )
        finalItem.extractedMetadata = item.extractedMetadata

        ShareIntakeQueue.shared.remove(id: item.id)
        ShareIntakeQueue.shared.enqueue(finalItem)

        Task { @MainActor in
            let delivered = await onSend?(finalItem) ?? false
            isSending = false
            if delivered {
                withAnimation { didDeliver = true }
            } else {
                // Not sent right now (offline, or a transient send error). It stays queued and
                // is delivered automatically the next time the app connects.
                errorMessage = "Saved to your share queue — it'll be sent when you're connected."
            }
            // Brief pause so the user sees the result, then advance / close. Closing is driven
            // by onDelivered (not onDismiss), so the queued item is kept for the drain.
            try? await Task.sleep(nanoseconds: delivered ? 600_000_000 : 1_400_000_000)
            onDelivered?(finalItem)
        }
    }
}

// MARK: - ShareIntakeQueueView

/// Shows the current queue of pending/delivered/failed share items.
struct ShareIntakeQueueView: View {
    @State private var queue = ShareIntakeQueue.shared

    var body: some View {
        List {
            if queue.items.isEmpty {
                HStack {
                    Spacer()
                    Text("No shared items")
                        .foregroundStyle(Color.clawMuted)
                    Spacer()
                }
                .listRowBackground(Color.clawBg)
            } else {
                ForEach(queue.items) { item in
                    ShareQueueItemRow(item: item)
                        .listRowBackground(Color.clawBgElevated)
                        .listRowSeparatorTint(Color.clawBorder)
                }
                .onDelete { offsets in
                    let ids = offsets.map { queue.items[$0].id }
                    ids.forEach { queue.remove(id: $0) }
                }
            }
        }
        .listStyle(.plain)
        .background(Color.clawBg.ignoresSafeArea())
        .navigationTitle("Share Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if !queue.items.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear Done") { queue.removeDelivered() }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.clawMuted)
                }
            }
        }
    }
}

private struct ShareQueueItemRow: View {
    let item: ShareIntakeItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.action.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                    Text("·")
                        .foregroundStyle(Color.clawMuted)
                    Text(item.contentType.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                }

                Text(itemPreview)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.status.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())

                Text(item.createdAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.clawMuted.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
    }

    private var itemPreview: String {
        if let url = item.url { return url.absoluteString }
        if let name = item.fileName { return name }
        if let text = item.textContent { return String(text.prefix(80)) }
        return "—"
    }

    private var statusColor: Color {
        switch item.status {
        case .delivered: return .clawOk
        case .failed:    return .clawDanger
        case .sending:   return .clawTeal
        case .ready, .extracting: return .clawWarn
        default:         return .clawMuted
        }
    }
}

// MARK: - Preview

#Preview("ShareIntakeView") {
    let item = ShareIntakeItem(
        contentType: .logs,
        action: .explainLogs,
        url: nil,
        fileName: "app-crash.log",
        textContent: """
        2026-05-22 03:14:15.123 MyApp[1234:5678] FATAL: EXC_BAD_ACCESS (SIGSEGV)
        Thread 0 Crashed:
        0 MyApp 0x0000000100123456 -[ViewController viewDidLoad] + 42
        1 UIKit 0x00000001a2345678 -[UIViewController loadViewIfRequired] + 100
        """
    )
    ShareIntakeView(
        item: item,
        sessions: [
            ClawSession(id: "s1", title: "Main Claude", lastMessage: "Running diagnostics", lastMessageAt: Date(), agentStatus: .idle, unreadCount: 0, model: "claude-sonnet-4-6", totalTokens: nil, estimatedCostUsd: nil),
            ClawSession(id: "s2", title: "Build Agent", lastMessage: "Compiling…", lastMessageAt: Date(), agentStatus: .running, unreadCount: 0, model: nil, totalTokens: nil, estimatedCostUsd: nil)
        ],
        onDismiss: {}
    )
}

#Preview("ShareIntakeQueueView") {
    NavigationStack {
        ShareIntakeQueueView()
    }
}
