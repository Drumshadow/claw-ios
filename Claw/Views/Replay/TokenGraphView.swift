import SwiftUI
import Charts

struct TokenDataPoint: Identifiable {
    let id: UUID = UUID()
    let stepIndex: Int
    let tokens: Int
    let role: String
}

struct TokenGraphView: View {
    let steps: [ReplayStep]
    let currentIndex: Int

    private var dataPoints: [TokenDataPoint] {
        steps.map { TokenDataPoint(stepIndex: $0.index, tokens: $0.accumulatedTokens, role: $0.message.role.rawValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Token Usage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.clawMuted)
                .padding(.horizontal, 16)

            Chart(dataPoints) { point in
                AreaMark(
                    x: .value("Step", point.stepIndex),
                    y: .value("Tokens", point.tokens)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.clawAccent.opacity(0.6), Color.clawAccent.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Step", point.stepIndex),
                    y: .value("Tokens", point.tokens)
                )
                .foregroundStyle(Color.clawAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisValueLabel().font(.caption2).foregroundStyle(Color.clawMuted)
                }
            }
            .frame(height: 80)
            .padding(.horizontal, 16)
            // Vertical rule at current step
            .overlay(alignment: .leading) {
                if !steps.isEmpty {
                    let fraction = Double(currentIndex) / Double(max(steps.count - 1, 1))
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clawTextStrong.opacity(0.5))
                            .frame(width: 1)
                            .padding(.horizontal, 16)
                            .offset(x: (geo.size.width - 32) * fraction)
                    }
                }
            }
        }
    }
}
