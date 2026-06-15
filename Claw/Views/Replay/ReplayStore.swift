import Foundation

// MARK: - ReplayStep
//
// A snapshot of one step in a session for replay playback.
// Includes accumulated cost/token data for the cost graph.

struct ReplayStep: Identifiable {
    let id: UUID = UUID()
    let index: Int
    let message: ClawMessage
    let accumulatedTokens: Int
    let estimatedCostUsd: Double    // running total USD cost at this step
    let timestamp: Date
    let branchId: String?           // non-nil if step belongs to an alternate branch

    var isAssistant: Bool { message.role == .assistant }
    var isTool: Bool { message.role == .tool }
    var isUser: Bool { message.role == .user }
    var isThinking: Bool { message.thinkingContent != nil }

    // Incremental tokens (delta from previous step)
    var stepTokens: Int { max(0, accumulatedTokens) }
}

// MARK: - ReplayBranch
//
// An alternate branch in the conversation — e.g., a retry or a parallel sub-agent.

struct ReplayBranch: Identifiable, Hashable {
    let id: String
    var label: String
    var startIndex: Int         // index in the main step list where this branch diverges
    var messageCount: Int
    var tokenCount: Int
    var costUsd: Double
    var isMain: Bool
    var parentBranchId: String?
}

// MARK: - ReplayStore

@Observable
@MainActor
final class ReplayStore {
    let sessionId: String

    // Step data
    private(set) var steps: [ReplayStep] = []
    private(set) var currentIndex: Int = 0
    var playbackSpeed: Double = 1.0   // 0.5x, 1x, 2x, 4x

    // Branch data
    private(set) var branches: [ReplayBranch] = []
    private(set) var selectedBranchId: String? = nil  // nil = main branch

    // Playback state
    private(set) var isPlaying: Bool = false
    private(set) var isLoadingBranches: Bool = false

    // Cost summary
    var totalCostUsd: Double { steps.last?.estimatedCostUsd ?? 0 }
    var totalTokens: Int { steps.last?.accumulatedTokens ?? 0 }

    // Cost per step (for per-message granularity in bar chart)
    var costPerStep: [(index: Int, costUsd: Double)] {
        var previous = 0.0
        return steps.map { step in
            let delta = step.estimatedCostUsd - previous
            previous = step.estimatedCostUsd
            return (index: step.index, costUsd: delta)
        }
    }

    // Messages visible at current replay position
    var visibleMessages: [ClawMessage] {
        steps.prefix(currentIndex + 1).map { $0.message }
    }

    var currentStep: ReplayStep? {
        guard steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    var progress: Double {
        steps.isEmpty ? 0 : Double(currentIndex) / Double(max(steps.count - 1, 1))
    }

    var progressLabel: String {
        "\(currentIndex + 1)/\(steps.count)"
    }

    // MARK: - Init

    init(sessionId: String, messages: [ClawMessage]) {
        self.sessionId = sessionId
        loadMessages(messages)
    }

    // MARK: - Load

    func loadMessages(_ messages: [ClawMessage]) {
        var accTokens = 0
        var accCost = 0.0

        steps = messages.enumerated().map { index, message in
            // Token estimation: ~4 chars/token for assistant, full for tool results
            let contentTokens = message.content.count / 4
            let thinkingTokens = (message.thinkingContent?.count ?? 0) / 4
            let stepTokens = contentTokens + thinkingTokens

            accTokens += stepTokens

            // Cost estimation: $3/MTok input, $15/MTok output (Sonnet approximation)
            let inputCostPer1M  = 3.0
            let outputCostPer1M = 15.0
            let stepCost: Double
            if message.role == .assistant {
                stepCost = Double(stepTokens) / 1_000_000 * outputCostPer1M
            } else {
                stepCost = Double(stepTokens) / 1_000_000 * inputCostPer1M
            }
            accCost += stepCost

            return ReplayStep(
                index: index,
                message: message,
                accumulatedTokens: accTokens,
                estimatedCostUsd: accCost,
                timestamp: message.createdAt,
                branchId: nil
            )
        }

        currentIndex = 0
    }

    // MARK: - Scrubbing

    func scrubTo(index: Int) {
        guard !steps.isEmpty else { return }
        currentIndex = max(0, min(index, steps.count - 1))
    }

    func scrubTo(progress: Double) {
        guard !steps.isEmpty else { return }
        let targetIndex = Int(round(progress * Double(max(steps.count - 1, 1))))
        scrubTo(index: targetIndex)
    }

    // Scrub to the first step matching a given timestamp
    func scrubTo(timestamp: Date) {
        guard !steps.isEmpty else { return }
        let nearest = steps.min(by: { abs($0.timestamp.timeIntervalSince(timestamp)) < abs($1.timestamp.timeIntervalSince(timestamp)) })
        if let idx = nearest?.index { scrubTo(index: idx) }
    }

    // MARK: - Step Navigation

    func stepForward() { scrubTo(index: currentIndex + 1) }
    func stepBackward() { scrubTo(index: currentIndex - 1) }

    func jumpToStart() { pause(); scrubTo(index: 0) }
    func jumpToEnd() { pause(); scrubTo(index: steps.count - 1) }

    // Jump to next user message
    func jumpToNextUserMessage() {
        let next = steps.dropFirst(currentIndex + 1).first(where: { $0.isUser })
        if let idx = next?.index { scrubTo(index: idx) }
    }

    // Jump to next tool call
    func jumpToNextToolCall() {
        let next = steps.dropFirst(currentIndex + 1).first(where: { $0.isTool })
        if let idx = next?.index { scrubTo(index: idx) }
    }

    // MARK: - Playback

    func play() {
        guard !isPlaying, currentIndex < steps.count - 1 else { return }
        isPlaying = true
        scheduleNextStep()
    }

    func pause() {
        isPlaying = false
    }

    private func scheduleNextStep() {
        guard isPlaying, currentIndex < steps.count - 1 else {
            isPlaying = false
            return
        }

        // Base delay: 500ms per step, adjusted by speed
        let delay = 0.5 / playbackSpeed

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard self.isPlaying else { return }
            self.stepForward()
            self.scheduleNextStep()
        }
    }

    // MARK: - Branch Management

    func selectBranch(_ branchId: String?) {
        selectedBranchId = branchId
        // In a full implementation: reload steps for the selected branch
    }

    // Load branches from a flat branch list (preview/stub)
    func loadPreviewBranches() {
        branches = [
            ReplayBranch(
                id: "main",
                label: "Main",
                startIndex: 0,
                messageCount: steps.count,
                tokenCount: totalTokens,
                costUsd: totalCostUsd,
                isMain: true,
                parentBranchId: nil
            )
        ]
    }
}
