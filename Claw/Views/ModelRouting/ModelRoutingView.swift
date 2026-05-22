import SwiftUI

// MARK: - ModelRoutingView
//
// Main view for configuring model routing profiles and provider endpoints.
// Accessible from Settings.

struct ModelRoutingView: View {
    @Environment(ModelRouterStore.self) private var store
    @State private var showAddProfile  = false
    @State private var editingProfile: RoutingProfile? = nil
    @State private var showProviders   = false
    @State private var showModelCatalog = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Active profile summary
                        ActiveProfileBanner(store: store)
                            .padding(.horizontal)

                        // Provider health
                        ProviderStatusRow(store: store)
                            .padding(.horizontal)

                        // Routing profiles
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Routing Profiles")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: { showAddProfile = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .padding(.horizontal)

                            ForEach(store.profiles) { profile in
                                RoutingProfileCard(
                                    profile: profile,
                                    isActive: store.activeProfileId == profile.id,
                                    onSelect: { store.setActiveProfile(profile.id) },
                                    onEdit:   { editingProfile = profile },
                                    onDuplicate: { store.duplicateProfile(profile) },
                                    onDelete: { store.deleteProfile(profile) }
                                )
                                .padding(.horizontal)
                            }
                        }

                        // Model catalog section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Model Catalog")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {
                                    Task { await store.fetchAvailableModels() }
                                }) {
                                    if store.isLoadingModels {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .disabled(store.isLoadingModels)
                            }
                            .padding(.horizontal)

                            ModelCatalogSummaryCard(models: store.availableModels)
                                .padding(.horizontal)
                                .onTapGesture { showModelCatalog = true }
                        }

                        // Last sync
                        if let sync = store.lastSyncDate {
                            Text("Last synced \(sync, style: .relative) ago")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.top, 4)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Model Routing")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showProviders = true }) {
                        Label("Providers", systemImage: "network")
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .sheet(isPresented: $showAddProfile) {
                RoutingProfileEditorView(
                    profile: RoutingProfile(
                        name: "New Profile",
                        description: "",
                        isDefault: false,
                        rules: [],
                        fallbackModelId: "claude-sonnet-4-6",
                        preferLocalWhenAvailable: false
                    ),
                    availableModels: store.availableModels
                ) { newProfile in
                    store.addProfile(newProfile)
                }
            }
            .sheet(item: $editingProfile) { profile in
                RoutingProfileEditorView(
                    profile: profile,
                    availableModels: store.availableModels
                ) { updated in
                    store.updateProfile(updated)
                }
            }
            .sheet(isPresented: $showProviders) {
                ProviderListView(store: store)
            }
            .sheet(isPresented: $showModelCatalog) {
                ModelCatalogView(models: store.availableModels)
            }
        }
        .task { await store.fetchAvailableModels() }
    }
}

// MARK: - ActiveProfileBanner

private struct ActiveProfileBanner: View {
    let store: ModelRouterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE PROFILE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                    Text(store.activeProfile?.name ?? "None")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.clawTeal)
            }

            if let desc = store.activeProfile?.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }

            // Stats row
            HStack(spacing: 16) {
                ProfileStat(
                    value: "\(store.activeProfile?.rules.filter(\.isEnabled).count ?? 0)",
                    label: "Rules"
                )
                ProfileStat(
                    value: store.availableModels.filter(\.isAvailable).count.description,
                    label: "Models"
                )
                if let budget = store.activeProfile?.costBudgetDailyUSD {
                    ProfileStat(value: "$\(String(format: "%.2f", budget))", label: "Daily Cap")
                }
                if store.activeProfile?.preferLocalWhenAvailable == true {
                    ProfileStat(value: "Local", label: "Prefer")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.clawTeal.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.clawTeal.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private struct ProfileStat: View {
        let value: String
        let label: String
        var body: some View {
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - ProviderStatusRow

private struct ProviderStatusRow: View {
    let store: ModelRouterStore

    var availableCount: Int { store.availableModels.filter(\.isAvailable).count }
    var localCount: Int { store.availableModels.filter { $0.isAvailable && $0.isLocal }.count }

    var body: some View {
        HStack(spacing: 0) {
            ProviderPill(
                label: "\(availableCount) Available",
                icon: "checkmark.circle",
                color: .green
            )
            Divider().frame(height: 20).background(Color.white.opacity(0.15))
            ProviderPill(
                label: "\(localCount) Local",
                icon: "desktopcomputer",
                color: .cyan
            )
            Divider().frame(height: 20).background(Color.white.opacity(0.15))
            ProviderPill(
                label: "\(store.providers.count) Endpoints",
                icon: "network",
                color: .white.opacity(0.6)
            )
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
    }

    private struct ProviderPill: View {
        let label: String
        let icon: String
        let color: Color
        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - RoutingProfileCard

struct RoutingProfileCard: View {
    let profile: RoutingProfile
    let isActive: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isActive {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.clawTeal)
                        }
                        Text(profile.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isActive ? .white : .white.opacity(0.8))
                    }

                    if !profile.description.isEmpty {
                        Text(profile.description)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Active indicator / select button
                Button(action: onSelect) {
                    Text(isActive ? "Active" : "Use")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isActive ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.clawTeal : Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            // Rule preview
            if !profile.rules.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(profile.rules.filter(\.isEnabled).prefix(4)) { rule in
                            RuleChip(rule: rule)
                        }
                        if profile.rules.filter(\.isEnabled).count > 4 {
                            Text("+\(profile.rules.filter(\.isEnabled).count - 4) more")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
            }

            // Footer
            HStack(spacing: 8) {
                if let budget = profile.costBudgetDailyUSD {
                    Label("$\(String(format: "%.2f", budget))/day", systemImage: "dollarsign.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                if profile.preferLocalWhenAvailable {
                    Label("Local-prefer", systemImage: "desktopcomputer")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan.opacity(0.8))
                }
                Spacer()
                Text("\(profile.rules.count) rules")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color(white: 0.14) : Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isActive ? Color.clawTeal.opacity(0.4) : Color.white.opacity(0.08),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - RuleChip

struct RuleChip: View {
    let rule: RoutingRule

    var body: some View {
        HStack(spacing: 4) {
            Text(rule.taskPattern)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.4))
            Text(rule.preferredModelIds.first.map { shortModelName($0) } ?? "?")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.clawTeal.opacity(0.9))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
        )
    }

    private func shortModelName(_ id: String) -> String {
        if id.hasPrefix("claude-") { return id.replacingOccurrences(of: "claude-", with: "") }
        if id.hasPrefix("gpt-")    { return id }
        return String(id.split(separator: "/").last ?? Substring(id))
    }
}

// MARK: - ModelCatalogSummaryCard

struct ModelCatalogSummaryCard: View {
    let models: [ModelDefinition]

    var byProvider: [(type: ModelProviderType, count: Int)] {
        let grouped = Dictionary(grouping: models, by: \.providerType)
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.type.displayName < $1.type.displayName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(models.count) models in catalog")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            // Provider breakdown
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                ForEach(byProvider, id: \.type.id) { entry in
                    HStack(spacing: 4) {
                        Image(systemName: entry.type.iconName)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(entry.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Text(entry.type.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - ModelCatalogView

struct ModelCatalogView: View {
    let models: [ModelDefinition]
    @State private var filterProvider: ModelProviderType? = nil
    @State private var filterCapability: ModelCapability? = nil
    @Environment(\.dismiss) var dismiss

    var filteredModels: [ModelDefinition] {
        models.filter { model in
            if let prov = filterProvider, model.providerType != prov { return false }
            if let cap = filterCapability, !model.has(cap) { return false }
            return true
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(
                                label: "All",
                                isSelected: filterProvider == nil && filterCapability == nil,
                                action: { filterProvider = nil; filterCapability = nil }
                            )
                            ForEach(ModelProviderType.allCases) { type in
                                FilterChip(
                                    label: type.rawValue,
                                    isSelected: filterProvider == type,
                                    action: {
                                        filterProvider = filterProvider == type ? nil : type
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    List {
                        ForEach(filteredModels) { model in
                            ModelCatalogRow(model: model)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Model Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

struct ModelCatalogRow: View {
    let model: ModelDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: model.providerType.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(model.isAvailable ? .white : .white.opacity(0.5))
                    Text(model.providerType.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    // Cost tier badge
                    Text(model.costTier.displayLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: model.costTier.color))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(hex: model.costTier.color).opacity(0.15))
                        )

                    // Availability dot
                    HStack(spacing: 3) {
                        Circle()
                            .fill(model.isAvailable ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                        Text(model.isAvailable ? "Available" : "Offline")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }

            // Capabilities + context
            HStack(spacing: 6) {
                Text(model.contextDescription)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                Text("·")
                    .foregroundColor(.white.opacity(0.3))

                Text(model.latencyClass.rawValue)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                // Top 3 capabilities
                HStack(spacing: 4) {
                    ForEach(model.capabilities.prefix(4), id: \.id) { cap in
                        Image(systemName: cap.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.09))
        )
        .padding(.vertical, 2)
    }
}

// MARK: - ProviderListView

struct ProviderListView: View {
    @Bindable var store: ModelRouterStore
    @State private var showAddProvider = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if store.providers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No Custom Providers")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        Text("The gateway uses the model catalog by default.\nAdd custom endpoints for Ollama or private APIs.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.providers) { provider in
                            ProviderRow(provider: provider)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Providers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddProvider = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showAddProvider) {
                ProviderEditorView(store: store)
            }
        }
    }
}

private struct ProviderRow: View {
    let provider: ModelProvider

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.type.iconName)
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(provider.baseURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if provider.isLocal {
                    Text("Local")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan)
                }
                Circle()
                    .fill(provider.isEnabled ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.09))
        )
        .padding(.vertical, 2)
    }
}

// MARK: - ProviderEditorView

struct ProviderEditorView: View {
    let store: ModelRouterStore
    @State private var providerType: ModelProviderType = .ollama
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Provider Type") {
                    Picker("Type", selection: $providerType) {
                        ForEach(ModelProviderType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    .onChange(of: providerType) { _, newType in
                        if baseURL.isEmpty { baseURL = newType.defaultBaseURL }
                        if name.isEmpty    { name = newType.displayName }
                    }
                }

                Section("Connection") {
                    TextField("Display Name", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }

                if !providerType.isLocal {
                    Section(header: Text("Authentication"), footer: Text("API key stored securely in Keychain.")) {
                        SecureField("API Key", text: $apiKey)
                            .autocapitalization(.none)
                    }
                }
            }
            .navigationTitle("Add Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        var provider = ModelProvider(
                            type: providerType,
                            name: name.isEmpty ? providerType.displayName : name,
                            baseURL: baseURL.isEmpty ? providerType.defaultBaseURL : baseURL,
                            apiKeyKeychainRef: nil,
                            isEnabled: true,
                            customHeaders: [:],
                            availableModels: []
                        )
                        if !apiKey.isEmpty {
                            let ref = store.setAPIKey(apiKey, for: provider)
                            provider.apiKeyKeychainRef = ref
                        }
                        store.addProvider(provider)
                        dismiss()
                    }
                    .disabled(name.isEmpty && baseURL.isEmpty)
                }
            }
        }
    }
}

#Preview {
    ModelRoutingView()
        .environment(ModelRouterStore())
}
