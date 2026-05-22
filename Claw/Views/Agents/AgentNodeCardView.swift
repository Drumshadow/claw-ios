import SwiftUI

struct AgentNodeCardView: View {
    let node: AgentTreeNode
    var onTap: (() -> Void)? = nil
    @State private var pulse: Bool = false

    var statusColor: Color {
        Color(hex: node.status.color)
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 10) {
                // Status indicator
                ZStack {
                    if node.status == .running || node.status == .thinking {
                        Circle()
                            .fill(statusColor.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .scaleEffect(pulse ? 1.3 : 1.0)
                    }
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: node.status.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let model = node.model {
                            Text(model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.clawTeal.opacity(0.8))
                        }
                        if let tokens = node.tokenCount, tokens > 0 {
                            Text("\(tokens)t")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.clawMuted)
                        }
                    }
                }

                Spacer()

                // Child count badge
                if !node.children.isEmpty {
                    Text("\(node.children.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.clawAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.clawAccent.opacity(0.12))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.clawBgElevated)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(statusColor.opacity(node.status == .running ? 0.4 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if node.status == .running || node.status == .thinking {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

// Color(hex:) is defined in Approvals/RiskBadge.swift — no redeclaration needed here
