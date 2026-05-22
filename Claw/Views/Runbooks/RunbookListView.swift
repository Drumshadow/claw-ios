import SwiftUI

// MARK: - RunbookListView
//
// Browse and launch runbooks. Shows the catalog from RunbookStore,
// lets the user filter by tag/environment, and navigate to detail.

struct RunbookListView: View {
    @Environment(RunbookStore.self) private var store: RunbookStore?

    @State private var searchText: String = ""
    @State private var selectedEnvironment: String = "all"

    private let environmentOptions = ["all", "production", "staging", "dev"]

    private var filtered: [Runbook] {
        let base = store?.runbooks ?? Runbook.allSamples
        var result = base.filter { $0.isEnabled }

        if selectedEnvironment != "all" {
            result = result.filter {
                $0.environment == "*" || $0.environment == selectedEnvironment
            }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.description.lowercased().contains(q) ||
                $0.tags.contains { $0.lowercased().contains(q) }
            }
        }

        return result
    }

    var body: some View {
        Group {
            if filtered.isEmpty && (store?.runbooks.isEmpty ?? true) {
                emptyState
            } else if filtered.isEmpty {
                noResultsState
            } else {
                runbookList
            }
        }
        .searchable(text: $searchText, prompt: "Search runbooks…")
        .task { try? await store?.load() }
    }

    // MARK: - List

    private var runbookList: some View {
        List {
            // Environment filter chips
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(environmentOptions, id: \.self) { env in
                            Button {
                                withAnimation(.spring(response: 0.25)) {
                                    selectedEnvironment = env
                                }
                            } label: {
                                Text(env == "all" ? "All" : env.capitalized)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selectedEnvironment == env ? Color.clawBg : Color.clawText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedEnvironment == env
                                        ? Color.clawAccent
                                        : Color.clawBgElevated
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            // Runbook rows
            Section {
                ForEach(filtered) { runbook in
                    NavigationLink(value: RunbookNavigation.detail(runbook)) {
                        RunbookRowView(runbook: runbook)
                    }
                    .listRowBackground(Color.clawCard)
                }
            } header: {
                HStack {
                    Text("RUNBOOKS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.clawMuted)
                    Text("\(filtered.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.clawMuted)
                }
                .textCase(nil)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(Color.clawMuted.opacity(0.3))
            Text("No Runbooks")
                .font(.headline)
                .foregroundStyle(Color.clawTextStrong)
            Text("Runbook definitions will load from the gateway. Sample runbooks are shown in preview.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clawBg)
    }

    private var noResultsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No results for "\(searchText)"")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clawBg)
    }
}

// MARK: - RunbookRowView

struct RunbookRowView: View {
    let runbook: Runbook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title + environment badge
            HStack(spacing: 8) {
                Text(runbook.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if runbook.environment != "*" {
                    envBadge(runbook.environment)
                }
            }

            // Description
            if !runbook.description.isEmpty {
                Text(runbook.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(2)
            }

            // Footer metadata
            HStack(spacing: 12) {
                // Step count
                Label("\(runbook.steps.count) steps", systemImage: "list.number")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clawMuted)
                    .labelStyle(.titleAndIcon)

                // Duration
                Label(runbook.formattedDuration, systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clawMuted)
                    .labelStyle(.titleAndIcon)

                // Execution mode
                Label(runbook.executionMode.displayLabel, systemImage: runbook.executionMode.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.clawTeal)
                    .labelStyle(.titleAndIcon)

                // Danger step warning
                if runbook.dangerStepCount > 0 {
                    Label("\(runbook.dangerStepCount) danger", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.clawWarn)
                        .labelStyle(.titleAndIcon)
                }
            }

            // Tags
            if !runbook.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(runbook.tags.prefix(5), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.clawMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.clawBgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func envBadge(_ env: String) -> some View {
        Text(env)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(envColor(env))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(envColor(env).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func envColor(_ env: String) -> Color {
        switch env {
        case "production": return Color.clawDanger
        case "staging":    return Color.clawWarn
        case "dev":        return Color.clawOk
        default:           return Color.clawMuted
        }
    }
}

// MARK: - Navigation value

enum RunbookNavigation: Hashable {
    case detail(Runbook)
    case execution(String)  // executionId
}

// MARK: - Preview

#Preview("Runbook List") {
    NavigationStack {
        RunbookListView()
            .navigationTitle("Runbooks")
    }
    .preferredColorScheme(.dark)
}
