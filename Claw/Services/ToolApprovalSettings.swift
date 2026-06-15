import Foundation

// MARK: - Tool Approval Settings

/// User opt-in for tool-call approvals (off by default).
///
/// When OFF, the client connects with only `operator.read` / `operator.write` and never
/// receives `exec.approval.requested` events — so existing devices are never bounced for a
/// scope upgrade. When the user turns it ON, the client additionally requests
/// `operator.approvals`; the gateway treats that as a scope upgrade and requires the device
/// to be re-approved once (`openclaw devices approve <id>`) before approvals start flowing.
///
/// Read by `GatewayClient` when building the connect handshake scopes, and toggled from
/// Settings, which reconnects so the new scope is negotiated.
enum ToolApprovalSettings {
    private static let enabledKey = "claw.toolApprovals.enabled"

    /// Whether the client requests the `operator.approvals` scope. Off by default. The
    /// Settings toggle persists this and then reconnects so the new scope is negotiated.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}
