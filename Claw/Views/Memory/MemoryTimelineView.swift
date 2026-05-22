import SwiftUI

// MARK: - MemoryTimelineView
//
// Searchable, filterable timeline of the agent's knowledge graph events.
// Shows incidents, deploys, fixes, skills, infra changes, and more.

struct MemoryTimelineView: View {
    @Environment(MemoryTimelineStore.self) private var store
    @State private var searchText: String = ""
    @State private var showGraphView: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Category filter chips
            categoryFilter

            Divider().background(Color.clawBorder)

            // Timeline content
            timelineList
        }
        .background(Color.clawBg)
        .navigationTitle("Memory Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showGraphView = true
                } label: {
                    Image(systemName: "circle.hexagongrid.circle")
                }
                .tint(Color.clawTeal)
            }
        }
        .sheet(isPresented: $showGraphView) {
            NavigationStack {
                KnowledgeGraphView(snapshot: store.graphSnapshot)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showGraphView = false }
                                .tint(Color.clawAccent)
                        }
                    }
            }
        }
        .task { try? await store.reload() }
        .refreshable { try? await store.reload() }
        .onChange(of: searchText) { _, newValue in
            store.search(query: newValue)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.clawMuted)
            TextField("Search timeline…", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(Color.clawText)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    store.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.clawMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.clawBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clawBgAccent)
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "All")
                ForEach(EventCategory.allCases) { cat in
                    categoryChip(cat, label: cat.displayName)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.clawBgAccent)
    }

    private func categoryChip(_ category: EventCategory?, label: String) -> some View {
        let isSelected = store.selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.setCategory(category)
            }
        } label: {
            HStack(spacing: 4) {
                if let cat = category {
                    Image(systemName: cat.systemImage)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white : Color(hex: cat.colorHex))
                }
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.clawText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.clawAccent : Color.clawBgElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        Group {
            if store.isLoading && store.filteredEvents.isEmpty {
                VStack {
                    Spacer()
                    ProgressView().tint(Color.clawAccent)
                    Spacer()
                }
            } else if store.filteredEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredEvents) { event in
                            TimelineEventRow(event: event) {
                                store.toggleBookmark(event.id)
                            }
                            Divider().background(Color.clawBorder).padding(.leading, 52)
                        }
                        if store.hasMore && !store.isLoading {
                            Button {
                                Task { await store.loadMore() }
                            } label: {
                                Text("Load more")
                                    .font(.caption)
                                    .foregroundStyle(Color.clawAccent)
                                    .padding(.vertical, 12)
                            }
                        }
                        if store.isLoading {
                            ProgressView().tint(Color.clawAccent).padding(.vertical, 12)
                        }
                    }
                }
                .background(Color.clawBg)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No events")
                .font(.headline).foregroundStyle(Color.clawMuted)
            if !searchText.isEmpty {
                Text("No timeline events match \"\(searchText)\"")
                    .font(.subheadline).foregroundStyle(Color.clawMuted.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TimelineEventRow

struct TimelineEventRow: View {
    let event: MemoryTimelineEvent
    let onBookmark: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Category icon
            ZStack {
                Circle()
                    .fill(Color(hex: event.category.colorHex).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: event.category.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: event.category.colorHex))
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawTextStrong)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onBookmark) {
                        Image(systemName: event.isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 12))
                            .foregroundStyle(event.isBookmarked ? Color.clawAccent : Color.clawMuted.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                Text(event.summary)
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(event.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted.opacity(0.7))
                    if let source = event.source {
                        Text("·")
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(Color.clawMuted.opacity(0.7))
                    }
                    if !event.tags.isEmpty {
                        Text("·")
                        Text(event.tags.prefix(2).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(Color.clawTeal.opacity(0.7))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
