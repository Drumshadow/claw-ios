import SwiftUI

// MARK: - RoutingProfileEditorView
//
// Full editor for a routing profile's name, description, fallback,
// cost budget, and ordered routing rules.

struct RoutingProfileEditorView: View {
    @State var profile: RoutingProfile
    let availableModels: [ModelDefinition]
    let onSave: (RoutingProfile) -> Void

    @State private var showAddRule  = false
    @State private var editingRule: RoutingRule? = nil
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                // Basic info
                Section("Profile Info") {
                    TextField("Name", text: $profile.name)
                    TextField("Description", text: $profile.description, axis: .vertical)
                        .lineLimit(2...4)
                }

                // Fallback model
                Section(header: Text("Fallback Model"), footer: Text("Used when no rule matches or all preferred models are unavailable.")) {
                    Picker("Fallback", selection: $profile.fallbackModelId) {
                        ForEach(availableModels) { model in
                            HStack {
                                Image(systemName: model.providerType.iconName)
                                    .foregroundColor(.secondary)
                                Text(model.name)
                            }
                            .tag(model.id)
                        }
                        // Allow typing custom model ID
                        Text("Custom…").tag(profile.fallbackModelId)
                    }
                    .pickerStyle(.menu)
                }

                // Routing rules
                Section(header: routingRulesHeader) {
                    if profile.rules.isEmpty {
                        Text("No rules — all tasks use the fallback model")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(profile.rules) { rule in
                            RoutingRuleRow(rule: rule)
                                .contentShape(Rectangle())
                                .onTapGesture { editingRule = rule }
                        }
                        .onMove { from, to in
                            profile.rules.move(fromOffsets: from, toOffset: to)
                        }
                        .onDelete { offsets in
                            profile.rules.remove(atOffsets: offsets)
                        }
                    }
                }

                // Cost & preferences
                Section("Cost & Performance") {
                    Toggle("Prefer local models when available", isOn: $profile.preferLocalWhenAvailable)

                    HStack {
                        Text("Daily budget")
                        Spacer()
                        if let budget = profile.costBudgetDailyUSD {
                            Text("$\(String(format: "%.2f", budget))")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unlimited")
                                .foregroundColor(.secondary)
                        }
                    }

                    // Budget slider (nil = unlimited = slider value 0)
                    let budgetBinding = Binding<Double>(
                        get: { profile.costBudgetDailyUSD ?? 0 },
                        set: { profile.costBudgetDailyUSD = $0 > 0 ? $0 : nil }
                    )
                    Slider(value: budgetBinding, in: 0...100, step: 0.5) {
                        Text("Budget")
                    } minimumValueLabel: {
                        Text("∞").font(.caption).foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text("$100").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(profile.name.isEmpty ? "New Profile" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(profile)
                        dismiss()
                    }
                    .disabled(profile.name.isEmpty)
                }
            }
            .sheet(isPresented: $showAddRule) {
                RoutingRuleEditorView(
                    rule: RoutingRule(
                        name: "New Rule",
                        taskPattern: "*",
                        preferredModelIds: [],
                        fallbackModelIds: [],
                        requiredCapabilities: [],
                        isEnabled: true
                    ),
                    availableModels: availableModels
                ) { newRule in
                    profile.rules.append(newRule)
                }
            }
            .sheet(item: $editingRule) { rule in
                RoutingRuleEditorView(rule: rule, availableModels: availableModels) { updated in
                    if let idx = profile.rules.firstIndex(where: { $0.id == updated.id }) {
                        profile.rules[idx] = updated
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
    }

    private var routingRulesHeader: some View {
        HStack {
            Text("Routing Rules")
            Spacer()
            Button(action: { showAddRule = true }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - RoutingRuleRow

struct RoutingRuleRow: View {
    let rule: RoutingRule

    var body: some View {
        HStack(spacing: 10) {
            // Enabled indicator
            Circle()
                .fill(rule.isEnabled ? Color.green : Color.gray)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.taskPattern)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(rule.preferredModelIds.first.map(shortModelName) ?? "—")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                if !rule.name.isEmpty {
                    Text(rule.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Capability requirements
            if !rule.requiredCapabilities.isEmpty {
                HStack(spacing: 3) {
                    ForEach(rule.requiredCapabilities.prefix(3), id: \.id) { cap in
                        Image(systemName: cap.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func shortModelName(_ id: String) -> String {
        if id.hasPrefix("claude-") { return String(id.dropFirst("claude-".count)) }
        return String(id.split(separator: "/").last ?? Substring(id))
    }
}

// MARK: - RoutingRuleEditorView

struct RoutingRuleEditorView: View {
    @State var rule: RoutingRule
    let availableModels: [ModelDefinition]
    let onSave: (RoutingRule) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var preferredInput: String = ""
    @State private var fallbackInput:  String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Rule Info") {
                    TextField("Rule Name", text: $rule.name)
                    TextField("Task Pattern (glob)", text: $rule.taskPattern)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .textCase(.none)
                }

                Section(header: Text("Preferred Models"), footer: Text("Ordered list. First available model is used.")) {
                    ForEach(rule.preferredModelIds, id: \.self) { modelId in
                        ModelPickerRow(modelId: modelId, models: availableModels)
                    }
                    .onDelete { offsets in rule.preferredModelIds.remove(atOffsets: offsets) }
                    .onMove  { from, to in rule.preferredModelIds.move(fromOffsets: from, toOffset: to) }

                    // Quick-add picker
                    Picker("Add model", selection: $preferredInput) {
                        Text("Select…").tag("")
                        ForEach(availableModels) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: preferredInput) { _, newId in
                        guard !newId.isEmpty, !rule.preferredModelIds.contains(newId) else { return }
                        rule.preferredModelIds.append(newId)
                        preferredInput = ""
                    }
                }

                Section(header: Text("Fallback Models"), footer: Text("Used when preferred models are unavailable.")) {
                    ForEach(rule.fallbackModelIds, id: \.self) { modelId in
                        ModelPickerRow(modelId: modelId, models: availableModels)
                    }
                    .onDelete { offsets in rule.fallbackModelIds.remove(atOffsets: offsets) }
                    .onMove  { from, to in rule.fallbackModelIds.move(fromOffsets: from, toOffset: to) }

                    Picker("Add fallback", selection: $fallbackInput) {
                        Text("Select…").tag("")
                        ForEach(availableModels) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: fallbackInput) { _, newId in
                        guard !newId.isEmpty, !rule.fallbackModelIds.contains(newId) else { return }
                        rule.fallbackModelIds.append(newId)
                        fallbackInput = ""
                    }
                }

                Section("Required Capabilities") {
                    ForEach(ModelCapability.allCases) { cap in
                        Toggle(isOn: Binding(
                            get: { rule.requiredCapabilities.contains(cap) },
                            set: { enabled in
                                if enabled { rule.requiredCapabilities.append(cap) }
                                else { rule.requiredCapabilities.removeAll { $0 == cap } }
                            }
                        )) {
                            Label(cap.displayName, systemImage: cap.iconName)
                        }
                    }
                }

                Section("Constraints") {
                    Toggle("Enabled", isOn: $rule.isEnabled)

                    Picker("Max Latency", selection: Binding(
                        get: { rule.maxLatencyClass ?? LatencyClass.slow },
                        set: { rule.maxLatencyClass = $0 == .slow ? nil : $0 }
                    )) {
                        Text("Any").tag(LatencyClass.slow)
                        ForEach(LatencyClass.allCases.filter { $0 != .slow }) { lc in
                            Text(lc.displayName).tag(lc)
                        }
                    }

                    if let notes = rule.notes {
                        TextField("Notes", text: Binding(
                            get: { notes },
                            set: { rule.notes = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }
            }
            .navigationTitle("Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(rule.taskPattern.isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
        }
    }
}

// MARK: - ModelPickerRow

private struct ModelPickerRow: View {
    let modelId: String
    let models: [ModelDefinition]

    var model: ModelDefinition? { models.first { $0.id == modelId } }

    var body: some View {
        HStack {
            if let m = model {
                Image(systemName: m.providerType.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                Text(m.name)
                    .font(.system(size: 14))
            } else {
                Text(modelId)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    RoutingProfileEditorView(
        profile: RoutingProfile.defaultProfiles[0],
        availableModels: ModelDefinition.catalog,
        onSave: { _ in }
    )
}
