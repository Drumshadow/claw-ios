import SwiftUI

struct MoreTabView: View {
    let client: GatewayClient
    @Environment(AppState.self) private var appState
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(SkillsStore.self) private var skillsStore
    @Environment(CronStore.self) private var cronStore
    @Environment(NodeStore.self) private var nodeStore
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
                    SkillsView()
                        .environment(skillsStore)
                } label: {
                    Label("Skills", systemImage: "bolt")
                }
                NavigationLink {
                    CronView()
                        .environment(cronStore)
                } label: {
                    Label("Scheduled Tasks", systemImage: "clock")
                }
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
                Text("Tools")
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
