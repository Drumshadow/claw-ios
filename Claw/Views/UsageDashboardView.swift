import SwiftUI

// MARK: - UsageDashboardView

/// Shows usage summary and a per-day cost trend chart.
/// Loads `usage.cost` with selectable period (day / week / month).
struct UsageDashboardView: View {
    @Environment(AppState.self) private var appState

    @State private var period: UsagePeriod = .week
    @State private var stats: UsageStats?
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                periodPicker

                if isLoading && stats == nil {
                    loadingView
                } else if let err = loadError, stats == nil {
                    errorView(err)
                } else if let stats {
                    summaryCards(stats)
                    chartSection(stats)
                    modelBreakdownSection(stats)
                } else {
                    emptyStateView
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            await loadStats()
        }
        .navigationTitle("Usage & Costs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: period) { _, _ in
            Task { await loadStats() }
        }
        .task {
            if stats == nil { await loadStats() }
        }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(UsagePeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .colorMultiply(Color.clawText)
    }

    // MARK: - Summary cards

    private func summaryCards(_ stats: UsageStats) -> some View {
        VStack(spacing: 10) {
            SummaryCard(
                icon: "dollarsign.circle.fill",
                label: "Total Cost",
                value: formatCost(stats.totalCostUsd),
                accent: Color.clawAccent
            )
            SummaryCard(
                icon: "number",
                label: "Tokens",
                value: formatTokens(stats.totalTokens),
                accent: Color.clawTeal
            )
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clawMuted)
                    .padding(.top, 1)
                Text("Estimated API-equivalent cost. Actual cost is covered by your Claude Max subscription.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clawMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Chart section

    private func chartSection(_ stats: UsageStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Daily Cost")
            if stats.byDay.isEmpty {
                Text("No daily data for this period.")
                    .font(.caption)
                    .foregroundStyle(Color.clawMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clawCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
            } else {
                DailyBarChart(data: stats.byDay)
                    .frame(height: 180)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clawCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Model breakdown section

    @ViewBuilder
    private func modelBreakdownSection(_ stats: UsageStats) -> some View {
        if !stats.byModel.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("By Model")
                VStack(spacing: 0) {
                    ForEach(Array(stats.byModel.enumerated()), id: \.element.id) { index, entry in
                        ModelBreakdownRow(entry: entry, totalCost: stats.totalCostUsd)
                        if index < stats.byModel.count - 1 {
                            Divider()
                                .background(Color.clawBorder)
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.clawCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.clawMuted)
            .textCase(.uppercase)
    }

    // MARK: - Loading / empty / error

    private var loadingView: some View {
        VStack {
            ProgressView("Loading usage…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("No usage data")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.clawDanger)
            Text("Couldn't load usage")
                .font(.headline)
                .foregroundStyle(Color.clawTextStrong)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadStats() }
            } label: {
                Text("Retry")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clawCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
                    .foregroundStyle(Color.clawAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    // MARK: - Loading

    private func loadStats() async {
        guard let client = appState.activeClient else {
            loadError = "Not connected"
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let payload = try await client.send(method: GatewayMethod.usageCost, params: UsageCostParams(days: period.dayCount))
            stats = parseUsageStats(payload)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Parsing

    private func parseUsageStats(_ payload: [String: JSONValue]) -> UsageStats {
        // Totals are nested under "totals"
        let totals: [String: JSONValue]
        if let v = payload["totals"], case .object(let obj) = v {
            totals = obj
        } else {
            totals = [:]
        }

        let totalCost = doubleFromJSONValue(totals["totalCost"]) ?? 0
        let totalTokens = intFromJSONValue(totals["totalTokens"]) ?? 0

        // Daily entries are under "daily"; each entry has "date", "totalCost", "totalTokens"
        var byDay: [UsageDayEntry] = []
        if let v = payload["daily"], case .array(let arr) = v {
            for item in arr {
                guard case .object(let obj) = item else { continue }
                let date: String
                if let v = obj["date"], case .string(let s) = v { date = s } else { continue }
                let cost = doubleFromJSONValue(obj["totalCost"]) ?? 0
                let tokens = intFromJSONValue(obj["totalTokens"]) ?? 0
                byDay.append(UsageDayEntry(date: date, cost: cost, tokens: tokens))
            }
        }

        // byModel entries are under "byModel"; each entry has "model", "totalCost", "totalTokens"
        var byModel: [UsageModelEntry] = []
        if let v = payload["byModel"], case .array(let arr) = v {
            for item in arr {
                guard case .object(let obj) = item else { continue }
                let model: String
                if let v = obj["model"], case .string(let s) = v { model = s } else { continue }
                let cost = doubleFromJSONValue(obj["totalCost"]) ?? 0
                let tokens = intFromJSONValue(obj["totalTokens"]) ?? 0
                byModel.append(UsageModelEntry(model: model, totalCost: cost, totalTokens: tokens))
            }
        }

        return UsageStats(
            totalCostUsd: totalCost,
            totalTokens: totalTokens,
            byDay: byDay,
            byModel: byModel
        )
    }

    private func intFromJSONValue(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    private func doubleFromJSONValue(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    // MARK: - Formatting

    private func formatCost(_ value: Double) -> String {
        UsageFormatters.cost.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// MARK: - Shared formatters

/// File-private cache so the chart, summary cards, and breakdown rows reuse
/// one NumberFormatter instead of allocating a fresh one per cell on every render.
private enum UsageFormatters {
    static let cost: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()
}

// MARK: - Request params

private struct UsageCostParams: Encodable {
    let days: Int
}

// MARK: - UsagePeriod

private enum UsagePeriod: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    var dayCount: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

// MARK: - Data structs

private struct UsageStats {
    let totalCostUsd: Double
    let totalTokens: Int
    let byDay: [UsageDayEntry]
    let byModel: [UsageModelEntry]
}

private struct UsageDayEntry: Identifiable, Hashable {
    var id: String { date }
    let date: String
    let cost: Double
    let tokens: Int
}

private struct UsageModelEntry: Identifiable, Hashable {
    var id: String { model }
    let model: String
    let totalCost: Double
    let totalTokens: Int
}

// MARK: - SummaryCard

private struct SummaryCard: View {
    let icon: String
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.clawTextStrong)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }
}

// MARK: - ModelBreakdownRow

private struct ModelBreakdownRow: View {
    let entry: UsageModelEntry
    let totalCost: Double

    private var shortModelName: String {
        // Strip "claude-" prefix for compact display
        entry.model.hasPrefix("claude-") ? String(entry.model.dropFirst(7)) : entry.model
    }

    private var costFraction: Double {
        guard totalCost > 0 else { return 0 }
        return min(1.0, entry.totalCost / totalCost)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shortModelName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(1)
                Spacer()
                Text(formatCost(entry.totalCost))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.clawBorder.opacity(0.5))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.clawAccent)
                        .frame(width: geo.size.width * CGFloat(costFraction), height: 4)
                }
            }
            .frame(height: 4)
            Text(formatTokens(entry.totalTokens))
                .font(.system(size: 11))
                .foregroundStyle(Color.clawMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func formatCost(_ value: Double) -> String {
        UsageFormatters.cost.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fk tokens", Double(value) / 1_000)
        }
        return "\(value) tokens"
    }
}

// MARK: - DailyBarChart (SwiftUI Canvas)

private struct DailyBarChart: View {
    let data: [UsageDayEntry]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !data.isEmpty else { return }
                let maxCost = data.map(\.cost).max() ?? 0
                guard maxCost > 0 else {
                    // Draw a baseline line
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: size.height - 1))
                    line.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                    context.stroke(line, with: .color(Color.clawBorder), lineWidth: 1)
                    return
                }

                let count = data.count
                let availableWidth = size.width
                let spacing: CGFloat = max(2, min(6, availableWidth / CGFloat(count) * 0.2))
                let totalSpacing = spacing * CGFloat(max(0, count - 1))
                let barWidth = max(2, (availableWidth - totalSpacing) / CGFloat(count))
                let chartHeight = size.height - 14 // leave room for baseline label

                // Baseline
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: chartHeight))
                baseline.addLine(to: CGPoint(x: size.width, y: chartHeight))
                context.stroke(baseline, with: .color(Color.clawBorder.opacity(0.6)), lineWidth: 0.5)

                for (idx, entry) in data.enumerated() {
                    let ratio = entry.cost / maxCost
                    let barHeight = max(2, chartHeight * CGFloat(ratio))
                    let x = CGFloat(idx) * (barWidth + spacing)
                    let y = chartHeight - barHeight
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let path = Path(roundedRect: rect, cornerRadius: min(3, barWidth / 2))
                    context.fill(path, with: .color(Color.clawAccent))
                }

                // Max label
                let maxText = Text(formatCost(maxCost))
                    .font(.system(size: 9))
                    .foregroundColor(Color.clawMuted)
                context.draw(maxText, at: CGPoint(x: 4, y: 6), anchor: .topLeading)

                // First / last date labels
                if let first = data.first?.date.shortDateLabel,
                   let last = data.last?.date.shortDateLabel {
                    let firstText = Text(first)
                        .font(.system(size: 9))
                        .foregroundColor(Color.clawMuted)
                    context.draw(firstText, at: CGPoint(x: 0, y: size.height - 2), anchor: .bottomLeading)

                    if data.count > 1 {
                        let lastText = Text(last)
                            .font(.system(size: 9))
                            .foregroundColor(Color.clawMuted)
                        context.draw(lastText, at: CGPoint(x: size.width, y: size.height - 2), anchor: .bottomTrailing)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func formatCost(_ value: Double) -> String {
        UsageFormatters.cost.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

private extension String {
    /// Returns a short MM/DD label if the string looks like an ISO-ish "YYYY-MM-DD" prefix.
    var shortDateLabel: String? {
        let parts = self.split(separator: "-")
        guard parts.count >= 3 else { return self }
        let monthRaw = String(parts[1])
        let dayRawWithSuffix = String(parts[2])
        let dayRaw = String(dayRawWithSuffix.prefix(2))
        let month = Int(monthRaw) ?? 0
        let day = Int(dayRaw) ?? 0
        if month > 0 && day > 0 {
            return "\(month)/\(day)"
        }
        return self
    }
}

