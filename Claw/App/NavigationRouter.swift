import SwiftUI

// MARK: - ClawTab

enum ClawTab: String, Hashable, CaseIterable {
    case chat
    case ops
    case dashboard
    case more

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .ops: return "Ops"
        case .dashboard: return "Dashboard"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .ops: return "terminal.fill"
        case .dashboard: return "square.grid.2x2.fill"
        case .more: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - NavigationRouter

@Observable
@MainActor
final class NavigationRouter {
    var selectedTab: ClawTab = .chat
    var chatPath = NavigationPath()
    var opsPath = NavigationPath()
    var dashboardPath = NavigationPath()
    var morePath = NavigationPath()

    // MARK: - Share intake presentation

    /// Pending share intake items waiting for user action.
    /// Populated when the app opens via claw://share deep link.
    var pendingShareItems: [ShareIntakeItem] = []
    var showShareIntake: Bool = false

    // MARK: - Voice driving mode (global — accessible from any tab)

    var showGlobalVoiceDriving: Bool = false

    // MARK: - Navigation helpers

    func switchTo(_ tab: ClawTab) {
        selectedTab = tab
    }

    /// Present pending share items from the App Group queue.
    func presentPendingShares() {
        let queue = ShareIntakeQueue.shared
        queue.reloadFromDisk()
        let pending = queue.pendingItems
        guard !pending.isEmpty else { return }
        pendingShareItems = pending
        showShareIntake = true
    }
}
