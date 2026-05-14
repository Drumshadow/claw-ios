import SwiftUI

// MARK: - MemoryBrowserView

/// Search and browse memory entries with debounced search, pagination,
/// detail sheet, and swipe-to-delete.
struct MemoryBrowserView: View {
    @Environment(MemoryStore.self) private var store

    @State private var searchText: String = ""
    @State private var actionError: String?
    @State private var selectedEntry: MemoryEntry?
    @State private var pendingDeleteEntry: MemoryEntry?
    @State private var searchDebounceTask: Task<Void, Never>?

    private var isShowingSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleEntries: [MemoryEntry] {
        isShowingSearch ? store.searchResults : store.entries
    }

    var body: some View {
        ScrollView {
            Group {
                if store.isLoading && store.entries.isEmpty && !isShowingSearch {
                    loadingView
                } else if isShowingSearch && store.isSearching && store.searchResults.isEmpty {
                    searchLoadingView
                } else if visibleEntries.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleEntries) { entry in
                            MemoryRow(
                                entry: entry,
                                onTap: { selectedEntry = entry },
                                onDelete: { pendingDeleteEntry = entry }
                            )
                            .onAppear {
                                if !isShowingSearch,
                                   let last = store.entries.last,
                                   entry.id == last.id,
                                   store.hasMore,
                                   !store.isLoading {
                                    Task { try? await store.loadMore() }
                                }
                            }
                        }
                        if !isShowingSearch && store.isLoading && !store.entries.isEmpty {
                            ProgressView()
                                .tint(Color.clawAccent)
                                .padding(.vertical, 12)
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
            try? await store.reload()
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search memory")
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(newValue)
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedEntry) { entry in
            MemoryDetailSheet(entry: entry)
        }
        .alert(
            "Delete memory entry?",
            isPresented: Binding(
                get: { pendingDeleteEntry != nil },
                set: { if !$0 { pendingDeleteEntry = nil } }
            ),
            presenting: pendingDeleteEntry
        ) { entry in
            Button("Delete", role: .destructive) {
                Task { await performDelete(entry.id) }
                pendingDeleteEntry = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEntry = nil
            }
        } message: { entry in
            Text("Remove \"\(entry.key.isEmpty ? entry.id : entry.key)\" from memory? This cannot be undone.")
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
            if store.entries.isEmpty {
                try? await store.reload()
            }
        }
    }

    // MARK: - Debounced search

    private func scheduleSearch(_ query: String) {
        searchDebounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            store.search(query: "")
            return
        }
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            store.search(query: trimmed)
        }
    }

    // MARK: - Loading / empty states

    private var loadingView: some View {
        VStack {
            ProgressView("Loading memory…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var searchLoadingView: some View {
        VStack {
            ProgressView("Searching…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: isShowingSearch ? "magnifyingglass" : "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))

            Text(isShowingSearch ? "No matches" : "No memory entries")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)

            Text(isShowingSearch
                 ? "Try a different search term."
                 : "Stored memory entries from the gateway will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func performDelete(_ entryId: String) async {
        do {
            try await store.delete(entryId)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - MemoryRow (swipe-to-delete)

private struct MemoryRow: View {
    let entry: MemoryEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var showDeleteAction: Bool = false

    private let deleteWidth: CGFloat = 80

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack {
                Spacer()
                Button {
                    onDelete()
                    withAnimation { offsetX = 0; showDeleteAction = false }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                        Text("Delete")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.clawDanger)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onTap) {
                content
            }
            .buttonStyle(.plain)
            .offset(x: offsetX)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.width < 0 {
                            offsetX = max(gesture.translation.width, -deleteWidth)
                        } else if showDeleteAction {
                            offsetX = min(-deleteWidth + gesture.translation.width, 0)
                        }
                    }
                    .onEnded { _ in
                        withAnimation {
                            if offsetX < -deleteWidth / 2 {
                                offsetX = -deleteWidth
                                showDeleteAction = true
                            } else {
                                offsetX = 0
                                showDeleteAction = false
                            }
                        }
                    }
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.key.isEmpty ? entry.id : entry.key)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.clawTextStrong)
                .lineLimit(1)

            Text(entry.value)
                .font(.system(size: 12))
                .foregroundStyle(Color.clawMuted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let date = entry.updatedAt ?? entry.createdAt {
                Text(formattedDate(date))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.clawMuted.opacity(0.7))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

// MARK: - MemoryDetailSheet

private struct MemoryDetailSheet: View {
    let entry: MemoryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key")
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                            .textCase(.uppercase)
                        Text(entry.key.isEmpty ? "—" : entry.key)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.clawTextStrong)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clawCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Value")
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                            .textCase(.uppercase)
                        Text(entry.value.isEmpty ? "—" : entry.value)
                            .font(.body)
                            .foregroundStyle(Color.clawText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clawCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )

                    if entry.createdAt != nil || entry.updatedAt != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            if let created = entry.createdAt {
                                metaRow(label: "Created", date: created)
                            }
                            if let updated = entry.updatedAt {
                                metaRow(label: "Updated", date: updated)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Memory Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(Color.clawAccent)
                }
            }
        }
    }

    private func metaRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.clawMuted)
            Spacer()
            Text(formattedDate(date))
                .font(.caption)
                .foregroundStyle(Color.clawText)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
