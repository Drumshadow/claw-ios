import SwiftUI
import Charts

// MARK: - CostDataPoint

struct CostDataPoint: Identifiable {
    let id: UUID = UUID()
    let stepIndex: Int
    let cumulativeCostUsd: Double
    let role: String
}

// MARK: - CostGraphView
//
// Dual-panel chart: cumulative cost curve + per-step incremental cost bar.

struct CostGraphView: View {
    let steps: [ReplayStep]
    let currentIndex: Int

    private var dataPoints: [CostDataPoint] {
        steps.map { CostDataPoint(
            stepIndex: $0.index,
            cumulativeCostUsd: $0.estimatedCostUsd,
            role: $0.message.role.rawValue
        )}
    }

    private var totalCost: Double { steps.last?.estimatedCostUsd ?? 0 }
    private var currentCost: Double {
        guard !steps.isEmpty, steps.indices.contains(currentIndex) else { return 0 }
        return steps[currentIndex].estimatedCostUsd
    }
    private var totalTokens: Int { steps.last?.accumulatedTokens ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header stats row
            HStack(spacing: 0) {
                statCell(
                    label: "Cost so far",
                    value: String(format: "$%.4f", currentCost),
                    color: .clawAccent
                )
                Divider()
                    .frame(height: 28)
                    .background(Color.clawBorder)
                statCell(
                    label: "Total run",
                    value: String(format: "$%.4f", totalCost),
                    color: .clawText
                )
                Divider()
                    .frame(height: 28)
                    .background(Color.clawBorder)
                statCell(
                    label: "Tokens",
                    value: tokensLabel(totalTokens),
                    color: .clawTeal
                )
            }
            .padding(.horizontal, 16)

            // Cumulative cost area chart
            Chart(dataPoints) { point in
                AreaMark(
                    x: .value("Step", point.stepIndex),
                    y: .value("Cost ($)", point.cumulativeCostUsd)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.clawAccent.opacity(0.5), Color.clawAccent.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Step", point.stepIndex),
                    y: .value("Cost ($)", point.cumulativeCostUsd)
                )
                .foregroundStyle(Color.clawAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisValueLabel(format: .currency(code: "USD").precision(.fractionLength(4)))
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted)
                }
            }
            .frame(height: 64)
            .padding(.horizontal, 16)
            .overlay(alignment: .leading) {
                // Vertical playhead
                if !steps.isEmpty {
                    let fraction = Double(currentIndex) / Double(max(steps.count - 1, 1))
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clawTextStrong.opacity(0.6))
                            .frame(width: 1)
                            .padding(.horizontal, 16)
                            .offset(x: (geo.size.width - 32) * fraction)
                    }
                }
            }
        }
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func tokensLabel(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }
}
