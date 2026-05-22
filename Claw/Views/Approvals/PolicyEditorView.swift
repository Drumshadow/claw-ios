import SwiftUI

struct PolicyEditorView: View {
    @State private var policies: [ApprovalPolicy] = PolicyEditorView.defaultPolicies
    @State private var editingPolicy: ApprovalPolicy? = nil
    @State private var showAddPolicy = false
    @Environment(\.dismiss) var dismiss

    static let defaultPolicies: [ApprovalPolicy] = [
        ApprovalPolicy(
            name: "Production Database Operations",
            environment: "production",
            toolPattern: "db.*",
            riskLevel: .critical,
            autoApprove: false,
            requireBiometric: true,
            timeoutSeconds: 30,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Production Deployments",
            environment: "production",
            toolPattern: "deploy*",
            riskLevel: .danger,
            autoApprove: false,
            requireBiometric: false,
            timeoutSeconds: 60,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Dev Environment Restarts",
            environment: "dev",
            toolPattern: "docker restart *",
            riskLevel: .caution,
            autoApprove: true,
            requireBiometric: false,
            timeoutSeconds: 0,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Staging Rollbacks",
            environment: "staging",
            toolPattern: "rollback*",
            riskLevel: .danger,
            autoApprove: false,
            requireBiometric: false,
            timeoutSeconds: 45,
            isEnabled: true
        ),
        ApprovalPolicy(
            name: "Read Operations (All Envs)",
            environment: "*",
            toolPattern: "read*",
            riskLevel: .info,
            autoApprove: true,
            requireBiometric: false,
            timeoutSeconds: 0,
            isEnabled: true
        ),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Approval Policies")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Text("Configure risk levels and approval gates")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                    // Policy list
                    if policies.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(policies) { policy in
                                    PolicyRowView(policy: policy)
                                        .onTapGesture {
                                            editingPolicy = policy
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deletePolicy(policy)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }

                                            Button {
                                                duplicatePolicy(policy)
                                            } label: {
                                                Label("Duplicate", systemImage: "doc.on.doc")
                                            }
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddPolicy = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(item: $editingPolicy) { policy in
                PolicyEditSheet(
                    policy: policy,
                    onSave: { updated in
                        if let index = policies.firstIndex(where: { $0.id == policy.id }) {
                            policies[index] = updated
                        }
                    }
                )
            }
            .sheet(isPresented: $showAddPolicy) {
                PolicyEditSheet(
                    policy: ApprovalPolicy(
                        name: "New Policy",
                        environment: "*",
                        toolPattern: "*",
                        riskLevel: .caution,
                        autoApprove: false,
                        requireBiometric: false,
                        timeoutSeconds: 30,
                        isEnabled: true
                    ),
                    onSave: { newPolicy in
                        policies.append(newPolicy)
                    }
                )
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.slash")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("No Policies Configured")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("Add your first approval policy to get started")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deletePolicy(_ policy: ApprovalPolicy) {
        policies.removeAll { $0.id == policy.id }
    }

    private func duplicatePolicy(_ policy: ApprovalPolicy) {
        var duplicate = policy
        duplicate.id = UUID()
        duplicate.name = "\(policy.name) (Copy)"
        policies.append(duplicate)
    }
}

struct PolicyRowView: View {
    let policy: ApprovalPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: name and risk badge
            HStack {
                Text(policy.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                RiskBadge(risk: policy.riskLevel)
            }

            // Environment and pattern
            HStack(spacing: 16) {
                Label {
                    Text(policy.environment)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                } icon: {
                    Image(systemName: "cloud")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }

                Label {
                    Text(policy.toolPattern)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "command")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Status badges
            HStack(spacing: 8) {
                if policy.autoApprove {
                    StatusBadge(text: "Auto-approve", color: .green)
                }

                if policy.requireBiometric {
                    StatusBadge(text: "Biometric", color: .blue)
                }

                if policy.timeoutSeconds > 0 {
                    StatusBadge(text: "\(policy.timeoutSeconds)s timeout", color: .orange)
                }

                Spacer()

                Toggle("", isOn: .constant(policy.isEnabled))
                    .labelsHidden()
                    .disabled(true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .opacity(policy.isEnabled ? 1.0 : 0.5)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}

struct PolicyEditSheet: View {
    @State var policy: ApprovalPolicy
    let onSave: (ApprovalPolicy) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Policy Name", text: $policy.name)
                    TextField("Environment", text: $policy.environment)
                        .autocapitalization(.none)
                    TextField("Tool Pattern", text: $policy.toolPattern)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                }

                Section("Risk Level") {
                    Picker("Risk Level", selection: $policy.riskLevel) {
                        ForEach(RiskLevel.allCases, id: \.self) { level in
                            HStack {
                                RiskBadge(risk: level)
                                Spacer()
                            }
                            .tag(level)
                        }
                    }
                }

                Section("Approval Settings") {
                    Toggle("Auto-approve", isOn: $policy.autoApprove)
                    Toggle("Require Biometric", isOn: $policy.requireBiometric)

                    Stepper(value: $policy.timeoutSeconds, in: 0...300, step: 15) {
                        HStack {
                            Text("Timeout")
                            Spacer()
                            Text(policy.timeoutSeconds == 0 ? "None" : "\(policy.timeoutSeconds)s")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $policy.isEnabled)
                }
            }
            .navigationTitle("Edit Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(policy)
                        dismiss()
                    }
                    .disabled(policy.name.isEmpty || policy.environment.isEmpty || policy.toolPattern.isEmpty)
                }
            }
        }
    }
}

#Preview {
    PolicyEditorView()
}
