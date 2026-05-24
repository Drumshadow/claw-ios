import Foundation

// MARK: - DashboardStore
//
// Manages dashboard layouts (widget configuration) with local persistence.
// Multiple named dashboards are stored in UserDefaults as Codable JSON.
// Also acts as the widget data provider, pulling from topology + session
// data and caching for the UI layer.

@Observable
@MainActor
final class DashboardStore {

    // MARK: - State

    private(set) var config: DashboardConfig
    var activeLayoutIndex: Int {
        get { config.activeLayoutIndex }
        set {
            config.activeLayoutIndex = newValue
            persist()
        }
    }

    var activeLayout: DashboardLayout {
        get { config.activeLayout }
        set {
            config.activeLayout = newValue
            persist()
        }
    }

    var layouts: [DashboardLayout] { config.layouts }

    // MARK: - Widget-level live data (fetched / derived externally, stored here for widgets)

    private(set) var activeSessions: Int   = 0
    private(set) var runningAgents: Int    = 0
    private(set) var pendingApprovals: Int = 0
    private(set) var cronRecentFailures: Int = 0
    private(set) var totalTokensToday: Int = 0
    private(set) var totalCostTodayUsd: Double = 0

    // MARK: - UserDefaults key

    private static let persistKey = "dashboardConfig_v2"

    // MARK: - Init

    init() {
        if AppReviewSampleData.isEnabled {
            self.config = AppReviewSampleData.screenshotDashboardConfig
        } else if let data = UserDefaults.standard.data(forKey: Self.persistKey),
                  let saved = try? JSONDecoder().decode(DashboardConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = .default
        }
    }

    // MARK: - Layout management

    func addLayout(_ layout: DashboardLayout) {
        config.layouts.append(layout)
        persist()
    }

    func deleteLayout(at offsets: IndexSet) {
        config.layouts.remove(atOffsets: offsets)
        // Clamp active index
        config.activeLayoutIndex = min(
            config.activeLayoutIndex,
            max(0, config.layouts.count - 1)
        )
        persist()
    }

    func renameActiveLayout(to name: String) {
        guard config.layouts.indices.contains(config.activeLayoutIndex) else { return }
        config.layouts[config.activeLayoutIndex].name = name
        persist()
    }

    /// Add a widget to the active layout.
    func addWidget(_ widget: DashboardWidget) {
        config.layouts[config.activeLayoutIndex].widgets.append(widget)
        persist()
    }

    /// Remove a widget from the active layout by ID.
    func removeWidget(id: UUID) {
        config.layouts[config.activeLayoutIndex].widgets.removeAll { $0.id == id }
        persist()
    }

    /// Toggle widget hidden state.
    func toggleWidget(id: UUID) {
        guard let idx = config.layouts[config.activeLayoutIndex].widgets.firstIndex(where: { $0.id == id }) else { return }
        config.layouts[config.activeLayoutIndex].widgets[idx].isHidden.toggle()
        persist()
    }

    /// Move widgets for reordering (used in edit mode).
    func moveWidgets(from source: IndexSet, to destination: Int) {
        config.layouts[config.activeLayoutIndex].widgets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Live data update (called from DashboardTabView on refresh)

    func updateLiveData(
        activeSessions: Int,
        runningAgents: Int,
        pendingApprovals: Int,
        cronRecentFailures: Int,
        totalTokensToday: Int,
        totalCostTodayUsd: Double
    ) {
        self.activeSessions = activeSessions
        self.runningAgents = runningAgents
        self.pendingApprovals = pendingApprovals
        self.cronRecentFailures = cronRecentFailures
        self.totalTokensToday = totalTokensToday
        self.totalCostTodayUsd = totalCostTodayUsd
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.persistKey)
        }
    }

    // MARK: - Reset to defaults

    func resetToDefault() {
        config = .default
        persist()
    }

    func loadAppReviewSampleData() {
        config = AppReviewSampleData.screenshotDashboardConfig
        updateLiveData(
            activeSessions: AppReviewSampleData.sessions.count,
            runningAgents: 1,
            pendingApprovals: 1,
            cronRecentFailures: 0,
            totalTokensToday: AppReviewSampleData.sessions.reduce(0) { $0 + ($1.totalTokens ?? 0) },
            totalCostTodayUsd: AppReviewSampleData.sessions.reduce(0) { $0 + ($1.estimatedCostUsd ?? 0) }
        )
    }

    func clearAppReviewSampleData() {
        if config.layouts.count == 1, config.layouts.first?.name == "App Review" {
            config = .default
        }
        activeSessions = 0
        runningAgents = 0
        pendingApprovals = 0
        cronRecentFailures = 0
        totalTokensToday = 0
        totalCostTodayUsd = 0
    }
}
