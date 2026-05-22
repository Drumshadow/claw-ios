import SwiftUI

struct AgentTreeView: View {
    let rootNode: AgentTreeNode?
    let allNodes: [AgentTreeNode]   // flat list for stats
    var onSelectNode: ((String) -> Void)? = nil  // session ID

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Summary header
                agentSummaryHeader

                Divider().background(Color.clawBorder)

                if let root = rootNode {
                    // Recursive tree rendering with indentation
                    AgentTreeBranchView(node: root, onSelectNode: onSelectNode)
                        .padding(.top, 8)
                } else {
                    emptyState
                }
            }
        }
        .background(Color.clawBg)
        .navigationTitle("Agent Network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var agentSummaryHeader: some View {
        HStack(spacing: 0) {
            statPill(
                count: allNodes.filter { $0.status == .running || $0.status == .thinking }.count,
                label: "Active",
                color: .green
            )
            statPill(count: allNodes.filter { $0.status == .completed }.count, label: "Done", color: .blue)
            statPill(count: allNodes.filter { $0.status == .failed }.count, label: "Failed", color: .red)
            statPill(count: allNodes.count, label: "Total", color: Color.clawMuted)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func statPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 44))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No active agents")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.top, 60)
    }
}

// Recursive branch renderer
struct AgentTreeBranchView: View {
    let node: AgentTreeNode
    var onSelectNode: ((String) -> Void)?
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Node card with indentation based on depth
            HStack(spacing: 0) {
                // Indent + connector line
                if node.depth > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<node.depth, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.clawBorder)
                                .frame(width: 1)
                                .padding(.leading, 19)
                                .padding(.trailing, 11)
                        }
                    }
                }

                AgentNodeCardView(node: node) {
                    onSelectNode?(node.id)
                }
            }
            .padding(.horizontal, node.depth == 0 ? 16 : 0)
            .padding(.trailing, node.depth > 0 ? 16 : 0)
            .padding(.vertical, 4)

            // Children
            if isExpanded && !node.children.isEmpty {
                ForEach(node.children) { child in
                    AgentTreeBranchView(node: child, onSelectNode: onSelectNode)
                }
            }
        }
    }
}
