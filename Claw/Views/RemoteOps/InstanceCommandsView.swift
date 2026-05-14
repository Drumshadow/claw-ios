import SwiftUI

// MARK: - InstanceCommandsView

struct InstanceCommandsView: View {
    let instance: EC2Instance
    let sshStore: InstanceSSHStore

    @State private var commands: [CustomCommand] = []
    @State private var showAddSheet: Bool = false
    @State private var runningCommand: CustomCommand? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Commands")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawAccent)
                }
            }

            if commands.isEmpty {
                Text("No commands yet. Tap + to add one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawMuted)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(commands) { command in
                        CommandRow(command: command) {
                            runningCommand = command
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteCommand(command)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                        if command.id != commands.last?.id {
                            Divider().background(Color.clawBorder)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.clawCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCommandSheet { newCommand in
                commands.append(newCommand)
                sshStore.saveCommands(commands, for: instance.id)
            }
        }
        .sheet(item: $runningCommand) { command in
            CommandResultSheet(command: command, instance: instance, sshStore: sshStore)
        }
        .onAppear {
            commands = sshStore.loadCommands(for: instance.id)
        }
    }

    private func deleteCommand(_ command: CustomCommand) {
        commands.removeAll { $0.id == command.id }
        sshStore.saveCommands(commands, for: instance.id)
    }
}

// MARK: - CommandRow

private struct CommandRow: View {
    let command: CustomCommand
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(command.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)

                    Text(command.command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.clawMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawAccent)
                    .padding(7)
                    .background(Color.clawAccent.opacity(0.12), in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CommandResultSheet

struct CommandResultSheet: View {
    let command: CustomCommand
    let instance: EC2Instance
    let sshStore: InstanceSSHStore

    @Environment(\.dismiss) private var dismiss

    @State private var isRunning: Bool = true
    @State private var output: String = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isRunning {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(Color.clawAccent)
                            Text("Running \(command.name)…")
                                .font(.subheadline)
                                .foregroundStyle(Color.clawMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    } else if let err = error {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.clawDanger)
                            Text(err)
                                .font(.subheadline)
                                .foregroundStyle(Color.clawDanger)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.clawDanger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                    } else {
                        Text(output.isEmpty ? "(no output)" : output)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.clawText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.clawBgAccent, in: RoundedRectangle(cornerRadius: 10))
                            .textSelection(.enabled)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg.ignoresSafeArea())
            .navigationTitle(command.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .tint(Color.clawMuted)
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        isRunning = true
        error = nil
        do {
            output = try await sshStore.runCommand(command, for: instance)
        } catch {
            self.error = error.localizedDescription
        }
        isRunning = false
    }
}

// MARK: - AddCommandSheet

private struct AddCommandSheet: View {
    let onAdd: (CustomCommand) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var commandText: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !commandText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Command Name") {
                    TextField("e.g. Restart nginx", text: $name)
                        .autocorrectionDisabled()
                }
                Section("Shell Command") {
                    TextField("e.g. sudo systemctl restart nginx", text: $commandText, axis: .vertical)
                        .lineLimit(3...)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg.ignoresSafeArea())
            .navigationTitle("New Command")
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
                    Button("Add") {
                        let cmd = CustomCommand(
                            name: name.trimmingCharacters(in: .whitespaces),
                            command: commandText.trimmingCharacters(in: .whitespaces)
                        )
                        onAdd(cmd)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(Color.clawAccent)
                    .disabled(!isValid)
                }
            }
        }
    }
}
