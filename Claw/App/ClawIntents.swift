import AppIntents
import Foundation

struct NewSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start New Claw Session"
    static var description = IntentDescription("Opens Claw and starts a new AI session.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("claw.intent.newSession"), object: nil)
        return .result()
    }
}

struct OpenSessionListIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Claw Sessions"
    static var description = IntentDescription("Opens Claw and shows your sessions.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct SendToClawIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Message to Claw"
    static var description = IntentDescription("Opens Claw and sends a message to the active session.")
    static var openAppWhenRun: Bool = true

    /// Maximum number of characters accepted from a Shortcuts/Siri intent.
    /// Caps the prefilled text to prevent an automated flow from injecting an
    /// arbitrarily large payload without the user reviewing it.
    private static let maxMessageLength = 4_000

    @Parameter(title: "Message")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult {
        // Trim and cap the incoming message before forwarding to the UI layer.
        // The user still sees the prefilled text in the compose field and must
        // explicitly tap Send — this cap prevents oversized automated injections.
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result() }
        let capped = trimmed.count > Self.maxMessageLength
            ? String(trimmed.prefix(Self.maxMessageLength))
            : trimmed
        NotificationCenter.default.post(
            name: Notification.Name("claw.intent.sendMessage"),
            object: nil,
            userInfo: ["message": capped]
        )
        return .result()
    }
}
