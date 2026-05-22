import SwiftUI

// MARK: - NewSessionView

/// Sheet shown when the user taps the "New Session" button. Lets them pick an
/// agent and optionally provide a label, then calls `sessions.create` through
/// the `SessionStore`.
struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ModelRouterStore.self) private var modelRouterStore

    @State private var selectedAgentId: String = GatewayAgentId.main
    @State private var selectedModelId: String = ""
    @State private var label: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    /// Called with the newly-created session key on success.
    var onCreated: ((String) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    Picker("Agent", selection: $selectedAgentId) {
                        ForEach(sessionStore.availableAgentOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .listRowBackground(Color.clawCard)
                }

                Section("Model") {
                    Picker("Model", selection: $selectedModelId) {
                        Text("Gateway default").tag("")
                        ForEach(selectableModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .listRowBackground(Color.clawCard)

                    if modelRouterStore.isLoadingModels {
                        HStack(spacing: 8) {
                            ProgressView().tint(Color.clawAccent)
                            Text("Refreshing models…")
                                .font(.caption)
                                .foregroundStyle(Color.clawMuted)
                        }
                        .listRowBackground(Color.clawCard)
                    }
                }

                Section("Label (optional)") {
                    TextField("e.g. Refactor onboarding", text: $label)
                        .foregroundStyle(Color.clawText)
                        .listRowBackground(Color.clawCard)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.clawDanger)
                            .listRowBackground(Color.clawCard)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await sessionStore.loadAvailableAgents()
                await modelRouterStore.fetchAvailableModels()
            }
            .onChange(of: sessionStore.availableAgentOptions) { _, options in
                if !options.contains(where: { $0.id == selectedAgentId }) {
                    selectedAgentId = options.first?.id ?? GatewayAgentId.main
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.clawMuted)
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .tint(Color.clawAccent)
                        } else {
                            Text("Create")
                        }
                    }
                    .tint(Color.clawAccent)
                    .disabled(isCreating)
                }
            }
        }
    }

    private var selectableModels: [ModelDefinition] {
        let available = modelRouterStore.availableModels.filter { $0.isAvailable }
        return available.isEmpty ? modelRouterStore.availableModels : available
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let key = try await sessionStore.createSession(
                agentId: selectedAgentId,
                label: label,
                model: selectedModelId.isEmpty ? nil : selectedModelId
            )
            onCreated?(key)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
