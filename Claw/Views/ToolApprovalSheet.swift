import SwiftUI
import LocalAuthentication

// MARK: - ToolApprovalSheet

struct ToolApprovalSheet: View {
    let request: ToolApprovalRequest
    let store: ToolApprovalStore

    var body: some View {
        ZStack {
            Color.clawBgAccent.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: Icon + header
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(request.isDestructive ? Color.clawDanger : Color.clawWarn)

                        Text("Tool Approval Required")
                            .font(.title2.bold())
                            .foregroundStyle(Color.clawTextStrong)

                        Text("An agent wants to run:")
                            .font(.subheadline)
                            .foregroundStyle(Color.clawMuted)
                    }
                    .padding(.top, 32)

                    // MARK: Tool name
                    Text(request.toolName)
                        .font(.system(.title2, design: .monospaced).bold())
                        .foregroundStyle(Color.clawText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    // MARK: Tool input code block
                    if !request.toolInput.isEmpty {
                        toolInputBlock
                    }

                    // MARK: Meta labels
                    VStack(spacing: 6) {
                        if let nodeId = request.nodeId {
                            Text("on node: \(nodeId)")
                                .font(.caption)
                                .foregroundStyle(Color.clawMuted)
                        }
                        Text("session: \(String(request.sessionKey.prefix(12)))…")
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                    }

                    // MARK: Action buttons
                    VStack(spacing: 12) {
                        approveButton
                        alwaysAllowButton
                        denyButton
                        denyNeverAllowButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Tool input block

    private var toolInputBlock: some View {
        let lines = request.toolInput.sorted(by: { $0.key < $1.key }).map { key, value in
            "\"\(key)\": \(displayValue(value))"
        }
        let capped = Array(lines.prefix(8))
        let text = capped.joined(separator: "\n")

        return ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.clawText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.clawBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func displayValue(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return "\"\(s)\""
        case .int(let i):    return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "null"
        case .array(let a):  return "[\(a.count) items]"
        case .object(let o): return "{\(o.count) keys}"
        }
    }

    // MARK: - Buttons

    private var approveButton: some View {
        Button {
            handleApprove()
        } label: {
            Text("Approve")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.clawOk, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var alwaysAllowButton: some View {
        Button {
            store.alwaysAllow(toolName: request.toolName)
            store.approve(id: request.id)
        } label: {
            Text("Always Allow \"\(request.toolName)\"")
                .font(.subheadline)
                .foregroundStyle(Color.clawAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.clawBgAccent, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.clawBorder, lineWidth: 1)
                )
        }
    }

    private var denyButton: some View {
        Button {
            store.deny(id: request.id)
        } label: {
            Text("Deny")
                .font(.headline)
                .foregroundStyle(Color.clawDanger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.clawDanger, lineWidth: 1.5)
                )
        }
    }

    private var denyNeverAllowButton: some View {
        Button {
            store.deny(id: request.id)
        } label: {
            Text("Deny & Never Allow")
                .font(.caption)
                .foregroundStyle(Color.clawMuted)
        }
    }

    // MARK: - Face ID for destructive approve

    private func handleApprove() {
        guard request.isDestructive else {
            store.approve(id: request.id)
            return
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No biometrics available — allow anyway
            store.approve(id: request.id)
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Confirm destructive tool execution"
        ) { success, _ in
            if success {
                Task { @MainActor in store.approve(id: request.id) }
            }
        }
    }
}
