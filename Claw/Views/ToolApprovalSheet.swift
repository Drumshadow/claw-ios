import SwiftUI

// MARK: - ToolApprovalSheet

struct ToolApprovalSheet: View {
    let request: ToolApprovalRequest
    let store: ToolApprovalStore

    /// True while a biometric / passcode prompt is in flight — prevents double-tap.
    @State private var isAuthenticating = false

    /// Whether this request requires user authentication before proceeding.
    /// Triggers on gateway-supplied `isDestructive`, policy-level `requireBiometric`,
    /// or a `RiskLevel.critical` evaluation (which always requires biometric).
    private var needsAuth: Bool {
        request.isDestructive
            || request.riskLevel.requiresBiometric
            || (request.matchedPolicy?.requireBiometric == true)
    }

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
            Task { await handleApprove() }
        } label: {
            Text("Approve")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.clawOk, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isAuthenticating)
    }

    private var alwaysAllowButton: some View {
        Button {
            Task { await handleAlwaysAllow() }
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
        .disabled(isAuthenticating)
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

    // MARK: - Approve with optional biometric / passcode gate

    /// Approves the request, requiring device authentication when `needsAuth` is true.
    /// Uses `BiometricGuard` so Face ID / Touch ID failures fall back to the device
    /// passcode rather than silently approving.
    @MainActor
    private func handleApprove() async {
        guard needsAuth else {
            store.approve(id: request.id)
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ok = await BiometricGuard.shared.authenticate(
            reason: "Confirm tool execution: \(request.toolName)"
        )
        guard ok else { return }
        store.approve(id: request.id)
    }

    /// Adds the tool to the always-allow list and approves the current request.
    /// When the request requires authentication (destructive / critical / policy-gated),
    /// the same biometric / passcode check is required before the permanent bypass
    /// is recorded — preventing a UI shortcut that skips the auth gate.
    @MainActor
    private func handleAlwaysAllow() async {
        if needsAuth {
            isAuthenticating = true
            defer { isAuthenticating = false }
            let ok = await BiometricGuard.shared.authenticate(
                reason: "Allow \"\(request.toolName)\" to always run without approval"
            )
            guard ok else { return }
        }
        store.alwaysAllow(toolName: request.toolName)
        store.approve(id: request.id)
    }
}
