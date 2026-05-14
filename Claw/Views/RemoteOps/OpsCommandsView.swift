import SwiftUI

struct OpsCommandsView: View {
    let store: RemoteOpsStore
    @State private var showCreateSheet = false
    @State private var editingCommand: OpsCommand?
    @State private var runningCommand: OpsCommand?
    @State private var toastMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                if store.commands.isEmpty {
                    emptyState
                } else {
                    ForEach(store.commands) { command in
                        OpsCommandRow(
                            command: command,
                            store: store,
                            onRun: { runningCommand = command }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { editingCommand = command }
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            store.deleteCommand(id: store.commands[i].id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Color.clawAccent)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                OpsCommandEditorView(store: store, command: nil)
            }
            .sheet(item: $editingCommand) { command in
                OpsCommandEditorView(store: store, command: command)
            }
            .sheet(item: $runningCommand) { command in
                OpsCommandRunSheet(
                    command: command,
                    store: store,
                    onQueued: { message in
                        toastMessage = message
                    }
                )
            }

            if let toast = toastMessage {
                ToastBanner(message: toast)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toastMessage)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Commands", systemImage: "terminal")
        } description: {
            Text("Tap + to define a shell command to run on your EC2 instances.")
        }
        .listRowBackground(Color.clawBg)
        .foregroundStyle(Color.clawMuted)
    }
}

private struct OpsCommandRow: View {
    let command: OpsCommand
    let store: RemoteOpsStore
    let onRun: () -> Void

    private var targetName: String {
        guard let id = command.targetInstanceId,
              let instance = store.ec2Instances.first(where: { $0.id == id }) else {
            return "Any instance"
        }
        return instance.name
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(command.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.clawTextStrong)

                    if command.requiresApproval {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.clawMuted)
                    }
                }

                if !command.description.isEmpty {
                    Text(command.description)
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                        .lineLimit(1)
                }

                Text(targetName)
                    .font(.caption2)
                    .foregroundStyle(Color.clawAccent.opacity(0.8))
            }

            Spacer()

            Button {
                onRun()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.clawAccent)
                    .padding(8)
                    .background(Color.clawAccent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clawBg)
    }
}

private struct OpsCommandRunSheet: View {
    let command: OpsCommand
    let store: RemoteOpsStore
    let onQueued: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInstanceId: String?
    @State private var isRunning = false

    private var needsInstancePicker: Bool {
        command.targetInstanceId == nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.clawMuted)
                        .textCase(.uppercase)

                    Text(command.command)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.clawTextStrong)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.clawBgAccent, in: RoundedRectangle(cornerRadius: 10))
                }

                if needsInstancePicker {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Instance")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.clawMuted)
                            .textCase(.uppercase)

                        if store.ec2Instances.isEmpty {
                            Text("No instances loaded")
                                .font(.body)
                                .foregroundStyle(Color.clawMuted)
                        } else {
                            Picker("Instance", selection: $selectedInstanceId) {
                                Text("Pick an instance").tag(Optional<String>(nil))
                                ForEach(store.ec2Instances) { instance in
                                    Text(instance.name).tag(Optional(instance.id))
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .clipped()
                        }
                    }
                }

                if command.requiresApproval {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                        Text("This command requires approval before execution.")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.clawMuted)
                    .padding(12)
                    .background(Color.clawBgAccent, in: RoundedRectangle(cornerRadius: 10))
                }

                Spacer()

                Button {
                    runCommand()
                } label: {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Run Command")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.clawAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(isRunning || (needsInstancePicker && selectedInstanceId == nil && !store.ec2Instances.isEmpty))
            }
            .padding(20)
            .background(Color.clawBg.ignoresSafeArea())
            .navigationTitle(command.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.clawMuted)
                }
            }
        }
    }

    private func runCommand() {
        isRunning = true
        let target = command.targetInstanceId ?? selectedInstanceId
        Task {
            await store.runCommand(command, on: target)
            await MainActor.run {
                isRunning = false
                dismiss()
                onQueued("Command queued — requires gateway SSH")
            }
        }
    }
}

private struct OpsCommandEditorView: View {
    let store: RemoteOpsStore
    let command: OpsCommand?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var commandText: String = ""
    @State private var targetInstanceId: String?
    @State private var requiresApproval: Bool = false

    private var isEditing: Bool { command != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !commandText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                    TextField("Description", text: $description)
                }

                Section("Shell Command") {
                    TextField("e.g. docker restart my-service", text: $commandText, axis: .vertical)
                        .lineLimit(4...)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Target") {
                    Picker("Instance", selection: $targetInstanceId) {
                        Text("Any (pick at run time)").tag(Optional<String>(nil))
                        ForEach(store.ec2Instances) { instance in
                            Text(instance.name).tag(Optional(instance.id))
                        }
                    }
                }

                Section {
                    Toggle("Require approval before running", isOn: $requiresApproval)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle(isEditing ? "Edit Command" : "New Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .tint(Color.clawAccent)
                        .disabled(!isValid)
                }
            }
            .onAppear { loadFromCommand() }
        }
    }

    private func loadFromCommand() {
        guard let command else { return }
        name = command.name
        description = command.description
        commandText = command.command
        targetInstanceId = command.targetInstanceId
        requiresApproval = command.requiresApproval
    }

    private func save() {
        if let existing = command {
            var updated = existing
            updated.name = name
            updated.description = description
            updated.command = commandText
            updated.targetInstanceId = targetInstanceId
            updated.requiresApproval = requiresApproval
            store.updateCommand(updated)
        } else {
            store.addCommand(OpsCommand(
                id: UUID(),
                name: name,
                description: description,
                command: commandText,
                targetInstanceId: targetInstanceId,
                requiresApproval: requiresApproval
            ))
        }
        dismiss()
    }
}

private struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.clawBgAccent, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}
