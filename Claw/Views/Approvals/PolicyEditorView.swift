import SwiftUI

// MARK: - PolicyEditorView
//
// Full CRUD editor for approval policies backed by PolicyStore.
// Policies are persisted to UserDefaults (with biometric-gated ones
// cross-referenced in Keychain for tamper detection).

struct PolicyEditorView: View {
    @State private var store = PolicyStore.shared
    @State private var editingPolicy: ApprovalPolicy? = nil
    @State private var showAddPolicy = false
    @State private var showAlwaysAllowSheet = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Approval Policies")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Configure risk levels and approval gates")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            // Policy count badge
                            Text("\(store.policies.count)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // Engine health summary
                    PolicyEngineStatusBanner(policies: store.policies)
                        .padding(.horizontal)
                        .padding(.bottom, 12)

                    // Policy list
                    if store.policies.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            ForEach(store.policies) { policy in
                                PolicyRowView(policy: policy)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .onTapGesture { editingPolicy = policy }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.delete(policy)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            store.duplicate(policy)
                                        } label: {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }
                                        .tint(.blue)

                                        Button {
                                            store.setEnabled(policy.id, enabled: !policy.isEnabled)
                                        } label: {
                                            Label(
                                                policy.isEnabled ? "Disable" : "Enable",
                                                systemImage: policy.isEnabled ? "pause.circle" : "play.circle"
                                            )
                                        }
                                        .tint(policy.isEnabled ? .orange : .green)
                                    }
                                    .contextMenu {
                                        Button {
                                            editingPolicy = policy
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        Button {
                                            store.duplicate(policy)
                                        } label: {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }

                                        Button {
                                            store.setEnabled(policy.id, enabled: !policy.isEnabled)
                                        } label: {
                                            Label(
                                                policy.isEnabled ? "Disable" : "Enable",
                                                systemImage: policy.isEnabled ? "pause.circle" : "play.circle"
                                            )
                                        }

                                        if policy.requireBiometric {
                                            Divider()
                                            Label(
                                                store.isVerifiedSensitive(policy.id) ? "Keychain: Verified ✓" : "Keychain: NOT indexed ⚠",
                                                systemImage: "key.fill"
                                            )
                                            .foregroundColor(store.isVerifiedSensitive(policy.id) ? .green : .red)
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            store.delete(policy)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                            .onMove { from, to in
                                store.reorder(fromOffsets: from, toOffset: to)
                            }

                            // Always-allow section
                            Section {
                                Button(action: { showAlwaysAllowSheet = true }) {
                                    HStack {
                                        Image(systemName: "checkmark.shield.fill")
                                            .foregroundColor(.green)
                                        Text("Always-Allow List")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.white.opacity(0.4))
                                            .font(.system(size: 12))
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green.opacity(0.08))
                                        .padding(.vertical, 2)
                                )
                            }
                            .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        EditButton()
                            .foregroundColor(.white.opacity(0.7))
                        Button(action: { showAddPolicy = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .sheet(item: $editingPolicy) { policy in
                PolicyEditSheet(policy: policy) { updated in
                    store.update(updated)
                }
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
                    )
                ) { newPolicy in
                    store.add(newPolicy)
                }
            }
            .sheet(isPresented: $showAlwaysAllowSheet) {
                AlwaysAllowSheet()
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

            Button(action: { showAddPolicy = true }) {
                Label("Add Policy", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.clawAccent.opacity(0.8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - PolicyEngineStatusBanner

private struct PolicyEngineStatusBanner: View {
    let policies: [ApprovalPolicy]

    var activeCount: Int  { policies.filter(\.isEnabled).count }
    var criticalCount: Int { policies.filter { $0.isEnabled && $0.riskLevel == .critical }.count }
    var autoApproveCount: Int { policies.filter { $0.isEnabled && $0.autoApprove }.count }

    var body: some View {
        HStack(spacing: 0) {
            BannerStat(value: "\(activeCount)", label: "Active", color: .green)
            Divider().frame(height: 24).background(Color.white.opacity(0.15))
            BannerStat(value: "\(criticalCount)", label: "Critical", color: .red)
            Divider().frame(height: 24).background(Color.white.opacity(0.15))
            BannerStat(value: "\(autoApproveCount)", label: "Auto-OK", color: .cyan)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private struct BannerStat: View {
        let value: String
        let label: String
        let color: Color
        var body: some View {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - AlwaysAllowSheet
//
// Manages the Keychain-backed list of tools that skip approval entirely.

struct AlwaysAllowSheet: View {
    @State private var approvalStore: ToolApprovalStore? = nil
    @State private var newTool: String = ""
    @Environment(\.dismiss) var dismiss

    // We read the always-allow list from a local viewmodel since we need
    // an active ToolApprovalStore reference. Show empty state if none.
    @State private var toolList: [String] = []

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Warning banner
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Tools in this list bypass approval entirely. Use with caution.")
                            .font(.system(size: 13))
                            .foregroundColor(.yellow.opacity(0.9))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.1))
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(.yellow.opacity(0.2)),
                        alignment: .bottom
                    )

                    // Add new
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 14))
                        TextField("tool.name or pattern*", text: $newTool)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                        Button(action: addTool) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(newTool.isEmpty ? .white.opacity(0.3) : .green)
                                .font(.system(size: 20))
                        }
                        .disabled(newTool.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.06))

                    if toolList.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.2))
                            Text("No always-allowed tools")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 15))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(toolList, id: \.self) { tool in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 14))
                                    Text(tool)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .listRowBackground(Color.white.opacity(0.06))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeTool(tool)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Always-Allow List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func addTool() {
        let trimmed = newTool.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !toolList.contains(trimmed) else { return }
        toolList.append(trimmed)
        toolList.sort()
        newTool = ""
        // Persist: in a real app this delegates to ToolApprovalStore.alwaysAllow()
        // We store directly to Keychain here since we may not have the store ref.
        syncToKeychain()
    }

    private func removeTool(_ tool: String) {
        toolList.removeAll { $0 == tool }
        syncToKeychain()
    }

    private func syncToKeychain() {
        guard let data = try? JSONEncoder().encode(toolList) else { return }
        try? KeychainStore.save(key: "claw.toolAlwaysAllow", data: data)
    }
}

// MARK: - PolicyRowView

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
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - PolicyEditSheet

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

                Section(header: Text("Risk Level"), footer: Text("'Critical' always requires biometric confirmation.")) {
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

                Section(header: Text("Approval Settings"), footer: Text("Auto-approve bypasses the review prompt entirely. Use only for low-risk, high-confidence patterns.")) {
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
                    Button("Cancel") { dismiss() }
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
