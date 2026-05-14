import SwiftUI

// MARK: - AgentMonitorView

struct AgentMonitorView: View {
    let store: AgentMonitorStore

    private let columns: [GridItem] = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.sessions.isEmpty {
                    loadingView
                } else if store.sessions.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.sessions) { session in
                                AgentMonitorCard(session: session, store: store)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await store.refresh()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clawBg)
            .navigationTitle("Agent Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if store.runningCount > 0 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        runningIndicator
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(Color.clawAccent)
                    .disabled(store.isLoading)
                }
            }
        }
        .task {
            await store.refresh()
            store.startPollingIfNeeded()
        }
        .onDisappear {
            store.stopPolling()
        }
    }

    // MARK: - Running indicator

    private var runningIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.clawOk)
                .frame(width: 8, height: 8)
            Text("\(store.runningCount) running")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.clawOk)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            ProgressView("Loading agents…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Image(systemName: "cpu")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.clawMuted.opacity(0.4))
                Image(systemName: "eye.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.clawAccent.opacity(0.7))
                    .offset(x: 22, y: 18)
            }
            Text("Nothing to spectate")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
            Text("Subagents dispatched by your sessions will appear here. Tap one to watch its conversation in read-only mode.")
                .font(.caption)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - AgentMonitorCard

private struct AgentMonitorCard: View {
    let session: AgentMonitorSession
    let store: AgentMonitorStore

    @State private var showThread = false
    @State private var pulse = false

    private var isRunning: Bool { session.status.isActive }

    private var statusColor: Color {
        switch session.status {
        case .running:   return Color.clawOk
        case .completed: return Color.clawMuted.opacity(0.5)
        case .error:     return Color.clawDanger
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isRunning {
                LinearGradient(
                    colors: [Color.clawAccent.opacity(0.06), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                topRow
                titleSection
                bottomRow
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isRunning ? Color.clawAccent.opacity(0.4) : Color.clawBorder,
                    lineWidth: isRunning ? 1.5 : 1
                )
        )
        .shadow(
            color: isRunning ? .black.opacity(0.15) : .clear,
            radius: 8,
            y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { showThread = true }
        .sheet(isPresented: $showThread) {
            AgentReadOnlyThreadView(session: session)
        }
        .onAppear {
            if isRunning {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    pulse = true
                }
            }
        }
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(spacing: 6) {
            ZStack {
                if isRunning {
                    Circle()
                        .fill(statusColor.opacity(0.35))
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulse ? 2.0 : 1.0)
                }
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            Text(session.status.label)
                .font(.caption)
                .foregroundStyle(Color.clawMuted)

            Spacer()

            Text(session.agentId ?? "agent")
                .font(.caption2)
                .foregroundStyle(Color.clawAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.clawAccent.opacity(0.15))
                )
                .lineLimit(1)
        }
    }

    // MARK: - Title + last message

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.clawTextStrong)
                .lineLimit(2)

            if let msg = session.lastMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(3)
            } else {
                Text("No output yet")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Color.clawMuted.opacity(0.6))
            }
        }
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if let model = session.model {
                Text(model)
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let updated = session.updatedAt {
                Text(relativeTime(updated))
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }

            Image(systemName: "eye")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.clawAccent.opacity(isRunning ? 0.9 : 0.5))
        }
    }

    // MARK: - Relative time

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 {
            return "just now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m ago"
        } else if diff < 86400 {
            let hrs = Int(diff / 3600)
            return "\(hrs)h ago"
        } else {
            let days = Int(diff / 86400)
            return "\(days)d ago"
        }
    }
}
