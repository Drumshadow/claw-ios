import Foundation

// A snapshot of one step in a session for replay
struct ReplayStep: Identifiable {
    let id: UUID = UUID()
    let index: Int
    let message: ClawMessage
    let accumulatedTokens: Int
    let timestamp: Date

    var isAssistant: Bool { message.role == .assistant }
    var isTool: Bool { message.role == .tool }
    var isUser: Bool { message.role == .user }
}

@Observable
@MainActor
final class ReplayStore {
    let sessionId: String
    private(set) var steps: [ReplayStep] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying: Bool = false
    var playbackSpeed: Double = 1.0   // 0.5x, 1x, 2x, 4x

    // Messages visible at current replay position
    var visibleMessages: [ClawMessage] {
        steps.prefix(currentIndex + 1).map { $0.message }
    }

    var currentStep: ReplayStep? { steps[safe: currentIndex] }
    var progress: Double {
        steps.isEmpty ? 0 : Double(currentIndex) / Double(steps.count - 1)
    }

    init(sessionId: String, messages: [ClawMessage]) {
        self.sessionId = sessionId
        loadMessages(messages)
    }

    func loadMessages(_ messages: [ClawMessage]) {
        var accumulated = 0
        steps = messages.enumerated().map { index, message in
            // Estimate tokens: ~4 characters per token
            let messageTokens = message.content.count / 4
            if let thinking = message.thinkingContent {
                accumulated += thinking.count / 4
            }
            accumulated += messageTokens

            return ReplayStep(
                index: index,
                message: message,
                accumulatedTokens: accumulated,
                timestamp: message.createdAt
            )
        }

        // Start at beginning
        currentIndex = 0
    }

    func scrubTo(index: Int) {
        guard !steps.isEmpty else { return }
        currentIndex = max(0, min(index, steps.count - 1))
    }

    func scrubTo(progress: Double) {
        guard !steps.isEmpty else { return }
        let targetIndex = Int(round(progress * Double(steps.count - 1)))
        scrubTo(index: targetIndex)
    }

    func stepForward() {
        scrubTo(index: currentIndex + 1)
    }

    func stepBackward() {
        scrubTo(index: currentIndex - 1)
    }

    func play() {
        guard !isPlaying, currentIndex < steps.count - 1 else { return }
        isPlaying = true
        scheduleNextStep()
    }

    func pause() {
        isPlaying = false
    }

    func jumpToStart() {
        pause()
        scrubTo(index: 0)
    }

    func jumpToEnd() {
        pause()
        scrubTo(index: steps.count - 1)
    }

    private func scheduleNextStep() {
        guard isPlaying, currentIndex < steps.count - 1 else {
            isPlaying = false
            return
        }

        // Base delay: 0.5 seconds, adjusted by playback speed
        let delay = 0.5 / playbackSpeed

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard isPlaying else { return }
            stepForward()
            scheduleNextStep()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
