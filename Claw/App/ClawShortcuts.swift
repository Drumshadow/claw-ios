import AppIntents

struct ClawShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewSessionIntent(),
            phrases: [
                "Start a new \(.applicationName) session",
                "New \(.applicationName) chat",
                "Open \(.applicationName)"
            ],
            shortTitle: "New Session",
            systemImageName: "plus.bubble"
        )
        AppShortcut(
            intent: SendToClawIntent(),
            phrases: [
                "Send a message to \(.applicationName)"
            ],
            shortTitle: "Send Message",
            systemImageName: "paperplane"
        )
    }
}
