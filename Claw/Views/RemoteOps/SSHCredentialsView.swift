import SwiftUI
import UniformTypeIdentifiers

// MARK: - SSHCredentialsView

struct SSHCredentialsView: View {
    let instance: EC2Instance
    let sshStore: InstanceSSHStore
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var privateKeyPEM: String = ""
    @State private var isSaving: Bool = false
    @State private var isImportingKey: Bool = false
    @State private var importError: String? = nil

    private var isEditing: Bool {
        sshStore.hasCredential(for: instance.id)
    }

    private var isValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !privateKeyPEM.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(port) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledTextField(label: "Username", placeholder: "ec2-user", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    LabeledTextField(label: "Host / IP", placeholder: instance.publicIP ?? "0.0.0.0", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    LabeledTextField(label: "Port", placeholder: "22", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Connection")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if privateKeyPEM.isEmpty {
                            Text("Paste your PEM private key here…\n(e.g. -----BEGIN OPENSSH PRIVATE KEY-----)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Color.clawMuted)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $privateKeyPEM)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.clawText)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Button {
                        isImportingKey = true
                    } label: {
                        Label("Import from Files", systemImage: "doc.badge.plus")
                            .font(.subheadline)
                            .foregroundStyle(Color.clawAccent)
                    }

                    if let err = importError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.clawDanger)
                    } else if privateKeyPEM.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("Private key is required to connect.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.clawDanger)
                    }
                } header: {
                    Text("Private Key (PEM)")
                }
                .fileImporter(
                    isPresented: $isImportingKey,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { result in
                    importError = nil
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        guard url.startAccessingSecurityScopedResource() else {
                            importError = "Permission denied reading file."
                            return
                        }
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            let content = try String(contentsOf: url, encoding: .utf8)
                            privateKeyPEM = content
                        } catch {
                            importError = "Could not read file: \(error.localizedDescription)"
                        }
                    case .failure(let error):
                        importError = error.localizedDescription
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit SSH Credentials" : "Add SSH Credentials")
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
                        .disabled(!isValid || isSaving)
                }
            }
            .onAppear { prefill() }
        }
    }

    // MARK: - Helpers

    private func prefill() {
        if let cred = sshStore.loadCredential(for: instance.id) {
            username = cred.username
            host = cred.host
            port = String(cred.port)
        } else {
            host = instance.publicIP ?? instance.privateIP ?? ""
        }
        if let key = sshStore.loadPrivateKey(for: instance.id) {
            privateKeyPEM = key
        }
    }

    private func save() {
        guard let portInt = Int(port), isValid else { return }
        isSaving = true
        let cred = SSHCredential(
            username: username.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            port: portInt
        )
        sshStore.saveCredential(cred, privateKeyPEM: privateKeyPEM, for: instance.id)
        isSaving = false
        onSaved?()
        dismiss()
    }
}

// MARK: - LabeledTextField

private struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.clawMuted)
                .frame(width: 80, alignment: .leading)
            TextField(placeholder, text: $text)
                .foregroundStyle(Color.clawText)
                .multilineTextAlignment(.trailing)
        }
    }
}
