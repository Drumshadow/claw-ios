import SwiftUI

struct MoreTabView: View {
    let client: GatewayClient
    @Environment(AppState.self) private var appState
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(SkillsStore.self) private var skillsStore
    @Environment(CronStore.self) private var cronStore
    @Environment(NodeStore.self) private var nodeStore
    @Environment(BackgroundAgentStore.self) private var bgAgentStore
    @Environment(MemoryTimelineStore.self) private var timelineStore
    @Environment(HomeOrchestrationStore.self) private var homeStore
    @Environment(SessionStore.self) private var sessionStore
    @Environment(AgentMonitorStore.self) private var agentMonitorStore
    @State private var showSettings = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    MemoryBrowserView()
                        .environment(memoryStore)
                } label: {
                    destinationRow(
                        title: "Memory",
                        subtitle: "Saved facts and conversation context",
                        systemImage: "brain"
                    )
                }

                NavigationLink {
                    MemoryTimelineView()
                        .environment(timelineStore)
                } label: {
                    destinationRow(
                        title: "Knowledge Graph",
                        subtitle: "Bookmarked events and linked context",
                        systemImage: "circle.hexagongrid",
                        badge: timelineStore.bookmarkedEvents.isEmpty ? nil : "\(timelineStore.bookmarkedEvents.count)"
                    )
                }

                NavigationLink {
                    SkillsView()
                        .environment(skillsStore)
                } label: {
                    destinationRow(
                        title: "Skills",
                        subtitle: "Slash commands and custom agent tools",
                        systemImage: "bolt"
                    )
                }
            } header: {
                Text("Intelligence")
            } footer: {
                Text("Context and capabilities the agent can use while responding.")
            }
            .listRowBackground(Color.clawCard)

            Section {
                NavigationLink {
                    BackgroundAgentListView()
                        .environment(bgAgentStore)
                } label: {
                    destinationRow(
                        title: "Background Agents",
                        subtitle: "Detached work, incidents, and long-running tasks",
                        systemImage: "eyes",
                        badge: bgAgentStore.activeIncidents.isEmpty ? nil : "\(bgAgentStore.activeIncidents.count)",
                        badgeColor: bgAgentStore.activeIncidents.isEmpty ? .clawMuted : .clawWarn
                    )
                }

                NavigationLink {
                    MultiAgentDashboardView()
                        .environment(sessionStore)
                        .environment(agentMonitorStore)
                        .environment(bgAgentStore)
                } label: {
                    destinationRow(
                        title: "Agent Network",
                        subtitle: "Monitor child sessions and coordination",
                        systemImage: "circle.hexagongrid.circle"
                    )
                }

                NavigationLink {
                    CronView()
                        .environment(cronStore)
                } label: {
                    destinationRow(
                        title: "Scheduled Tasks",
                        subtitle: "Recurring checks, reminders, and jobs",
                        systemImage: "clock"
                    )
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("Things OpenClaw can keep doing after you leave the chat.")
            }
            .listRowBackground(Color.clawCard)

            Section {
                NavigationLink {
                    HomeOrchestrationView()
                        .environment(homeStore)
                        .environment(sessionStore)
                } label: {
                    destinationRow(
                        title: "Home AI",
                        subtitle: "Personal tasks and household orchestration",
                        systemImage: "house.fill",
                        badge: homeStore.unreadTaskCount == 0 ? nil : "\(homeStore.unreadTaskCount)"
                    )
                }

                NavigationLink {
                    IntegrationRegistryView()
                        .environment(homeStore)
                } label: {
                    destinationRow(
                        title: "Integrations",
                        subtitle: "Connected services and available providers",
                        systemImage: "plug",
                        badge: "\(homeStore.connectedCount) connected"
                    )
                }
            } header: {
                Text("Personal")
            }
            .listRowBackground(Color.clawCard)

            Section {
                NavigationLink {
                    NodeListView()
                        .environment(nodeStore)
                } label: {
                    destinationRow(
                        title: "Nodes",
                        subtitle: "Gateway, phone, and compute connections",
                        systemImage: "macbook.and.iphone"
                    )
                }

                NavigationLink {
                    UsageDashboardView()
                } label: {
                    destinationRow(
                        title: "Usage & Costs",
                        subtitle: "Token usage and API spend from reported sessions",
                        systemImage: "chart.bar"
                    )
                }
            } header: {
                Text("Infrastructure")
            } footer: {
                Text("Operational surfaces. Counts are only shown when the gateway reports live data.")
            }
            .listRowBackground(Color.clawCard)

            Section {
                Button {
                    showSettings = true
                } label: {
                    destinationRow(
                        title: "Settings",
                        subtitle: "Notifications, connection, and app preferences",
                        systemImage: "gear"
                    )
                    .foregroundStyle(Color.clawText)
                }
                Button(role: .destructive) {
                    Task { await appState.disconnect() }
                } label: {
                    Label("Disconnect Gateway", systemImage: "xmark.circle")
                }
            } header: {
                Text("System")
            }
            .listRowBackground(Color.clawCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func destinationRow(
        title: String,
        subtitle: String,
        systemImage: String,
        badge: String? = nil,
        badgeColor: Color = .clawMuted
    ) -> some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.clawText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: systemImage)
            }
            Spacer(minLength: 8)
            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
