import SwiftUI
import WatchKit

struct ApprovalView: View {
    let approval: WatchBridge.WatchApprovalRequest
    @Environment(WatchBridge.self) private var bridge
    @State private var isProcessing = false

    var riskColor: Color {
        switch approval.riskLevel {
        case "critical": return .red
        case "danger": return .orange
        case "caution": return .yellow
        default: return .green
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Risk indicator bar at top
            Rectangle()
                .fill(riskColor)
                .frame(height: 3)
                .cornerRadius(1.5)

            // Tool name
            Text(approval.toolName)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Description
            Text(approval.description)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Spacer()

            // Approve / Deny buttons
            HStack(spacing: 12) {
                Button(action: { deny() }) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button(action: { approve() }) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.3))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black)
    }

    private func approve() {
        WKInterfaceDevice.current().play(.success)
        bridge.sendApproval(id: approval.id, approved: true)
    }

    private func deny() {
        WKInterfaceDevice.current().play(.failure)
        bridge.sendApproval(id: approval.id, approved: false)
    }
}
