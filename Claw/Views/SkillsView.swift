import SwiftUI

// MARK: - SkillsView

/// Lists all skills available on the gateway, grouped by category, with
/// per-skill enable/disable toggles, search filtering, and pull-to-refresh.
struct SkillsView: View {
    @Environment(SkillsStore.self) private var store

    @State private var searchText: String = ""
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            Group {
                if store.isLoading && store.skills.isEmpty {
                    loadingView
                } else if filteredGroups.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(filteredGroups, id: \.category) { group in
                            categorySection(group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            try? await store.load()
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search skills")
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Link(destination: URL(string: "https://agentskills.io")!) {
                    Label("Discover", systemImage: "globe")
                        .font(.body)
                        .tint(Color.clawAccent)
                }
            }
        }
        .alert(
            "Action failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button("OK") { actionError = nil }
        } message: { detail in
            Text(detail)
        }
        .task {
            if store.skills.isEmpty {
                try? await store.load()
            }
        }
    }

    // MARK: - Filtering / grouping

    private struct CategoryGroup {
        let category: String
        let skills: [ClawSkill]
        let enabledCount: Int
    }

    private var filteredGroups: [CategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [ClawSkill]
        if trimmed.isEmpty {
            filtered = store.skills
        } else {
            filtered = store.skills.filter {
                $0.name.lowercased().contains(trimmed) ||
                $0.id.lowercased().contains(trimmed) ||
                $0.description.lowercased().contains(trimmed)
            }
        }

        let grouped = Dictionary(grouping: filtered, by: { $0.category })
        return grouped
            .map { CategoryGroup(category: $0.key, skills: $0.value, enabledCount: $0.value.filter(\.enabled).count) }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    // MARK: - Category section

    private func categorySection(_ group: CategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(group.category, enabled: group.enabledCount, total: group.skills.count)
            VStack(spacing: 10) {
                ForEach(group.skills) { skill in
                    SkillRow(
                        skill: skill,
                        onToggle: { newValue in
                            Task { await performToggle(skill.id, enabled: newValue) }
                        }
                    )
                }
            }
        }
    }

    private func sectionHeader(_ title: String, enabled: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
            Text("\(enabled)/\(total) enabled")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.clawBgElevated))
            Spacer()
        }
    }

    // MARK: - Loading / empty states

    private var loadingView: some View {
        VStack {
            ProgressView("Loading skills…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))

            Text(searchText.isEmpty ? "No skills available" : "No matches")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)

            Text(searchText.isEmpty
                 ? "The gateway has not reported any skills."
                 : "Try a different search term.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func performToggle(_ skillId: String, enabled: Bool) async {
        do {
            try await store.toggle(skillId, enabled: enabled)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - SkillRow

private struct SkillRow: View {
    let skill: ClawSkill
    let onToggle: (Bool) -> Void

    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let emoji = skill.emoji {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 28)
                    .padding(.top, 2)
            } else {
                Image(systemName: skill.enabled ? "checkmark.seal.fill" : "circle.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(skill.enabled ? Color.clawAccent : Color.clawMuted.opacity(0.6))
                    .frame(width: 28)
                    .padding(.top, 2)
            }

            Button {
                showDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                        .lineLimit(1)

                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawMuted)
                            .lineLimit(3)
                    }

                    Text(skill.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.clawMuted.opacity(0.7))
                        .padding(.top, 1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { skill.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(Color.clawAccent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
        .sheet(isPresented: $showDetail) {
            SkillDetailSheet(skill: skill, onToggle: onToggle)
        }
    }
}

// MARK: - SkillDetailSheet

private struct SkillDetailSheet: View {
    let skill: ClawSkill
    let onToggle: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header: emoji + name
                    HStack(spacing: 12) {
                        if let emoji = skill.emoji {
                            Text(emoji)
                                .font(.system(size: 44))
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.clawAccent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.clawTextStrong)
                            Text(skill.id)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.clawMuted)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.clawCard))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.clawBorder, lineWidth: 1))

                    // Description
                    if !skill.description.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.clawMuted)
                                .textCase(.uppercase)
                            Text(skill.description)
                                .font(.body)
                                .foregroundStyle(Color.clawText)
                        }
                    }

                    // Source + status badges
                    HStack(spacing: 8) {
                        Text(skill.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.clawMuted)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.clawBgElevated))
                        if skill.eligible {
                            Text("Ready")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.clawOk)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.clawOk.opacity(0.15)))
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { skill.enabled }, set: { onToggle($0) }))
                            .labelsHidden()
                            .tint(Color.clawAccent)
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle(skill.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.tint(Color.clawAccent)
                }
            }
        }
    }
}
