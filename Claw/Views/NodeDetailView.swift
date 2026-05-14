import SwiftUI

// MARK: - NodeDetailView

/// Detail screen for a paired node. Surfaces metadata and lets the user send a push notification.
struct NodeDetailView: View {
    @Environment(NodeStore.self) private var store

    let node: ClawNode

    @State private var copiedNodeId: Bool = false
    @State private var showNotificationComposer: Bool = false
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    @State private var isSending: Bool = false
    @State private var sendError: String?
    @State private var sendConfirmation: Bool = false

    /// Live-tracked version of the node from the store, so reactive event updates
    /// (e.g. connect/disconnect) reflect immediately.
    private var liveNode: ClawNode {
        store.nodes.first(where: { $0.id == node.id }) ?? node
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                metadataCard
                if !liveNode.caps.isEmpty {
                    capsCard
                }
                actionsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .navigationTitle(liveNode.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showNotificationComposer) {
            notificationComposer
        }
        .alert(
            "Send failed",
            isPresented: Binding(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            ),
            presenting: sendError
        ) { _ in
            Button("OK") { sendError = nil }
        } message: { detail in
            Text(detail)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 14) {
            Image(systemName: liveNode.platformIconName)
                .font(.system(size: 44))
                .foregroundStyle(Color.clawAccent)
                .frame(width: 80, height: 80)
                .background(
                    Circle().fill(Color.clawAccentSubtle)
                )

            VStack(spacing: 4) {
                Text(liveNode.displayName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                Text(liveNode.platformLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawMuted)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(liveNode.connected ? Color.clawOk : Color.clawMuted.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(liveNode.connected ? "Online" : "Offline")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(liveNode.connected ? Color.clawOk : Color.clawMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.clawBgElevated)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    // MARK: - Metadata

    private var metadataCard: some View {
        VStack(spacing: 0) {
            metadataRow(label: "Node ID", trailing: {
                AnyView(
                    Button {
                        UIPasteboard.general.string = liveNode.id
                        withAnimation { copiedNodeId = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await MainActor.run { withAnimation { copiedNodeId = false } }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(liveNode.id)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Color.clawText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: copiedNodeId ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(copiedNodeId ? Color.clawOk : Color.clawAccent)
                        }
                    }
                    .buttonStyle(.plain)
                )
            })

            divider

            metadataRow(label: "Platform", trailing: {
                AnyView(
                    Text(liveNode.platformLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.clawText)
                )
            })

            divider

            metadataRow(label: "Status", trailing: {
                AnyView(
                    Text(liveNode.connected ? "Connected" : "Disconnected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(liveNode.connected ? Color.clawOk : Color.clawMuted)
                )
            })

            if let approved = liveNode.approvedAt {
                divider
                metadataRow(label: "Approved", trailing: {
                    AnyView(
                        Text(Self.dateFormatter.string(from: approved))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.clawText)
                    )
                })
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func metadataRow(label: String, trailing: () -> AnyView) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.clawTextStrong)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.clawBorder)
            .frame(height: 1)
    }

    // MARK: - Capabilities

    private var capsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capabilities")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(liveNode.caps, id: \.self) { cap in
                    Text(cap)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.clawTextStrong)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.clawBgElevated)
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.clawBorder, lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                notificationTitle = ""
                notificationBody = ""
                showNotificationComposer = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Send Notification")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(liveNode.connected ? Color.clawAccent : Color.clawMuted.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
            .disabled(!liveNode.connected)

            if sendConfirmation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.clawOk)
                    Text("Notification sent")
                        .foregroundStyle(Color.clawOk)
                        .font(.system(size: 13, weight: .medium))
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    // MARK: - Notification composer

    private var notificationComposer: some View {
        NavigationStack {
            ZStack {
                Color.clawBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Send notification to \(liveNode.displayName)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.clawMuted)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.clawMuted)
                            .textCase(.uppercase)
                        TextField("", text: $notificationTitle, prompt: Text("e.g. Build complete").foregroundColor(Color.clawMuted.opacity(0.6)))
                            .textFieldStyle(.plain)
                            .foregroundStyle(Color.clawText)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.clawCard)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.clawBorder, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Body")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.clawMuted)
                            .textCase(.uppercase)
                        TextEditor(text: $notificationBody)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(Color.clawText)
                            .frame(minHeight: 100, maxHeight: 200)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.clawCard)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.clawBorder, lineWidth: 1)
                            )
                    }

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("New Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showNotificationComposer = false
                    }
                    .tint(Color.clawText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await performSend() }
                    } label: {
                        if isSending {
                            ProgressView()
                                .tint(Color.clawAccent)
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .tint(Color.clawAccent)
                    .disabled(isSending || !canSend)
                }
            }
        }
    }

    private var canSend: Bool {
        !notificationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !notificationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func performSend() async {
        isSending = true
        defer { isSending = false }
        do {
            try await store.sendNotification(
                to: liveNode.id,
                title: notificationTitle,
                body: notificationBody
            )
            showNotificationComposer = false
            withAnimation { sendConfirmation = true }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { withAnimation { sendConfirmation = false } }
            }
        } catch {
            sendError = error.localizedDescription
        }
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

// MARK: - FlowLayout (wrapping chips)

private struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
