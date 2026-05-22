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
                    Label("Memory", systemImage: "brain")
                }

                NavigationLink {
                    MemoryTimelineView()
                        .environment(timelineStore)
                } label: {
                    HStack {
                        Label("Knowledge Graph", systemImage: "circle.hexagongrid")
                        Spacer()
                        if timelineStore.bookmarkedEvents.count > 0 {
                            Text("\(timelineStore.bookmarkedEvents.count)")
                                .font(.caption2)
                                .foregroundStyle(Color.clawMuted)
                        }
                    }
                }

                NavigationLink {
                    SkillsView()
                        .environment(skillsStore)
                } label: {
                    Label("Skills", systemImage: "bolt")
                }
            } header: {
                Text("Intelligence")
            }
            .listRowBackground(Color.clawCard)

            Section {
                NavigationLink {
                    BackgroundAgentListView()
                        .environment(bgAgentStore)
                } label: {
                    HStack {
                        Label("Background Agents", systemImage: "eyes")
                        Spacer()
                        if bgAgentStore.activeIncidents.count > 0 {
                            Text("\(bgAgentStore.activeIncidents.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.clawWarn)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.clawWarn.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                NavigationLink {
                    MultiAgentDashboardView()
                        .environment(sessionStore)
                        .environment(agentMonitorStore)
                        .environment(bgAgentStore)
                } label: {
                    Label("Agent Network", systemImage: "circle.hexagongrid.circle")
                }

                NavigationLink {
                    CronView()
                        .environment(cronStore)
                } label: {
                    Label("Scheduled Tasks", systemImage: "clock")
                }
            } header: {
                Text("Automation")
            }
            .listRowBackground(Color.clawCard)

            Section {
                NavigationLink {
                    HomeOrchestrationView()
                        .environment(homeStore)
                        .environment(sessionStore)
                } label: {
                    HStack {
                        Label("Home AI", systemImage: "house.fill")
                        Spacer()
                        if homeStore.unreadTaskCount > 0 {
                            Text("\(homeStore.unreadTaskCount)")
                                .font(.caption2)
                                .foregroundStyle(Color.clawMuted)
                        }
                    }
                }

                NavigationLink {
                    IntegrationRegistryView()
                        .environment(homeStore)
                } label: {
                    HStack {
                        Label("Integrations", systemImage: "plug")
                        Spacer()
                        Text("\(homeStore.connectedCount) connected")
                            .font(.caption2)
                            .foregroundStyle(Color.clawMuted)
                    }
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
                    Label("Nodes", systemImage: "macbook.and.iphone")
                }

                NavigationLink {
                    UsageDashboardView()
                } label: {
                    Label("Usage & Costs", systemImage: "chart.bar")
                }
            } header: {
                Text("Infrastructure")
            }
            .listRowBackground(Color.clawCard)

            Section {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
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
}
