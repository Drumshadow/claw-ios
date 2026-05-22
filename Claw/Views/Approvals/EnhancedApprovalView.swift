import SwiftUI

struct EnhancedApprovalView: View {
    let toolName: String
    let toolInput: String?      // JSON string of tool params
    let risk: RiskLevel
    let environment: String
    var onApprove: () -> Void
    var onDeny: () -> Void
    var onDryRun: (() -> Void)? = nil   // nil if dry-run not supported for this tool

    @State private var isAuthenticating: Bool = false
    @State private var showInput: Bool = false
    @State private var authError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with risk badge and environment
            HStack {
                RiskBadge(risk: risk)

                Spacer()

                Text(environment.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
            }

            // Tool name
            Text(toolName)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            // Tool input (collapsible)
            if let input = toolInput, !input.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: { showInput.toggle() }) {
                        HStack {
                            Text("Parameters")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

                            Image(systemName: showInput ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    if showInput {
                        ScrollView {
                            Text(formatJSON(input))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.3))
                        )
                    }
                }
            }

            // Auth error message
            if let error = authError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)

                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.1))
                )
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Action buttons
            HStack(spacing: 12) {
                // Dry run button (if supported)
                if let dryRunAction = onDryRun {
                    Button(action: dryRunAction) {
                        HStack(spacing: 6) {
                            Image(systemName: "eyes")
                                .font(.system(size: 14))
                            Text("Dry Run")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                }

                // Deny button
                Button(action: onDeny) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Deny")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.3))
                    )
                }

                // Approve button
                Button(action: { Task { await handleApprove() } }) {
                    HStack(spacing: 6) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            if risk.requiresBiometric {
                                Image(systemName: BiometricGuard.shared.availableType == .faceID ? "faceid" : "touchid")
                                    .font(.system(size: 14))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                            }
                            Text("Approve")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: risk.color))
                    )
                }
                .disabled(isAuthenticating)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding()
    }

    private func handleApprove() async {
        authError = nil

        if risk.requiresBiometric {
            isAuthenticating = true
            let ok = await BiometricGuard.shared.authenticate(reason: "Approve \(toolName)")
            isAuthenticating = false

            if ok {
                onApprove()
            } else {
                authError = "Authentication failed. Please try again."
            }
        } else {
            onApprove()
        }
    }

    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return json
        }
        return prettyString
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            EnhancedApprovalView(
                toolName: "db.delete",
                toolInput: #"{"table": "users", "where": {"id": 12345}}"#,
                risk: .critical,
                environment: "production",
                onApprove: { print("Approved") },
                onDeny: { print("Denied") },
                onDryRun: { print("Dry run") }
            )

            EnhancedApprovalView(
                toolName: "deploy.rollout",
                toolInput: #"{"service": "api", "version": "v2.1.0"}"#,
                risk: .danger,
                environment: "staging",
                onApprove: { print("Approved") },
                onDeny: { print("Denied") }
            )
        }
    }
}
