import SwiftUI

// MARK: - NodeListView

/// Main node management screen. Shows paired nodes and nodes awaiting approval.
struct NodeListView: View {
    @Environment(NodeStore.self) private var store

    @State private var selectedNode: ClawNode?
    @State private var actionError: String?
    @State private var pendingRejectId: String?

    var body: some View {
        ScrollView {
            Group {
                if store.isLoading && store.nodes.isEmpty && store.pendingNodes.isEmpty {
                    loadingView
                } else if store.nodes.isEmpty && store.pendingNodes.isEmpty {
                    emptyStateView
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        if !store.pendingNodes.isEmpty {
                            pendingSection
                        }
                        if !store.nodes.isEmpty {
                            pairedSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            try? await store.load()
        }
        .navigationTitle("Nodes")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selectedNode) { node in
            NodeDetailView(node: node)
                .environment(store)
        }
        .alert(
            "Action failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button("OK") { actionError = nil }
        } message: { detail in
            Text(detail)
        }
        .task {
            if store.nodes.isEmpty && store.pendingNodes.isEmpty {
                try? await store.load()
            }
        }
    }

    // MARK: - Pending section

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Pending Approval", count: store.pendingNodes.count)
            VStack(spacing: 10) {
                ForEach(store.pendingNodes) { node in
                    PendingNodeRow(
                        node: node,
                        onApprove: { Task { await performApprove(node) } },
                        onReject: { pendingRejectId = node.id }
                    )
                }
            }
        }
        .confirmationDialog(
            "Reject this node?",
            isPresented: Binding(
                get: { pendingRejectId != nil },
                set: { if !$0 { pendingRejectId = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRejectId
        ) { nodeId in
            Button("Reject", role: .destructive) {
                Task { await performReject(nodeId: nodeId) }
            }
            Button("Cancel", role: .cancel) {
                pendingRejectId = nil
            }
        } message: { _ in
            Text("This device will not be able to connect until it requests pairing again.")
        }
    }

    // MARK: - Paired section

    private var pairedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Paired Nodes", count: store.nodes.count)
            VStack(spacing: 10) {
                ForEach(store.nodes) { node in
                    Button {
                        selectedNode = node
                    } label: {
                        PairedNodeRow(node: node)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.clawBgElevated))
            Spacer()
        }
    }

    // MARK: - Loading / empty states

    private var loadingView: some View {
        VStack {
            ProgressView("Loading nodes…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))

            Text("No nodes connected")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)

            Text("Pair a device to manage it from here.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func performApprove(_ node: ClawNode) async {
        do {
            try await store.approve(node.id)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performReject(nodeId: String) async {
        pendingRejectId = nil
        do {
            try await store.reject(nodeId)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - PairedNodeRow

private struct PairedNodeRow: View {
    let node: ClawNode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.platformIconName)
                .font(.system(size: 20))
                .foregroundStyle(Color.clawAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(node.platformLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.clawMuted)
                    Text("·")
                        .foregroundStyle(Color.clawMuted)
                    Text(node.connected ? "Online" : "Offline")
                        .font(.system(size: 12))
                        .foregroundStyle(node.connected ? Color.clawOk : Color.clawMuted)
                }
            }

            Spacer()

            statusDot
                .padding(.trailing, 2)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.clawMuted.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusDot: some View {
        Circle()
            .fill(node.connected ? Color.clawOk : Color.clawMuted.opacity(0.5))
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .stroke(Color.clawOk.opacity(0.3), lineWidth: 3)
                    .scaleEffect(node.connected ? 1.6 : 1)
                    .opacity(node.connected ? 0.6 : 0)
            )
    }
}

// MARK: - PendingNodeRow

private struct PendingNodeRow: View {
    let node: ClawNode
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: node.platformIconName)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.clawWarn)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(node.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(node.platformLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawMuted)
                        Text("·")
                            .foregroundStyle(Color.clawMuted)
                        Text("Awaiting approval")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawWarn)
                    }
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button(action: onReject) {
                    Text("Reject")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawDanger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.clawDanger.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.clawDanger.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onApprove) {
                    Text("Approve")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.clawAccent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawWarn.opacity(0.5), lineWidth: 1)
        )
    }
}
