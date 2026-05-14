import SwiftUI
import AuthenticationServices

struct RemoteOpsSettingsView: View {
    let store: RemoteOpsStore
    @Environment(\.dismiss) private var dismiss

    @State private var datadogApiKey: String = ""
    @State private var datadogAppKey: String = ""
    @State private var datadogSite: String = ""
    @State private var awsAccessKeyId: String = ""
    @State private var awsSecretAccessKey: String = ""
    @State private var awsRegion: String = ""

    @State private var oauthManager = GitHubOAuthManager()

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    if store.credentials.githubToken != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("Connected to GitHub")
                                .foregroundStyle(Color.clawText)
                            Spacer()
                            Button("Sign out", role: .destructive) {
                                signOutGitHub()
                            }
                            .font(.subheadline)
                        }
                    } else {
                        Button {
                            Task { await signInWithGitHub() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Sign in with GitHub")
                            }
                            .foregroundStyle(Color.clawAccent)
                        }
                        .disabled(oauthManager.isAuthenticating)

                        if oauthManager.isAuthenticating {
                            HStack {
                                ProgressView()
                                    .tint(Color.clawMuted)
                                Text("Authenticating…")
                                    .foregroundStyle(Color.clawMuted)
                                    .font(.subheadline)
                            }
                        }

                        if let errorMessage = oauthManager.error {
                            Text(errorMessage)
                                .foregroundStyle(Color.clawDanger)
                                .font(.subheadline)
                        }
                    }
                }

                Section {
                    SecureField("API Key", text: $datadogApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Application Key", text: $datadogAppKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Site", text: $datadogSite, prompt: Text("datadoghq.com"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Datadog")
                } footer: {
                    Label("Stored securely on this device", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                }

                Section {
                    SecureField("Access Key ID", text: $awsAccessKeyId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Secret Access Key", text: $awsSecretAccessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Default Region", text: $awsRegion, prompt: Text("us-east-1"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("AWS")
                } footer: {
                    Label("Stored securely on this device", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Ops Settings")
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
                }
            }
            .onAppear { loadCredentials() }
        }
    }

    private func loadCredentials() {
        let c = store.credentials
        datadogApiKey = c.datadogApiKey ?? ""
        datadogAppKey = c.datadogAppKey ?? ""
        datadogSite = c.datadogSite
        awsAccessKeyId = c.awsAccessKeyId ?? ""
        awsSecretAccessKey = c.awsSecretAccessKey ?? ""
        awsRegion = c.awsRegion
    }

    private func save() {
        var updated = store.credentials
        updated.datadogApiKey = datadogApiKey.isEmpty ? nil : datadogApiKey
        updated.datadogAppKey = datadogAppKey.isEmpty ? nil : datadogAppKey
        updated.datadogSite = datadogSite.isEmpty ? "datadoghq.com" : datadogSite
        updated.awsAccessKeyId = awsAccessKeyId.isEmpty ? nil : awsAccessKeyId
        updated.awsSecretAccessKey = awsSecretAccessKey.isEmpty ? nil : awsSecretAccessKey
        updated.awsRegion = awsRegion.isEmpty ? "us-east-1" : awsRegion
        store.credentials = updated
        dismiss()
        Task { await store.refresh() }
    }

    private func signInWithGitHub() async {
        let anchor = presentationAnchor()
        do {
            let token = try await oauthManager.authenticate(presentationAnchor: anchor)
            store.credentials.githubToken = token
            await store.refresh()
        } catch {
            oauthManager.error = error.localizedDescription
        }
    }

    private func signOutGitHub() {
        try? KeychainStore.delete(key: "claw.ops.github.token")
        store.credentials.githubToken = nil
    }

    private func presentationAnchor() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
