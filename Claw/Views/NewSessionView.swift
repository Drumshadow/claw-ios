import SwiftUI

// MARK: - NewSessionView

/// Sheet shown when the user taps the "New Session" button. Lets them pick an
/// agent and optionally provide a label, then calls `sessions.create` through
/// the `SessionStore`.
struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    @State private var selectedAgentId: String = GatewayAgentId.main
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
                        ForEach(GatewayAgentId.options) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clawCard)
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

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let key = try await sessionStore.createSession(
                agentId: selectedAgentId,
                label: label
            )
            onCreated?(key)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
