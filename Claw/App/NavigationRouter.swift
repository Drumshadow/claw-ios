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

    func switchTo(_ tab: ClawTab) {
        selectedTab = tab
    }
}
