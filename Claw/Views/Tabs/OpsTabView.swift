import SwiftUI

// MARK: - OpsTabView
//
// Main entry point for the Ops tab — contains two sub-tabs:
//   • Terminal  — live session list → TerminalSessionView
//   • Runbooks  — catalog + launch  → RunbookDetailView → RunbookExecutionView

struct OpsTabView: View {
    @Environment(TerminalSessionStore.self) private var terminalStore: TerminalSessionStore?
    @Environment(RunbookStore.self) private var runbookStore: RunbookStore?

    @State private var selectedOpsTab: OpsSubTab = .terminal
    @State private var terminalPath = NavigationPath()
    @State private var runbookPath = NavigationPath()

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            subTabPicker
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()
                .background(Color.clawBorder)

            // Content
            switch selectedOpsTab {
            case .terminal:
                terminalTab
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            case .runbooks:
                runbooksTab
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
            }
        }
        .background(Color.clawBg.ignoresSafeArea())
        .navigationTitle("Ops")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                refreshButton
            }
        }
    }

    // MARK: - Sub-tab picker

    private var subTabPicker: some View {
        HStack(spacing: 4) {
            ForEach(OpsSubTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        selectedOpsTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))

                        // Badge for live sessions
                        if tab == .terminal, let count = terminalStore?.sessions.filter({ $0.status.isLive }).count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(selectedOpsTab == tab ? Color.clawBg : Color.clawOk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(selectedOpsTab == tab ? Color.clawOk : Color.clawOk.opacity(0.16))
                                .clipShape(Capsule())
                        }

                        // Badge for pending approvals in executions
                        if tab == .runbooks, let count = pendingApprovalCount, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(selectedOpsTab == tab ? Color.clawBg : Color.clawWarn)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(selectedOpsTab == tab ? Color.clawWarn : Color.clawWarn.opacity(0.16))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(selectedOpsTab == tab ? Color.clawBg : Color.clawMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedOpsTab == tab
                        ? tab.accentColor
                        : Color.clawBgElevated
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pendingApprovalCount: Int? {
        guard let store = runbookStore else { return nil }
        let count = store.sortedExecutions.flatMap { exec in
            exec.stepExecutions.filter { $0.status == .awaitingApproval }
        }.count
        return count > 0 ? count : nil
    }

    // MARK: - Terminal tab

    private var terminalTab: some View {
        NavigationStack(path: $terminalPath) {
            Group {
                if let store = terminalStore {
                    TerminalSessionListView()
                        .environment(store)
                } else {
                    // Preview / no-environment fallback
                    TerminalSessionListView()
                }
            }
            .navigationDestination(for: TerminalSession.self) { session in
                terminalDestination(for: session)
            }
        }
    }

    @ViewBuilder
    private func terminalDestination(for session: TerminalSession) -> some View {
        if let termStore = terminalStore {
            let sessionStore = termStore.store(for: session)
            TerminalSessionView(session: session, store: sessionStore)
                .environment(terminalStore)
        } else {
            TerminalSessionView(session: session, store: TerminalStore.preview())
        }
    }

    // MARK: - Runbooks tab

    private var runbooksTab: some View {
        NavigationStack(path: $runbookPath) {
            Group {
                if let store = runbookStore {
                    runbooksContent(store: store)
                } else {
                    runbooksContent(store: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func runbooksContent(store: RunbookStore?) -> some View {
        VStack(spacing: 0) {
            // Active executions strip (when there are running executions)
            if let store, !store.sortedExecutions.filter({ !$0.status.isTerminal }).isEmpty {
                activeExecutionsStrip(store: store)
            }

            RunbookListView()
                .environment(runbookStore)
        }
        .background(Color.clawBg)
        .navigationTitle("Runbooks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: RunbookNavigation.self) { nav in
            switch nav {
            case .detail(let runbook):
                RunbookDetailView(runbook: runbook)
                    .environment(runbookStore)
            case .execution(let execId):
                if let exec = store?.executions[execId] {
                    RunbookExecutionView(execution: exec, store: store)
                }
            }
        }
    }

    // MARK: - Active executions strip

    private func activeExecutionsStrip(store: RunbookStore) -> some View {
        let running = store.sortedExecutions.filter { !$0.status.isTerminal }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(running) { exec in
                    NavigationLink(value: RunbookNavigation.execution(exec.id)) {
                        ActiveExecutionChip(execution: exec)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.clawBgAccent)
        .overlay(
            Rectangle()
                .fill(Color.clawBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Refresh

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            Task {
                if selectedOpsTab == .terminal {
                    try? await terminalStore?.load()
                } else {
                    try? await runbookStore?.load()
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(Color.clawMuted)
        }
    }
}

// MARK: - OpsSubTab

enum OpsSubTab: String, CaseIterable {
    case terminal = "terminal"
    case runbooks = "runbooks"

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .runbooks: return "Runbooks"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal.fill"
        case .runbooks: return "list.bullet.clipboard.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .terminal: return Color.clawAccent
        case .runbooks: return Color.clawTeal
        }
    }
}

// MARK: - ActiveExecutionChip

struct ActiveExecutionChip: View {
    let execution: RunbookExecution

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: execution.progress)
                .progressViewStyle(.circular)
                .scaleEffect(0.6)
                .tint(Color.clawAccent)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(execution.runbook.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)
                Text("\(Int(execution.progress * 100))% • \(execution.mode.displayLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.clawMuted)
            }

            // Approval badge
            if execution.stepExecutions.contains(where: { $0.status == .awaitingApproval }) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.clawWarn)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.clawCard)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.clawBorder, lineWidth: 1))
    }
}

// MARK: - Previews

#Preview("Ops Tab – Terminal") {
    NavigationStack {
        OpsTabView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Ops Tab – Runbooks") {
    NavigationStack {
        OpsTabView()
    }
    .preferredColorScheme(.dark)
}
